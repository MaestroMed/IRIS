import Foundation

/// v1.338 — Google Gemini REST API client (chat completions, non-streaming).
/// Endpoint : POST https://generativelanguage.googleapis.com/v1beta/models/{MODEL}:generateContent?key={KEY}
///
/// Lit la clé API depuis IRISKeychain (account "gemini-api-key").
/// Modèles : gemini-2.5-flash (rapide/cheap), gemini-2.5-pro (reasoning).
/// Architecture miroir d'AnthropicClient mais simplifiée : pas de streaming v1, pas de tool-use.
public actor GeminiClient {
    public static let shared = GeminiClient()

    public enum GeminiModel: String, Sendable, CaseIterable {
        case flash25 = "gemini-2.5-flash"
        case pro25 = "gemini-2.5-pro"

        public var displayName: String {
            switch self {
            case .flash25: return "Gemini 2.5 Flash"
            case .pro25: return "Gemini 2.5 Pro"
            }
        }
    }

    public struct GeminiMessage: Sendable {
        public enum Role: String, Sendable { case user, model }
        public let role: Role
        public let text: String
        public init(role: Role, text: String) { self.role = role; self.text = text }
    }

    public struct GeminiUsage: Sendable {
        public let promptTokens: Int
        public let outputTokens: Int
        public let totalTokens: Int

        // Tarifs publics Google AI Studio (2026, USD/1M tokens, prompt | output)
        // Source : https://ai.google.dev/gemini-api/docs/pricing
        public func estimatedCostUSD(model: GeminiModel) -> Double {
            let (pIn, pOut): (Double, Double)
            switch model {
            case .flash25: (pIn, pOut) = (0.075, 0.30)
            case .pro25:   (pIn, pOut) = (1.25, 5.00)
            }
            let inCost = Double(promptTokens) * pIn / 1_000_000
            let outCost = Double(outputTokens) * pOut / 1_000_000
            return inCost + outCost
        }
    }

    public struct GeminiResponse: Sendable {
        public let text: String
        public let usage: GeminiUsage
        public let finishReason: String?
    }

    public enum GeminiError: Error, CustomStringConvertible, Sendable {
        case missingAPIKey
        case invalidURL
        case http(Int, String)
        case decoding(String)
        case empty

        public var description: String {
            switch self {
            case .missingAPIKey: return "Gemini API key absente du Keychain"
            case .invalidURL: return "URL Gemini invalide"
            case .http(let code, let body): return "HTTP \(code): \(body.prefix(200))"
            case .decoding(let reason): return "Decoding: \(reason)"
            case .empty: return "Réponse Gemini vide"
            }
        }
    }

    // MARK: — Public API

    public func sendMessage(
        model: GeminiModel = .flash25,
        system: String? = nil,
        messages: [GeminiMessage],
        maxOutputTokens: Int = 1024
    ) async throws -> GeminiResponse {
        guard let apiKey = IRISKeychain.shared.getGeminiAPIKey() else {
            throw GeminiError.missingAPIKey
        }
        let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/\(model.rawValue):generateContent?key=\(apiKey)"
        guard let url = URL(string: endpoint) else { throw GeminiError.invalidURL }

        var contents: [[String: Any]] = []
        for m in messages {
            contents.append([
                "role": m.role.rawValue,
                "parts": [["text": m.text]],
            ])
        }
        var body: [String: Any] = [
            "contents": contents,
            "generationConfig": [
                "maxOutputTokens": maxOutputTokens,
            ],
        ]
        if let system, !system.isEmpty {
            body["systemInstruction"] = [
                "parts": [["text": system]],
            ]
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GeminiError.http(0, "no response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let snippet = String(data: data, encoding: .utf8) ?? ""
            throw GeminiError.http(http.statusCode, snippet)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GeminiError.decoding("not a JSON object")
        }
        let candidates = (json["candidates"] as? [[String: Any]]) ?? []
        guard let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            throw GeminiError.empty
        }
        let text = parts.compactMap { $0["text"] as? String }.joined(separator: "")
        let finish = first["finishReason"] as? String

        let usageMeta = json["usageMetadata"] as? [String: Any] ?? [:]
        let usage = GeminiUsage(
            promptTokens: (usageMeta["promptTokenCount"] as? Int) ?? 0,
            outputTokens: (usageMeta["candidatesTokenCount"] as? Int) ?? 0,
            totalTokens: (usageMeta["totalTokenCount"] as? Int) ?? 0
        )

        return GeminiResponse(text: text, usage: usage, finishReason: finish)
    }
}

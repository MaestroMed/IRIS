import Foundation

/// Client REST Anthropic Messages API — Swift native, zéro dépendance externe.
/// Utilisé par Conductor (Opus 4.7), Auditor / Quill (Sonnet 4.6), Sentinel / Scribe / Cartographer / Envoy (Haiku 4.5).
///
/// Features v0.1 :
/// - POST /v1/messages (non-streaming)
/// - Prompt caching automatique (cache_control sur system prompt > 1024 tokens estimés)
/// - Cost tracking via usage tokens (returned dans la réponse)
/// - Errors typed (apiError / network / decoding)
/// - API key via Keychain (cf IRISKeychain helper)
///
/// Phases suivantes :
/// - v0.1.1 : streaming via SSE
/// - v0.2 : tool use (function calling) pour les agents qui appellent skills/MCP
/// - v0.3 : retry exponentiel + circuit breaker
public actor AnthropicClient {
    public static let shared = AnthropicClient()

    private let baseURL = URL(string: "https://api.anthropic.com/v1")!
    private let session: URLSession
    private let anthropicVersion = "2023-06-01"
    private let userAgent = "IRIS/0.1 (macOS; app.iris.macos)"

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 180
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
    }

    // MARK: — Public API

    public func sendMessage(
        model: ClaudeModel,
        system: String? = nil,
        messages: [Message],
        maxTokens: Int = 4096,
        cacheSystem: Bool = true
    ) async throws -> MessageResponse {
        guard let apiKey = IRISKeychain.shared.getAnthropicAPIKey() else {
            throw AnthropicError.missingAPIKey
        }

        let requestBody = MessageRequest(
            model: model.rawValue,
            messages: messages,
            system: system.map { systemContent in
                cacheSystem && systemContent.count > 4000  // ~1024 tokens
                    ? [SystemBlock(type: "text", text: systemContent, cacheControl: .init(type: "ephemeral"))]
                    : [SystemBlock(type: "text", text: systemContent, cacheControl: nil)]
            },
            maxTokens: maxTokens
        )

        var request = URLRequest(url: baseURL.appendingPathComponent("messages"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue(userAgent, forHTTPHeaderField: "user-agent")

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(requestBody)

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw AnthropicError.network("Non-HTTP response")
        }

        guard http.statusCode == 200 else {
            // Try parse error structure
            if let errorPayload = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
                throw AnthropicError.apiError(status: http.statusCode, message: errorPayload.error.message, type: errorPayload.error.type)
            }
            let bodyStr = String(data: data, encoding: .utf8) ?? "<unreadable>"
            throw AnthropicError.apiError(status: http.statusCode, message: bodyStr, type: "unknown")
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(MessageResponse.self, from: data)
    }

    // MARK: — Convenience : single turn user → assistant

    public func ask(
        _ userPrompt: String,
        model: ClaudeModel = .opus47,
        system: String? = nil,
        maxTokens: Int = 4096
    ) async throws -> String {
        let response = try await sendMessage(
            model: model,
            system: system,
            messages: [Message(role: .user, content: userPrompt)],
            maxTokens: maxTokens
        )
        return response.firstTextContent ?? ""
    }
}

// MARK: — Models

public enum ClaudeModel: String, Sendable, Codable, CaseIterable {
    case opus47 = "claude-opus-4-7"
    case sonnet46 = "claude-sonnet-4-6"
    case haiku45 = "claude-haiku-4-5-20251001"

    /// Cost per 1M input tokens en USD (à jour 2026-05). Mettre à jour quand la grille bouge.
    public var inputCostPer1M: Double {
        switch self {
        case .opus47: return 15.0
        case .sonnet46: return 3.0
        case .haiku45: return 1.0
        }
    }

    public var outputCostPer1M: Double {
        switch self {
        case .opus47: return 75.0
        case .sonnet46: return 15.0
        case .haiku45: return 5.0
        }
    }

    public var cacheReadCostPer1M: Double {
        // Anthropic prompt caching : 10% du cost input normal pour les reads cachés
        inputCostPer1M * 0.1
    }
}

public struct Message: Codable, Sendable {
    public enum Role: String, Codable, Sendable {
        case user, assistant
    }
    public let role: Role
    public let content: String

    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }
}

struct MessageRequest: Encodable {
    let model: String
    let messages: [Message]
    let system: [SystemBlock]?
    let maxTokens: Int
}

struct SystemBlock: Encodable {
    let type: String
    let text: String
    let cacheControl: CacheControl?

    struct CacheControl: Encodable {
        let type: String
    }
}

public struct MessageResponse: Decodable, Sendable {
    public let id: String
    public let type: String
    public let role: String
    public let model: String
    public let content: [ContentBlock]
    public let stopReason: String?
    public let usage: Usage

    public var firstTextContent: String? {
        content.first(where: { $0.type == "text" })?.text
    }

    public struct ContentBlock: Decodable, Sendable {
        public let type: String
        public let text: String?
    }

    public struct Usage: Decodable, Sendable {
        public let inputTokens: Int
        public let outputTokens: Int
        public let cacheCreationInputTokens: Int?
        public let cacheReadInputTokens: Int?

        public func estimatedCostUSD(model: ClaudeModel) -> Double {
            let cachedRead = cacheReadInputTokens ?? 0
            let cachedCreate = cacheCreationInputTokens ?? 0
            let regularInput = inputTokens - cachedRead - cachedCreate
            let inCost = (Double(max(0, regularInput)) / 1_000_000.0) * model.inputCostPer1M
            let cacheReadCost = (Double(cachedRead) / 1_000_000.0) * model.cacheReadCostPer1M
            // Cache creation costs 25% more than input on Anthropic. Approximation :
            let cacheCreateCost = (Double(cachedCreate) / 1_000_000.0) * model.inputCostPer1M * 1.25
            let outCost = (Double(outputTokens) / 1_000_000.0) * model.outputCostPer1M
            return inCost + cacheReadCost + cacheCreateCost + outCost
        }
    }
}

// MARK: — Errors

public enum AnthropicError: Error, LocalizedError, Sendable {
    case missingAPIKey
    case network(String)
    case apiError(status: Int, message: String, type: String)
    case decoding(String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "Anthropic API key absente du Keychain. Renseigne-la dans Settings."
        case .network(let msg): return "Erreur réseau : \(msg)"
        case .apiError(let status, let msg, let type): return "API error \(status) (\(type)) : \(msg)"
        case .decoding(let msg): return "Erreur décodage : \(msg)"
        }
    }
}

private struct APIErrorResponse: Decodable {
    let type: String
    let error: ErrorPayload
    struct ErrorPayload: Decodable {
        let type: String
        let message: String
    }
}

import Foundation
import SwiftData

/// Quill v0.4 — rédige drafts en réponse aux signaux importants. JAMAIS n'envoie.
/// Subscribe `signalEmitted` importance ≥ 4 → invoke Claude Sonnet 4.6 → publish `draftReady`.
///
/// v0.4 : draft générique (email FR formel client). v1.x : routing tonalité par audience
/// + intégration Scribe pour contexte personnalisé par projet/client.
///
/// Cf docs/IRIS-AGENTS-CATALOG.md §4 Quill.
public actor Quill {
    public static let shared = Quill()

    private var subscriptionTask: Task<Void, Never>?
    private var onCost: ((Double) -> Void)?
    private weak var modelContainer: ModelContainer?

    private init() {}

    public func start(
        modelContainer: ModelContainer,
        onCost: @escaping @Sendable (Double) -> Void
    ) async {
        self.modelContainer = modelContainer
        self.onCost = onCost
        guard subscriptionTask == nil else { return }

        let stream = await EventBus.shared.subscribe()
        subscriptionTask = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                if case .signalEmitted(let from, let importance, let summary, let source) = event,
                   from == .sentinel,
                   importance >= .high {
                    await self.handleSignal(importance: importance, summary: summary, source: source)
                }
            }
        }

        irisLog(.info, "Quill started — listening signals ≥ high", category: IRISLogger.agents)
    }

    public func stop() {
        subscriptionTask?.cancel()
        subscriptionTask = nil
    }

    // MARK: — Drafting

    private static let systemPrompt = """
    Tu es Quill — l'agent rédacteur d'IRIS pour Mehdi (opérateur solo Numelite, agency FR).

    Ta mission : drafter une réponse courte et utile à un signal entrant.
    Tu NE renvoies JAMAIS l'email ; tu produis juste le brouillon. Envoy s'en charge.

    Règles :
    - Style cohérent : direct, no glazing, FR-casual + termes EN techniques quand pertinent
    - Pour les clients (atelier_frisson / az_construction / ief_and_co / sconnect / sconnect / nacks): ton formel-FR poli
    - Pour les internes (github, ci_failure): ton bref technique
    - Adapté à la criticité (importance 4 = posé, importance 5 = urgent + concret)
    - Pas de "great question", pas de "I'd be happy to" — directement utile
    - Format : sujet (1 ligne) + corps (3-8 lignes)

    Output STRICT JSON :
    {"subject": "...", "body": "...", "tone": "formel-fr-client|tech-en-pr|casual-fr-team", "channel": "email|slack|github_comment"}
    """

    private func handleSignal(
        importance: SignalImportance,
        summary: String,
        source: String?
    ) async {
        let userPrompt = """
        Signal entrant à drafter :
        - Source : \(source ?? "inconnu")
        - Importance : \(importance.rawValue)/5
        - Résumé : \(summary)

        Drafte la réponse en JSON strict.
        """

        do {
            let response = try await AnthropicClient.shared.sendMessage(
                model: .sonnet46,
                system: Self.systemPrompt,
                messages: [Message(role: .user, content: userPrompt)],
                maxTokens: 1024,
                cacheSystem: true
            )

            let content = response.firstTextContent ?? "{}"
            let cost = response.usage.estimatedCostUSD(model: .sonnet46)
            onCost?(cost)

            // Parse JSON (best-effort — si malformé, on fallback en texte brut comme body)
            let parsed = Self.parseDraftJSON(content) ?? .init(
                subject: nil,
                body: content,
                tone: "formel-fr-client",
                channel: "email"
            )

            // Persist Draft
            let draftId = UUID()
            if let container = await modelContainer {
                await MainActor.run {
                    let context = container.mainContext
                    let draft = Draft(
                        id: draftId,
                        signalId: nil,  // v0.4 : pas de FK propre ; v0.5+ tracker via correlationId bus
                        audience: "client",
                        channel: parsed.channel,
                        tone: parsed.tone,
                        subject: parsed.subject,
                        content: parsed.body,
                        modelUsed: ClaudeModel.sonnet46.rawValue,
                        costUSD: cost,
                        status: "pending"
                    )
                    context.insert(draft)
                    try? context.save()
                }
            }

            // Publish on bus
            await EventBus.shared.publish(
                .draftReady(
                    draftId: draftId,
                    signalId: nil,
                    channel: parsed.channel,
                    summary: parsed.subject ?? String(parsed.body.prefix(80))
                )
            )

            irisLog(.info,
                "Quill draft ready \(draftId.uuidString.prefix(8)) — channel=\(parsed.channel) cost=$\(String(format: "%.5f", cost))",
                category: IRISLogger.agents
            )
        } catch {
            irisLog(.error, "Quill draft failed: \(error.localizedDescription)", category: IRISLogger.agents)
            await EventBus.shared.publish(.agentFailure(agent: .quill, error: error.localizedDescription))
        }
    }

    // MARK: — Helpers

    private struct ParsedDraft: Sendable {
        let subject: String?
        let body: String
        let tone: String
        let channel: String
    }

    private static func parseDraftJSON(_ raw: String) -> ParsedDraft? {
        // Trim markdown fences si Claude les ajoute parfois
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            // Strip fences
            cleaned = cleaned
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        return ParsedDraft(
            subject: json["subject"] as? String,
            body: (json["body"] as? String) ?? "",
            tone: (json["tone"] as? String) ?? "formel-fr-client",
            channel: (json["channel"] as? String) ?? "email"
        )
    }
}

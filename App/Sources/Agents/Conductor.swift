import Foundation
import SwiftData

/// Conductor — orchestrateur central. v0.0.5 (mock) + v0.1 (LLM réel) + v1.6 (Scribe integration).
///
/// Mode automatique :
/// - Si `IRISKeychain.hasAnthropicAPIKey() == false` → mode mock (echo enrichi)
/// - Sinon → mode LLM (Claude Opus 4.7 + prompt caching + Scribe context retrieval)
///
/// v1.6 — avant chaque appel API : Scribe.retrieve top-3 mémoires pertinentes au query
/// → inject dans system prompt enrichi. Après réponse : store Q/R comme Memory type="conversation".
///
/// Cf docs/IRIS-AGENTS-CATALOG.md §1 Conductor.
public actor Conductor {
    public static let shared = Conductor()

    private var subscriptionTask: Task<Void, Never>?
    private var onCost: ((Double) -> Void)?
    private weak var modelContainer: ModelContainer?

    private init() {}

    /// Démarre l'écoute du bus. À appeler une seule fois au launch (depuis IRISApp).
    public func start(
        modelContainer: ModelContainer? = nil,
        onCost: @escaping @Sendable (Double) -> Void
    ) async {
        self.modelContainer = modelContainer
        self.onCost = onCost
        guard subscriptionTask == nil else { return }

        let stream = await EventBus.shared.subscribe()
        subscriptionTask = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                if case .userInput(let text, _) = event {
                    await self.handleUserInput(text)
                }
            }
        }
        irisLog(.info, "Conductor started (Scribe integration: \(modelContainer != nil ? "ON" : "OFF"))",
                category: IRISLogger.conductor)
    }

    public func stop() {
        subscriptionTask?.cancel()
        subscriptionTask = nil
    }

    // MARK: — Routing

    private func handleUserInput(_ text: String) async {
        let eventId = UUID()
        irisLog(.info, "Conductor handling user input (\(text.prefix(40))…)", category: IRISLogger.conductor)

        let hasKey = IRISKeychain.shared.hasAnthropicAPIKey()
        if hasKey {
            await respondWithClaude(text, eventId: eventId)
        } else {
            await respondMock(text, eventId: eventId)
        }
    }

    // MARK: — Mock mode (sans API key)

    private func respondMock(_ text: String) async {
        await respondMock(text, eventId: UUID())
    }

    private func respondMock(_ text: String, eventId: UUID) async {
        let response = """
        [mode mock — API key Anthropic absente du Keychain]

        Tu as dit : "\(text)"

        Ajoute ta clé API dans Settings (Cmd+,) pour activer le Conductor Claude Opus 4.7.
        """
        await EventBus.shared.publish(
            .agentResponse(from: .conductor, content: response, eventId: eventId)
        )
    }

    // MARK: — Live mode (Claude Opus)

    private static let systemPrompt = """
    Tu es Conductor — l'agent orchestrateur central d'IRIS, l'exocortex local desktop de Mehdi (opérateur solo Numelite).

    Ton rôle :
    - Recevoir les inputs de Mehdi en français (sa langue principale, mix avec termes EN techniques)
    - Comprendre l'intent en 1 phrase
    - Pour v0.1, tu réponds directement (les autres agents arriveront en v0.3+)
    - Style : direct, no glazing, dense, FR-casual + termes EN techniques quand pertinent
    - Pas de "great choice!", pas de "I'd be happy to help" — exécute

    Tu connais le contexte IRIS :
    - Stack : Mac native SwiftUI + Tuist + SwiftData + macOS 26
    - 10 agents prévus : Conductor (toi), Sentinel, Scribe, Quill, Auditor, Cartographer, Builder, Envoy, Witness, Advisor
    - Phases : v0.1 (toi seul actif), v0.3 (Sentinel Gmail), v0.5 (Quill+Envoy email loop), v1.0 (10 agents), v1.5+ (eyes), v2.0+ (cloud sync MIND)
    - Sister project : MIND iOS (cockpit Numelite pour ses clients)

    Si Mehdi te demande un truc qui requiert un autre agent pas encore actif, dis-le franchement.
    """

    private func respondWithClaude(_ text: String, eventId: UUID) async {
        // v1.6 — retrieve top-3 mémoires pertinentes via Scribe avant l'appel LLM
        let memoriesContext = await retrieveMemoryContext(query: text, topK: 3)
        let enrichedSystemPrompt = memoriesContext.isEmpty
            ? Self.systemPrompt
            : Self.systemPrompt + "\n\n## Mémoires pertinentes (Scribe top-3 par similarité)\n\n" + memoriesContext

        do {
            let response = try await AnthropicClient.shared.sendMessage(
                model: .opus47,
                system: enrichedSystemPrompt,
                messages: [Message(role: .user, content: text)],
                maxTokens: 2048,
                cacheSystem: true
            )

            let content = response.firstTextContent ?? "[réponse vide]"
            let cost = response.usage.estimatedCostUSD(model: .opus47)
            onCost?(cost)

            irisLog(.info,
                "Conductor response \(response.usage.inputTokens)in + \(response.usage.outputTokens)out = $\(String(format: "%.4f", cost)) memories=\(memoriesContext.isEmpty ? 0 : 3)",
                category: IRISLogger.conductor
            )

            await EventBus.shared.publish(
                .agentResponse(from: .conductor, content: content, eventId: eventId)
            )

            // v1.6 — store Q/R as Memory pour calibration future (Quill / Advisor / retrieval)
            await storeConversationMemory(query: text, response: content)
        } catch {
            irisLog(.error, "Conductor LLM failed: \(error.localizedDescription)", category: IRISLogger.conductor)
            await EventBus.shared.publish(
                .agentFailure(agent: .conductor, error: error.localizedDescription)
            )
        }
    }

    // MARK: — v1.6 Scribe integration

    /// Retrieve top-K mémoires pertinentes à un query via Scribe. Retourne string formaté pour system prompt.
    private func retrieveMemoryContext(query: String, topK: Int) async -> String {
        guard let container = modelContainer else { return "" }
        return await Self.fetchMemoryContext(container: container, query: query, topK: topK)
    }

    /// MainActor-isolated helper : accès au ModelContext + appel Scribe.retrieve + format String Sendable.
    @MainActor
    private static func fetchMemoryContext(
        container: ModelContainer,
        query: String,
        topK: Int
    ) async -> String {
        let context = container.mainContext
        let results = await Scribe.retrieve(
            query: query,
            topK: topK,
            type: nil,
            projectScope: nil,
            in: context
        )

        guard !results.isEmpty else { return "" }

        return results.enumerated().map { idx, item in
            let (memory, score) = item
            let scope = memory.projectScope.map { " [\($0)]" } ?? ""
            let scoreStr = String(format: "%.2f", score)
            return """
            ### \(idx + 1). \(memory.name)\(scope) — similarité \(scoreStr)
            **Type** : \(memory.type)
            \(memory.summary.isEmpty ? memory.content : memory.summary)
            """
        }.joined(separator: "\n\n")
    }

    /// Store Q/R user/conductor comme Memory type="conversation". Indexe via Scribe automatiquement.
    private func storeConversationMemory(query: String, response: String) async {
        guard let container = modelContainer else { return }
        await Self.persistConversation(container: container, query: query, response: response)
    }

    @MainActor
    private static func persistConversation(
        container: ModelContainer,
        query: String,
        response: String
    ) async {
        let summary = String(query.prefix(120))
        let content = """
        ## Question utilisateur
        \(query)

        ## Réponse Conductor
        \(response)
        """

        let memory = Memory(
            type: "conversation",
            name: "conv-\(Int(Date().timeIntervalSince1970))",
            summary: summary,
            content: content,
            sourceAgent: AgentID.conductor.rawValue,
            projectScope: nil,
            tagsCSV: "conversation,conductor"
        )

        await Scribe.store(memory: memory, in: container.mainContext)
    }
}

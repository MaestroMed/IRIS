import Foundation

/// Conductor — orchestrateur central. v0.0.5 (mock) + v0.1 (LLM réel via Anthropic).
///
/// Mode automatique :
/// - Si `IRISKeychain.hasAnthropicAPIKey() == false` → mode mock (echo enrichi)
/// - Sinon → mode LLM (Claude Opus 4.7 + prompt caching)
///
/// Subscribe au bus au démarrage (`start()`), écoute `IRISEvent.userInput`, publie `.agentResponse`
/// ou `.agentFailure` selon issue. Persiste tout dans EventLog SwiftData (via callback fourni).
///
/// Cf docs/IRIS-AGENTS-CATALOG.md §1 Conductor.
public actor Conductor {
    public static let shared = Conductor()

    private var subscriptionTask: Task<Void, Never>?
    private var onCost: ((Double) -> Void)?

    private init() {}

    /// Démarre l'écoute du bus. À appeler une seule fois au launch (depuis IRISApp).
    public func start(onCost: @escaping @Sendable (Double) -> Void) async {
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
        irisLog(.info, "Conductor started", category: IRISLogger.conductor)
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
        do {
            let response = try await AnthropicClient.shared.sendMessage(
                model: .opus47,
                system: Self.systemPrompt,
                messages: [Message(role: .user, content: text)],
                maxTokens: 2048,
                cacheSystem: true
            )

            let content = response.firstTextContent ?? "[réponse vide]"
            let cost = response.usage.estimatedCostUSD(model: .opus47)
            onCost?(cost)

            irisLog(.info,
                "Conductor response \(response.usage.inputTokens)in + \(response.usage.outputTokens)out = $\(String(format: "%.4f", cost))",
                category: IRISLogger.conductor
            )

            await EventBus.shared.publish(
                .agentResponse(from: .conductor, content: content, eventId: eventId)
            )
        } catch {
            irisLog(.error, "Conductor LLM failed: \(error.localizedDescription)", category: IRISLogger.conductor)
            await EventBus.shared.publish(
                .agentFailure(agent: .conductor, error: error.localizedDescription)
            )
        }
    }
}

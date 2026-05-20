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
    private var onCost: CostSink?
    private weak var modelContainer: ModelContainer?

    /// v1.54 — Task de la réponse en cours, pour permettre l'annulation user.
    private var currentResponseTask: Task<Void, Never>?

    /// v1.19 — history derniers échanges (alternance user/assistant) pour multi-turn dialog.
    /// Max 10 paires = 20 messages pour éviter explosion context.
    private var conversationHistory: [Message] = []
    private let maxHistoryPairs = 10

    private init() {}

    /// v1.19 — Reset conversation (nouvelle session dialog).
    public func resetHistory() {
        conversationHistory.removeAll()
        irisLog(.info, "Conductor conversation history reset", category: IRISLogger.conductor)
    }

    /// v1.31 — Restore conversationHistory depuis EventLog SwiftData.
    /// Au launch IRIS, repopulate derniers échanges Conductor pour continuité cross-launch.
    public func restoreHistory(from container: ModelContainer) async {
        // Skip si déjà des messages (start déjà fait restore — idempotence)
        guard conversationHistory.isEmpty else { return }
        let messages = await Self.fetchRecentMessages(container: container, limit: maxHistoryPairs * 2)
        conversationHistory = messages
        if !messages.isEmpty {
            irisLog(.info, "Conductor history restored \(messages.count) msgs from EventLog", category: IRISLogger.conductor)
        }
    }

    @MainActor
    private static func fetchRecentMessages(container: ModelContainer, limit: Int) async -> [Message] {
        var descriptor = FetchDescriptor<EventLog>(
            predicate: #Predicate {
                $0.kind == "userInput" || ($0.kind == "agentResponse" && $0.fromAgent == "conductor")
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        let events = (try? container.mainContext.fetch(descriptor)) ?? []
        // events arrive en order desc → reverse pour avoir chrono croissant
        return events.reversed().compactMap { event -> Message? in
            guard let data = event.payloadJSON.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }
            if event.kind == "userInput" {
                if let text = json["text"] as? String, !text.isEmpty {
                    return Message(role: .user, content: text)
                }
            } else if event.kind == "agentResponse" {
                if let content = json["content"] as? String, !content.isEmpty {
                    return Message(role: .assistant, content: content)
                }
            }
            return nil
        }
    }

    private func appendToHistory(_ message: Message) {
        conversationHistory.append(message)
        if conversationHistory.count > maxHistoryPairs * 2 {
            let excess = conversationHistory.count - maxHistoryPairs * 2
            conversationHistory.removeFirst(excess)
        }
    }

    /// Démarre l'écoute du bus. À appeler une seule fois au launch (depuis IRISApp).
    public func start(
        modelContainer: ModelContainer? = nil,
        onCost: @escaping CostSink
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

    /// v1.54 — Annule la réponse en cours (stream SSE Claude). Le streamMessage for-await throws
    /// CancellationError → catch publie le partial accumulé + tag annulée.
    public func cancelCurrentResponse() {
        currentResponseTask?.cancel()
        currentResponseTask = nil
    }

    /// v1.54 — Indique si une réponse Conductor est actuellement en cours (pour UI Stop button).
    public var isResponding: Bool {
        currentResponseTask != nil && !(currentResponseTask?.isCancelled ?? true)
    }

    // MARK: — Routing

    private func handleUserInput(_ text: String) async {
        let eventId = UUID()
        irisLog(.info, "Conductor handling user input (\(text.prefix(40))…)", category: IRISLogger.conductor)

        let hasKey = IRISKeychain.shared.hasAnthropicAPIKey()
        // v1.54 — wrap dans Task pour permettre cancel via cancelCurrentResponse()
        let task = Task { [weak self] in
            guard let self else { return }
            if hasKey {
                await self.respondWithClaude(text, eventId: eventId)
            } else {
                await self.respondMock(text, eventId: eventId)
            }
        }
        currentResponseTask = task
        await task.value
        currentResponseTask = nil
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

    /// v1.42 — System prompt par défaut, peut être overridé via UserDefaults.
    private static let systemPromptOverrideKey = "iris.conductor.systemPromptOverride"

    public static let defaultSystemPrompt = """
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

    /// Computed : si UserDefaults contient un override non-vide, l'utilise. Sinon le defaultSystemPrompt.
    private static var systemPrompt: String {
        if let override = UserDefaults.standard.string(forKey: systemPromptOverrideKey),
           !override.trimmingCharacters(in: .whitespaces).isEmpty {
            return override
        }
        return defaultSystemPrompt
    }

    /// Public — lecture du system prompt actuellement utilisé (override OU default).
    public static func currentSystemPrompt() -> String {
        systemPrompt
    }

    /// Public — set override (nil = reset au default).
    public static func setSystemPromptOverride(_ override: String?) {
        if let override, !override.trimmingCharacters(in: .whitespaces).isEmpty {
            UserDefaults.standard.set(override, forKey: systemPromptOverrideKey)
        } else {
            UserDefaults.standard.removeObject(forKey: systemPromptOverrideKey)
        }
    }

    // MARK: — v1.47 Model picker (Opus / Sonnet / Haiku)

    private static let modelKey = "iris.conductor.model"

    /// Modèle actuel : lit UserDefaults, fallback opus47.
    public static var currentModel: ClaudeModel {
        if let raw = UserDefaults.standard.string(forKey: modelKey),
           let model = ClaudeModel(rawValue: raw) {
            return model
        }
        return .opus47
    }

    public static func setModel(_ model: ClaudeModel) {
        UserDefaults.standard.set(model.rawValue, forKey: modelKey)
    }

    private func respondWithClaude(_ text: String, eventId: UUID) async {
        // v1.6 — retrieve top-3 mémoires pertinentes via Scribe avant l'appel LLM
        let memoriesContext = await retrieveMemoryContext(query: text, topK: 3)
        // v1.25 — récupère le contexte Witness le plus récent (frontmost app/project)
        let witnessContext = await retrieveWitnessContext()

        var enrichedSystemPrompt = Self.systemPrompt
        if !witnessContext.isEmpty {
            enrichedSystemPrompt += "\n\n## Contexte actuel Mehdi (Witness, < 60s)\n\n" + witnessContext
        }
        if !memoriesContext.isEmpty {
            enrichedSystemPrompt += "\n\n## Mémoires pertinentes (Scribe top-3 par similarité)\n\n" + memoriesContext
        }

        // v1.17 + v1.19 — streaming SSE + multi-turn history
        // v1.47 — model depuis UserDefaults
        let currentModel = Self.currentModel
        appendToHistory(Message(role: .user, content: text))
        var accumulated = ""
        let costCallback = onCost  // @Sendable capture (typed property)
        let history = conversationHistory  // snapshot pour l'appel

        let stream = AnthropicClient.shared.streamMessage(
            model: currentModel,
            system: enrichedSystemPrompt,
            messages: history,  // v1.19 : envoie tout l'history (alternance user/assistant)
            maxTokens: 2048,
            cacheSystem: true,
            onUsage: { usage in
                let cost = usage.estimatedCostUSD(model: currentModel)
                costCallback?(cost, currentModel.rawValue)
            }
        )

        do {
            for try await delta in stream {
                accumulated += delta
                await EventBus.shared.publish(
                    .conductorChunk(eventId: eventId, delta: delta)
                )
            }

            // v1.19 — append assistant response to history for next turn
            appendToHistory(Message(role: .assistant, content: accumulated))

            irisLog(.info,
                "Conductor stream done — \(accumulated.count) chars memories=\(memoriesContext.isEmpty ? 0 : 3) history=\(conversationHistory.count) msgs",
                category: IRISLogger.conductor
            )

            await EventBus.shared.publish(
                .agentResponse(from: .conductor, content: accumulated, eventId: eventId)
            )

            // v1.6 — store Q/R as Memory pour calibration future (Quill / Advisor / retrieval)
            await storeConversationMemory(query: text, response: accumulated)
        } catch is CancellationError {
            // v1.54 — Annulation user. Publie le partial accumulé + tag.
            let final = accumulated + "\n\n_[génération annulée]_"
            appendToHistory(Message(role: .assistant, content: final))
            irisLog(.info, "Conductor stream cancelled by user — \(accumulated.count) chars partial",
                    category: IRISLogger.conductor)
            await EventBus.shared.publish(
                .agentResponse(from: .conductor, content: final, eventId: eventId)
            )
        } catch {
            irisLog(.error, "Conductor stream failed: \(error.localizedDescription)", category: IRISLogger.conductor)
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

    // MARK: — v1.25 Witness context

    /// Récupère le dernier Signal source="screen" Witness (frontmost app/project) si récent (<60s).
    private func retrieveWitnessContext() async -> String {
        guard let container = modelContainer else { return "" }
        return await Self.fetchWitnessContext(container: container)
    }

    @MainActor
    private static func fetchWitnessContext(container: ModelContainer) async -> String {
        let cutoff = Date().addingTimeInterval(-60)
        var descriptor = FetchDescriptor<Signal>(
            predicate: #Predicate { $0.source == "screen" && $0.emittedAt > cutoff },
            sortBy: [SortDescriptor(\.emittedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        let results = (try? container.mainContext.fetch(descriptor)) ?? []
        guard let signal = results.first else { return "" }
        return signal.summary
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

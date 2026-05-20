import SwiftUI
import SwiftData

// IRIS v0.0.5 / v0.1 — entry point.
// - ModelContainer SwiftData wired (6 modèles)
// - AgentSeeder au premier launch
// - Conductor démarré (subscribe au bus + handler userInput)
// - EventBus → AppState transcript bridge
// - SettingsView via Cmd+, ou menu

@main
struct IRISApp: App {
    @State private var appState = IRISAppState()
    @State private var bridge: EventBusBridge?

    private let modelContainer: ModelContainer = ModelContainerFactory.makeLocalContainer()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .modelContainer(modelContainer)
                .frame(minWidth: 1100, minHeight: 700)
                .task {
                    await bootstrap()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 1400, height: 900)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    NSApplication.openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandGroup(after: .appInfo) {
                Divider()
                Button("À propos d'IRIS") {
                    NSApplication.shared.orderFrontStandardAboutPanel(nil)
                }
            }
        }

        Settings {
            SettingsView()
                .environment(appState)
        }
    }

    // MARK: — Bootstrap

    @MainActor
    private func bootstrap() async {
        // 1. Seed agents si nécessaire
        let context = modelContainer.mainContext
        AgentSeeder.seedIfNeeded(in: context)

        // 2. Bridge EventBus → AppState transcript
        if bridge == nil {
            bridge = EventBusBridge(appState: appState, modelContext: context)
            await bridge?.start()
        }

        // 3. Conductor démarre + écoute userInput
        let costSink: @Sendable (Double) -> Void = { cost in
            Task { @MainActor in
                appState.sessionCostUSD += cost
            }
        }
        await Conductor.shared.start(onCost: costSink)

        // 4. Quill démarre — listen signaux importance ≥ 4, drafte via Sonnet
        await Quill.shared.start(modelContainer: modelContainer, onCost: costSink)

        // 5. Envoy démarre — listen draftReady, propose actionRequested + executeApproved
        await Envoy.shared.start(modelContainer: modelContainer)

        // 6. Sentinel démarre — stub signaux fictifs toutes les 60s (v0.3.5+ : vrai MCP Gmail)
        await Sentinel.shared.start(modelContainer: modelContainer, intervalSeconds: 60)

        // 7. Cartographer démarre — scan ~/Developer + gh repo list MaestroMed (refresh 6h)
        await Cartographer.shared.start(modelContainer: modelContainer)

        // 8. Auditor démarre — on-demand audit via UI (v0.7 mock)
        await Auditor.shared.start(modelContainer: modelContainer)

        // 9. Builder démarre — scaffold on-demand via UI (v0.8 mock)
        await Builder.shared.start(modelContainer: modelContainer)

        // 10. Advisor démarre — briefing scheduled 8h00 + manual on-demand
        await Advisor.shared.start(modelContainer: modelContainer, onCost: costSink)

        irisLog(.info, "IRIS bootstrapped — 10 agents live (Conductor + Sentinel + Scribe + Quill + Envoy + Cartographer + Auditor + Builder + Advisor)",
                category: IRISLogger.ui)
    }
}

// MARK: — NSApplication settings helper (workaround : SwiftUI Settings scene)

extension NSApplication {
    /// Ouvre la scene Settings native macOS (SwiftUI Settings { ... } scène).
    static func openSettings() {
        if #available(macOS 14, *) {
            // macOS 14+ : action standard
            let selector = Selector(("showSettingsWindow:"))
            if NSApp.responds(to: selector) {
                NSApp.perform(selector, with: nil)
                return
            }
        }
        // Fallback legacy macOS 13
        let selector = Selector(("showPreferencesWindow:"))
        if NSApp.responds(to: selector) {
            NSApp.perform(selector, with: nil)
        }
    }
}

// MARK: — Bridge EventBus → AppState (UI live) + SwiftData EventLog (persistance)

@MainActor
final class EventBusBridge {
    private let appState: IRISAppState
    private let modelContext: ModelContext
    private var task: Task<Void, Never>?

    init(appState: IRISAppState, modelContext: ModelContext) {
        self.appState = appState
        self.modelContext = modelContext
    }

    func start() async {
        guard task == nil else { return }
        let stream = await EventBus.shared.subscribe()
        task = Task { @MainActor [weak self] in
            for await event in stream {
                self?.handle(event)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func handle(_ event: IRISEvent) {
        switch event {
        case .userInput(let text, let timestamp):
            // Le user input est déjà ajouté au transcript par MainCanvasView.submitInput()
            // (pour latence UI < 16ms). On persiste juste dans EventLog ici.
            persist(.userInput(text, timestamp: timestamp), payload: ["text": text])

        case .agentResponse(let from, let content, let eventId):
            appState.appendEntry(TranscriptEntry(role: .agent(from), content: content))
            appState.isProcessing = false
            persist(event, payload: ["content": content, "correlationId": eventId.uuidString], from: from.rawValue, correlationId: eventId)

        case .agentDispatched(let from, let to, let intent, let eventId):
            persist(event, payload: ["intent": intent], from: from.rawValue, to: to.rawValue, correlationId: eventId)

        case .signalEmitted(let from, let importance, let summary, let source):
            persist(event, payload: ["importance": "\(importance.rawValue)", "summary": summary, "source": source ?? "—"], from: from.rawValue)

        case .actionLogged(let by, let action, let params, let reversible):
            var p = params
            p["action"] = action
            p["reversible"] = "\(reversible)"
            persist(event, payload: p, from: by.rawValue)

        case .agentFailure(let agent, let error):
            appState.appendEntry(TranscriptEntry(
                role: .system(level: "error"),
                content: "⚠️ \(agent.rawValue) : \(error)"
            ))
            appState.lastError = error
            appState.isProcessing = false
            persist(event, payload: ["error": error], from: agent.rawValue)

        case .systemLog(let level, let message, let file, let line):
            appState.appendEntry(TranscriptEntry(
                role: .system(level: level.rawValue),
                content: "[\(level.rawValue)] \(message) (\(file):\(line))"
            ))
            persist(event, payload: ["level": level.rawValue, "message": message, "file": file, "line": "\(line)"])

        case .draftReady(let draftId, _, let channel, let summary):
            appState.appendEntry(TranscriptEntry(
                role: .agent(.quill),
                content: "📝 Draft \(channel) : \(summary)"
            ))
            persist(event, payload: ["draftId": draftId.uuidString, "channel": channel, "summary": summary], from: AgentID.quill.rawValue)

        case .actionRequested(let actionId, let agent, let summary, let isReversible):
            let banner = isReversible ? "" : " (irréversible)"
            appState.pendingActions.append(PendingActionUI(
                actionId: actionId,
                agentName: agent.descriptor.displayName,
                summary: summary,
                isReversible: isReversible
            ))
            appState.appendEntry(TranscriptEntry(
                role: .system(level: "notice"),
                content: "✋ Action proposée par \(agent.rawValue)\(banner) : \(summary). Approve dans l'Inspector."
            ))
            persist(event, payload: ["actionId": actionId.uuidString, "summary": summary, "reversible": "\(isReversible)"], from: agent.rawValue)

        case .actionApproved(let actionId, let approvedAt):
            appState.pendingActions.removeAll { $0.actionId == actionId }
            persist(event, payload: ["actionId": actionId.uuidString, "at": "\(approvedAt)"])

        case .actionRejected(let actionId, let reason):
            appState.pendingActions.removeAll { $0.actionId == actionId }
            appState.appendEntry(TranscriptEntry(
                role: .system(level: "notice"),
                content: "❌ Action \(actionId.uuidString.prefix(8)) rejetée. Raison : \(reason ?? "—")"
            ))
            persist(event, payload: ["actionId": actionId.uuidString, "reason": reason ?? ""])

        case .actionExecuted(let actionId, let success, let result):
            let icon = success ? "✅" : "⚠️"
            appState.appendEntry(TranscriptEntry(
                role: .agent(.envoy),
                content: "\(icon) Action exécutée \(actionId.uuidString.prefix(8)) : \(result)"
            ))
            persist(event, payload: ["actionId": actionId.uuidString, "success": "\(success)", "result": result], from: AgentID.envoy.rawValue)
        }
    }

    private func persist(
        _ event: IRISEvent,
        payload: [String: String],
        from: String? = nil,
        to: String? = nil,
        correlationId: UUID? = nil
    ) {
        let kind: String = {
            switch event {
            case .userInput: return "userInput"
            case .agentDispatched: return "agentDispatched"
            case .agentResponse: return "agentResponse"
            case .signalEmitted: return "signalEmitted"
            case .actionLogged: return "actionLogged"
            case .agentFailure: return "agentFailure"
            case .systemLog: return "systemLog"
            case .draftReady: return "draftReady"
            case .actionRequested: return "actionRequested"
            case .actionApproved: return "actionApproved"
            case .actionRejected: return "actionRejected"
            case .actionExecuted: return "actionExecuted"
            }
        }()

        let json = (try? JSONSerialization.data(withJSONObject: payload, options: []))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

        let log = EventLog(
            timestamp: event.timestamp,
            kind: kind,
            fromAgent: from,
            toAgent: to,
            payloadJSON: json,
            correlationId: correlationId
        )
        modelContext.insert(log)
        // Best-effort save : si ça échoue, on log via os_log mais on n'explose pas.
        do {
            try modelContext.save()
        } catch {
            IRISLogger.store.error("EventLog persist failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

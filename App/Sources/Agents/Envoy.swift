import Foundation
import SwiftData

/// Envoy v0.5 — actions externes irréversibles. STUB (mock send) en v0.5.
/// v0.5.5+ : remplace mock par vrais appels MCP Gmail send, GitHub PR create, etc.
///
/// Flow :
/// 1. Subscribe `draftReady` → auto-publish `actionRequested` (isReversible: false pour email)
/// 2. Subscribe `actionApproved` (user a cliqué Approve dans UI) → execute mock
/// 3. Publish `actionExecuted` + ActionLog append-only
///
/// Cf docs/IRIS-AGENTS-CATALOG.md §8 Envoy + archi §6.2 user approval + §6.3 reversibilité.
public actor Envoy {
    public static let shared = Envoy()

    private var subscriptionTask: Task<Void, Never>?
    private weak var modelContainer: ModelContainer?

    /// Actions en attente d'approbation user. actionId → draftId (pour retrouver le draft à envoyer).
    private var pending: [UUID: UUID] = [:]

    private init() {}

    public func start(modelContainer: ModelContainer) async {
        self.modelContainer = modelContainer
        guard subscriptionTask == nil else { return }

        let stream = await EventBus.shared.subscribe()
        subscriptionTask = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                await self.handle(event)
            }
        }

        irisLog(.info, "Envoy started — waiting draftReady + actionApproved events", category: IRISLogger.agents)
    }

    public func stop() {
        subscriptionTask?.cancel()
        subscriptionTask = nil
    }

    // MARK: — Event handling

    private func handle(_ event: IRISEvent) async {
        switch event {
        case .draftReady(let draftId, _, let channel, let summary):
            await proposeAction(draftId: draftId, channel: channel, summary: summary)

        case .actionApproved(let actionId, _):
            await executeAction(actionId: actionId)

        case .actionRejected(let actionId, let reason):
            await rejectAction(actionId: actionId, reason: reason)

        default:
            break
        }
    }

    private func proposeAction(draftId: UUID, channel: String, summary: String) async {
        let actionId = UUID()
        pending[actionId] = draftId

        let actionSummary = "Envoyer \(channel) : \(summary.prefix(80))"
        await EventBus.shared.publish(
            .actionRequested(
                actionId: actionId,
                agent: .envoy,
                summary: actionSummary,
                isReversible: false  // email / post = jamais réversible
            )
        )

        irisLog(.notice,
            "Envoy proposed action \(actionId.uuidString.prefix(8)) (draft=\(draftId.uuidString.prefix(8))) channel=\(channel)",
            category: IRISLogger.agents
        )
    }

    private func executeAction(actionId: UUID) async {
        guard let draftId = pending.removeValue(forKey: actionId) else {
            irisLog(.warning, "Envoy: actionId \(actionId) inconnu (déjà exécuté ?)", category: IRISLogger.agents)
            return
        }

        // v0.5 MOCK : on log + on update Draft.status = "sent" + on append ActionLog.
        // v0.5.5+ : on appellera vraiment MCP Gmail send ici.
        var resultText = "MOCK SEND — aucune action réelle effectuée. v0.5.5+ : MCP Gmail send wired."

        if let container = await modelContainer {
            await MainActor.run {
                let context = container.mainContext

                // Update Draft
                let descriptor = FetchDescriptor<Draft>(predicate: #Predicate { $0.id == draftId })
                if let draft = (try? context.fetch(descriptor))?.first {
                    draft.status = "sent"
                    draft.sentAt = .now
                    resultText = "MOCK SEND OK — draft \(draftId.uuidString.prefix(8)) marqué sent (channel=\(draft.channel))"
                }

                // Append ActionLog (append-only)
                let log = ActionLog(
                    agentId: AgentID.envoy.rawValue,
                    actionType: "email.send.mock",
                    paramsJSON: "{\"draftId\":\"\(draftId.uuidString)\",\"actionId\":\"\(actionId.uuidString)\"}",
                    resultJSON: "{\"result\":\"\(resultText)\"}",
                    success: true,
                    reversible: false,
                    executedByUserApproval: true
                )
                context.insert(log)
                try? context.save()
            }
        }

        await EventBus.shared.publish(
            .actionExecuted(actionId: actionId, success: true, result: resultText)
        )

        irisLog(.notice,
            "Envoy executed (MOCK) action \(actionId.uuidString.prefix(8))",
            category: IRISLogger.agents
        )
    }

    private func rejectAction(actionId: UUID, reason: String?) async {
        guard let draftId = pending.removeValue(forKey: actionId) else { return }

        if let container = await modelContainer {
            await MainActor.run {
                let context = container.mainContext
                let descriptor = FetchDescriptor<Draft>(predicate: #Predicate { $0.id == draftId })
                if let draft = (try? context.fetch(descriptor))?.first {
                    draft.status = "rejected"
                    draft.rejectionReason = reason
                }
                try? context.save()
            }
        }

        irisLog(.notice,
            "Envoy rejected action \(actionId.uuidString.prefix(8)) — reason=\(reason ?? "—")",
            category: IRISLogger.agents
        )
    }
}

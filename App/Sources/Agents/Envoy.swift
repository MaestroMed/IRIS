import Foundation
import SwiftData
import AppKit

/// Envoy v1.344 — actions externes irréversibles. Real send (Mail.app handoff + generic webhook POST).
/// channel="email" / "mail" → opens Mail.app via mailto: URL (subject + body pré-remplis, Mehdi voit le draft et choisit envoyer/modifier).
/// channel="webhook" / "post" → POST JSON {channel, subject, content, draftId, timestamp} vers URL configurée
///   dans Settings → Envoy webhook (UserDefaults key `envoyWebhookURL`, ex: Slack incoming hook, Discord, n8n).
/// Fallback : si channel inconnu mais webhook URL configurée → POST. Sinon skip avec actionType "skip.no-channel".
///
/// Flow :
/// 1. Subscribe `draftReady` → auto-publish `actionRequested` (isReversible: false pour email/webhook)
/// 2. Subscribe `actionApproved` (user a cliqué Approve dans UI) → execute real send
/// 3. Publish `actionExecuted` + ActionLog append-only (success bool + actionType précis)
///
/// Cf docs/IRIS-AGENTS-CATALOG.md §8 Envoy + archi §6.2 user approval + §6.3 reversibilité.
public actor Envoy {
    public static let shared = Envoy()

    private var subscriptionTask: Task<Void, Never>?
    private weak var modelContainer: ModelContainer?

    /// Actions en attente d'approbation user. actionId → draftId (pour retrouver le draft à envoyer).
    private var pending: [UUID: UUID] = [:]

    /// v1.344 — snapshot Sendable du Draft pour passer la frontière actor sans @Model.
    private struct DraftSnapshot: Sendable {
        let id: UUID
        let channel: String
        let subject: String?
        let content: String
    }

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

        guard let container = await modelContainer else {
            irisLog(.warning, "Envoy: no modelContainer for action \(actionId)", category: IRISLogger.agents)
            return
        }

        // 1. Fetch Draft into a Sendable snapshot (MainActor — Draft is @Model, not actor-safe).
        let snapshot: DraftSnapshot? = await MainActor.run {
            let context = container.mainContext
            let descriptor = FetchDescriptor<Draft>(predicate: #Predicate { $0.id == draftId })
            guard let draft = (try? context.fetch(descriptor))?.first else { return nil }
            return DraftSnapshot(
                id: draft.id,
                channel: draft.channel,
                subject: draft.subject,
                content: draft.content
            )
        }

        guard let snap = snapshot else {
            irisLog(.warning, "Envoy: draft \(draftId) introuvable", category: IRISLogger.agents)
            return
        }

        // 2. Perform real send off-MainActor.
        let outcome = await performRealSend(draft: snap)

        // 3. Update Draft.status + append ActionLog on MainActor.
        await MainActor.run {
            let context = container.mainContext
            let descriptor = FetchDescriptor<Draft>(predicate: #Predicate { $0.id == draftId })
            if let draft = (try? context.fetch(descriptor))?.first {
                if outcome.success {
                    draft.status = "sent"
                    draft.sentAt = .now
                } else {
                    draft.status = "error"
                    draft.rejectionReason = outcome.result
                }
            }

            let resultEscaped = outcome.result
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            let log = ActionLog(
                agentId: AgentID.envoy.rawValue,
                actionType: outcome.actionType,
                paramsJSON: "{\"draftId\":\"\(draftId.uuidString)\",\"actionId\":\"\(actionId.uuidString)\",\"channel\":\"\(snap.channel)\"}",
                resultJSON: "{\"result\":\"\(resultEscaped)\"}",
                success: outcome.success,
                reversible: false,
                executedByUserApproval: true
            )
            context.insert(log)
            try? context.save()
        }

        // 4. Publish actionExecuted with real success/result.
        await EventBus.shared.publish(
            .actionExecuted(actionId: actionId, success: outcome.success, result: outcome.result)
        )

        irisLog(.notice,
            "Envoy executed action \(actionId.uuidString.prefix(8)) — \(outcome.actionType) success=\(outcome.success)",
            category: IRISLogger.agents
        )
    }

    // MARK: — Real send (v1.344)

    private func performRealSend(draft: DraftSnapshot) async -> (success: Bool, result: String, actionType: String) {
        switch draft.channel.lowercased() {
        case "email", "mail":
            return await sendViaMail(draft: draft)
        case "webhook", "post":
            return await sendViaWebhook(draft: draft)
        default:
            // Fallback : tente webhook si URL configurée, sinon skip.
            let webhookURL = UserDefaults.standard.string(forKey: "envoyWebhookURL") ?? ""
            if !webhookURL.isEmpty {
                return await sendViaWebhook(draft: draft)
            }
            return (false, "Channel '\(draft.channel)' non supporté + pas de webhook configuré", "skip.no-channel")
        }
    }

    private func sendViaMail(draft: DraftSnapshot) async -> (success: Bool, result: String, actionType: String) {
        // Mail.app handoff via mailto: URL. Mehdi voit le draft pré-rempli + choisit envoyer/modifier.
        let subject = draft.subject ?? "(no subject)"
        let body = draft.content
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = ""  // empty recipient → Mail.app demande à Mehdi
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body),
        ]
        guard let url = components.url else {
            return (false, "Mailto URL invalide", "email.mailto.invalid")
        }
        let ok = await MainActor.run { NSWorkspace.shared.open(url) }
        if ok {
            return (true, "Mail.app ouvert avec draft pré-rempli (subject=\(subject.prefix(40)))", "email.mailto.opened")
        }
        return (false, "Mail.app n'a pas pu être ouvert", "email.mailto.failed")
    }

    private func sendViaWebhook(draft: DraftSnapshot) async -> (success: Bool, result: String, actionType: String) {
        let urlString = UserDefaults.standard.string(forKey: "envoyWebhookURL") ?? ""
        guard !urlString.isEmpty, let url = URL(string: urlString) else {
            return (false, "Webhook URL non configurée (Settings → Envoy)", "webhook.no-url")
        }
        let payload: [String: Any] = [
            "channel": draft.channel,
            "subject": draft.subject ?? "",
            "content": draft.content,
            "draftId": draft.id.uuidString,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            return (false, "Sérialisation payload échouée", "webhook.serialize.failed")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("IRIS-Envoy/1.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = body
        request.timeoutInterval = 15
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return (false, "Réponse webhook non HTTP", "webhook.invalid-response")
            }
            if (200..<300).contains(http.statusCode) {
                return (true, "Webhook POST OK (HTTP \(http.statusCode)) → \(url.host ?? urlString)", "webhook.post.ok")
            }
            return (false, "Webhook HTTP \(http.statusCode)", "webhook.post.http-\(http.statusCode)")
        } catch {
            return (false, "Webhook error: \(error.localizedDescription)", "webhook.post.error")
        }
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

import Foundation
import SwiftData

/// Advisor v0.9 — sparring partner. Briefing matinal 8h00 + briefing on-demand.
///
/// Lit Memory + Signal récents + ProjectRecord stats + ActionLog → synthèse Opus →
/// top 3 priorités + 2 risques + 1 challenge no-glazing.
///
/// Cf docs/IRIS-AGENTS-CATALOG.md §10 Advisor.
public actor Advisor {
    public static let shared = Advisor()

    private weak var modelContainer: ModelContainer?
    private var dailyBriefingTask: Task<Void, Never>?
    private var onCost: CostSink?

    private init() {}

    public func start(
        modelContainer: ModelContainer,
        onCost: @escaping CostSink
    ) async {
        self.modelContainer = modelContainer
        self.onCost = onCost
        startScheduledBriefing()
    }

    public func stop() {
        dailyBriefingTask?.cancel()
        dailyBriefingTask = nil
    }

    private func startScheduledBriefing() {
        guard dailyBriefingTask == nil else { return }
        dailyBriefingTask = Task { [weak self] in
            while !Task.isCancelled {
                let now = Date()
                let next8AM = Self.nextHourOccurrence(hour: 8, after: now)
                let sleepInterval = next8AM.timeIntervalSince(now)
                irisLog(.info, "Advisor next briefing in \(Int(sleepInterval/3600))h\(Int((sleepInterval.truncatingRemainder(dividingBy: 3600))/60))m",
                        category: IRISLogger.agents)
                try? await Task.sleep(nanoseconds: UInt64(sleepInterval * 1_000_000_000))
                await self?.runBriefing(kind: .scheduled)
            }
        }
    }

    public enum BriefingKind: Sendable {
        case scheduled  // 8h00 auto
        case manual     // user-initiated
    }

    /// Génère et publie un briefing — appelable depuis l'UI ("Brief now").
    public func runBriefing(kind: BriefingKind = .manual) async {
        irisLog(.notice, "Advisor briefing \(kind == .scheduled ? "scheduled" : "manual")", category: IRISLogger.agents)

        let context = await gatherContext()

        guard IRISKeychain.shared.hasAnthropicAPIKey() else {
            await publishMockBriefing(context: context, kind: kind)
            return
        }

        await publishLiveBriefing(context: context, kind: kind)
    }

    // MARK: — Context gathering

    private struct BriefContext: Sendable {
        let projectsActive: [String]    // top 10 active codenames
        let projectsTotal: Int
        let recentSignals: [(source: String, importance: Int, summary: String)]
        let pendingDrafts: Int
        let pendingActions: Int
        let recentAudits: [(codename: String, verdict: String, headline: String)]
        let memoriesCount: Int
        let lastActionsToday: Int
    }

    private func gatherContext() async -> BriefContext {
        guard let container = await modelContainer else {
            return BriefContext(
                projectsActive: [], projectsTotal: 0, recentSignals: [],
                pendingDrafts: 0, pendingActions: 0, recentAudits: [],
                memoriesCount: 0, lastActionsToday: 0
            )
        }

        return await MainActor.run {
            let ctx = container.mainContext
            let now = Date()
            let oneDayAgo = now.addingTimeInterval(-86400)

            let activeProjects = ((try? ctx.fetch(FetchDescriptor<ProjectRecord>())) ?? [])
                .filter { $0.status == "active" }
                .sorted { ($0.lastPushAt ?? .distantPast) > ($1.lastPushAt ?? .distantPast) }
                .prefix(10)
                .map(\.codename)

            let projectsTotal = (try? ctx.fetchCount(FetchDescriptor<ProjectRecord>())) ?? 0

            let signalsRaw = (try? ctx.fetch(FetchDescriptor<Signal>(sortBy: [SortDescriptor(\.emittedAt, order: .reverse)]))) ?? []
            let recentSignals: [(source: String, importance: Int, summary: String)] = signalsRaw
                .prefix(10)
                .map { ($0.source, $0.importance, $0.summary) }

            let pendingDrafts = ((try? ctx.fetch(FetchDescriptor<Draft>())) ?? [])
                .filter { $0.status == "pending" }
                .count

            let pendingActionsCount = 0  // l'état pending vit dans AppState, pas SwiftData

            let auditsRaw = (try? ctx.fetch(FetchDescriptor<AuditReport>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []
            let recentAudits: [(codename: String, verdict: String, headline: String)] = auditsRaw
                .prefix(5)
                .map { ($0.projectCodename, $0.verdict, $0.headline) }

            let memoriesCount = (try? ctx.fetchCount(FetchDescriptor<Memory>())) ?? 0

            let actionsTodayDescriptor = FetchDescriptor<ActionLog>(
                predicate: #Predicate { $0.executedAt >= oneDayAgo }
            )
            let lastActionsToday = (try? ctx.fetchCount(actionsTodayDescriptor)) ?? 0

            return BriefContext(
                projectsActive: Array(activeProjects),
                projectsTotal: projectsTotal,
                recentSignals: recentSignals,
                pendingDrafts: pendingDrafts,
                pendingActions: pendingActionsCount,
                recentAudits: recentAudits,
                memoriesCount: memoriesCount,
                lastActionsToday: lastActionsToday
            )
        }
    }

    // MARK: — Publish briefing

    private static let systemPrompt = """
    Tu es Advisor — l'agent sparring partner d'IRIS pour Mehdi (opérateur solo Numelite).

    Tu produis un BRIEFING quotidien dense, no-glazing, FR-casual + EN technique.

    Structure stricte (markdown) :

    ## ☀️ Briefing du <date>

    **Top 3 priorités aujourd'hui** (action concrete, pas tâche vague)
    1. [priorité 1 + 1 phrase pourquoi]
    2. [...]
    3. [...]

    **2 risques à surveiller**
    - [risque 1 + signal qui le justifie]
    - [risque 2 + signal]

    **1 challenge** (question piquante qui pousse Mehdi à réfléchir)
    > [Une seule question. Vraiment provocatrice. Pas de "comment tu vois ?", plutôt
    > "Pourquoi tu pousses encore X alors que data Y montre Z ?")

    Règles :
    - Pas de glazing, pas de "great choice"
    - Cite les données fournies (signaux + drafts + audits + actions)
    - Si la data est mince (pas assez de signaux), dis-le explicitement
    - Si rien de critique : recommande des actions de fond (productisation, post-mortem, etc.)
    """

    private func publishLiveBriefing(context: BriefContext, kind: BriefingKind) async {
        let userPrompt = Self.formatContext(context)

        do {
            let response = try await AnthropicClient.shared.sendMessage(
                model: .opus47,
                system: Self.systemPrompt,
                messages: [Message(role: .user, content: userPrompt)],
                maxTokens: 1024,
                cacheSystem: true
            )

            let content = response.firstTextContent ?? "[Advisor : réponse vide]"
            let cost = response.usage.estimatedCostUSD(model: .opus47)
            onCost?(cost, ClaudeModel.opus47.rawValue)

            await EventBus.shared.publish(
                .agentResponse(from: .advisor, content: content, eventId: UUID())
            )

            irisLog(.info,
                "Advisor briefing OK (\(kind), cost=$\(String(format: "%.5f", cost)))",
                category: IRISLogger.agents
            )
        } catch {
            await EventBus.shared.publish(.agentFailure(agent: .advisor, error: error.localizedDescription))
            irisLog(.error, "Advisor briefing failed: \(error.localizedDescription)", category: IRISLogger.agents)
        }
    }

    private func publishMockBriefing(context: BriefContext, kind: BriefingKind) async {
        let mock = """
        ## ☀️ Briefing mock — \(Self.todayString())

        [mode mock — API key Anthropic absente du Keychain]

        Stats récupérées :
        - \(context.projectsTotal) projets cartographiés (\(context.projectsActive.count) actifs)
        - \(context.recentSignals.count) signaux récents
        - \(context.pendingDrafts) drafts pending
        - \(context.recentAudits.count) audits récents
        - \(context.memoriesCount) mémoires Scribe
        - \(context.lastActionsToday) actions exécutées sur les dernières 24h

        Ajoute ta clé API Anthropic dans Settings (Cmd+,) pour activer l'Advisor Opus 4.7.
        """

        await EventBus.shared.publish(
            .agentResponse(from: .advisor, content: mock, eventId: UUID())
        )
    }

    // MARK: — Helpers

    private static func formatContext(_ ctx: BriefContext) -> String {
        let signals = ctx.recentSignals.prefix(10).map { "- [\($0.source)] importance=\($0.importance)/5 — \($0.summary)" }.joined(separator: "\n")
        let audits = ctx.recentAudits.map { "- \($0.codename) → \($0.verdict) : \($0.headline)" }.joined(separator: "\n")
        let activeList = ctx.projectsActive.joined(separator: ", ")

        return """
        # Contexte du jour (\(todayString()))

        ## Portfolio
        - Total projets cartographiés : \(ctx.projectsTotal)
        - Actifs (push < 30j) : \(ctx.projectsActive.count) — \(activeList.isEmpty ? "—" : activeList)

        ## Signaux récents (\(ctx.recentSignals.count))
        \(signals.isEmpty ? "(aucun)" : signals)

        ## Drafts en attente
        \(ctx.pendingDrafts) drafts générés par Quill, non envoyés.

        ## Audits récents
        \(audits.isEmpty ? "(aucun)" : audits)

        ## Activité
        - Mémoires Scribe : \(ctx.memoriesCount)
        - Actions exécutées dernières 24h : \(ctx.lastActionsToday)

        Produis le briefing maintenant, strictement selon le format.
        """
    }

    private static func todayString() -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE d MMMM yyyy"
        f.locale = Locale(identifier: "fr_FR")
        return f.string(from: Date())
    }

    static func nextHourOccurrence(hour: Int, after date: Date) -> Date {
        let cal = Calendar.current
        var components = cal.dateComponents([.year, .month, .day], from: date)
        components.hour = hour
        components.minute = 0
        components.second = 0
        var target = cal.date(from: components) ?? date
        if target <= date {
            target = cal.date(byAdding: .day, value: 1, to: target) ?? date
        }
        return target
    }
}

import Foundation
import SwiftData
import CryptoKit  // v1.124 — project fingerprint hash

/// Auditor v0.7 — audit projets via skill damage-control.
/// v0.7 : MOCK report (verdict random + findings + actions hardcoded).
/// v0.7.5+ : shell-out `claude --skill damage-control --project <path>` et parse l'output Markdown.
/// v1.353 — Weekly auto-audit loop (`startAutoAuditLoop`) avec daily cost cap, batch ≤ 3,
///          30s pause inter-projets, picker oldest-first (or never-audited). Persiste
///          costUSD sur AuditReport pour pouvoir borner via sumOfAuditCostsToday.
///
/// Cf docs/IRIS-AGENTS-CATALOG.md §5 Auditor + skill installé ~/.claude/skills/damage-control/.
public actor Auditor {
    public static let shared = Auditor()

    private weak var modelContainer: ModelContainer?
    private var subscriptionTask: Task<Void, Never>?
    private var monthlyAuditTask: Task<Void, Never>?  // v1.93
    private var autoAuditTask: Task<Void, Never>?  // v1.353
    private var onCost: CostSink?

    private init() {}

    public func start(
        modelContainer: ModelContainer,
        onCost: @escaping CostSink = { _, _ in }
    ) async {
        self.modelContainer = modelContainer
        self.onCost = onCost
        // v1.93 — Démarre la boucle monthly auto-audit si activée
        startMonthlyAuditLoopIfEnabled()
    }

    public func stop() {
        subscriptionTask?.cancel()
        subscriptionTask = nil
        monthlyAuditTask?.cancel()
        monthlyAuditTask = nil
        autoAuditTask?.cancel()  // v1.353
        autoAuditTask = nil
    }

    // MARK: — v1.93 Monthly auto-audit (active projects, opt-in)

    private static let monthlyEnabledKey = "iris.auditor.monthlyAutoEnabled"
    private static let monthlyLastAtKey = "iris.auditor.monthlyLastAt"

    public static var monthlyAutoEnabled: Bool {
        UserDefaults.standard.bool(forKey: monthlyEnabledKey)
    }

    public static func setMonthlyAutoEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: monthlyEnabledKey)
    }

    public static var monthlyLastAt: Date? {
        UserDefaults.standard.object(forKey: monthlyLastAtKey) as? Date
    }

    private func startMonthlyAuditLoopIfEnabled() {
        guard monthlyAuditTask == nil else { return }
        monthlyAuditTask = Task { [weak self] in
            // Premier check 5min après start (laisse le bootstrap finir)
            try? await Task.sleep(nanoseconds: 300 * 1_000_000_000)
            while !Task.isCancelled {
                await self?.runMonthlyAuditIfDue()
                // Re-check toutes les 6h
                try? await Task.sleep(nanoseconds: 6 * 3600 * 1_000_000_000)
            }
        }
    }

    private func runMonthlyAuditIfDue() async {
        guard Self.monthlyAutoEnabled, let container = modelContainer else { return }
        let last = Self.monthlyLastAt ?? .distantPast
        let elapsed = Date().timeIntervalSince(last)
        guard elapsed > 30 * 86400 else { return }  // > 30 days

        // Fetch active projects
        let codenames = await Self.fetchActiveCodenames(container: container)
        guard !codenames.isEmpty else { return }

        irisLog(.notice, "Auditor monthly auto-audit run — \(codenames.count) projects", category: IRISLogger.agents)
        for codename in codenames {
            await auditProject(codename: codename)
            // Pause 30s entre audits pour respecter rate limits Anthropic
            try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
        }
        UserDefaults.standard.set(Date(), forKey: Self.monthlyLastAtKey)
    }

    @MainActor
    private static func fetchActiveCodenames(container: ModelContainer) async -> [String] {
        let descriptor = FetchDescriptor<ProjectRecord>(
            predicate: #Predicate { $0.status == "active" }
        )
        let projects = (try? container.mainContext.fetch(descriptor)) ?? []
        return projects.map(\.codename)
    }

    // MARK: — v1.353 Weekly auto-audit loop (cost-capped, batched)

    /// @AppStorage("auditorAutoAuditEnabled") · default true.
    public static let autoAuditEnabledKey = "auditorAutoAuditEnabled"
    /// @AppStorage("auditorMaxDailyAuditCostUSD") · default 1.0 USD.
    public static let autoAuditMaxDailyCostKey = "auditorMaxDailyAuditCostUSD"
    /// @AppStorage("auditorAutoAuditIntervalDays") · default 7 days (= weekly).
    public static let autoAuditIntervalDaysKey = "auditorAutoAuditIntervalDays"
    /// Internal timestamp (Date) of last successful auto-audit batch.
    private static let autoAuditLastBatchAtKey = "iris.auditor.autoAuditLastBatchAt"
    /// Per-call batch cap (max projects audited per wake).
    private static let autoAuditBatchSize = 3
    /// Pause inter-projets pour respecter rate limits Anthropic + éviter thundering herd.
    private static let autoAuditInterProjectSleepSeconds: UInt64 = 30
    /// Wake cadence (1h). Le loop re-vérifie l'éligibilité (interval, cost cap) à chaque wake.
    private static let autoAuditWakeIntervalSeconds: UInt64 = 3600

    public static var autoAuditEnabled: Bool {
        // Default true (UserDefaults.bool returns false if key absent, donc on check présence).
        if UserDefaults.standard.object(forKey: autoAuditEnabledKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: autoAuditEnabledKey)
    }

    public static var maxDailyAuditCostUSD: Double {
        if UserDefaults.standard.object(forKey: autoAuditMaxDailyCostKey) == nil { return 1.0 }
        let raw = UserDefaults.standard.double(forKey: autoAuditMaxDailyCostKey)
        return raw > 0 ? raw : 1.0
    }

    public static var autoAuditIntervalDays: Int {
        let raw = UserDefaults.standard.integer(forKey: autoAuditIntervalDaysKey)
        return raw > 0 ? raw : 7
    }

    public static var autoAuditLastBatchAt: Date? {
        UserDefaults.standard.object(forKey: autoAuditLastBatchAtKey) as? Date
    }

    /// v1.353 — Démarre la boucle wake/check/batch. Idempotent. Wake toutes les 1h,
    /// run batch si enabled + interval écoulé + cost cap pas dépassé.
    /// Doit être appelé depuis IRISApp.bootstrap après `Auditor.shared.start(...)`.
    public func startAutoAuditLoop() {
        guard autoAuditTask == nil else { return }
        autoAuditTask = Task { [weak self] in
            // Premier check 60s après start (laisse les autres agents bootstrap).
            try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
            while !Task.isCancelled {
                await self?.runAutoAuditBatchIfDue()
                try? await Task.sleep(nanoseconds: Self.autoAuditWakeIntervalSeconds * 1_000_000_000)
            }
        }
        irisLog(.info, "Auditor auto-audit loop started (wake every 1h, batch ≤ \(Self.autoAuditBatchSize), interval=\(Self.autoAuditIntervalDays)d, dailyCap=$\(String(format: "%.2f", Self.maxDailyAuditCostUSD)))",
                category: IRISLogger.agents)
    }

    /// Sum costUSD des AuditReport créés depuis startOfDay (calendrier user).
    /// Utilisé par le cost cap (skip run si > maxDailyAuditCostUSD).
    @MainActor
    public static func sumOfAuditCostsToday(container: ModelContainer) -> Double {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<AuditReport>(
            predicate: #Predicate { $0.createdAt >= startOfDay }
        )
        let reports = (try? container.mainContext.fetch(descriptor)) ?? []
        return reports.reduce(0.0) { $0 + $1.costUSD }
    }

    /// Sendable struct pour traverser MainActor isolation lors du batch select.
    private struct BatchCandidate: Sendable {
        let codename: String
        let lastAuditAt: Date?  // nil = never audited
    }

    /// Pick batch : status=="active", lastAudit > intervalDays jours OR jamais audité.
    /// Ordered : never-audited first (lastAuditAt = nil), puis oldest audit first.
    /// Limit autoAuditBatchSize (3).
    @MainActor
    private static func selectAutoAuditBatch(container: ModelContainer, intervalDays: Int) -> [BatchCandidate] {
        let projDescriptor = FetchDescriptor<ProjectRecord>(
            predicate: #Predicate { $0.status == "active" }
        )
        let activeProjects = (try? container.mainContext.fetch(projDescriptor)) ?? []
        guard !activeProjects.isEmpty else { return [] }

        // Cutoff : last audit must be older than this to qualify.
        let cutoff = Date().addingTimeInterval(-Double(intervalDays) * 86400)

        // Fetch all audits (we'll group in-memory ; cheap pour ≤ N audits totaux).
        let auditDescriptor = FetchDescriptor<AuditReport>()
        let allAudits = (try? container.mainContext.fetch(auditDescriptor)) ?? []
        // Map codename → most recent audit date.
        var latestByCodename: [String: Date] = [:]
        for audit in allAudits {
            let existing = latestByCodename[audit.projectCodename]
            if existing == nil || audit.createdAt > existing! {
                latestByCodename[audit.projectCodename] = audit.createdAt
            }
        }

        // Build candidates : keep si never audited OR last audit < cutoff.
        var candidates: [BatchCandidate] = []
        for project in activeProjects {
            let lastAt = latestByCodename[project.codename]
            if lastAt == nil || lastAt! < cutoff {
                candidates.append(BatchCandidate(codename: project.codename, lastAuditAt: lastAt))
            }
        }

        // Order : never-audited (nil) first, puis oldest audit first.
        candidates.sort { lhs, rhs in
            switch (lhs.lastAuditAt, rhs.lastAuditAt) {
            case (nil, nil): return lhs.codename < rhs.codename
            case (nil, _): return true
            case (_, nil): return false
            case (let a?, let b?): return a < b
            }
        }
        return Array(candidates.prefix(autoAuditBatchSize))
    }

    private func runAutoAuditBatchIfDue() async {
        guard Self.autoAuditEnabled else { return }
        guard let container = modelContainer else { return }

        // Interval check : skip si dernier batch < intervalDays jours.
        // Note : on borne au niveau batch (pas au niveau projet) — le picker s'occupe
        // de filtrer projets déjà audités récemment. Ça évite plusieurs batches/jour
        // si l'utilisateur a moins de projets que la batch size.
        if let last = Self.autoAuditLastBatchAt {
            let elapsed = Date().timeIntervalSince(last)
            // Run au plus une fois par 24h (rate-limit du loop lui-même), même si
            // intervalDays est > 1 ça permet d'étaler les audits sur plusieurs jours
            // si on a > batch size projets éligibles.
            guard elapsed > 86400 else { return }
        }

        // Cost cap check : skip si déjà dépassé pour aujourd'hui.
        let spentToday = await MainActor.run { Self.sumOfAuditCostsToday(container: container) }
        let cap = Self.maxDailyAuditCostUSD
        guard spentToday < cap else {
            irisLog(.info, "Auditor auto-audit skipped — daily cost cap atteint ($\(String(format: "%.2f", spentToday)) / $\(String(format: "%.2f", cap)))",
                    category: IRISLogger.agents)
            return
        }

        // Select batch.
        let intervalDays = Self.autoAuditIntervalDays
        let batch = await MainActor.run {
            Self.selectAutoAuditBatch(container: container, intervalDays: intervalDays)
        }
        guard !batch.isEmpty else {
            irisLog(.info, "Auditor auto-audit : aucun projet éligible (tous audités < \(intervalDays)d)",
                    category: IRISLogger.agents)
            return
        }

        irisLog(.notice, "Auditor auto-audit batch start — \(batch.count) projets (interval=\(intervalDays)d, spentToday=$\(String(format: "%.4f", spentToday))/$\(String(format: "%.2f", cap)))",
                category: IRISLogger.agents)

        let costBefore = spentToday
        var audited: [String] = []
        for (idx, candidate) in batch.enumerated() {
            // Re-check cap entre chaque audit (au cas où un audit serait coûteux).
            let currentSpent = await MainActor.run { Self.sumOfAuditCostsToday(container: container) }
            if currentSpent >= cap {
                irisLog(.notice, "Auditor auto-audit batch interrompu — cost cap atteint ($\(String(format: "%.4f", currentSpent)) / $\(String(format: "%.2f", cap)))",
                        category: IRISLogger.agents)
                break
            }
            await auditProject(codename: candidate.codename)
            audited.append(candidate.codename)
            // 30s pause inter-projets (sauf après le dernier).
            if idx < batch.count - 1 {
                try? await Task.sleep(nanoseconds: Self.autoAuditInterProjectSleepSeconds * 1_000_000_000)
            }
        }

        UserDefaults.standard.set(Date(), forKey: Self.autoAuditLastBatchAtKey)

        // Compute batch cost (delta vs start).
        let costAfter = await MainActor.run { Self.sumOfAuditCostsToday(container: container) }
        let batchCost = max(0, costAfter - costBefore)

        let summary = "Auto-audit batch: \(audited.count) projets · \(audited.joined(separator: ", ")) · $\(String(format: "%.4f", batchCost))"
        irisLog(.notice, summary, category: IRISLogger.agents)
        await EventBus.shared.publish(
            .signalEmitted(
                from: .auditor,
                importance: .low,
                summary: summary,
                source: "auditor-auto"
            )
        )
    }

    // MARK: — v1.49 Model picker (Sonnet/Opus/Haiku)

    private static let modelKey = "iris.auditor.model"

    public static var currentModel: ClaudeModel {
        if let raw = UserDefaults.standard.string(forKey: modelKey),
           let model = ClaudeModel(rawValue: raw) {
            return model
        }
        return .sonnet46
    }

    public static func setModel(_ model: ClaudeModel) {
        UserDefaults.standard.set(model.rawValue, forKey: modelKey)
    }

    // MARK: — v1.122 Audit depth (file budget tuning)

    private static let auditPerFileKey = "iris.auditor.perFileCapBytes"
    private static let auditTotalKey = "iris.auditor.totalBudgetBytes"

    public static var perFileCapBytes: Int {
        let raw = UserDefaults.standard.integer(forKey: auditPerFileKey)
        return raw > 0 ? raw : 4_000
    }

    public static func setPerFileCapBytes(_ v: Int) {
        UserDefaults.standard.set(max(500, min(20_000, v)), forKey: auditPerFileKey)
    }

    public static var totalBudgetBytes: Int {
        let raw = UserDefaults.standard.integer(forKey: auditTotalKey)
        return raw > 0 ? raw : 15_000
    }

    public static func setTotalBudgetBytes(_ v: Int) {
        UserDefaults.standard.set(max(2_000, min(100_000, v)), forKey: auditTotalKey)
    }

    // MARK: — v1.124 Project fingerprint cache (skip re-audit if unchanged)

    private static let fingerprintCacheKey = "iris.auditor.fingerprintCache"  // [codename: hash]

    /// Compute un fingerprint léger : SHA256 des top-level entries + mtimes triées.
    /// Change si fichiers ajoutés / supprimés / modifiés au top-level. Skip sous-dirs
    /// pour rester rapide (sub-dir mtime hérite des inner changes sur APFS).
    public static func projectFingerprint(at path: String) -> String? {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: URL(fileURLWithPath: path),
                                                         includingPropertiesForKeys: [.contentModificationDateKey],
                                                         options: [.skipsHiddenFiles]) else {
            return nil
        }
        let parts: [String] = entries
            .filter { !["node_modules", ".git", "DerivedData", ".build"].contains($0.lastPathComponent) }
            .compactMap { url -> String? in
                guard let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else { return nil }
                return "\(url.lastPathComponent):\(Int(mtime.timeIntervalSince1970))"
            }
            .sorted()
        let combined = parts.joined(separator: "|")
        let digest = SHA256.hash(data: Data(combined.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func cachedFingerprint(codename: String) -> String? {
        let map = (UserDefaults.standard.dictionary(forKey: fingerprintCacheKey) as? [String: String]) ?? [:]
        return map[codename]
    }

    public static func storeFingerprint(codename: String, fingerprint: String) {
        var map = (UserDefaults.standard.dictionary(forKey: fingerprintCacheKey) as? [String: String]) ?? [:]
        map[codename] = fingerprint
        UserDefaults.standard.set(map, forKey: fingerprintCacheKey)
    }

    public static func clearFingerprintCache(codename: String? = nil) {
        if let codename {
            var map = (UserDefaults.standard.dictionary(forKey: fingerprintCacheKey) as? [String: String]) ?? [:]
            map.removeValue(forKey: codename)
            UserDefaults.standard.set(map, forKey: fingerprintCacheKey)
        } else {
            UserDefaults.standard.removeObject(forKey: fingerprintCacheKey)
        }
    }

    /// Lance un audit. v1.18 : vrai audit via Claude Sonnet si API key, sinon fallback mock v0.7.
    /// v1.124 — `force` bypass le fingerprint cache (re-audit même si projet pas changé).
    public func auditProject(codename: String, force: Bool = false) async {
        irisLog(.info, "Auditor starting audit for \(codename) (force=\(force))", category: IRISLogger.agents)

        // v1.124 — Skip si fingerprint inchangé depuis last audit (sauf force)
        if !force, let info = await fetchProjectInfo(codename: codename), let path = info.localPath {
            let current = Self.projectFingerprint(at: path)
            let cached = Self.cachedFingerprint(codename: codename)
            if let current, let cached, current == cached {
                irisLog(.info, "Auditor skip \(codename) — fingerprint unchanged (use force pour bypass)",
                        category: IRISLogger.agents)
                await EventBus.shared.publish(
                    .signalEmitted(
                        from: .auditor,
                        importance: .trivial,
                        summary: "Audit \(codename) skipped (projet inchangé depuis last audit)",
                        source: "auditor"
                    )
                )
                return
            }
        }

        let start = Date()
        await EventBus.shared.publish(
            .signalEmitted(
                from: .auditor,
                importance: .low,
                summary: "Audit démarré : \(codename)",
                source: "auditor"
            )
        )

        let useReal = IRISKeychain.shared.hasAnthropicAPIKey()
        if useReal {
            await runRealAudit(codename: codename, start: start)
        } else {
            await runMockAudit(codename: codename, start: start)
        }

        // v1.124 — store fingerprint après audit successful
        if let info = await fetchProjectInfo(codename: codename),
           let path = info.localPath,
           let fp = Self.projectFingerprint(at: path) {
            Self.storeFingerprint(codename: codename, fingerprint: fp)
        }
    }

    // MARK: — v0.7 mock

    private func runMockAudit(codename: String, start: Date) async {
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        let duration = Date().timeIntervalSince(start)
        let mockResult = Self.makeMockReportPayload(for: codename)

        var resultVerdict = mockResult.verdict
        var resultHeadline = mockResult.headline
        if let container = await modelContainer {
            await MainActor.run {
                let report = AuditReport(
                    projectCodename: codename,
                    verdict: mockResult.verdict,
                    headline: mockResult.headline,
                    findingsJSON: mockResult.findingsJSON,
                    topActionsJSON: mockResult.actionsJSON,
                    modelUsed: "mock-v0.7",
                    executedSkill: nil,
                    costUSD: 0,
                    durationSeconds: duration
                )
                container.mainContext.insert(report)
                try? container.mainContext.save()
                resultVerdict = report.verdict
                resultHeadline = report.headline
            }
        }
        await publishAuditDone(codename: codename, verdict: resultVerdict, headline: resultHeadline)
    }

    // MARK: — v1.18 real audit via Claude Sonnet

    private static let realAuditSystemPrompt = """
    Tu es Auditor — l'agent audit projet d'IRIS, basé sur le skill `damage-control` de Mehdi (Numelite).

    Tu produis un audit 8 axes :
    01 Attribution & Analytics (server-side tracking, Consent Mode v2, named conversion events)
    02 CRO (session replay, heatmaps, funnel analytics, A/B testing)
    03 Observability (Sentry, RUM, feature flags, uptime, alerting)
    04 Growth loops (north star, k-factor, retention, compounding assets)
    05 Edge performance (Core Web Vitals, edge functions, caching)
    06 AI observability (LLM tracing, prompt versioning, eval harness, cost monitoring)
    07 Compliance (WCAG/RGAA, AI Act, RGPD, DSA, security baselines)
    08 Business leverage (pricing model, productisation, moat)

    Pour chaque axe, verdict 🟢 GREEN / 🟡 YELLOW / 🔴 RED (ou ⚫ N/A).
    Verdict global = pire des verdicts validés (RED > YELLOW > GREEN).

    Output STRICT JSON (pas de markdown autour, juste JSON valide) :
    {
      "verdict": "GREEN|YELLOW|RED",
      "headline": "1 ligne synthèse — what's the headline reality",
      "findings": ["finding 1 concret avec file path si applicable", "finding 2", "..."],
      "topActions": [
        {"action": "action concrète (pas générique)", "effort": "Xh/Xj", "impact": 1-5}
      ]
    }

    Règles : no glazing, dense, FR-casual + termes EN techniques. Cap findings 5, actions 5.
    """

    private func runRealAudit(codename: String, start: Date) async {
        let projectInfo = await fetchProjectInfo(codename: codename)
        let userPrompt = Self.buildAuditPrompt(codename: codename, info: projectInfo)

        // v1.49 — model depuis UserDefaults
        let auditModel = Self.currentModel
        var accumulated = ""
        let costCallback = onCostCallback
        // v1.353 — accumulate cost so we can persist it on AuditReport (needed by
        // sumOfAuditCostsToday daily cap enforcement).
        let costBox = CostBox()
        let stream = AnthropicClient.shared.streamMessage(
            model: auditModel,
            system: Self.realAuditSystemPrompt,
            messages: [Message(role: .user, content: userPrompt)],
            maxTokens: 2048,
            cacheSystem: true,
            onUsage: { usage in
                let cost = usage.estimatedCostUSD(model: auditModel)
                costBox.add(cost)
                costCallback?(cost, auditModel.rawValue)
            }
        )

        do {
            for try await delta in stream {
                accumulated += delta
            }
        } catch {
            irisLog(.error, "Auditor real audit failed: \(error.localizedDescription)", category: IRISLogger.agents)
            await EventBus.shared.publish(.agentFailure(agent: .auditor, error: error.localizedDescription))
            return
        }

        let duration = Date().timeIntervalSince(start)
        let parsed = Self.parseAuditOutput(accumulated) ?? Self.fallbackParsedOutput(verdict: "YELLOW", headline: "Audit parsing failed — voir Logs")

        var resultVerdict = parsed.verdict
        var resultHeadline = parsed.headline
        let auditCost = costBox.total  // v1.353
        if let container = await modelContainer {
            await MainActor.run {
                let report = AuditReport(
                    projectCodename: codename,
                    verdict: parsed.verdict,
                    headline: parsed.headline,
                    findingsJSON: parsed.findingsJSON,
                    topActionsJSON: parsed.actionsJSON,
                    modelUsed: auditModel.rawValue,
                    executedSkill: "damage-control-api",
                    costUSD: auditCost,  // v1.353 — persist pour daily cap + dashboards
                    durationSeconds: duration
                )
                container.mainContext.insert(report)
                try? container.mainContext.save()
                resultVerdict = report.verdict
                resultHeadline = report.headline
            }
        }

        await publishAuditDone(codename: codename, verdict: resultVerdict, headline: resultHeadline)
    }

    /// v1.353 — Thread-safe cost accumulator pour capturer le coût total d'un audit
    /// depuis le callback onUsage (qui peut être invoqué plusieurs fois pendant le stream).
    private final class CostBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _total: Double = 0
        func add(_ amount: Double) {
            lock.lock(); defer { lock.unlock() }
            _total += amount
        }
        var total: Double {
            lock.lock(); defer { lock.unlock() }
            return _total
        }
    }

    private func publishAuditDone(codename: String, verdict: String, headline: String) async {
        let importance: SignalImportance = verdict == "RED" ? .critical : (verdict == "YELLOW" ? .high : .medium)
        await EventBus.shared.publish(
            .signalEmitted(
                from: .auditor,
                importance: importance,
                summary: "Audit terminé \(codename): \(verdict) — \(headline)",
                source: "auditor"
            )
        )
        irisLog(.notice, "Auditor finished \(codename) — verdict=\(verdict)", category: IRISLogger.agents)
    }

    private var onCostCallback: CostSink? {
        onCost
    }

    /// Sendable info struct pour traverser MainActor isolation.
    private struct ProjectInfo: Sendable {
        let codename: String
        let localPath: String?
        let stackJSON: String
        let status: String
        let domain: String?
    }

    private func fetchProjectInfo(codename: String) async -> ProjectInfo? {
        guard let container = await modelContainer else { return nil }
        return await Self.fetchProjectInfoMainActor(container: container, codename: codename)
    }

    @MainActor
    private static func fetchProjectInfoMainActor(container: ModelContainer, codename: String) -> ProjectInfo? {
        let descriptor = FetchDescriptor<ProjectRecord>(predicate: #Predicate { $0.codename == codename })
        guard let project = (try? container.mainContext.fetch(descriptor))?.first else { return nil }
        return ProjectInfo(
            codename: project.codename,
            localPath: project.localPath,
            stackJSON: project.stackJSON,
            status: project.status,
            domain: project.domain
        )
    }

    private static func buildAuditPrompt(codename: String, info: ProjectInfo?) -> String {
        guard let info else {
            return "Audit projet `\(codename)` — pas d'info ProjectRecord disponible. Audit aveugle générique 8 axes."
        }

        // Liste top-level files si localPath dispo (FS scan léger)
        var topLevel: [String] = []
        var keyFilesExtract = ""
        if let path = info.localPath {
            let url = URL(fileURLWithPath: path)
            topLevel = ((try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [])
                .map { $0.lastPathComponent }
                .filter { !$0.hasPrefix(".") && $0 != "node_modules" }
                .prefix(30)
                .map { $0 }

            // v1.121 — Read actual key files content (cap 4KB each, ~15KB total)
            keyFilesExtract = readKeyFiles(at: path)
        }

        var prompt = """
        Audit projet `\(codename)` :

        - Status : \(info.status)
        - Domain : \(info.domain ?? "(non spécifié)")
        - Stack : \(info.stackJSON)
        - Local path : \(info.localPath ?? "(non clonage local)")
        - Top-level files : \(topLevel.joined(separator: ", "))
        """

        if !keyFilesExtract.isEmpty {
            prompt += "\n\n" + keyFilesExtract
        }

        prompt += "\n\nProduis le rapport JSON 8 axes selon le format spécifié. Base les findings sur le contenu réel des fichiers ci-dessus quand c'est possible (cite file paths)."
        return prompt
    }

    /// v1.121 — Lit le contenu de fichiers clés (README, manifests, CLAUDE.md, main src).
    /// Cap 4KB par fichier, total ~15KB budget. Skip si > 100KB (binaire/lock).
    private static func readKeyFiles(at projectPath: String) -> String {
        let fm = FileManager.default
        // Priorité top : si présents au top-level, on les lit en premier
        let priorityNames: [String] = [
            "README.md", "README", "readme.md",
            "CLAUDE.md", "AGENTS.md",
            "package.json", "Package.swift",
            "pyproject.toml", "Cargo.toml", "Gemfile",
            "next.config.js", "next.config.mjs", "vite.config.ts",
            ".env.example",
            "src/index.ts", "src/index.tsx", "src/index.js",
            "src/main.swift", "App/Sources/IRISApp.swift",
            "main.py", "app.py"
        ]

        var sections: [String] = []
        var totalBytes = 0
        let totalBudget = Self.totalBudgetBytes  // v1.122 — UserDefaults
        let perFileCapBytes = Self.perFileCapBytes

        for name in priorityNames {
            if totalBytes >= totalBudget { break }
            let fullPath = (projectPath as NSString).appendingPathComponent(name)
            guard fm.fileExists(atPath: fullPath) else { continue }
            guard let attrs = try? fm.attributesOfItem(atPath: fullPath),
                  let sizeNum = attrs[.size] as? NSNumber else { continue }
            let size = sizeNum.intValue
            if size > 100_000 { continue }  // skip lockfiles / binaires
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: fullPath)) else { continue }
            let head = data.prefix(perFileCapBytes)
            guard let text = String(data: head, encoding: .utf8) else { continue }

            let truncationNote = size > perFileCapBytes ? "\n[…tronqué \(size - perFileCapBytes) bytes…]" : ""
            sections.append("### \(name) (\(size) bytes)\n```\n\(text)\(truncationNote)\n```")
            totalBytes += head.count
        }

        // v1.123 — Si encore du budget, scan récursif src/ pour les fichiers code récents
        if totalBytes < totalBudget {
            let remaining = totalBudget - totalBytes
            let extra = scanRecentSourceFiles(
                projectPath: projectPath,
                budgetBytes: remaining,
                perFileCap: perFileCapBytes
            )
            sections.append(contentsOf: extra.sections)
            totalBytes += extra.bytesUsed
        }

        guard !sections.isEmpty else { return "" }
        return "## Key files extract (per-file \(perFileCapBytes / 1000)KB cap · total \(totalBudget / 1000)KB budget)\n\n" + sections.joined(separator: "\n\n")
    }

    /// v1.123 — Scan récursif léger (depth ≤ 3) des fichiers source récents.
    /// Skip patterns node_modules / .git / .build / DerivedData / dist / .next / vendor.
    /// Trie par mtime desc → privilégie les fichiers modifiés récemment (= actifs).
    private static func scanRecentSourceFiles(
        projectPath: String,
        budgetBytes: Int,
        perFileCap: Int
    ) -> (sections: [String], bytesUsed: Int) {
        let skipDirs: Set<String> = [
            "node_modules", ".git", ".build", "DerivedData",
            "dist", "build", ".next", ".turbo", "vendor",
            "Pods", "__pycache__", ".swiftpm"
        ]
        let codeExts: Set<String> = [
            "swift", "ts", "tsx", "js", "jsx",
            "py", "rb", "go", "rs", "java", "kt",
            "md"  // docs aussi (utile pour audit)
        ]
        let projectURL = URL(fileURLWithPath: projectPath)
        let fm = FileManager.default

        // Enumerate récursif manuel avec depth cap
        var candidates: [(URL, Int, Date)] = []  // (url, size, mtime)
        func walk(_ url: URL, depth: Int) {
            guard depth <= 3 else { return }
            guard let contents = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey], options: [.skipsHiddenFiles]) else { return }
            for child in contents {
                let name = child.lastPathComponent
                if skipDirs.contains(name) { continue }
                guard let vals = try? child.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]) else { continue }
                if vals.isDirectory == true {
                    walk(child, depth: depth + 1)
                } else {
                    let ext = child.pathExtension.lowercased()
                    guard codeExts.contains(ext) else { continue }
                    let size = vals.fileSize ?? 0
                    if size == 0 || size > 100_000 { continue }
                    let mtime = vals.contentModificationDate ?? .distantPast
                    candidates.append((child, size, mtime))
                }
            }
        }
        walk(projectURL, depth: 0)

        // Trie par mtime desc (récent first)
        candidates.sort { $0.2 > $1.2 }

        // Build sections jusqu'à budget
        var sections: [String] = []
        var bytesUsed = 0
        for (url, size, _) in candidates {
            if bytesUsed >= budgetBytes { break }
            guard let data = try? Data(contentsOf: url) else { continue }
            let head = data.prefix(perFileCap)
            guard let text = String(data: head, encoding: .utf8) else { continue }
            let relPath = url.path.replacingOccurrences(of: projectPath, with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let truncNote = size > perFileCap ? "\n[…tronqué \(size - perFileCap) bytes…]" : ""
            sections.append("### \(relPath) (\(size) bytes)\n```\n\(text)\(truncNote)\n```")
            bytesUsed += head.count
        }
        return (sections, bytesUsed)
    }

    // MARK: — Output parser

    struct ParsedAuditOutput: Sendable {
        let verdict: String
        let headline: String
        let findingsJSON: String
        let actionsJSON: String
    }

    private static func parseAuditOutput(_ raw: String) -> ParsedAuditOutput? {
        // Strip markdown fences si présents
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let verdict = (json["verdict"] as? String) ?? "YELLOW"
        let headline = (json["headline"] as? String) ?? "Audit complete — voir findings"

        let findingsArray = (json["findings"] as? [String]) ?? []
        let findingsJSON = (try? JSONSerialization.data(withJSONObject: findingsArray))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

        let actionsArray = (json["topActions"] as? [[String: Any]]) ?? []
        let actionsJSON = (try? JSONSerialization.data(withJSONObject: actionsArray))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

        return ParsedAuditOutput(
            verdict: verdict,
            headline: headline,
            findingsJSON: findingsJSON,
            actionsJSON: actionsJSON
        )
    }

    private static func fallbackParsedOutput(verdict: String, headline: String) -> ParsedAuditOutput {
        ParsedAuditOutput(
            verdict: verdict,
            headline: headline,
            findingsJSON: "[]",
            actionsJSON: "[]"
        )
    }

    // MARK: — Mock report generation

    /// Payload Sendable (struct) — utilisé pour passer le résultat à travers isolation
    /// avant la création du AuditReport @Model sur MainActor.
    struct MockPayload: Sendable {
        let verdict: String
        let headline: String
        let findingsJSON: String
        let actionsJSON: String
    }

    private static func makeMockReportPayload(for codename: String) -> MockPayload {
        let verdicts = ["GREEN", "YELLOW", "RED"]
        let weights = [2, 5, 3]  // YELLOW most common (réaliste)
        let verdict = Self.weightedRandom(from: verdicts, weights: weights)

        let headlines: [String: [String]] = [
            "GREEN": [
                "Stack moderne, observability OK, growth loops engineered.",
                "Tous les axes au vert. Tu peux pousser l'ambition.",
                "Project healthy. Focus next sur business leverage."
            ],
            "YELLOW": [
                "Bases solides mais CRO + AI obs gappy.",
                "Tracking client OK, mais session replay manquant.",
                "Stack ✓, mais pas de feature flags = risque déploiements."
            ],
            "RED": [
                "Production sans Sentry + sans analytics conversion. Urgent.",
                "Auth admin avec bootstrap email/password en clair, plusieurs vulns potentielles.",
                "CWV mobile poor + pas de monitoring = perte conversions silencieuse."
            ]
        ]

        let findings: [String: [String]] = [
            "GREEN": [
                "Sentry frontend + backend OK avec source maps",
                "PostHog session replay 1% + funnels définis",
                "Feature flags actifs (GrowthBook ou PostHog)",
                "Core Web Vitals tous \"good\" P75",
                "RGPD : cookie consent granulaire + DPA signés"
            ],
            "YELLOW": [
                "Sentry frontend OK mais backend manquant",
                "GA4 client-side seulement (perte 30-60% EU traffic)",
                "Pas de Microsoft Clarity (gratuit, lowest-effort fix)",
                "Pas de feature flags — risk déploiements big-bang",
                "Aucun A/B test run dans les 90 derniers jours"
            ],
            "RED": [
                "Pas de Sentry installé (production aveugle)",
                "Aucune analytics — funnel drop-off invisible",
                "Pas de Consent Mode v2 (Ad data dégradée)",
                "CWV P75 LCP > 4s mobile (poor)",
                "Pas de mentions légales / CGV (compliance FR fail)"
            ]
        ]

        let topActions: [String: [[String: Any]]] = [
            "GREEN": [
                ["action": "Productiser l'offre en 3 tiers (audit / accompagnement / certification)", "effort": "1j", "impact": 5],
                ["action": "Setup MMM ou geo-lift expérience", "effort": "1sem", "impact": 4]
            ],
            "YELLOW": [
                ["action": "Add Microsoft Clarity (session replay gratuit)", "effort": "30min", "impact": 4],
                ["action": "Install Sentry backend + source maps frontend", "effort": "2h", "impact": 5],
                ["action": "Setup Consent Mode v2 via CMP", "effort": "3h", "impact": 4],
                ["action": "Première campagne A/B sur CTA hero", "effort": "1j", "impact": 3]
            ],
            "RED": [
                ["action": "Sentry frontend + backend en priorité absolue", "effort": "2h", "impact": 5],
                ["action": "PostHog client + server tracking + Consent Mode v2", "effort": "4h", "impact": 5],
                ["action": "Optimize LCP image hero (AVIF + preload)", "effort": "4h", "impact": 4],
                ["action": "Mentions légales + CGV + politique confidentialité", "effort": "2h", "impact": 5]
            ]
        ]

        let headlinesPool = headlines[verdict] ?? []
        let findingsPool = findings[verdict] ?? []
        let actionsPool = topActions[verdict] ?? []

        let headline = headlinesPool.randomElement() ?? "Audit mock — verdict \(verdict)"
        let findingsJSON = (try? JSONSerialization.data(withJSONObject: findingsPool))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let actionsJSON = (try? JSONSerialization.data(withJSONObject: actionsPool))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

        return MockPayload(
            verdict: verdict,
            headline: headline,
            findingsJSON: findingsJSON,
            actionsJSON: actionsJSON
        )
    }

    private static func weightedRandom<T>(from items: [T], weights: [Int]) -> T {
        let total = weights.reduce(0, +)
        let r = Int.random(in: 0..<total)
        var acc = 0
        for (i, w) in weights.enumerated() {
            acc += w
            if r < acc { return items[i] }
        }
        return items.last!
    }
}

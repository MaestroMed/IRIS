import Foundation
import SwiftData

/// Auditor v0.7 — audit projets via skill damage-control.
/// v0.7 : MOCK report (verdict random + findings + actions hardcoded).
/// v0.7.5+ : shell-out `claude --skill damage-control --project <path>` et parse l'output Markdown.
///
/// Cf docs/IRIS-AGENTS-CATALOG.md §5 Auditor + skill installé ~/.claude/skills/damage-control/.
public actor Auditor {
    public static let shared = Auditor()

    private weak var modelContainer: ModelContainer?
    private var subscriptionTask: Task<Void, Never>?
    private var monthlyAuditTask: Task<Void, Never>?  // v1.93
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

    /// Lance un audit. v1.18 : vrai audit via Claude Sonnet si API key, sinon fallback mock v0.7.
    public func auditProject(codename: String) async {
        irisLog(.info, "Auditor starting audit for \(codename)", category: IRISLogger.agents)

        let start = Date()
        await EventBus.shared.publish(
            .signalEmitted(
                from: .auditor,
                importance: .low,
                summary: "Audit démarré : \(codename)",
                source: "auditor"
            )
        )

        // v1.18 : route real vs mock
        let useReal = IRISKeychain.shared.hasAnthropicAPIKey()
        if useReal {
            await runRealAudit(codename: codename, start: start)
        } else {
            await runMockAudit(codename: codename, start: start)
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
        let stream = AnthropicClient.shared.streamMessage(
            model: auditModel,
            system: Self.realAuditSystemPrompt,
            messages: [Message(role: .user, content: userPrompt)],
            maxTokens: 2048,
            cacheSystem: true,
            onUsage: { usage in
                let cost = usage.estimatedCostUSD(model: auditModel)
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
                    costUSD: 0,  // cost tracké via onCost callback global, pas attribué ici
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
        let totalBudget = 15_000
        let perFileCapBytes = 4_000

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

        guard !sections.isEmpty else { return "" }
        return "## Key files extract (cap 4KB/file)\n\n" + sections.joined(separator: "\n\n")
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

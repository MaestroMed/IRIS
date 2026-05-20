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

    private init() {}

    public func start(modelContainer: ModelContainer) async {
        self.modelContainer = modelContainer
        // v0.7 : audit on-demand uniquement (pas de schedule). v1.0+ : audit mensuel par projet actif.
    }

    public func stop() {
        subscriptionTask?.cancel()
        subscriptionTask = nil
    }

    /// Lance un audit (mock v0.7). projectCodename doit matcher un ProjectRecord existant.
    public func auditProject(codename: String) async {
        irisLog(.info, "Auditor starting (mock) audit for \(codename)", category: IRISLogger.agents)

        let start = Date()
        await EventBus.shared.publish(
            .signalEmitted(
                from: .auditor,
                importance: .low,
                summary: "Audit démarré : \(codename)",
                source: "auditor"
            )
        )

        // Simulate work (v0.7.5+ remplacé par Process spawn)
        try? await Task.sleep(nanoseconds: 1_500_000_000)

        let duration = Date().timeIntervalSince(start)
        let mockResult = Self.makeMockReportPayload(for: codename)

        // Crée + persiste le @Model directement sur le MainActor (évite passage cross-isolation)
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

        let importance: SignalImportance = resultVerdict == "RED" ? .critical : (resultVerdict == "YELLOW" ? .high : .medium)
        await EventBus.shared.publish(
            .signalEmitted(
                from: .auditor,
                importance: importance,
                summary: "Audit terminé \(codename): \(resultVerdict) — \(resultHeadline)",
                source: "auditor"
            )
        )

        irisLog(.notice, "Auditor finished \(codename) — verdict=\(resultVerdict)", category: IRISLogger.agents)
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

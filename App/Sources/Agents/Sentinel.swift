import Foundation
import SwiftData

/// Sentinel v0.3 — STUB qui génère des signaux fictifs périodiques.
/// Permet de tester le flow bus → Conductor → Quill → Envoy sans MCP Gmail fonctionnel.
/// v0.3.5 : remplacer le SignalGenerator par un vrai poll Gmail via MCP server (Process spawn).
///
/// Cf docs/IRIS-AGENTS-CATALOG.md §2 Sentinel.
public actor Sentinel {
    public static let shared = Sentinel()

    private var timerTask: Task<Void, Never>?
    private var pollIntervalSeconds: UInt64 = 60
    private weak var modelContainer: ModelContainer?

    /// Templates de signaux fictifs pour démo / dev. Chacun a un poids d'importance.
    private static let stubSignals: [StubSignal] = [
        StubSignal(source: "gmail", importance: .high, summary: "Nouveau thread \"Devis Atelier Frisson\" de Odelie", project: "atelier_frisson"),
        StubSignal(source: "gmail", importance: .medium, summary: "Email marketing — newsletter Numelite", project: nil),
        StubSignal(source: "github", importance: .high, summary: "PR ouverte sur AZConstruction_v0 par contributor X", project: "az_construction"),
        StubSignal(source: "github", importance: .critical, summary: "CI failure sur main de IEFandCo_v0", project: "ief_and_co"),
        StubSignal(source: "calendar", importance: .high, summary: "Event dans 15 min : appel Numelite × Odelie", project: nil),
        StubSignal(source: "fs", importance: .low, summary: "Fichier modifié dans ~/Developer/atelierfrissons_v0/src", project: "atelier_frisson"),
        StubSignal(source: "gmail", importance: .high, summary: "Réponse client S'Connect sur devis intervention", project: "sconnect"),
        StubSignal(source: "github", importance: .medium, summary: "Issue tagguée \"urgent\" sur Sconnect", project: "sconnect"),
        StubSignal(source: "calendar", importance: .medium, summary: "Reminder : audit mensuel MonJoel à planifier", project: nil),
        StubSignal(source: "gmail", importance: .critical, summary: "Lead inbound : nouvelle demande agency 10k€/mois", project: nil),
    ]

    private init() {}

    public func start(modelContainer: ModelContainer, intervalSeconds: UInt64 = 60) async {
        self.modelContainer = modelContainer
        self.pollIntervalSeconds = intervalSeconds
        guard timerTask == nil else { return }

        timerTask = Task { [weak self] in
            // Premier tick après 5s pour donner du feedback rapide à Mehdi.
            try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
            while !Task.isCancelled {
                await self?.emitStubSignal()
                try? await Task.sleep(nanoseconds: (self?.pollIntervalSeconds ?? 60) * 1_000_000_000)
            }
        }

        irisLog(.info, "Sentinel started (stub mode, interval=\(pollIntervalSeconds)s)", category: IRISLogger.agents)
    }

    public func stop() {
        timerTask?.cancel()
        timerTask = nil
    }

    public func setInterval(_ seconds: UInt64) {
        self.pollIntervalSeconds = max(10, seconds)
    }

    // MARK: — Emit

    private func emitStubSignal() async {
        let stub = Self.stubSignals.randomElement()!
        let signalId = UUID()

        // Publish event on bus
        await EventBus.shared.publish(
            .signalEmitted(
                from: .sentinel,
                importance: stub.importance,
                summary: stub.summary,
                source: stub.source
            )
        )

        // Persist Signal in SwiftData (best-effort)
        if let container = await modelContainer {
            await MainActor.run {
                let context = container.mainContext
                let signal = Signal(
                    id: signalId,
                    emittedAt: .now,
                    source: stub.source,
                    importance: stub.importance.rawValue,
                    summary: stub.summary,
                    projectScope: stub.project
                )
                context.insert(signal)
                try? context.save()
            }
        }

        irisLog(.notice,
            "Sentinel stub signal: [\(stub.source)] importance=\(stub.importance.rawValue) — \(stub.summary)",
            category: IRISLogger.agents
        )
    }

    // MARK: — Helpers

    private struct StubSignal: Sendable {
        let source: String
        let importance: SignalImportance
        let summary: String
        let project: String?
    }
}

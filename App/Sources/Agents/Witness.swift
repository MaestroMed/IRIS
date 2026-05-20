import Foundation
import AppKit
import SwiftData

/// Witness v1.5.A — observe l'app frontmost de Mehdi via NSWorkspace.
/// Pas de screenshot vision encore (v1.6+ avec Gemini Flash-Lite + Screen Recording permission).
/// Pas de webcam attention (v1.7+).
///
/// Émet Signal "Mehdi sur [app] / [project]" importance .trivial à chaque changement de focus
/// (debounce 10s pour éviter spam si Mehdi swap rapidement entre fenêtres).
///
/// Cf docs/IRIS-AGENTS-CATALOG.md §9 Witness.
public actor Witness {
    public static let shared = Witness()

    private var timerTask: Task<Void, Never>?
    private weak var modelContainer: ModelContainer?
    private var lastFrontmostBundleId: String?
    private var lastFrontmostAt: Date = .distantPast
    private let debounceSeconds: TimeInterval = 10
    private let pollInterval: UInt64 = 5  // seconds

    private init() {}

    public func start(modelContainer: ModelContainer) async {
        self.modelContainer = modelContainer
        guard timerTask == nil else { return }

        timerTask = Task { [weak self] in
            // First tick after 8s pour laisser le bootstrap finir
            try? await Task.sleep(nanoseconds: 8 * 1_000_000_000)
            while !Task.isCancelled {
                await self?.captureFrontmost()
                try? await Task.sleep(nanoseconds: (self?.pollInterval ?? 5) * 1_000_000_000)
            }
        }

        irisLog(.info, "Witness started — NSWorkspace frontmost poll \(pollInterval)s (debounce \(Int(debounceSeconds))s)",
                category: IRISLogger.agents)
    }

    public func stop() {
        timerTask?.cancel()
        timerTask = nil
    }

    /// v1.27 — Pause / Resume sans détruire la config. Cancel le timer si paused, restart si false.
    public func setPaused(_ paused: Bool) async {
        if paused {
            timerTask?.cancel()
            timerTask = nil
            irisLog(.info, "Witness paused", category: IRISLogger.agents)
        } else if timerTask == nil, let container = modelContainer {
            await start(modelContainer: container)
            irisLog(.info, "Witness resumed", category: IRISLogger.agents)
        }
    }

    public var isPaused: Bool {
        timerTask == nil
    }

    // MARK: — Capture frontmost

    private func captureFrontmost() async {
        let snapshot = await Self.fetchFrontmostSnapshot()
        guard let snapshot else { return }

        // Ignore IRIS lui-même (pas intéressant à signaler)
        guard snapshot.bundleId != "app.iris.macos" else {
            lastFrontmostBundleId = snapshot.bundleId
            return
        }

        // Debounce : si même app que dernier tick et < debounceSeconds, skip
        let now = Date()
        if snapshot.bundleId == lastFrontmostBundleId && now.timeIntervalSince(lastFrontmostAt) < debounceSeconds {
            return
        }

        lastFrontmostBundleId = snapshot.bundleId
        lastFrontmostAt = now

        // Cross-ref Cartographer pour project guess
        let projectGuess = await guessProject(snapshot: snapshot)

        let summary: String
        if let project = projectGuess {
            summary = "Mehdi sur \(snapshot.appName) · \(project)"
        } else {
            summary = "Mehdi sur \(snapshot.appName)"
        }

        await EventBus.shared.publish(
            .signalEmitted(
                from: .witness,
                importance: .trivial,
                summary: summary,
                source: "screen"
            )
        )

        irisLog(.debug, "Witness frontmost: \(summary)", category: IRISLogger.agents)
    }

    /// MainActor helper : NSWorkspace n'est pas Sendable, accès doit être main-isolated.
    @MainActor
    private static func fetchFrontmostSnapshot() async -> FrontmostSnapshot? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return FrontmostSnapshot(
            appName: app.localizedName ?? "Unknown",
            bundleId: app.bundleIdentifier ?? ""
        )
    }

    /// Cross-ref avec ProjectRecord SwiftData si l'app suggère un repo actif.
    /// Heuristique simple v1.5.A : si app == Cursor / Xcode / Visual Studio Code,
    /// retourne le projet le plus récemment actif.
    private func guessProject(snapshot: FrontmostSnapshot) async -> String? {
        let devApps = ["com.apple.dt.Xcode", "com.todesktop.230313mzl4w4u92",  // Cursor
                       "com.microsoft.VSCode", "com.jetbrains.intellij", "io.warp.Warp"]
        guard devApps.contains(snapshot.bundleId) else { return nil }

        guard let container = await modelContainer else { return nil }
        return await Self.fetchMostRecentActiveProject(container: container)
    }

    @MainActor
    private static func fetchMostRecentActiveProject(container: ModelContainer) async -> String? {
        let context = container.mainContext
        var descriptor = FetchDescriptor<ProjectRecord>(
            sortBy: [SortDescriptor(\.lastPushAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        let results = (try? context.fetch(descriptor)) ?? []
        return results.first?.codename
    }

    // MARK: — Helpers types

    struct FrontmostSnapshot: Sendable {
        let appName: String
        let bundleId: String
    }
}

import Foundation
import AppKit
import SwiftData
import CoreGraphics
import ImageIO  // v1.108 — PNG encoding via CGImageDestination
import ScreenCaptureKit  // v1.108 — replaces CGWindowListCreateImage (deprecated macOS 14+)

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

    /// v1.80 — Force une capture frontmost immédiate (bypass debounce 10s).
    public func triggerSnapshotNow() async {
        lastFrontmostBundleId = nil  // reset debounce
        lastFrontmostAt = .distantPast
        await captureFrontmost()
    }

    // MARK: — v1.108 Screenshot capture (frontmost window only)

    /// Capture la frontmost window de l'app focus en PNG. Requiert Screen Recording TCC permission.
    /// Retourne nil si pas de window OU si TCC denied (CGWindowListCreateImage retourne nil).
    /// Note : privacy-conscious — capture seulement la window focus, pas l'écran entier.
    public func captureFrontmostWindowPNG() async -> Data? {
        return await Self.fetchFrontmostWindowPNG()
    }

    /// Capture frontmost window via ScreenCaptureKit (macOS 14+).
    /// SCShareableContent.current throws si TCC denied — on catch et retourne nil.
    private static func fetchFrontmostWindowPNG() async -> Data? {
        let pid: pid_t = await MainActor.run { NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0 }
        guard pid != 0 else { return nil }

        // List windows shareable (throws si user a denié Screen Recording)
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.current
        } catch {
            irisLog(.warning, "Witness vision : SCShareableContent denied — \(error.localizedDescription)",
                    category: IRISLogger.agents)
            return nil
        }

        // Cherche la première window owned by frontmost app (skip background / off-screen)
        let target = content.windows.first { window in
            guard let app = window.owningApplication else { return false }
            return app.processID == pid && window.isOnScreen && window.windowLayer == 0
        }
        guard let targetWindow = target else { return nil }

        // Config capture : dimensions natives, format BGRA (le défaut SCKit)
        let config = SCStreamConfiguration()
        config.width = Int(targetWindow.frame.width)
        config.height = Int(targetWindow.frame.height)
        config.showsCursor = false  // pas besoin du curseur

        let filter = SCContentFilter(desktopIndependentWindow: targetWindow)

        let cgImage: CGImage
        do {
            cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            irisLog(.warning, "Witness vision : captureImage failed — \(error.localizedDescription)",
                    category: IRISLogger.agents)
            return nil
        }

        // Encode en PNG via ImageIO
        let mutableData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            mutableData,
            "public.png" as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return mutableData as Data
    }

    // MARK: — v1.58 Blocklist (apps sensibles : Mail, Slack, 1Password, etc.)

    private static let blocklistKey = "iris.witness.blockedBundleIds"

    /// Bundle IDs ignorés lors de la capture frontmost. Persisté UserDefaults.
    public static var blockedBundleIds: Set<String> {
        let raw = UserDefaults.standard.stringArray(forKey: blocklistKey) ?? []
        return Set(raw)
    }

    public static func setBlocked(_ ids: Set<String>) {
        UserDefaults.standard.set(Array(ids), forKey: blocklistKey)
    }

    public static func addBlocked(_ id: String) {
        var ids = blockedBundleIds
        ids.insert(id.trimmingCharacters(in: .whitespaces))
        setBlocked(ids)
    }

    public static func removeBlocked(_ id: String) {
        var ids = blockedBundleIds
        ids.remove(id)
        setBlocked(ids)
    }

    /// Bundle IDs courants suggérés à blocker (apps sensibles).
    public static let suggestedBlocklist: [(bundleId: String, name: String)] = [
        ("com.apple.mail", "Mail"),
        ("com.tinyspeck.slackmacgap", "Slack"),
        ("com.agilebits.onepassword7", "1Password"),
        ("com.1password.1password", "1Password 8"),
        ("com.apple.MobileSMS", "Messages"),
        ("com.hnc.Discord", "Discord"),
        ("com.apple.facetime", "FaceTime"),
        ("com.apple.AddressBook", "Contacts")
    ]

    // MARK: — Capture frontmost

    private func captureFrontmost() async {
        let snapshot = await Self.fetchFrontmostSnapshot()
        guard let snapshot else { return }

        // Ignore IRIS lui-même (pas intéressant à signaler)
        guard snapshot.bundleId != "app.iris.macos" else {
            lastFrontmostBundleId = snapshot.bundleId
            return
        }

        // v1.58 — Ignore bundle IDs blocklistés par Mehdi (apps sensibles)
        guard !Self.blockedBundleIds.contains(snapshot.bundleId) else {
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

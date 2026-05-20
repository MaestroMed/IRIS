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
    private var githubPollTask: Task<Void, Never>?
    private var fsPollTask: Task<Void, Never>?
    private var pollIntervalSeconds: UInt64 = 60
    private var githubPollIntervalSeconds: UInt64 = 300  // 5 min
    private var fsPollIntervalSeconds: UInt64 = 60       // 1 min
    private weak var modelContainer: ModelContainer?
    private static let githubAccount = "MaestroMed"
    private static let githubCacheKey = "iris.sentinel.githubCache"
    private static let fsCacheKey = "iris.sentinel.fsCache"
    private static let fsSkipPatterns = ["node_modules", ".next", ".build", "Derived", ".git",
                                         "DerivedData", "dist", "build", ".turbo", ".swiftpm",
                                         "Pods", "vendor", "__pycache__"]

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
        restoreIntervalsFromDefaults()  // v1.30 — restore intervals from UserDefaults
        guard timerTask == nil else { return }

        timerTask = Task { [weak self] in
            // Premier tick après 5s pour donner du feedback rapide à Mehdi.
            try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
            while !Task.isCancelled {
                await self?.emitStubSignal()
                try? await Task.sleep(nanoseconds: (self?.pollIntervalSeconds ?? 60) * 1_000_000_000)
            }
        }

        // v1.2.A — GitHub poll task : check pushedAt deltas toutes les 5 min
        githubPollTask = Task { [weak self] in
            // Premier poll après 10s pour init le cache sans signal
            try? await Task.sleep(nanoseconds: 10 * 1_000_000_000)
            await self?.initGitHubCache()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: (self?.githubPollIntervalSeconds ?? 300) * 1_000_000_000)
                await self?.pollGitHubDeltas()
            }
        }

        // v1.2.B — FS watcher : poll mtime des projets actifs toutes les 60s
        fsPollTask = Task { [weak self] in
            // Premier poll après 15s pour init le cache sans signal
            try? await Task.sleep(nanoseconds: 15 * 1_000_000_000)
            await self?.initFSCache()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: (self?.fsPollIntervalSeconds ?? 60) * 1_000_000_000)
                await self?.pollFSDeltas()
            }
        }

        irisLog(.info,
            "Sentinel started — stub=\(pollIntervalSeconds)s + GitHub=\(githubPollIntervalSeconds)s + FS=\(fsPollIntervalSeconds)s",
            category: IRISLogger.agents
        )
    }

    public func stop() {
        timerTask?.cancel()
        timerTask = nil
        githubPollTask?.cancel()
        githubPollTask = nil
        fsPollTask?.cancel()
        fsPollTask = nil
    }

    public func setInterval(_ seconds: UInt64) {
        self.pollIntervalSeconds = max(10, seconds)
    }

    // MARK: — v1.30 Configurable intervals + UserDefaults persist

    private static let stubIntervalKey = "iris.sentinel.intervalStub"
    private static let githubIntervalKey = "iris.sentinel.intervalGithub"
    private static let fsIntervalKey = "iris.sentinel.intervalFS"

    public func setStubInterval(_ seconds: UInt64) {
        let bounded = max(10, min(600, seconds))
        self.pollIntervalSeconds = bounded
        UserDefaults.standard.set(Int(bounded), forKey: Self.stubIntervalKey)
    }

    public func setGithubInterval(_ seconds: UInt64) {
        let bounded = max(30, min(1800, seconds))
        self.githubPollIntervalSeconds = bounded
        UserDefaults.standard.set(Int(bounded), forKey: Self.githubIntervalKey)
    }

    public func setFSInterval(_ seconds: UInt64) {
        let bounded = max(10, min(600, seconds))
        self.fsPollIntervalSeconds = bounded
        UserDefaults.standard.set(Int(bounded), forKey: Self.fsIntervalKey)
    }

    public var currentStubInterval: UInt64 { pollIntervalSeconds }
    public var currentGithubInterval: UInt64 { githubPollIntervalSeconds }
    public var currentFSInterval: UInt64 { fsPollIntervalSeconds }

    /// Restore intervals depuis UserDefaults (appelé au start).
    private func restoreIntervalsFromDefaults() {
        if let stored = UserDefaults.standard.object(forKey: Self.stubIntervalKey) as? Int, stored > 0 {
            self.pollIntervalSeconds = UInt64(stored)
        }
        if let stored = UserDefaults.standard.object(forKey: Self.githubIntervalKey) as? Int, stored > 0 {
            self.githubPollIntervalSeconds = UInt64(stored)
        }
        if let stored = UserDefaults.standard.object(forKey: Self.fsIntervalKey) as? Int, stored > 0 {
            self.fsPollIntervalSeconds = UInt64(stored)
        }
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

    // MARK: — v1.2.A GitHub poll

    /// Init cache au démarrage sans émettre de signal (évite spam initial avec pushedAt anciens).
    private func initGitHubCache() async {
        let current = await fetchGitHubPushedAtMap()
        guard !current.isEmpty else { return }
        await persistGitHubCache(current)
        irisLog(.info, "Sentinel GitHub cache initialized — \(current.count) repos tracked", category: IRISLogger.agents)
    }

    /// Poll deltas : compare current pushedAt vs cached, emit Signal pour chaque delta.
    private func pollGitHubDeltas() async {
        let cached = await loadGitHubCache()
        let current = await fetchGitHubPushedAtMap()
        guard !current.isEmpty else { return }

        var deltas: [(repo: String, oldDate: Date?, newDate: Date)] = []
        for (repo, newDate) in current {
            let oldDate = cached[repo]
            if oldDate == nil || (oldDate ?? .distantPast) < newDate {
                deltas.append((repo, oldDate, newDate))
            }
        }

        if !deltas.isEmpty {
            irisLog(.notice, "Sentinel detected \(deltas.count) GitHub push deltas", category: IRISLogger.agents)
        }

        for delta in deltas {
            // Skip si oldDate était nil (premier scan) — déjà géré par initGitHubCache mais safe net
            guard delta.oldDate != nil else { continue }

            let timeAgo = Date().timeIntervalSince(delta.newDate)
            let importance: SignalImportance = timeAgo < 600 ? .high : .medium
            let summary = "Nouveau push sur `\(delta.repo)` (\(formatTimeAgo(timeAgo)))"

            await EventBus.shared.publish(
                .signalEmitted(
                    from: .sentinel,
                    importance: importance,
                    summary: summary,
                    source: "github"
                )
            )

            if let container = await modelContainer {
                await MainActor.run {
                    let signal = Signal(
                        source: "github",
                        importance: importance.rawValue,
                        summary: summary,
                        rawLink: "https://github.com/\(Self.githubAccount)/\(delta.repo)",
                        projectScope: delta.repo
                    )
                    container.mainContext.insert(signal)
                    try? container.mainContext.save()
                }
            }
        }

        await persistGitHubCache(current)
    }

    /// Fetch pushedAt par repo via gh CLI. Retourne [repo_name: Date].
    private func fetchGitHubPushedAtMap() async -> [String: Date] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "gh", "repo", "list", Self.githubAccount,
            "--limit", "100",
            "--json", "name,pushedAt"
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return [:]
        }
        guard process.terminationStatus == 0 else { return [:] }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [:] }

        let iso = ISO8601DateFormatter()
        var map: [String: Date] = [:]
        for entry in json {
            guard let name = entry["name"] as? String,
                  let pushedAtStr = entry["pushedAt"] as? String,
                  let date = iso.date(from: pushedAtStr)
            else { continue }
            map[name] = date
        }
        return map
    }

    private func loadGitHubCache() async -> [String: Date] {
        guard let data = UserDefaults.standard.data(forKey: Self.githubCacheKey),
              let raw = try? JSONDecoder().decode([String: Date].self, from: data)
        else { return [:] }
        return raw
    }

    private func persistGitHubCache(_ map: [String: Date]) async {
        if let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: Self.githubCacheKey)
        }
    }

    // MARK: — v1.2.B FS watcher

    private func initFSCache() async {
        let current = await scanActiveProjectMtimes()
        guard !current.isEmpty else { return }
        await persistFSCache(current)
        irisLog(.info, "Sentinel FS cache initialized — \(current.count) projets actifs trackés",
                category: IRISLogger.agents)
    }

    private func pollFSDeltas() async {
        let cached = await loadFSCache()
        let current = await scanActiveProjectMtimes()
        guard !current.isEmpty else { return }

        var deltas: [(project: String, oldMtime: Date?, newMtime: Date)] = []
        for (project, mtime) in current {
            let oldMtime = cached[project]
            if oldMtime == nil || (oldMtime ?? .distantPast) < mtime {
                deltas.append((project, oldMtime, mtime))
            }
        }

        if !deltas.isEmpty {
            irisLog(.debug, "Sentinel FS deltas: \(deltas.count)", category: IRISLogger.agents)
        }

        // Batched : si > 5 deltas, regroupe en 1 signal pour éviter spam node_modules install etc.
        if deltas.count > 5 {
            let projects = deltas.map(\.project).joined(separator: ", ")
            await EventBus.shared.publish(
                .signalEmitted(
                    from: .sentinel,
                    importance: .low,
                    summary: "\(deltas.count) projets touchés (\(projects.prefix(80))...)",
                    source: "fs-batch"
                )
            )
        } else {
            for delta in deltas {
                guard delta.oldMtime != nil else { continue }
                let timeAgo = Date().timeIntervalSince(delta.newMtime)
                let importance: SignalImportance = timeAgo < 30 ? .low : .trivial
                let summary = "Fichier modifié dans `\(delta.project)` (\(formatTimeAgo(timeAgo)))"

                await EventBus.shared.publish(
                    .signalEmitted(
                        from: .sentinel,
                        importance: importance,
                        summary: summary,
                        source: "fs"
                    )
                )

                if let container = await modelContainer {
                    let projectName = delta.project
                    let summaryCopy = summary
                    await MainActor.run {
                        let signal = Signal(
                            source: "fs",
                            importance: importance.rawValue,
                            summary: summaryCopy,
                            projectScope: projectName
                        )
                        container.mainContext.insert(signal)
                        try? container.mainContext.save()
                    }
                }
            }
        }

        await persistFSCache(current)
    }

    /// Scan mtime des projets actifs depuis ProjectRecord SwiftData.
    /// Retourne [codename: mtime du dir top-level].
    private func scanActiveProjectMtimes() async -> [String: Date] {
        guard let container = await modelContainer else { return [:] }
        let projectPaths = await Self.fetchActiveProjectPaths(container: container)
        var result: [String: Date] = [:]
        for (codename, path) in projectPaths {
            guard let path else { continue }
            // Skip si pattern à ignorer
            if Self.fsSkipPatterns.contains(where: { path.contains("/\($0)/") }) { continue }
            let url = URL(fileURLWithPath: path)
            if let attrs = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
               let mtime = attrs.contentModificationDate {
                result[codename] = mtime
            }
        }
        return result
    }

    /// Extrait juste codename + localPath (Sendable) pour traverser actor isolation
    /// (ProjectRecord @Model n'est pas Sendable).
    @MainActor
    private static func fetchActiveProjectPaths(container: ModelContainer) async -> [(String, String?)] {
        let descriptor = FetchDescriptor<ProjectRecord>(
            predicate: #Predicate { $0.status == "active" }
        )
        let projects = (try? container.mainContext.fetch(descriptor)) ?? []
        return projects.map { ($0.codename, $0.localPath) }
    }

    private func loadFSCache() async -> [String: Date] {
        guard let data = UserDefaults.standard.data(forKey: Self.fsCacheKey),
              let raw = try? JSONDecoder().decode([String: Date].self, from: data)
        else { return [:] }
        return raw
    }

    private func persistFSCache(_ map: [String: Date]) async {
        if let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: Self.fsCacheKey)
        }
    }

    nonisolated private func formatTimeAgo(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "\(Int(seconds))s ago" }
        if seconds < 3600 { return "\(Int(seconds / 60))min ago" }
        if seconds < 86400 { return "\(Int(seconds / 3600))h ago" }
        return "\(Int(seconds / 86400))j ago"
    }

    // MARK: — Helpers

    private struct StubSignal: Sendable {
        let source: String
        let importance: SignalImportance
        let summary: String
        let project: String?
    }
}

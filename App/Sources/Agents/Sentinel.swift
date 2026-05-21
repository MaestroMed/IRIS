import Foundation
import SwiftData
import CryptoKit  // v1.119 — SHA256 dedup hash

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
    private var mcpPollTask: Task<Void, Never>?  // v1.117
    private var pollIntervalSeconds: UInt64 = 60
    private var githubPollIntervalSeconds: UInt64 = 300  // 5 min
    private var fsPollIntervalSeconds: UInt64 = 60       // 1 min
    private let mcpPollIntervalSeconds: UInt64 = 300     // v1.117 — 5 min

    // v1.156 — Last poll timestamps (visible Inspector pour debug santé)
    public private(set) var lastStubEmittedAt: Date? = nil
    public private(set) var lastGithubPollAt: Date? = nil
    public private(set) var lastFSPollAt: Date? = nil
    public private(set) var lastMCPPollAt: Date? = nil
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

        // v1.117 — MCP poll loop : pour chaque source avec backend MCP, ping le server
        // toutes les 5min pour prouver la wire end-to-end + initial tools discovery.
        mcpPollTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 20 * 1_000_000_000)  // attend que MCPManager discover
            while !Task.isCancelled {
                await self?.pollMCPSources()
                try? await Task.sleep(nanoseconds: (self?.mcpPollIntervalSeconds ?? 300) * 1_000_000_000)
            }
        }

        irisLog(.info,
            "Sentinel started — stub=\(pollIntervalSeconds)s + GitHub=\(githubPollIntervalSeconds)s + FS=\(fsPollIntervalSeconds)s + MCP=\(mcpPollIntervalSeconds)s",
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
        mcpPollTask?.cancel()
        mcpPollTask = nil
    }

    // MARK: — v1.117 MCP poll loop

    /// Pour chaque source configurée avec backend MCP, spawn temporairement le server,
    /// initialize + tools/list, et émet un Signal "MCP <source> ok: N tools".
    /// v1.118 enrichira avec real tool calling pour fetch les vrais data.
    private func pollMCPSources() async {
        // v1.148 — skip hors plage horaire active
        guard Self.isWithinActiveHours() else { return }
        for source in Self.knownSources {
            guard let serverName = Self.mcpServerName(for: source) else { continue }
            guard !Self.mutedSources.contains(source) else { continue }
            guard !Self.isSnoozedNow(source: source) else { continue }
            await pollMCPSource(source: source, serverName: serverName)
        }
        lastMCPPollAt = .now  // v1.156
    }

    @MainActor
    private static func resolveServerConfig(name: String) async -> MCPManager.ServerConfig? {
        return MCPManager.shared.servers.first(where: { $0.name == name })
    }

    private func pollMCPSource(source: String, serverName: String) async {
        // Récupère le ServerConfig depuis MainActor
        guard let server = await Self.resolveServerConfig(name: serverName) else {
            irisLog(.warning, "Sentinel MCP poll: server '\(serverName)' not found in MCPManager",
                    category: IRISLogger.agents)
            return
        }

        let clientConfig = await MainActor.run {
            MCPManager.shared.makeClientConfig(for: server)
        }
        let client = MCPClient(config: clientConfig)

        do {
            try await client.start()
        } catch {
            irisLog(.warning, "Sentinel MCP poll \(source) start failed: \(error)",
                    category: IRISLogger.agents)
            return
        }
        defer { Task { await client.stop() } }

        // Initialize handshake
        let initParams: [String: Any] = [
            "protocolVersion": "2024-11-05",
            "capabilities": [String: Any](),
            "clientInfo": ["name": "IRIS-Sentinel", "version": IRISRuntimeInfo.appVersion]
        ]
        do {
            _ = try await client.callMethod("initialize", params: initParams, timeout: 10)
        } catch {
            irisLog(.warning, "Sentinel MCP poll \(source) initialize failed: \(error)",
                    category: IRISLogger.agents)
            return
        }
        try? await client.notify("notifications/initialized")

        // v1.118 — Si un tool name est configuré pour cette source, call tools/call.
        // Sinon, fallback v1.117 : ping tools/list + signal "OK N tools".
        if let toolName = Self.mcpToolName(for: source) {
            await callMCPTool(client: client, source: source, serverName: serverName, toolName: toolName)
        } else {
            await pingMCPToolsList(client: client, source: source, serverName: serverName)
        }
    }

    /// v1.117 — Fallback : juste list les tools dispo et émet un ping signal.
    private func pingMCPToolsList(client: MCPClient, source: String, serverName: String) async {
        var toolNames: [String] = []
        if let data = try? await client.callMethod("tools/list", params: [:], timeout: 5),
           let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let tools = result["tools"] as? [[String: Any]] {
            toolNames = tools.compactMap { $0["name"] as? String }
        }

        let summary = "MCP \(source) (\(serverName)) OK : \(toolNames.count) tools — \(toolNames.prefix(3).joined(separator: ", "))"
        await emitSignal(source: source, summary: summary, importance: .low)
        irisLog(.info, "Sentinel MCP ping \(source) → \(toolNames.count) tools", category: IRISLogger.agents)
    }

    /// v1.118 — Call un tool spécifique + parse content[0].text → Signal.
    private func callMCPTool(client: MCPClient, source: String, serverName: String, toolName: String) async {
        let params: [String: Any] = [
            "name": toolName,
            "arguments": [String: Any]()  // empty pour v1.118 — args personnalisés en v1.119+
        ]
        guard let data = try? await client.callMethod("tools/call", params: params, timeout: 15) else {
            irisLog(.warning, "Sentinel MCP \(source) tools/call '\(toolName)' failed",
                    category: IRISLogger.agents)
            return
        }
        guard let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            irisLog(.warning, "Sentinel MCP \(source) decode result failed", category: IRISLogger.agents)
            return
        }

        // MCP tools/call response format : {content: [{type: "text", text: "..."}], isError: false}
        let content = result["content"] as? [[String: Any]] ?? []
        let texts: [String] = content.compactMap { block in
            (block["type"] as? String) == "text" ? (block["text"] as? String) : nil
        }
        let isError = (result["isError"] as? Bool) ?? false

        let combined = texts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !combined.isEmpty else {
            irisLog(.warning, "Sentinel MCP \(source) empty content from '\(toolName)'",
                    category: IRISLogger.agents)
            return
        }

        // v1.119 — Dedup : skip si déjà vu récemment pour cette source
        if Self.dedupCheckAndStore(source: source, content: combined) {
            irisLog(.debug, "Sentinel MCP \(source) dedup skip '\(toolName)' (\(combined.count) chars)",
                    category: IRISLogger.agents)
            return
        }

        let importance: SignalImportance = isError ? .critical : .medium
        let summary = "[\(serverName).\(toolName)] " + String(combined.prefix(200))
        await emitSignal(source: source, summary: summary, importance: importance)
        irisLog(.info,
            "Sentinel MCP \(source) call '\(toolName)' → \(combined.count) chars (isError=\(isError) cached=\(Self.dedupCacheCount(source: source)))",
            category: IRISLogger.agents
        )
    }

    /// Helper : publish + persist en SwiftData.
    private func emitSignal(source: String, summary: String, importance: SignalImportance) async {
        await EventBus.shared.publish(
            .signalEmitted(from: .sentinel, importance: importance, summary: summary, source: source)
        )
        if let container = await modelContainer {
            let summaryCopy = summary
            let sourceCopy = source
            let importanceRaw = importance.rawValue
            await MainActor.run {
                let signal = Signal(
                    source: sourceCopy,
                    importance: importanceRaw,
                    summary: summaryCopy
                )
                container.mainContext.insert(signal)
                try? container.mainContext.save()
            }
        }
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

    // MARK: — v1.60 Trigger now (force immediate scan, bypass timer)

    /// Force un signal stub immédiat (pour tester le flow Sentinel→Quill).
    public func triggerStubNow() async {
        await emitStubSignal()
    }

    // MARK: — v1.74 Source mute (per-source toggle Settings)

    private static let mutedSourcesKey = "iris.sentinel.mutedSources"

    /// Sources mutées : Sentinel skip l'émission pour ces sources (gmail/github/calendar/fs/screen).
    public static var mutedSources: Set<String> {
        let raw = UserDefaults.standard.stringArray(forKey: mutedSourcesKey) ?? []
        return Set(raw)
    }

    public static func setMuted(_ sources: Set<String>) {
        UserDefaults.standard.set(Array(sources), forKey: mutedSourcesKey)
    }

    public static func toggleMuted(_ source: String) {
        var ids = mutedSources
        if ids.contains(source) {
            ids.remove(source)
        } else {
            ids.insert(source)
        }
        setMuted(ids)
    }

    public static let knownSources: [String] = ["gmail", "github", "calendar", "fs"]

    // MARK: — v1.148 Active hours window (mute Sentinel hors plage horaire configurée)

    private static let activeHourStartKey = "iris.sentinel.activeHourStart"
    private static let activeHourEndKey = "iris.sentinel.activeHourEnd"

    public static var activeHourStart: Int {
        UserDefaults.standard.integer(forKey: activeHourStartKey)  // default 0
    }

    public static var activeHourEnd: Int {
        let raw = UserDefaults.standard.integer(forKey: activeHourEndKey)
        return raw > 0 ? raw : 24  // default 24 = always active
    }

    public static func setActiveHourWindow(start: Int, end: Int) {
        UserDefaults.standard.set(max(0, min(23, start)), forKey: activeHourStartKey)
        UserDefaults.standard.set(max(1, min(24, end)), forKey: activeHourEndKey)
    }

    /// True si l'heure courante est dans la fenêtre [start, end[. Toujours true si window = [0,24[.
    public static func isWithinActiveHours() -> Bool {
        let start = activeHourStart
        let end = activeHourEnd
        if start == 0 && end == 24 { return true }
        let hour = Calendar.current.component(.hour, from: Date())
        if start < end {
            return hour >= start && hour < end
        } else {
            // Window cross-midnight (e.g. 22..6)
            return hour >= start || hour < end
        }
    }

    // MARK: — v1.116 Source backend (stub vs MCP <serverName>)

    /// Backend par source : "stub" (templates fictifs) ou "mcp:<serverName>".
    /// Stocké comme [source: backend] dans UserDefaults.
    private static let sourceBackendKey = "iris.sentinel.sourceBackend"

    public static func sourceBackend(for source: String) -> String {
        let map = (UserDefaults.standard.dictionary(forKey: sourceBackendKey) as? [String: String]) ?? [:]
        return map[source] ?? "stub"
    }

    public static func setSourceBackend(_ backend: String, for source: String) {
        var map = (UserDefaults.standard.dictionary(forKey: sourceBackendKey) as? [String: String]) ?? [:]
        map[source] = backend
        UserDefaults.standard.set(map, forKey: sourceBackendKey)
    }

    /// True si backend de cette source est "mcp:..." (stub skip nécessaire).
    public static func isMCPBackend(for source: String) -> Bool {
        sourceBackend(for: source).hasPrefix("mcp:")
    }

    /// Extract le serverName depuis "mcp:<serverName>" — nil si stub.
    public static func mcpServerName(for source: String) -> String? {
        let backend = sourceBackend(for: source)
        guard backend.hasPrefix("mcp:") else { return nil }
        return String(backend.dropFirst("mcp:".count))
    }

    // v1.118 — Per-source tool name + args JSON (tools/call wire)
    private static let mcpToolNameKey = "iris.sentinel.mcpToolName"

    /// Tool name à invoquer pour cette source. Nil = ne pas appeler tools/call,
    /// juste émettre le ping "OK N tools" (comportement v1.117).
    public static func mcpToolName(for source: String) -> String? {
        let map = (UserDefaults.standard.dictionary(forKey: mcpToolNameKey) as? [String: String]) ?? [:]
        return map[source]
    }

    public static func setMcpToolName(_ name: String?, for source: String) {
        var map = (UserDefaults.standard.dictionary(forKey: mcpToolNameKey) as? [String: String]) ?? [:]
        if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty {
            map[source] = name.trimmingCharacters(in: .whitespaces)
        } else {
            map.removeValue(forKey: source)
        }
        UserDefaults.standard.set(map, forKey: mcpToolNameKey)
    }

    // v1.119 — Dedup cache : SHA256(source + content) per emit, ring buffer 1000/source
    private static let dedupCacheKey = "iris.sentinel.mcpDedupCache"  // [source: [hash hex]]
    private static let dedupCacheMaxPerSource = 1000

    /// True si déjà vu récemment (et noté). Retourne false + ajoute au cache sinon.
    public static func dedupCheckAndStore(source: String, content: String) -> Bool {
        let hash = sha256Hex(content)
        var cache = (UserDefaults.standard.dictionary(forKey: dedupCacheKey) as? [String: [String]]) ?? [:]
        let perSource = cache[source] ?? []
        if perSource.contains(hash) {
            return true  // already seen → skip emit
        }
        var updated = perSource
        updated.append(hash)
        if updated.count > dedupCacheMaxPerSource {
            updated.removeFirst(updated.count - dedupCacheMaxPerSource)
        }
        cache[source] = updated
        UserDefaults.standard.set(cache, forKey: dedupCacheKey)
        return false
    }

    public static func clearDedupCache(source: String? = nil) {
        if let source {
            var cache = (UserDefaults.standard.dictionary(forKey: dedupCacheKey) as? [String: [String]]) ?? [:]
            cache.removeValue(forKey: source)
            UserDefaults.standard.set(cache, forKey: dedupCacheKey)
        } else {
            UserDefaults.standard.removeObject(forKey: dedupCacheKey)
        }
    }

    public static func dedupCacheCount(source: String) -> Int {
        let cache = (UserDefaults.standard.dictionary(forKey: dedupCacheKey) as? [String: [String]]) ?? [:]
        return (cache[source] ?? []).count
    }

    private static func sha256Hex(_ s: String) -> String {
        let digest = SHA256.hash(data: Data(s.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: — v1.88 Snooze (timed mute per source)

    private static let snoozeUntilKey = "iris.sentinel.snoozeUntil"  // [source: ISO timestamp]

    /// Set snooze pour `source` jusqu'à `until`. Pendant la fenêtre, Sentinel skip.
    public static func snooze(source: String, until: Date) {
        var map = snoozeMap()
        let iso = ISO8601DateFormatter().string(from: until)
        map[source] = iso
        persistSnoozeMap(map)
    }

    public static func snoozeMap() -> [String: String] {
        return (UserDefaults.standard.dictionary(forKey: snoozeUntilKey) as? [String: String]) ?? [:]
    }

    public static func snoozeUntil(source: String) -> Date? {
        let map = snoozeMap()
        guard let iso = map[source] else { return nil }
        return ISO8601DateFormatter().date(from: iso)
    }

    public static func clearSnooze(source: String) {
        var map = snoozeMap()
        map.removeValue(forKey: source)
        persistSnoozeMap(map)
    }

    /// True si snooze actif (future timestamp). Auto-clean si dépassé.
    public static func isSnoozedNow(source: String) -> Bool {
        guard let until = snoozeUntil(source: source) else { return false }
        if until > Date() { return true }
        clearSnooze(source: source)
        return false
    }

    private static func persistSnoozeMap(_ map: [String: String]) {
        UserDefaults.standard.set(map, forKey: snoozeUntilKey)
    }

    /// v1.65 — Inject un signal custom (source/importance/summary par Mehdi).
    /// Émet sur bus + persiste Signal SwiftData. Utile pour tester Quill avec
    /// un input contrôlé (e.g. simuler signal client critical).
    public func injectManualSignal(
        source: String,
        importance: SignalImportance,
        summary: String,
        projectScope: String? = nil
    ) async {
        let signalId = UUID()
        await EventBus.shared.publish(
            .signalEmitted(from: .sentinel, importance: importance, summary: summary, source: source)
        )
        if let container = await modelContainer {
            await MainActor.run {
                let signal = Signal(
                    id: signalId,
                    emittedAt: .now,
                    source: source,
                    importance: importance.rawValue,
                    summary: summary,
                    projectScope: projectScope
                )
                container.mainContext.insert(signal)
                try? container.mainContext.save()
            }
        }
        irisLog(.notice,
            "Sentinel manual signal injected: [\(source)] importance=\(importance.rawValue) — \(summary)",
            category: IRISLogger.agents
        )
    }

    /// Force un poll GitHub immédiat (compare cache + emit deltas s'il y en a).
    public func triggerGithubNow() async {
        await pollGitHubDeltas()
    }

    /// Force un poll FS immédiat.
    public func triggerFSNow() async {
        await pollFSDeltas()
    }

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
        // v1.148 — skip si hors plage horaire active
        guard Self.isWithinActiveHours() else { return }
        // v1.74 — skip si source mutée
        guard !Self.mutedSources.contains(stub.source) else {
            irisLog(.debug, "Sentinel stub signal muted (source=\(stub.source))", category: IRISLogger.agents)
            return
        }
        // v1.88 — skip si source snoozée
        guard !Self.isSnoozedNow(source: stub.source) else {
            irisLog(.debug, "Sentinel stub signal snoozed (source=\(stub.source))", category: IRISLogger.agents)
            return
        }
        // v1.116 — skip si backend MCP configuré pour cette source (real poll en v1.117)
        guard !Self.isMCPBackend(for: stub.source) else {
            irisLog(.debug, "Sentinel stub skip (source=\(stub.source) backend=mcp)", category: IRISLogger.agents)
            return
        }
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

        lastStubEmittedAt = .now  // v1.156

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
        // v1.148 — skip hors plage horaire active
        guard Self.isWithinActiveHours() else { return }
        // v1.74 — skip si source github mutée
        guard !Self.mutedSources.contains("github") else { return }
        // v1.88 — skip si snoozée
        guard !Self.isSnoozedNow(source: "github") else { return }
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
        lastGithubPollAt = .now  // v1.156
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
        // v1.148 — skip hors plage horaire active
        guard Self.isWithinActiveHours() else { return }
        // v1.74 — skip si source fs mutée
        guard !Self.mutedSources.contains("fs") else { return }
        // v1.88 — skip si snoozée
        guard !Self.isSnoozedNow(source: "fs") else { return }
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
        lastFSPollAt = .now  // v1.156
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

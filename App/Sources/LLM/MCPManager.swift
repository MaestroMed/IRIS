import Foundation
import Observation

/// v1.113 — Discovery + lifecycle des MCP servers configurés.
///
/// Source de config : `~/Library/Application Support/Claude/claude_desktop_config.json`
/// (format standard Claude Desktop : `{"mcpServers": {"name": {"command": "...", "args": [...], "env": {...}}}}`).
///
/// Permet à IRIS de réutiliser les MCP servers que Mehdi a déjà configurés pour Claude Desktop
/// (Gmail, Calendar, Slack, etc.) sans dupliquer le setup.
@MainActor
@Observable
public final class MCPManager {
    public static let shared = MCPManager()

    public struct ServerConfig: Identifiable, Sendable, Hashable {
        public let name: String
        public let command: String
        public let args: [String]
        public let env: [String: String]?

        public var id: String { name }
    }

    /// Configs découverts (mis à jour par `discover()`).
    public private(set) var servers: [ServerConfig] = []
    public private(set) var lastDiscoveryError: String?

    private init() {}

    /// Path par défaut Claude Desktop config.
    public static let defaultConfigPath: String =
        ("~/Library/Application Support/Claude/claude_desktop_config.json" as NSString)
            .expandingTildeInPath

    /// Lit le fichier de config + parse les mcpServers. Idempotent — replace servers.
    /// Retourne le nombre de serveurs découverts.
    @discardableResult
    public func discover(from path: String = MCPManager.defaultConfigPath) -> Int {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else {
            lastDiscoveryError = "Config file not found: \(path)"
            servers = []
            return 0
        }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            lastDiscoveryError = "Failed to parse JSON at \(path)"
            servers = []
            return 0
        }
        guard let mcpServers = json["mcpServers"] as? [String: Any] else {
            lastDiscoveryError = "No 'mcpServers' key in config"
            servers = []
            return 0
        }

        var discovered: [ServerConfig] = []
        for (name, raw) in mcpServers {
            guard let entry = raw as? [String: Any],
                  let command = entry["command"] as? String else { continue }
            let args = (entry["args"] as? [String]) ?? []
            let env = entry["env"] as? [String: String]
            discovered.append(ServerConfig(name: name, command: command, args: args, env: env))
        }
        servers = discovered.sorted { $0.name < $1.name }
        lastDiscoveryError = nil
        irisLog(.info, "MCPManager discovered \(servers.count) servers from \(path)",
                category: IRISLogger.agents)
        return servers.count
    }

    // MARK: — v1.114 Test connection (initialize round-trip)

    public struct TestResult: Sendable {
        public let serverName: String
        public let success: Bool
        public let serverInfo: String?  // ex: "claude-mcp-gmail v1.2.3"
        public let toolsCount: Int?     // count from tools/list
        public let toolPreview: [String]  // v1.115 — first 3 tool names
        public let errorMessage: String?
    }

    /// Spawn temporairement le server, envoie `initialize` + `notifications/initialized`
    /// + `tools/list`, retourne result + stop. Timeout 10s.
    public func testConnection(_ server: ServerConfig) async -> TestResult {
        let client = MCPClient(config: makeClientConfig(for: server))
        do {
            try await client.start()
        } catch {
            return TestResult(
                serverName: server.name,
                success: false,
                serverInfo: nil,
                toolsCount: nil,
                toolPreview: [],
                errorMessage: "start: \(error)"
            )
        }

        defer {
            Task { await client.stop() }
        }

        let initParams: [String: Any] = [
            "protocolVersion": "2024-11-05",
            "capabilities": [String: Any](),
            "clientInfo": [
                "name": "IRIS",
                "version": IRISRuntimeInfo.appVersion
            ]
        ]

        // Étape 1 — initialize
        let initResult: [String: Any]
        do {
            let data = try await client.callMethod("initialize", params: initParams, timeout: 10)
            initResult = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        } catch {
            return TestResult(
                serverName: server.name,
                success: false,
                serverInfo: nil,
                toolsCount: nil,
                toolPreview: [],
                errorMessage: "initialize: \(error)"
            )
        }

        var serverInfo: String?
        if let si = initResult["serverInfo"] as? [String: Any],
           let name = si["name"] as? String {
            let version = (si["version"] as? String) ?? "?"
            serverInfo = "\(name) v\(version)"
        }

        // Étape 2 — notifications/initialized (fire-and-forget)
        do {
            try await client.notify("notifications/initialized")
        } catch {
            // Pas bloquant, on continue mais log
            irisLog(.warning, "MCP \(server.name) notify initialized failed: \(error)",
                    category: IRISLogger.agents)
        }

        // Étape 3 — tools/list (optionnel : certains servers n'ont pas de tools)
        var toolsCount: Int?
        var toolPreview: [String] = []
        if let toolsData = try? await client.callMethod("tools/list", params: [:], timeout: 5),
           let toolsResult = try? JSONSerialization.jsonObject(with: toolsData) as? [String: Any],
           let tools = toolsResult["tools"] as? [[String: Any]] {
            toolsCount = tools.count
            toolPreview = tools.prefix(3).compactMap { $0["name"] as? String }
        }

        return TestResult(
            serverName: server.name,
            success: true,
            serverInfo: serverInfo,
            toolsCount: toolsCount,
            toolPreview: toolPreview,
            errorMessage: nil
        )
    }

    /// Construit un MCPClient.Config à partir d'un ServerConfig.
    /// Résout `command` en URL absolue : si chemin absolu → tel quel, sinon résout via /usr/bin/env.
    public func makeClientConfig(for server: ServerConfig) -> MCPClient.Config {
        let executableURL: URL
        let arguments: [String]
        if server.command.hasPrefix("/") {
            executableURL = URL(fileURLWithPath: server.command)
            arguments = server.args
        } else {
            // Use /usr/bin/env pour résoudre via PATH (utile pour npx, node, python, etc.)
            executableURL = URL(fileURLWithPath: "/usr/bin/env")
            arguments = [server.command] + server.args
        }
        return MCPClient.Config(
            executableURL: executableURL,
            arguments: arguments,
            environment: mergedEnvironment(server.env)
        )
    }

    /// Merge process env (current) avec les overrides du server config.
    private func mergedEnvironment(_ overrides: [String: String]?) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        if let overrides {
            for (k, v) in overrides {
                env[k] = (v as NSString).expandingTildeInPath
            }
        }
        return env
    }
}

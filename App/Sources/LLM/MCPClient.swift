import Foundation

/// v1.112 — MCP (Model Context Protocol) client minimaliste.
/// Spawn un MCP server externe (process) et lui parle en JSON-RPC over stdin/stdout.
///
/// Spec MCP : https://modelcontextprotocol.io
/// Format JSON-RPC 2.0 ligne par ligne :
///   Request : `{"jsonrpc":"2.0","id":<n>,"method":"...","params":{...}}\n`
///   Response : `{"jsonrpc":"2.0","id":<n>,"result":{...}}` ou `{"jsonrpc":"2.0","id":<n>,"error":{...}}`
///
/// v1.112 = skeleton seulement : init/start/callMethod/stop. Pas encore plugged dans Sentinel.
/// v1.113+ : discovery `~/.claude/mcp/*.json` + OAuth tokens.
public actor MCPClient {
    public struct Config: Sendable {
        public let executableURL: URL
        public let arguments: [String]
        public let environment: [String: String]?

        public init(executableURL: URL, arguments: [String] = [], environment: [String: String]? = nil) {
            self.executableURL = executableURL
            self.arguments = arguments
            self.environment = environment
        }
    }

    public enum MCPError: Error, CustomStringConvertible {
        case notStarted
        case alreadyStarted
        case processFailed(String)
        case sendFailed(String)
        case decodeFailed(String)
        case apiError(code: Int, message: String)

        public var description: String {
            switch self {
            case .notStarted: return "MCP server not started"
            case .alreadyStarted: return "MCP server already started"
            case .processFailed(let msg): return "Process failed: \(msg)"
            case .sendFailed(let msg): return "Send failed: \(msg)"
            case .decodeFailed(let msg): return "Decode failed: \(msg)"
            case .apiError(let code, let msg): return "MCP error \(code): \(msg)"
            }
        }
    }

    private let config: Config
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var nextId: Int = 1
    private var pendingResponses: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private var readerTask: Task<Void, Never>?

    public init(config: Config) {
        self.config = config
    }

    /// Lance le process MCP server + setup les pipes + démarre le reader stdout.
    public func start() async throws {
        guard process == nil else { throw MCPError.alreadyStarted }

        let proc = Process()
        proc.executableURL = config.executableURL
        proc.arguments = config.arguments
        if let env = config.environment {
            proc.environment = env
        }
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = stderr

        do {
            try proc.run()
        } catch {
            throw MCPError.processFailed(error.localizedDescription)
        }

        self.process = proc
        self.stdinPipe = stdin
        self.stdoutPipe = stdout
        self.stderrPipe = stderr

        // Démarre le reader stdout en background (parse ligne par ligne)
        readerTask = Task { [weak self] in
            await self?.runStdoutReader()
        }

        irisLog(.info, "MCP started: \(config.executableURL.lastPathComponent) \(config.arguments.joined(separator: " "))",
                category: IRISLogger.agents)
    }

    /// Send JSON-RPC method + attend la response (timeout 30s).
    public func callMethod(_ method: String, params: [String: Any] = [:], timeout: TimeInterval = 30) async throws -> [String: Any] {
        guard process != nil, let stdin = stdinPipe else { throw MCPError.notStarted }

        let id = nextId
        nextId += 1

        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params
        ]
        let data: Data
        do {
            data = try JSONSerialization.data(withJSONObject: request, options: [])
        } catch {
            throw MCPError.sendFailed("encode request: \(error.localizedDescription)")
        }
        // JSON-RPC ligne par ligne : envoie + newline
        var lineData = data
        lineData.append(0x0A)  // \n

        do {
            try stdin.fileHandleForWriting.write(contentsOf: lineData)
        } catch {
            throw MCPError.sendFailed(error.localizedDescription)
        }

        // Attend la response via continuation. Timeout via Task.withTimeout (manuel).
        return try await withCheckedThrowingContinuation { continuation in
            pendingResponses[id] = continuation
            // Timeout fallback
            Task { [id, timeout] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                await self.failIfPending(id: id, timeoutSeconds: timeout)
            }
        }
    }

    /// Si toujours pending après timeout → resume avec error.
    private func failIfPending(id: Int, timeoutSeconds: TimeInterval) {
        if let cont = pendingResponses.removeValue(forKey: id) {
            cont.resume(throwing: MCPError.sendFailed("timeout \(timeoutSeconds)s"))
        }
    }

    /// Termine le process + nettoie.
    public func stop() {
        readerTask?.cancel()
        readerTask = nil
        process?.terminate()
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
        // Fail toutes les pending
        for (_, cont) in pendingResponses {
            cont.resume(throwing: MCPError.notStarted)
        }
        pendingResponses.removeAll()
    }

    // MARK: — Stdout reader (parse JSON-RPC responses ligne par ligne)

    private func runStdoutReader() async {
        guard let stdout = stdoutPipe else { return }
        let handle = stdout.fileHandleForReading
        var buffer = Data()
        while !Task.isCancelled {
            let chunk: Data
            do {
                // Bloquant read jusqu'à data ou EOF. Yield au runtime via continuation.
                chunk = try await withCheckedThrowingContinuation { cont in
                    DispatchQueue.global().async {
                        let data = handle.availableData
                        cont.resume(returning: data)
                    }
                }
            } catch {
                return
            }
            if chunk.isEmpty {
                // EOF
                return
            }
            buffer.append(chunk)
            // Split par newline
            while let newlineIdx = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer[..<newlineIdx]
                buffer.removeSubrange(...newlineIdx)
                guard !lineData.isEmpty else { continue }
                await handleResponseLine(Data(lineData))
            }
        }
    }

    private func handleResponseLine(_ data: Data) async {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            irisLog(.warning, "MCP unparseable response line", category: IRISLogger.agents)
            return
        }
        // Match by id
        guard let id = json["id"] as? Int else {
            // Notification ou réponse sans id : ignore pour v1.112 (pas de subscriptions encore)
            return
        }
        guard let cont = pendingResponses.removeValue(forKey: id) else { return }
        if let error = json["error"] as? [String: Any] {
            let code = (error["code"] as? Int) ?? -1
            let msg = (error["message"] as? String) ?? "(no message)"
            cont.resume(throwing: MCPError.apiError(code: code, message: msg))
        } else if let result = json["result"] as? [String: Any] {
            cont.resume(returning: result)
        } else {
            cont.resume(throwing: MCPError.decodeFailed("missing result/error in response"))
        }
    }
}

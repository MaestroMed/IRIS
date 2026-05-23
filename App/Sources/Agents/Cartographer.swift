// v1.339 — refresh() now parses real git status per local repo
import Foundation
import SwiftData

/// Cartographer v0.6 — maintient la carte vivante des projets de Mehdi.
///
/// Stratégie :
/// 1. Scan FileManager `~/Developer/*` (directories first-level seulement)
/// 2. Pour chaque projet : détection stack via fichiers indicateurs
/// 3. Shell-out `gh repo list MaestroMed --json name,isPrivate,pushedAt,description,primaryLanguage`
///    pour récupérer la métadonnée GitHub correspondante (matching par name)
/// 4. Upsert ProjectRecord SwiftData (codename = nom du dossier)
/// 5. Refresh on start + scheduled toutes les 6h
///
/// Cf docs/IRIS-AGENTS-CATALOG.md §6 Cartographer.
public actor Cartographer {
    public static let shared = Cartographer()

    private var refreshTask: Task<Void, Never>?
    private weak var modelContainer: ModelContainer?
    private static let developerDirPath = "\(NSHomeDirectory())/Developer"
    private static let githubAccount = "MaestroMed"

    private init() {}

    public func start(modelContainer: ModelContainer) async {
        self.modelContainer = modelContainer
        await refresh()
        startScheduledRefresh()
    }

    public func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    public func refresh() async {
        await refresh(localOnly: false)
    }

    /// v1.94 — Refresh complet ou local-only (skip gh repo list, plus rapide).
    public func refresh(localOnly: Bool) async {
        irisLog(.info, "Cartographer refresh start (localOnly=\(localOnly))", category: IRISLogger.agents)

        let localProjects = scanLocalProjects()
        let githubMeta: [String: GitHubProject] = localOnly ? [:] : await fetchGitHubMetadata()

        await persist(local: localProjects, github: githubMeta)

        let summary = localOnly
            ? "Carte projets rafraîchie (local-only) : \(localProjects.count) locaux"
            : "Carte projets rafraîchie : \(localProjects.count) locaux, \(githubMeta.count) GitHub"

        await EventBus.shared.publish(
            .signalEmitted(
                from: .cartographer,
                importance: .low,
                summary: summary,
                source: "cartographer"
            )
        )

        irisLog(.info, "Cartographer refresh done — \(localProjects.count) local + \(githubMeta.count) gh",
                category: IRISLogger.agents)
    }

    private func startScheduledRefresh() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                // Refresh toutes les 6h. Pour dev, on peut baisser via setRefreshInterval futur.
                try? await Task.sleep(nanoseconds: 6 * 3600 * 1_000_000_000)
                await self?.refresh()
            }
        }
    }

    // MARK: — Local scan

    private func scanLocalProjects() -> [LocalProject] {
        let url = URL(fileURLWithPath: Self.developerDirPath)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return contents.compactMap { dir -> LocalProject? in
            let isDir = (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDir else { return nil }
            let lastModified = (try? dir.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
            let stack = Self.detectStack(at: dir)
            let git = Self.parseGitStatus(at: dir)
            return LocalProject(
                codename: dir.lastPathComponent,
                localPath: dir.path,
                stack: stack,
                lastModified: lastModified,
                git: git
            )
        }
    }

    // MARK: — Git status parsing (v1.339)

    /// Parse l'état git d'un repo local en shell-out vers `/usr/bin/git`.
    /// Retourne `(nil, 0, 0, 0, nil, nil)` si ce n'est pas un repo git ou si git échoue.
    nonisolated static func parseGitStatus(at url: URL) -> GitStatus {
        let gitDir = url.appendingPathComponent(".git")
        guard FileManager.default.fileExists(atPath: gitDir.path) else {
            return GitStatus.empty
        }

        let statusOutput = runGit(args: ["-C", url.path, "status", "-sb", "-uall"])
        var branch: String? = nil
        var ahead = 0
        var behind = 0
        var dirty = 0

        if let statusOutput {
            let lines = statusOutput.split(separator: "\n", omittingEmptySubsequences: false)
            for (idx, line) in lines.enumerated() {
                if idx == 0, line.hasPrefix("## ") {
                    // Examples:
                    //   ## main...origin/main
                    //   ## main...origin/main [ahead 1, behind 2]
                    //   ## HEAD (no branch)
                    //   ## main
                    let header = String(line.dropFirst(3))
                    let (b, a, bh) = Self.parseStatusHeader(header)
                    branch = b
                    ahead = a
                    behind = bh
                } else if !line.isEmpty {
                    dirty += 1
                }
            }
        }

        var lastDate: Date? = nil
        var lastMessage: String? = nil
        if let logOutput = runGit(args: ["-C", url.path, "log", "-1", "--format=%ct|%s"]) {
            let trimmed = logOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            if let pipeIdx = trimmed.firstIndex(of: "|") {
                let tsString = String(trimmed[..<pipeIdx])
                let subject = String(trimmed[trimmed.index(after: pipeIdx)...])
                if let ts = TimeInterval(tsString) {
                    lastDate = Date(timeIntervalSince1970: ts)
                }
                if !subject.isEmpty {
                    lastMessage = subject
                }
            }
        }

        return GitStatus(
            branch: branch,
            dirty: dirty,
            ahead: ahead,
            behind: behind,
            lastDate: lastDate,
            lastMessage: lastMessage
        )
    }

    nonisolated private static func parseStatusHeader(_ header: String) -> (String?, Int, Int) {
        // Strip "(no branch)" detached-HEAD case → branch nil
        if header.hasPrefix("HEAD") || header.contains("(no branch)") {
            return (nil, 0, 0)
        }

        // Split off the optional " [ahead N, behind M]" tail
        var head = header
        var ahead = 0
        var behind = 0

        if let bracketStart = header.firstIndex(of: "["),
           let bracketEnd = header.firstIndex(of: "]"),
           bracketStart < bracketEnd {
            let tail = String(header[header.index(after: bracketStart)..<bracketEnd])
            for part in tail.split(separator: ",") {
                let kv = part.trimmingCharacters(in: .whitespaces).split(separator: " ")
                if kv.count == 2 {
                    let key = String(kv[0])
                    let val = Int(String(kv[1])) ?? 0
                    if key == "ahead" { ahead = val }
                    else if key == "behind" { behind = val }
                }
            }
            head = String(header[..<bracketStart]).trimmingCharacters(in: .whitespaces)
        }

        // head is "branch" or "branch...origin/branch"
        let branchPart: String
        if let dots = head.range(of: "...") {
            branchPart = String(head[..<dots.lowerBound])
        } else {
            branchPart = head
        }
        let branch = branchPart.trimmingCharacters(in: .whitespaces)
        return (branch.isEmpty ? nil : branch, ahead, behind)
    }

    nonisolated private static func runGit(args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }

    private static func detectStack(at url: URL) -> [String: String] {
        var stack: [String: String] = [:]
        let fm = FileManager.default

        // Framework root indicators
        if fm.fileExists(atPath: url.appendingPathComponent("Project.swift").path) {
            stack["framework"] = "swift-tuist"
            stack["language"] = "swift"
        } else if fm.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
            stack["framework"] = "swift-spm"
            stack["language"] = "swift"
        } else if fm.fileExists(atPath: url.appendingPathComponent("package.json").path) {
            stack["framework"] = "node"
            stack["language"] = "javascript"
            // Try parse package.json deps for next/vite/expo/etc.
            if let data = try? Data(contentsOf: url.appendingPathComponent("package.json")),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let deps = ((json["dependencies"] as? [String: Any]) ?? [:])
                    .merging(json["devDependencies"] as? [String: Any] ?? [:]) { a, _ in a }
                if deps["next"] != nil { stack["framework"] = "nextjs" }
                else if deps["vite"] != nil { stack["framework"] = "vite" }
                else if deps["astro"] != nil { stack["framework"] = "astro" }
                else if deps["expo"] != nil { stack["framework"] = "expo" }
                else if deps["@react-router/serve"] != nil { stack["framework"] = "react-router" }
                if deps["typescript"] != nil { stack["language"] = "typescript" }
            }
        } else if fm.fileExists(atPath: url.appendingPathComponent("pyproject.toml").path) {
            stack["framework"] = "python"
            stack["language"] = "python"
        } else if fm.fileExists(atPath: url.appendingPathComponent("requirements.txt").path) {
            stack["framework"] = "python"
            stack["language"] = "python"
        } else if fm.fileExists(atPath: url.appendingPathComponent("Cargo.toml").path) {
            stack["framework"] = "rust"
            stack["language"] = "rust"
        } else if fm.fileExists(atPath: url.appendingPathComponent("Podfile").path) {
            stack["framework"] = "ios-cocoapods"
            stack["language"] = "swift"
        }

        // Monorepo signals
        if fm.fileExists(atPath: url.appendingPathComponent("turbo.json").path) {
            stack["monorepo"] = "turborepo"
        }
        if fm.fileExists(atPath: url.appendingPathComponent("pnpm-workspace.yaml").path) {
            stack["pkg_manager"] = "pnpm"
        }

        // Claude / agents presence
        if fm.fileExists(atPath: url.appendingPathComponent("CLAUDE.md").path) {
            stack["has_claude_md"] = "true"
        }
        if fm.fileExists(atPath: url.appendingPathComponent("AGENTS.md").path)
            || fm.fileExists(atPath: url.appendingPathComponent("agents.md").path) {
            stack["has_agents_md"] = "true"
        }
        if fm.fileExists(atPath: url.appendingPathComponent(".claude").path) {
            stack["has_claude_dir"] = "true"
        }

        return stack
    }

    // MARK: — GitHub metadata via gh CLI

    private func fetchGitHubMetadata() async -> [String: GitHubProject] {
        // Spawn `gh repo list MaestroMed --limit 100 --json name,isPrivate,pushedAt,description,primaryLanguage`
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "gh", "repo", "list", Self.githubAccount,
            "--limit", "100",
            "--json", "name,isPrivate,pushedAt,description,primaryLanguage"
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            irisLog(.warning, "gh CLI introuvable ou échec (\(error.localizedDescription)) — metadata GitHub skippée",
                    category: IRISLogger.agents)
            return [:]
        }

        guard process.terminationStatus == 0 else {
            irisLog(.warning, "gh repo list exit code \(process.terminationStatus)", category: IRISLogger.agents)
            return [:]
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return [:]
        }

        var result: [String: GitHubProject] = [:]
        let iso = ISO8601DateFormatter()
        for entry in json {
            guard let name = entry["name"] as? String else { continue }
            let pushedAt: Date? = (entry["pushedAt"] as? String).flatMap { iso.date(from: $0) }
            let lang = (entry["primaryLanguage"] as? [String: Any])?["name"] as? String
            result[name] = GitHubProject(
                name: name,
                isPrivate: (entry["isPrivate"] as? Bool) ?? false,
                pushedAt: pushedAt,
                description: entry["description"] as? String,
                primaryLanguage: lang
            )
        }
        return result
    }

    // MARK: — Persistence

    @MainActor
    private func persist(local: [LocalProject], github: [String: GitHubProject]) async {
        guard let container = await modelContainer else { return }
        let context = container.mainContext

        // Union des codenames : local + github
        let allCodenames = Set(local.map(\.codename)).union(github.keys)

        for codename in allCodenames {
            let descriptor = FetchDescriptor<ProjectRecord>(predicate: #Predicate { $0.codename == codename })
            let existing = (try? context.fetch(descriptor))?.first

            let localMatch = local.first { $0.codename == codename }
            let ghMatch = github[codename]

            let mergedStack = mergeStack(local: localMatch?.stack, github: ghMatch)
            let stackJSON = (try? String(data: JSONSerialization.data(withJSONObject: mergedStack), encoding: .utf8)) ?? "{}"

            let repoURL = ghMatch.map { "https://github.com/\(Self.githubAccount)/\($0.name)" }
            let status = inferStatus(pushedAt: ghMatch?.pushedAt ?? localMatch?.lastModified)

            if let existing {
                if let path = localMatch?.localPath { existing.localPath = path }
                existing.stackJSON = stackJSON
                existing.lastScannedAt = .now
                existing.lastPushAt = ghMatch?.pushedAt ?? localMatch?.lastModified ?? existing.lastPushAt
                existing.isPrivate = ghMatch?.isPrivate ?? existing.isPrivate
                existing.repoURL = repoURL ?? existing.repoURL
                existing.status = status
                if let desc = ghMatch?.description, !desc.isEmpty {
                    existing.notes = desc
                }
                // v1.339 — live git status overwrite (only when we actually scanned the local repo)
                if let git = localMatch?.git {
                    existing.gitBranch = git.branch
                    existing.gitDirtyCount = git.dirty
                    existing.gitAhead = git.ahead
                    existing.gitBehind = git.behind
                    existing.lastCommitAt = git.lastDate ?? existing.lastCommitAt
                    existing.lastCommitMessage = git.lastMessage ?? existing.lastCommitMessage
                }
            } else {
                let git = localMatch?.git ?? .empty
                let record = ProjectRecord(
                    codename: codename,
                    displayName: codename,
                    repoURL: repoURL,
                    localPath: localMatch?.localPath,
                    domain: nil,
                    stackJSON: stackJSON,
                    status: status,
                    lastPushAt: ghMatch?.pushedAt ?? localMatch?.lastModified,
                    lastScannedAt: .now,
                    isPrivate: ghMatch?.isPrivate ?? false,
                    notes: ghMatch?.description ?? "",
                    gitBranch: git.branch,
                    gitDirtyCount: git.dirty,
                    gitAhead: git.ahead,
                    gitBehind: git.behind,
                    lastCommitAt: git.lastDate,
                    lastCommitMessage: git.lastMessage
                )
                context.insert(record)
            }
        }

        do {
            try context.save()
        } catch {
            irisLog(.error, "Cartographer persist failed: \(error)", category: IRISLogger.agents)
        }
    }

    nonisolated private func mergeStack(local: [String: String]?, github: GitHubProject?) -> [String: String] {
        var stack = local ?? [:]
        if let lang = github?.primaryLanguage, stack["language"] == nil {
            stack["language"] = lang.lowercased()
        }
        return stack
    }

    nonisolated private func inferStatus(pushedAt: Date?) -> String {
        guard let pushedAt else { return "unknown" }
        let daysAgo = Date().timeIntervalSince(pushedAt) / 86400
        if daysAgo < 30 { return "active" }
        if daysAgo < 180 { return "tiede" }
        if daysAgo < 730 { return "dormant" }
        return "archived"
    }

    // MARK: — Helpers types

    private struct LocalProject: Sendable {
        let codename: String
        let localPath: String
        let stack: [String: String]
        let lastModified: Date
        let git: GitStatus
    }

    /// État git d'un repo local (v1.339).
    struct GitStatus: Sendable {
        let branch: String?
        let dirty: Int
        let ahead: Int
        let behind: Int
        let lastDate: Date?
        let lastMessage: String?

        static let empty = GitStatus(branch: nil, dirty: 0, ahead: 0, behind: 0, lastDate: nil, lastMessage: nil)
    }

    private struct GitHubProject: Sendable {
        let name: String
        let isPrivate: Bool
        let pushedAt: Date?
        let description: String?
        let primaryLanguage: String?
    }
}

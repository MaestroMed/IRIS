import Foundation
import AppKit  // v1.137 — NSWorkspace pour openInIDE
import SwiftData

/// Builder v0.8 — instancie skills factory pour scaffold projets.
/// v0.8 MOCK : crée un dossier cible avec README placeholder + SCAFFOLD_REQUEST.md descripteur.
/// v0.8.5+ : shell-out `claude --print --skill <name> --` avec stdin prompt projet → applique diff.
///
/// Cf docs/IRIS-AGENTS-CATALOG.md §7 Builder + 11 skills factory dans ~/.claude/skills/.
public actor Builder {
    public static let shared = Builder()

    private weak var modelContainer: ModelContainer?

    /// v1.3 — pending git actions waiting for user approval, mapped by actionId.
    private var pendingGitActions: [UUID: GitContext] = [:]
    private var subscriptionTask: Task<Void, Never>?

    /// v1.1 — délégué au SkillRegistry. Liste filtrée par enabled state.
    @MainActor
    public static var availableSkills: [SkillRegistryAdapter] {
        SkillRegistry.shared.enabledFactorySkills.map { entry in
            SkillRegistryAdapter(name: entry.name, priorityRaw: entry.priority.rawValue, summary: entry.summary)
        }
    }

    /// Adapter Sendable pour traverser isolation (SkillEntry est MainActor-bound via SkillRegistry).
    public struct SkillRegistryAdapter: Sendable, Identifiable, Hashable {
        public var id: String { name }
        public let name: String
        public let priorityRaw: String
        public let summary: String
    }

    /// v1.3 — Context d'une action git en attente d'approval.
    private struct GitContext: Sendable {
        let projectName: String
        let dir: String
        let ghOwner: String  // ex "MaestroMed"
    }

    private init() {}

    public func start(modelContainer: ModelContainer) async {
        self.modelContainer = modelContainer

        // v1.3 — subscribe au bus pour intercepter actionApproved sur nos pending git actions
        guard subscriptionTask == nil else { return }
        let stream = await EventBus.shared.subscribe()
        subscriptionTask = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                if case .actionApproved(let actionId, _) = event {
                    await self.handleGitApproval(actionId: actionId)
                }
                if case .actionRejected(let actionId, _) = event {
                    await self.handleGitRejection(actionId: actionId)
                }
            }
        }
    }

    public func stop() {
        subscriptionTask?.cancel()
        subscriptionTask = nil
    }

    /// v1.137 — Scaffold + ouvre directement dans IDE (Cursor préf, fallback Finder).
    public func scaffoldAndOpen(skillName: String, projectName: String, targetDirectory: String? = nil) async {
        let dir = targetDirectory ?? "\(NSHomeDirectory())/Developer/\(projectName)"
        await scaffold(skillName: skillName, projectName: projectName, targetDirectory: dir)
        // Petit délai pour laisser le scaffold terminer ses writes + git init
        try? await Task.sleep(nanoseconds: 500_000_000)
        await Self.openInIDE(path: dir)
    }

    /// v1.137 — Reuse de la logique Inspector openProjectInIDE (Cursor → Xcode → Finder fallback)
    @MainActor
    private static func openInIDE(path: String) {
        let fm = FileManager.default
        let projectURL = URL(fileURLWithPath: path)
        if let contents = try? fm.contentsOfDirectory(atPath: path),
           let xcodeproj = contents.first(where: { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }) {
            NSWorkspace.shared.open(URL(fileURLWithPath: (path as NSString).appendingPathComponent(xcodeproj)))
            return
        }
        let cursorURL = URL(fileURLWithPath: "/Applications/Cursor.app")
        if fm.fileExists(atPath: cursorURL.path) {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([projectURL], withApplicationAt: cursorURL, configuration: config) { _, _ in }
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([projectURL])
    }

    /// Lance un scaffold. v1.126 — Si SKILL.md existe dans ~/.claude/skills/<skill>/,
    /// scaffold "real" (lit le skill + write CLAUDE.md + README + .gitignore + git init).
    /// Sinon fallback mock placeholder.
    public func scaffold(skillName: String, projectName: String, targetDirectory: String? = nil) async {
        let dir = targetDirectory ?? "\(NSHomeDirectory())/Developer/\(projectName)"
        irisLog(.info, "Builder scaffold \(skillName) → \(dir)", category: IRISLogger.agents)

        await EventBus.shared.publish(
            .signalEmitted(
                from: .builder,
                importance: .low,
                summary: "Scaffold démarré : skill=\(skillName) → \(projectName)",
                source: "builder"
            )
        )

        // v1.126 — Tente real scaffold d'abord, fallback mock si SKILL.md absent
        let skillPath = ("~/.claude/skills/\(skillName)/SKILL.md" as NSString).expandingTildeInPath
        let useReal = FileManager.default.fileExists(atPath: skillPath)

        let result: ScaffoldResult
        let actionType: String
        if useReal {
            result = await performRealScaffold(skill: skillName, skillMdPath: skillPath, project: projectName, targetDir: dir)
            actionType = "skill.scaffold.real"
        } else {
            result = await performMockScaffold(skill: skillName, project: projectName, targetDir: dir)
            actionType = "skill.scaffold.mock"
        }

        // Persist ActionLog
        if let container = await modelContainer {
            await MainActor.run {
                let context = container.mainContext
                let log = ActionLog(
                    agentId: AgentID.builder.rawValue,
                    actionType: actionType,
                    paramsJSON: "{\"skill\":\"\(skillName)\",\"project\":\"\(projectName)\",\"targetDir\":\"\(dir)\"}",
                    resultJSON: "{\"success\":\(result.success),\"filesCreated\":\(result.filesCreated)}",
                    success: result.success,
                    reversible: result.success,
                    undoPayloadJSON: result.success ? "{\"dir\":\"\(dir)\"}" : nil,
                    executedByUserApproval: false
                )
                context.insert(log)
                try? context.save()
            }
        }

        let mode = useReal ? "REAL" : "MOCK"
        let summary = result.success
            ? "✅ Scaffold [\(mode)] \(projectName) OK — \(result.filesCreated) fichiers (\(dir))"
            : "⚠️ Scaffold [\(mode)] \(projectName) failed — \(result.message)"

        await EventBus.shared.publish(
            .signalEmitted(
                from: .builder,
                importance: result.success ? .medium : .high,
                summary: summary,
                source: "builder"
            )
        )
    }

    // MARK: — v1.126 Real scaffold (reads SKILL.md, writes CLAUDE.md + README + .gitignore + git init)

    private nonisolated func performRealScaffold(
        skill: String,
        skillMdPath: String,
        project: String,
        targetDir: String
    ) async -> ScaffoldResult {
        let url = URL(fileURLWithPath: targetDir)
        let fm = FileManager.default

        // Crée le dir
        do {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            return ScaffoldResult(success: false, filesCreated: 0, message: "mkdir failed: \(error.localizedDescription)")
        }

        // Lit le SKILL.md (cap 50KB pour éviter excess)
        let skillContent: String
        if let data = try? Data(contentsOf: URL(fileURLWithPath: skillMdPath)),
           let text = String(data: data.prefix(50_000), encoding: .utf8) {
            skillContent = text
        } else {
            skillContent = "(SKILL.md introuvable ou non-UTF8 à \(skillMdPath))"
        }

        // v1.127 — Parse frontmatter pour pré-remplir le project context
        let frontmatter = Self.parseSkillFrontmatter(skillContent)
        let description = (frontmatter["description"] as? String) ?? ""
        let metadata = (frontmatter["metadata"] as? [String: Any]) ?? [:]
        let skillType = (metadata["type"] as? String) ?? "(non précisé)"
        let stackArray = (metadata["stack"] as? [String]) ?? []
        let stackList = stackArray.isEmpty ? "(non précisé — à remplir)" : stackArray.joined(separator: ", ")

        // 1. CLAUDE.md — source de vérité projet, hérite le skill
        let claudeMd = """
        # \(project)

        Projet scaffold par IRIS Builder via skill `\(skill)` le \(Self.isoNow()).

        ---

        ## Skill source (\(skill))

        \(skillContent)

        ---

        ## Project-specific context (v1.127 — pré-rempli depuis SKILL.md frontmatter)

        - **Type** : \(skillType)
        - **Stack** (du skill) : \(stackList)
        - **Description du skill** : \(description.isEmpty ? "(vide dans frontmatter)" : description)
        - **Domaine** : _à préciser pour ce projet_
        - **Client / use case** : _à préciser_
        - **Liens utiles** : _à ajouter_
        """

        // 2. README.md générique
        let readme = """
        # \(project)

        Projet bootstrap via IRIS Builder + skill `\(skill)`.

        Voir [CLAUDE.md](./CLAUDE.md) pour le contexte complet du projet (source de vérité pour Claude Code).

        ## Quick start

        ```bash
        # ouvre Claude Code dans ce dossier
        claude
        # invoque le skill : "Use the \(skill) skill"
        ```
        """

        // 3. .gitignore : v1.128 — stack-specific si frontmatter mentionne stack, sinon multi-stack
        let gitignore = Self.gitignoreForStack(stackArray)

        var filesCreated = 0
        let writes: [(String, String)] = [
            ("CLAUDE.md", claudeMd),
            ("README.md", readme),
            (".gitignore", gitignore)
        ]
        for (filename, content) in writes {
            let fileURL = url.appendingPathComponent(filename)
            if (try? content.write(to: fileURL, atomically: true, encoding: .utf8)) != nil {
                filesCreated += 1
            }
        }

        // 4. git init + initial commit (Process)
        Self.runGitCommand(args: ["init"], in: url)
        Self.runGitCommand(args: ["add", "."], in: url)
        Self.runGitCommand(args: ["commit", "-m", "Initial scaffold via IRIS Builder (\(skill))"], in: url)

        return ScaffoldResult(success: true, filesCreated: filesCreated, message: "real scaffold OK — \(skill) hydrated into CLAUDE.md + initial commit")
    }

    /// v1.129 — Helper git command non-bloquant (log warning si fail).
    nonisolated private static func runGitCommand(args: [String], in dir: URL) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["git"] + args
        proc.currentDirectoryURL = dir
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            irisLog(.warning, "Builder git \(args.joined(separator: " ")) failed (non-fatal): \(error.localizedDescription)",
                    category: IRISLogger.agents)
        }
    }

    // MARK: — Mock scaffold filesystem

    private nonisolated func performMockScaffold(
        skill: String,
        project: String,
        targetDir: String
    ) async -> ScaffoldResult {
        let url = URL(fileURLWithPath: targetDir)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            return ScaffoldResult(success: false, filesCreated: 0, message: "Création dir échouée : \(error.localizedDescription)")
        }

        // README placeholder
        let readme = """
        # \(project)

        Scaffold MOCK généré par IRIS Builder v0.8 le \(Self.isoNow()).

        - **Skill instancié** : `\(skill)`
        - **Cible** : `\(targetDir)`
        - **Statut** : placeholder. Le vrai scaffolding arrive en v0.8.5+ via shell-out
          `claude --print --skill \(skill)`.

        Pour lancer manuellement le skill depuis Claude Code :
        ```bash
        cd \(targetDir)
        # ouvre Claude Code dans ce dir, invoque le skill via "Use the \(skill) skill"
        ```
        """
        let scaffoldRequest = """
        # SCAFFOLD_REQUEST.md

        - skill: \(skill)
        - project: \(project)
        - generated_at: \(Self.isoNow())
        - status: mock-placeholder
        - target_dir: \(targetDir)

        ## Prochaines étapes (v0.8.5+)

        IRIS Builder v0.8.5+ va spawn un process `claude --print --skill \(skill)` dans
        ce dossier pour générer le scaffolding réel. Output capturé + diff proposé avant
        write effectif des fichiers.
        """

        var filesCreated = 0
        let writes: [(String, String)] = [
            ("README.md", readme),
            ("SCAFFOLD_REQUEST.md", scaffoldRequest),
        ]
        for (filename, content) in writes {
            let fileURL = url.appendingPathComponent(filename)
            if (try? content.write(to: fileURL, atomically: true, encoding: .utf8)) != nil {
                filesCreated += 1
            }
        }

        return ScaffoldResult(success: true, filesCreated: filesCreated, message: "OK")
    }

    // v1.128 — Stack-specific .gitignore variants
    /// Compose un .gitignore basé sur la stack du skill. Si stack vide ou inconnue → multi-stack default.
    /// Stack hints reconnus : "swift", "swiftui", "ios", "next", "nextjs", "node", "python", "py",
    /// "rust", "go", "ruby", "rails", "tauri", "r3f", "three".
    nonisolated static func gitignoreForStack(_ stack: [String]) -> String {
        let lowered = stack.map { $0.lowercased() }
        var sections: [String] = []

        // Toujours : IDE + secrets + OS
        sections.append("""
        # IDE / OS
        .vscode/
        .idea/
        .DS_Store
        Thumbs.db

        # Secrets
        .env
        .env.local
        .env.*.local
        *.pem
        *.key
        secrets/
        """)

        let hasNode = lowered.contains(where: { ["next", "nextjs", "node", "typescript", "ts", "react", "vue", "svelte"].contains($0) || $0.contains("next-") })
        let hasSwift = lowered.contains(where: { ["swift", "swiftui", "ios", "macos", "tuist"].contains($0) || $0.contains("swift") })
        let hasPython = lowered.contains(where: { ["python", "py", "django", "flask", "fastapi"].contains($0) })
        let hasRust = lowered.contains(where: { ["rust", "cargo"].contains($0) })
        let hasGo = lowered.contains(where: { ["go", "golang"].contains($0) })
        let hasRuby = lowered.contains(where: { ["ruby", "rails"].contains($0) })

        if hasNode {
            sections.append("""
            # Node / Next.js / TypeScript
            node_modules/
            .next/
            .turbo/
            dist/
            build/
            out/
            coverage/
            *.tsbuildinfo
            .pnp.*
            .yarn/install-state.gz
            npm-debug.log*
            yarn-debug.log*
            yarn-error.log*
            pnpm-debug.log*
            """)
        }
        if hasSwift {
            sections.append("""
            # Swift / iOS / macOS / Tuist
            DerivedData/
            .build/
            .swiftpm/
            *.xcodeproj
            *.xcworkspace
            Package.resolved
            Tuist/Dependencies/Lockfiles/
            xcuserdata/
            """)
        }
        if hasPython {
            sections.append("""
            # Python
            __pycache__/
            *.pyc
            *.pyo
            .venv/
            venv/
            env/
            *.egg-info/
            .pytest_cache/
            .mypy_cache/
            """)
        }
        if hasRust {
            sections.append("""
            # Rust
            target/
            **/*.rs.bk
            Cargo.lock
            """)
        }
        if hasGo {
            sections.append("""
            # Go
            *.exe
            *.test
            *.out
            vendor/
            """)
        }
        if hasRuby {
            sections.append("""
            # Ruby / Rails
            *.gem
            .bundle
            vendor/bundle
            log/*.log
            tmp/*
            """)
        }

        // Si rien de spécifique détecté → fallback multi-stack
        if !hasNode && !hasSwift && !hasPython && !hasRust && !hasGo && !hasRuby {
            sections.append("""
            # Multi-stack fallback (stack non détectée dans SKILL.md frontmatter)
            node_modules/
            dist/
            build/
            DerivedData/
            .build/
            __pycache__/
            *.log
            """)
        }

        return sections.joined(separator: "\n\n") + "\n"
    }

    // v1.127 — Parse YAML frontmatter d'un SKILL.md (entre les deux `---`)
    /// Retourne un dict avec keys top-level (name, description, metadata). Simple parser :
    /// `key: value` (string) ou `key: [item1, item2]` (array). `metadata:` nested support.
    nonisolated static func parseSkillFrontmatter(_ content: String) -> [String: Any] {
        let lines = content.components(separatedBy: .newlines)
        guard lines.first == "---" else { return [:] }
        // Trouve la fin du frontmatter
        var endIdx = -1
        for i in 1..<lines.count {
            if lines[i] == "---" {
                endIdx = i
                break
            }
        }
        guard endIdx > 0 else { return [:] }
        let frontLines = Array(lines[1..<endIdx])

        var result: [String: Any] = [:]
        var currentNestedKey: String?
        var nestedDict: [String: Any] = [:]

        for rawLine in frontLines {
            // Détection indentation nested (2-4 spaces)
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            let isNested = rawLine.hasPrefix("  ") || rawLine.hasPrefix("    ")

            if isNested, let key = currentNestedKey {
                // Parse "  subkey: value" ou "  subkey: [a, b]"
                let parts = trimmed.split(separator: ":", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
                guard parts.count == 2 else { continue }
                let subkey = parts[0]
                let value = parts[1]
                if value.hasPrefix("[") && value.hasSuffix("]") {
                    let inner = value.dropFirst().dropLast()
                    let items = inner.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
                    nestedDict[subkey] = items
                } else {
                    nestedDict[subkey] = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                }
                result[key] = nestedDict
            } else {
                // Top-level key
                let parts = trimmed.split(separator: ":", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
                guard parts.count >= 1 else { continue }
                let key = parts[0]
                let value = parts.count == 2 ? parts[1] : ""
                if value.isEmpty {
                    // Probable nested section qui suit
                    currentNestedKey = key
                    nestedDict = [:]
                    result[key] = nestedDict
                } else {
                    currentNestedKey = nil
                    if value.hasPrefix("[") && value.hasSuffix("]") {
                        let inner = value.dropFirst().dropLast()
                        let items = inner.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
                        result[key] = items
                    } else {
                        result[key] = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    }
                }
            }
        }
        return result
    }

    nonisolated private static func isoNow() -> String {
        let f = ISO8601DateFormatter()
        return f.string(from: Date())
    }

    struct ScaffoldResult: Sendable {
        let success: Bool
        let filesCreated: Int
        let message: String
    }

    // MARK: — v1.3 Scaffold + git push workflow

    /// Lance un scaffold ET prépare le push GitHub. L'utilisateur doit approve l'action git dans l'UI.
    /// Mock scaffold est appliqué localement immédiatement. Le push GitHub attend approval.
    public func scaffoldWithGitPush(
        skillName: String,
        projectName: String,
        ghOwner: String = "MaestroMed"
    ) async {
        let dir = "\(NSHomeDirectory())/Developer/\(projectName)"
        irisLog(.info, "Builder scaffoldWithGitPush \(skillName) → \(dir)", category: IRISLogger.agents)

        // 1. Scaffold local (re-use de l'existant)
        let result = await performMockScaffold(skill: skillName, project: projectName, targetDir: dir)
        if !result.success {
            await EventBus.shared.publish(
                .signalEmitted(from: .builder, importance: .high,
                               summary: "⚠️ Scaffold échoué : \(result.message)", source: "builder")
            )
            return
        }

        // 2. git init local (réversible, on peut delete le dossier si user reject)
        let gitInitOk = await runProcess(executable: "/usr/bin/env", args: ["git", "init", "-q"], cwd: dir)
        guard gitInitOk else {
            await EventBus.shared.publish(.signalEmitted(from: .builder, importance: .high,
                                                         summary: "⚠️ git init failed pour \(projectName)",
                                                         source: "builder"))
            return
        }

        // 3. Propose actionRequested pour push GitHub (irréversible une fois publiée)
        let actionId = UUID()
        pendingGitActions[actionId] = GitContext(projectName: projectName, dir: dir, ghOwner: ghOwner)

        await EventBus.shared.publish(
            .actionRequested(
                actionId: actionId,
                agent: .builder,
                summary: "Push GitHub \(ghOwner)/\(projectName) (scaffold via \(skillName))",
                isReversible: false  // une fois pushé public, irréversible
            )
        )

        irisLog(.notice,
            "Builder proposed git push action \(actionId.uuidString.prefix(8)) for \(projectName) — waiting approval",
            category: IRISLogger.agents
        )
    }

    private func handleGitApproval(actionId: UUID) async {
        guard let ctx = pendingGitActions.removeValue(forKey: actionId) else { return }
        irisLog(.notice, "Builder executing git push for \(ctx.projectName)", category: IRISLogger.agents)

        // Suite : git add . → git commit → gh repo create + push. Short-circuit manuel
        // car async expressions ne peuvent pas être à droite de && (autoclosure non-async).
        let addOk = await runProcess(executable: "/usr/bin/env", args: ["git", "add", "."], cwd: ctx.dir)

        var commitOk = false
        if addOk {
            commitOk = await runProcess(
                executable: "/usr/bin/env",
                args: ["git", "commit", "-q", "-m", "IRIS scaffold: \(ctx.projectName)"],
                cwd: ctx.dir
            )
        }

        // gh repo create --source=. --public --push (Mehdi peut bump --private via UI v1.3.1+)
        var ghCreateOk = false
        if commitOk {
            ghCreateOk = await runProcess(
                executable: "/usr/bin/env",
                args: ["gh", "repo", "create", "\(ctx.ghOwner)/\(ctx.projectName)",
                       "--source=.", "--public", "--push", "--description", "IRIS scaffold"],
                cwd: ctx.dir
            )
        }

        let success = ghCreateOk
        let result = success
            ? "✅ Repo \(ctx.ghOwner)/\(ctx.projectName) créé + pushé"
            : "⚠️ git workflow échoué — vérifie gh auth + repo existant"

        // Persist ActionLog
        if let container = await modelContainer {
            let projectName = ctx.projectName
            let ghOwner = ctx.ghOwner
            let dir = ctx.dir
            await MainActor.run {
                let log = ActionLog(
                    agentId: AgentID.builder.rawValue,
                    actionType: "git.scaffold_push",
                    paramsJSON: "{\"actionId\":\"\(actionId.uuidString)\",\"project\":\"\(projectName)\",\"owner\":\"\(ghOwner)\",\"dir\":\"\(dir)\"}",
                    resultJSON: "{\"success\":\(success)}",
                    success: success,
                    reversible: false,
                    executedByUserApproval: true
                )
                container.mainContext.insert(log)
                try? container.mainContext.save()
            }
        }

        await EventBus.shared.publish(
            .actionExecuted(actionId: actionId, success: success, result: result)
        )

        irisLog(success ? .notice : .error,
                "Builder git push done success=\(success) for \(ctx.projectName)",
                category: IRISLogger.agents)
    }

    private func handleGitRejection(actionId: UUID) async {
        guard let ctx = pendingGitActions.removeValue(forKey: actionId) else { return }
        irisLog(.info, "Builder git push rejected for \(ctx.projectName) — local scaffold preserved at \(ctx.dir)",
                category: IRISLogger.agents)
        // On garde le scaffold local (utile pour itérations sans push). User peut clean manuellement.
    }

    nonisolated private func runProcess(executable: String, args: [String], cwd: String) async -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

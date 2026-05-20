import Foundation
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

    /// Lance un scaffold (v0.8 mock : crée dossier cible + descripteur).
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

        let result = await performMockScaffold(skill: skillName, project: projectName, targetDir: dir)

        // Persist ActionLog
        if let container = await modelContainer {
            await MainActor.run {
                let context = container.mainContext
                let log = ActionLog(
                    agentId: AgentID.builder.rawValue,
                    actionType: "skill.scaffold.mock",
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

        let summary = result.success
            ? "✅ Scaffold \(projectName) OK — \(result.filesCreated) fichiers (\(dir))"
            : "⚠️ Scaffold \(projectName) failed — \(result.message)"

        await EventBus.shared.publish(
            .signalEmitted(
                from: .builder,
                importance: result.success ? .medium : .high,
                summary: summary,
                source: "builder"
            )
        )
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

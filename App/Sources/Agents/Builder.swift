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
    public static let availableSkills: [SkillDescriptor] = [
        .init(name: "lead-gen-local-services-fr", priority: .high, summary: "Site vitrine + devis multi-step + RGPD + SEO local FR"),
        .init(name: "doc-first-project-scaffolding", priority: .high, summary: "Suite .md systématique (ARCHITECTURE/FEATURES/SEO_STRATEGY/QUESTIONNAIRE/...)"),
        .init(name: "spec-driven-build-with-claude-md", priority: .high, summary: "CLAUDE.md exhaustif (30-130k) source de vérité projet"),
        .init(name: "programmatic-seo-local-combos", priority: .high, summary: "Pages [service]×[zone] générées (40-500 pages)"),
        .init(name: "backoffice-custom-cms-crm-rbac", priority: .high, summary: "Admin custom + CommandPalette + MediaPicker + 2FA"),
        .init(name: "nextjs-stack-baseline-2026", priority: .medium, summary: "Stack opinionated Next.js 15 + TS + Tailwind v4 + Supabase/Drizzle"),
        .init(name: "monorepo-turbo-with-claude-agents", priority: .medium, summary: "Turborepo + apps/packages + AGENTS.md + .claude/"),
        .init(name: "booking-marketplace-calcom-or-custom", priority: .medium, summary: "Cal.com embed ou booking custom + pricing engine + dispatch"),
        .init(name: "ai-pipeline-orchestrator", priority: .medium, summary: "Pipeline AI multi-étapes (Sentinel→Harvester→Clipper→Analyzer)"),
        .init(name: "viral-content-pipeline-long-to-short", priority: .low, summary: "Long-form → 9:16 clips + virality scoring + karaoke subs"),
        .init(name: "configurateur-3d-r3f-product", priority: .low, summary: "R3F + Three.js + glb + matériaux PBR + snapshot devis"),
    ]

    public enum Priority: String, Sendable {
        case high, medium, low
    }

    public struct SkillDescriptor: Sendable, Identifiable, Hashable {
        public var id: String { name }
        public let name: String
        public let priority: Priority
        public let summary: String
    }

    private init() {}

    public func start(modelContainer: ModelContainer) async {
        self.modelContainer = modelContainer
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
}

import Foundation
import Observation

/// v1.1 — Skill marketplace local. Liste les skills factory + plugins externes.
/// Enabled state persisté UserDefaults — Builder lit `enabledSkills` avant scaffold.
@MainActor
@Observable
public final class SkillRegistry {
    public static let shared = SkillRegistry()

    /// v1.55 — Skills découverts via scan disk (~/.claude/skills/). Mergés avec builtInSkills.
    public private(set) var discoveredSkills: [SkillEntry] = []

    /// v1.55 — Skills connus : built-in (factory + plugin) + découverts par scan disk.
    public var allSkills: [SkillEntry] {
        let builtInNames = Set(builtInSkills.map(\.name))
        // Filtre dupes : si un skill discoveredSkill matche un builtIn, garde le builtIn (plus riche)
        let extras = discoveredSkills.filter { !builtInNames.contains($0.name) }
        return builtInSkills + extras
    }

    /// Liste statique des skills built-in (factory + plugins externes Anthropic).
    public let builtInSkills: [SkillEntry] = [
        // Factory v1 (11 skills générés par la skill-factory phase 1)
        .init(name: "lead-gen-local-services-fr", priority: .high, source: .factory,
              summary: "Site vitrine + devis multi-step + RGPD + SEO local FR"),
        .init(name: "doc-first-project-scaffolding", priority: .high, source: .factory,
              summary: "Suite .md systématique (ARCHITECTURE/FEATURES/SEO_STRATEGY/QUESTIONNAIRE/...)"),
        .init(name: "spec-driven-build-with-claude-md", priority: .high, source: .factory,
              summary: "CLAUDE.md exhaustif (30-130k) source de vérité projet"),
        .init(name: "programmatic-seo-local-combos", priority: .high, source: .factory,
              summary: "Pages [service]×[zone] générées (40-500 pages)"),
        .init(name: "backoffice-custom-cms-crm-rbac", priority: .high, source: .factory,
              summary: "Admin custom + CommandPalette + MediaPicker + 2FA"),
        .init(name: "nextjs-stack-baseline-2026", priority: .medium, source: .factory,
              summary: "Stack opinionated Next.js 15 + TS + Tailwind v4 + Supabase/Drizzle"),
        .init(name: "monorepo-turbo-with-claude-agents", priority: .medium, source: .factory,
              summary: "Turborepo + apps/packages + AGENTS.md + .claude/"),
        .init(name: "booking-marketplace-calcom-or-custom", priority: .medium, source: .factory,
              summary: "Cal.com embed ou booking custom + pricing engine + dispatch"),
        .init(name: "ai-pipeline-orchestrator", priority: .medium, source: .factory,
              summary: "Pipeline AI multi-étapes (Sentinel→Harvester→Clipper→Analyzer)"),
        .init(name: "viral-content-pipeline-long-to-short", priority: .low, source: .factory,
              summary: "Long-form → 9:16 clips + virality scoring + karaoke subs"),
        .init(name: "configurateur-3d-r3f-product", priority: .low, source: .factory,
              summary: "R3F + Three.js + glb + matériaux PBR + snapshot devis"),

        // Plugins externes installés via Anthropic (anthropic-skills)
        .init(name: "damage-control", priority: .high, source: .anthropicPlugin,
              summary: "Audit multi-axes projet 8 dimensions (analytics/CRO/observability/...)"),
        .init(name: "gpt-image-2-prompter", priority: .medium, source: .anthropicPlugin,
              summary: "Prompt engineering GPT Image 2 (texte dans image, 4K, multi-ref)"),
        .init(name: "state-of-the-art", priority: .medium, source: .anthropicPlugin,
              summary: "Force vérification SOTA stacks/versions/standards via web_search"),
        .init(name: "animation-hero", priority: .low, source: .anthropicPlugin,
              summary: "Workflow Hero/animation web premium (Motion/GSAP/R3F/Lottie/Rive)"),
    ]

    /// Skills actuellement enabled (utilisables par Builder). Persisté UserDefaults.
    public var enabledNames: Set<String> {
        didSet { persist() }
    }

    private static let userDefaultsKey = "iris.skillRegistry.enabledNames"

    private init() {
        // Init : toutes les skills factory HIGH activées par défaut + tous les plugins externes.
        let stored = UserDefaults.standard.array(forKey: Self.userDefaultsKey) as? [String]
        if let stored, !stored.isEmpty {
            self.enabledNames = Set(stored)
        } else {
            self.enabledNames = Set(
                builtInSkills
                    .filter { $0.source == .anthropicPlugin || $0.priority == .high }
                    .map(\.name)
            )
            persist()
        }
    }

    // MARK: — v1.55 Hot-reload from disk

    /// Scan ~/.claude/skills/ pour découvrir des skills installées manuellement.
    /// Chaque subdir contenant SKILL.md devient un SkillEntry source=.userInstalled.
    /// Parse simple : name = dirname, summary = description front matter (ou première ligne body).
    @discardableResult
    public func reloadFromDisk() -> Int {
        let skillsPath = ("~/.claude/skills" as NSString).expandingTildeInPath
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: skillsPath) else {
            irisLog(.warning, "SkillRegistry: ~/.claude/skills/ introuvable", category: IRISLogger.ui)
            return 0
        }

        var discovered: [SkillEntry] = []
        for name in entries {
            let dirPath = (skillsPath as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dirPath, isDirectory: &isDir), isDir.boolValue else { continue }

            let skillMdPath = (dirPath as NSString).appendingPathComponent("SKILL.md")
            guard fm.fileExists(atPath: skillMdPath) else { continue }

            let summary = extractSummary(from: skillMdPath) ?? "(skill local — pas de description)"
            discovered.append(SkillEntry(
                name: name,
                priority: .medium,
                source: .userInstalled,
                summary: summary
            ))
        }

        self.discoveredSkills = discovered.sorted { $0.name < $1.name }
        irisLog(.info, "SkillRegistry reloaded \(discovered.count) skills from disk", category: IRISLogger.ui)
        return discovered.count
    }

    /// Extrait la description du front matter YAML d'un SKILL.md.
    /// Format attendu : `description: ...` dans le bloc `---` initial.
    private func extractSummary(from path: String) -> String? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        // Trouve le frontmatter --- ... ---
        let lines = content.components(separatedBy: .newlines)
        guard lines.first == "---" else {
            // Pas de frontmatter, prend la première ligne non-vide < 200 chars
            return lines.first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }?
                .trimmingCharacters(in: .whitespaces)
                .prefix(200).description
        }
        for line in lines.dropFirst() {
            if line == "---" { break }
            if line.hasPrefix("description:") {
                return line
                    .replacingOccurrences(of: "description:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
        }
        return nil
    }

    public func isEnabled(_ name: String) -> Bool {
        enabledNames.contains(name)
    }

    public func toggle(_ name: String) {
        if enabledNames.contains(name) {
            enabledNames.remove(name)
        } else {
            enabledNames.insert(name)
        }
    }

    public func enable(_ name: String) { enabledNames.insert(name) }
    public func disable(_ name: String) { enabledNames.remove(name) }

    public var enabledSkills: [SkillEntry] {
        allSkills.filter { enabledNames.contains($0.name) }
    }

    public var enabledFactorySkills: [SkillEntry] {
        enabledSkills.filter { $0.source == .factory }
    }

    private func persist() {
        UserDefaults.standard.set(Array(enabledNames), forKey: Self.userDefaultsKey)
    }

    // MARK: — v1.14 Export / Import config JSON

    public struct SkillsConfig: Codable, Sendable {
        public let version: String
        public let exportedAt: Date
        public let enabledNames: [String]
    }

    /// Export la config courante en JSON (pour partager entre machines / early adopters v2.x).
    public func exportConfig() -> Data? {
        let config = SkillsConfig(
            version: "1.14",
            exportedAt: .now,
            enabledNames: Array(enabledNames).sorted()
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(config)
    }

    /// Import une config JSON. Retourne true si valide + appliquée.
    /// Idempotent : remplace complètement enabledNames (pas de merge).
    @discardableResult
    public func importConfig(from data: Data) -> Bool {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let config = try? decoder.decode(SkillsConfig.self, from: data) else { return false }
        let validNames = Set(allSkills.map(\.name))
        let filtered = Set(config.enabledNames).intersection(validNames)
        self.enabledNames = filtered
        return true
    }
}

public struct SkillEntry: Identifiable, Sendable, Hashable {
    public var id: String { name }
    public let name: String
    public let priority: SkillPriority
    public let source: SkillSource
    public let summary: String
}

public enum SkillPriority: String, Sendable, Hashable, Comparable {
    case high, medium, low
    public static func < (lhs: SkillPriority, rhs: SkillPriority) -> Bool {
        let order: [SkillPriority] = [.high, .medium, .low]
        return (order.firstIndex(of: lhs) ?? 99) < (order.firstIndex(of: rhs) ?? 99)
    }
}

public enum SkillSource: String, Sendable, Hashable, CaseIterable {
    case factory          // Généré par la skill-factory IRIS phase 1
    case anthropicPlugin  // Installé via anthropic-skills plugin
    case userInstalled    // Skill custom installé par Mehdi (v1.x+)

    public var displayName: String {
        switch self {
        case .factory: return "Factory (skill-factory phase 1)"
        case .anthropicPlugin: return "Plugin Anthropic (anthropic-skills)"
        case .userInstalled: return "Custom (installé par Mehdi)"
        }
    }

    /// Ordre d'affichage UI : Factory en premier (les plus utiles au quotidien).
    public static var allCasesOrdered: [SkillSource] {
        [.factory, .anthropicPlugin, .userInstalled]
    }
}

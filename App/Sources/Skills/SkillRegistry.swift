import Foundation
import Observation

/// v1.1 — Skill marketplace local. Liste les skills factory + plugins externes.
/// Enabled state persisté UserDefaults — Builder lit `enabledSkills` avant scaffold.
@MainActor
@Observable
public final class SkillRegistry {
    public static let shared = SkillRegistry()

    /// Tous les skills connus (factory + plugins externes).
    public let allSkills: [SkillEntry] = [
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
                allSkills
                    .filter { $0.source == .anthropicPlugin || $0.priority == .high }
                    .map(\.name)
            )
            persist()
        }
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

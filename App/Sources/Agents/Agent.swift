import Foundation
import SwiftUI

// IRIS v0.0.2 — modèle Agent statique (placeholder UI uniquement).
// Les 10 agents du catalogue (cf docs/IRIS-AGENTS-CATALOG.md) sont représentés en sidebar.
// v0.0.5+ — chaque AgentID sera lié à un Module Swift implémentant son runtime (event bus, LLM call, etc).

/// Identifiant stable des 10 agents IRIS + `.system` pour les logs/events non attribués.
/// Sendable pour usage cross-isolation, Codable pour persistance + bus events.
public enum AgentID: String, CaseIterable, Hashable, Identifiable, Sendable, Codable {
    case conductor
    case sentinel
    case scribe
    case quill
    case auditor
    case cartographer
    case builder
    case envoy
    case witness
    case advisor
    /// Pour les logs/events système non attribués à un agent métier.
    case system

    public var id: String { rawValue }

    /// Les 10 vrais agents (exclut `.system`).
    public static var businessAgents: [AgentID] {
        allCases.filter { $0 != .system }
    }
}

/// Statut runtime d'un agent (placeholder en v0.0.2 — tous `.inactive`).
/// v0.0.5+ — alimenté par l'Event Bus + heartbeat agent.
public enum AgentStatus: String, Sendable, Hashable {
    case inactive
    case idle
    case working
    case error

    /// Couleur du dot status. Pour v0.0.2 tout est `inactive` donc grey.
    var dotColor: Color {
        switch self {
        case .inactive: return Color.secondary.opacity(0.45)
        case .idle:     return IRISTokens.aquaTint
        case .working:  return IRISTokens.irisAccent
        case .error:    return Color.red.opacity(0.85)
        }
    }
}

/// Métadonnées d'affichage d'un agent. Statiques pour v0.0.2.
public struct AgentDescriptor: Identifiable, Hashable, Sendable {
    public let id: AgentID
    public let displayName: String
    public let alias: String
    public let symbol: String  // SF Symbol name
    public let tagline: String

    public init(id: AgentID, displayName: String, alias: String, symbol: String, tagline: String) {
        self.id = id
        self.displayName = displayName
        self.alias = alias
        self.symbol = symbol
        self.tagline = tagline
    }
}

extension AgentID {
    /// Descripteur figé pour l'UI. Source : docs/IRIS-AGENTS-CATALOG.md.
    public var descriptor: AgentDescriptor {
        switch self {
        case .conductor:
            return AgentDescriptor(
                id: self,
                displayName: "Conductor",
                alias: "Maître d'œuvre",
                symbol: "wand.and.rays",
                tagline: "Orchestre tous les agents."
            )
        case .sentinel:
            return AgentDescriptor(
                id: self,
                displayName: "Sentinel",
                alias: "Vigie",
                symbol: "eye.circle",
                tagline: "Observe les sources externes."
            )
        case .scribe:
            return AgentDescriptor(
                id: self,
                displayName: "Scribe",
                alias: "Greffier",
                symbol: "books.vertical",
                tagline: "Mémoire long terme."
            )
        case .quill:
            return AgentDescriptor(
                id: self,
                displayName: "Quill",
                alias: "Plumitif",
                symbol: "pencil.and.scribble",
                tagline: "Rédige drafts, jamais n'envoie."
            )
        case .auditor:
            return AgentDescriptor(
                id: self,
                displayName: "Auditor",
                alias: "Inspecteur",
                symbol: "checkmark.shield",
                tagline: "Audite projets et code."
            )
        case .cartographer:
            return AgentDescriptor(
                id: self,
                displayName: "Cartographer",
                alias: "Cartographe",
                symbol: "map",
                tagline: "Carte vivante des projets."
            )
        case .builder:
            return AgentDescriptor(
                id: self,
                displayName: "Builder",
                alias: "Artisan",
                symbol: "hammer",
                tagline: "Scaffold + exécution code."
            )
        case .envoy:
            return AgentDescriptor(
                id: self,
                displayName: "Envoy",
                alias: "Ambassadeur",
                symbol: "paperplane",
                tagline: "Actions externes irréversibles."
            )
        case .witness:
            return AgentDescriptor(
                id: self,
                displayName: "Witness",
                alias: "Témoin",
                symbol: "eyes",
                tagline: "Comprend le contexte applicatif."
            )
        case .advisor:
            return AgentDescriptor(
                id: self,
                displayName: "Advisor",
                alias: "Conseiller",
                symbol: "lightbulb",
                tagline: "Sparring partner — peut challenger."
            )
        case .system:
            return AgentDescriptor(
                id: self,
                displayName: "System",
                alias: "Logs internes",
                symbol: "gear",
                tagline: "Événements système non attribués."
            )
        }
    }
}

/// Sections du sidebar.
public enum SidebarSection: String, CaseIterable, Hashable, Identifiable, Sendable {
    case agents
    case system

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .agents: return "Agents"
        case .system: return "System"
        }
    }
}

/// Entrées système (sous la section System, en bas du sidebar).
/// v0.0.3 — `logs` ouvrira le panel Logs runtime des agents.
/// v1.36 — `stats` panel bus events stats par kind.
public enum SystemDestination: String, CaseIterable, Hashable, Identifiable, Sendable {
    case logs
    case stats
    case memory  // v1.56 — browse Memory records + ad-hoc retrieval

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .logs: return "Logs"
        case .stats: return "Stats"
        case .memory: return "Memory"
        }
    }

    public var symbol: String {
        switch self {
        case .logs: return "list.bullet.rectangle"
        case .stats: return "chart.bar.fill"
        case .memory: return "books.vertical"
        }
    }
}

/// Cible courante de la sélection sidebar — un agent ou une entrée system.
public enum SidebarSelection: Hashable, Sendable {
    case agent(AgentID)
    case system(SystemDestination)
}

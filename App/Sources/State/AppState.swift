import Foundation
import Observation
import SwiftUI

/// v1.24 — typealias pour cost callbacks enrichis avec model name.
public typealias CostSink = @Sendable (_ amount: Double, _ model: String) -> Void

// IRIS v0.0.5 — état global app. @Observable (Swift 6) injecté via @Environment.
// Étend v0.0.2 avec : transcript (échanges user ↔ conductor), currentInput, isProcessing, lastError.
// v0.6+ — sera étendu avec drafts/audit stores, signals queue, etc.

/// État UI global d'IRIS.
@MainActor
@Observable
public final class IRISAppState {
    /// Sélection courante du sidebar. `nil` = écran d'accueil.
    public var selection: SidebarSelection?

    /// Visibilité des colonnes du NavigationSplitView.
    public var columnVisibility: NavigationSplitViewVisibility

    /// Transcript live des échanges (user + agent responses + system logs).
    public var transcript: [TranscriptEntry] = []

    /// Input en cours dans le TextField principal.
    public var currentInput: String = ""

    /// True quand un agent traite une requête (Conductor LLM en cours d'appel).
    public var isProcessing: Bool = false

    /// Dernière erreur affichable.
    public var lastError: String?

    /// Présence d'une API key Anthropic dans le Keychain (cached pour binding rapide).
    public var hasAnthropicKey: Bool

    /// Coût cumulé session (USD estimé via AnthropicClient usage tokens).
    public var sessionCostUSD: Double = 0

    /// v1.24 — Cost breakdown par modèle (ex ["claude-opus-4-7": 0.0532, "claude-sonnet-4-6": 0.0123]).
    public var costByModel: [String: Double] = [:]

    /// Helper unique : update sessionCostUSD + costByModel[model].
    /// v1.72 — Trigger costLimitAlert si on franchit le seuil configuré.
    public func addCost(_ amount: Double, model: String) {
        let previous = sessionCostUSD
        sessionCostUSD += amount
        costByModel[model, default: 0] += amount

        let limit = IRISAppState.costLimitUSD
        if limit > 0, previous < limit, sessionCostUSD >= limit {
            // Crossing point — notify
            costLimitTriggered = true
            let title = "IRIS — cost limit atteint"
            let body = "Session cost $\(String(format: "%.4f", sessionCostUSD)) ≥ limite $\(String(format: "%.2f", limit))"
            Task {
                await IRISNotifications.push(title: title, body: body)
            }
        }
    }

    // v1.72 — Cost limit
    public var costLimitTriggered: Bool = false

    private static let costLimitKey = "iris.cost.sessionLimitUSD"

    public static var costLimitUSD: Double {
        let raw = UserDefaults.standard.double(forKey: costLimitKey)
        return raw > 0 ? raw : 1.0  // default $1
    }

    public static func setCostLimit(_ value: Double) {
        UserDefaults.standard.set(max(0.01, value), forKey: costLimitKey)
    }

    public func resetCostLimitFlag() {
        costLimitTriggered = false
    }

    /// Actions en attente d'approbation user (proposées par Envoy après draftReady).
    public var pendingActions: [PendingActionUI] = []

    /// v1.17 — Texte en cours de stream Conductor (Claude tape en live).
    /// Non-empty pendant un stream actif, cleared quand .agentResponse final arrive.
    public var streamingText: String = ""
    public var streamingEventId: UUID? = nil

    /// v1.21 — Timestamps dernière activité par agent. Sidebar dot color dérive de là.
    public var recentlyActiveAgents: [AgentID: Date] = [:]

    /// Helper status agent pour Sidebar dot.
    public func agentStatus(_ id: AgentID) -> AgentStatus {
        guard let last = recentlyActiveAgents[id] else { return .inactive }
        let elapsed = Date().timeIntervalSince(last)
        if elapsed < 5 { return .working }
        if elapsed < 60 { return .idle }
        return .inactive
    }

    public func markAgentActive(_ id: AgentID) {
        recentlyActiveAgents[id] = .now
    }

    /// Convenience : extrait l'AgentID si la sélection est un agent.
    public var selectedAgent: AgentID? {
        if case let .agent(id) = selection { return id }
        return nil
    }

    public init(
        selection: SidebarSelection? = nil,
        columnVisibility: NavigationSplitViewVisibility = .all
    ) {
        self.selection = selection
        self.columnVisibility = columnVisibility
        self.hasAnthropicKey = IRISKeychain.shared.hasAnthropicAPIKey()
    }

    // MARK: — Mutations

    public func appendEntry(_ entry: TranscriptEntry) {
        transcript.append(entry)
        // Cap mémoire UI : on garde les 500 dernières entrées (le reste vit dans EventLog SwiftData).
        if transcript.count > 500 {
            transcript.removeFirst(transcript.count - 500)
        }
    }

    /// v1.19 — Clear le transcript UI (les events restent dans EventLog SwiftData).
    /// Couplé à Conductor.resetHistory() pour reset multi-turn dialog.
    public func clearTranscript() {
        transcript.removeAll()
        streamingText = ""
        streamingEventId = nil
        currentInput = ""
        isProcessing = false
    }

    public func refreshKeyPresence() {
        hasAnthropicKey = IRISKeychain.shared.hasAnthropicAPIKey()
    }
}

/// Action en attente d'approbation user (UI ↔ Envoy bridge).
public struct PendingActionUI: Identifiable, Sendable, Hashable {
    public var id: UUID { actionId }
    public let actionId: UUID
    public let agentName: String
    public let summary: String
    public let isReversible: Bool
    public let createdAt: Date

    public init(actionId: UUID, agentName: String, summary: String, isReversible: Bool, createdAt: Date = .now) {
        self.actionId = actionId
        self.agentName = agentName
        self.summary = summary
        self.isReversible = isReversible
        self.createdAt = createdAt
    }
}

/// Entrée transcript pour l'affichage UI.
public struct TranscriptEntry: Identifiable, Sendable, Hashable {
    public let id: UUID
    public let timestamp: Date
    public let role: Role
    public let content: String

    public enum Role: Sendable, Hashable {
        case user
        case agent(AgentID)
        case system(level: String)

        public var displayName: String {
            switch self {
            case .user: return "Vous"
            case .agent(let id): return id.descriptor.displayName
            case .system: return "System"
            }
        }
    }

    public init(role: Role, content: String, timestamp: Date = .now) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

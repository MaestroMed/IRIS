import Foundation
import Observation
import SwiftUI

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

    /// Actions en attente d'approbation user (proposées par Envoy après draftReady).
    public var pendingActions: [PendingActionUI] = []

    /// v1.17 — Texte en cours de stream Conductor (Claude tape en live).
    /// Non-empty pendant un stream actif, cleared quand .agentResponse final arrive.
    public var streamingText: String = ""
    public var streamingEventId: UUID? = nil

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

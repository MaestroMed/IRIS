import Foundation

// IRIS v0.0.3 — Types des événements transitant sur l'EventBus interne.
// Cf docs/IRIS-ARCHITECTURE.md §4 (Architecture multi-agents — Event Bus typé)
// Cf docs/IRIS-AGENTS-CATALOG.md (Convention commune : events_in / events_out par agent)
//
// Tous les agents publient et consomment des IRISEvent. Le Conductor en est le routeur
// principal (cf catalog §1). Garantie Sendable pour Swift 6 strict concurrency.

// `AgentID` est défini dans App/Sources/Agents/Agent.swift (source de vérité unique).
// Importé implicitement (même module IRIS).

/// Importance d'un signal — échelle 1 (trivial) à 5 (critique).
/// Cf catalog §2 Sentinel : règles de signalement (email standard = 2, CI failure = 5...).
public enum SignalImportance: Int, Sendable, Codable, Comparable {
    case trivial = 1
    case low = 2
    case medium = 3
    case high = 4
    case critical = 5

    public static func < (lhs: SignalImportance, rhs: SignalImportance) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Événements typés transitant sur le bus.
/// v0.0.3 — cases couvrant le flux Conductor → workers + signaux Sentinel + logs.
/// v0.0.4+ ajoutera : `memory.*` (Scribe), `mcp.*` (MCP Manager), `ui.update` (UI subscribers).
public enum IRISEvent: Sendable {
    /// Input direct utilisateur (palette Cmd+K, prompt principal...).
    case userInput(String, timestamp: Date)

    /// Conductor dispatche un intent à un worker.
    case agentDispatched(from: AgentID, to: AgentID, intent: String, eventId: UUID)

    /// Worker répond (succès) à un dispatch.
    case agentResponse(from: AgentID, content: String, eventId: UUID)

    /// Sentinel (ou autre observer) émet un signal qualifié.
    case signalEmitted(from: AgentID, importance: SignalImportance, summary: String, source: String?)

    /// Action effectuée par un agent — append-only, base de la reversibility (cf archi §6.3).
    case actionLogged(by: AgentID, action: String, params: [String: String], reversible: Bool)

    /// Échec d'un agent — Conductor écoute pour relayer / retry.
    case agentFailure(agent: AgentID, error: String)

    /// Log interne (mirroring os_log). file/line aident le triage côté UI Inspector.
    case systemLog(level: LogLevel, message: String, file: String, line: Int)

    /// Quill a produit un draft prêt à review (v0.4).
    case draftReady(draftId: UUID, signalId: UUID?, channel: String, summary: String)

    /// Envoy demande une approbation user pour exécuter une action (v0.5).
    case actionRequested(actionId: UUID, agent: AgentID, summary: String, isReversible: Bool)

    /// User a approuvé une action (depuis UI ou modal natif).
    case actionApproved(actionId: UUID, approvedAt: Date)

    /// User a rejeté une action (raison optionnelle).
    case actionRejected(actionId: UUID, reason: String?)

    /// Envoy a exécuté une action (succès ou échec via result).
    case actionExecuted(actionId: UUID, success: Bool, result: String)

    /// v1.17 — Chunk de texte streaming Conductor (Claude SSE live).
    /// L'UI accumule en streamingText jusqu'à recevoir .agentResponse final.
    case conductorChunk(eventId: UUID, delta: String)

    /// Niveaux alignés sur os.Logger (cf Apple `OSLogType`).
    public enum LogLevel: String, Sendable, Codable {
        case debug, info, notice, warning, error, fault
    }

    /// Timestamp de l'event. Pour les cases non-`userInput`, on retourne `Date()` à la lecture
    /// (les events sont publiés "live", donc ~ équivalent à l'instant courant).
    /// v0.0.5+ : si on a besoin d'un timestamp précis stocké, on l'embarquera dans chaque case.
    public var timestamp: Date {
        switch self {
        case .userInput(_, let t): return t
        default: return Date()
        }
    }
}

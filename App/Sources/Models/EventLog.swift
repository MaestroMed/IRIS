import Foundation
import SwiftData

/// Persistance d'un événement transitant sur le bus.
/// Cf docs/IRIS-AGENTS-CATALOG.md (events_in/events_out) + IRISEvent enum (EventBus/IRISEvent.swift).
///
/// `kind` matche le nom de la case IRISEvent : "userInput", "agentDispatched", "agentResponse",
/// "signalEmitted", "actionLogged", "agentFailure", "systemLog".
///
/// `payloadJSON` sérialise les associated values (timestamp, content, importance, etc.) pour
/// rester souple pendant que le schéma d'events évolue v0.0.x → v0.x.
///
/// `correlationId` groupe les events liés (ex: un dispatch + sa response partagent l'eventId).
@Model
public final class EventLog {
    public var id: UUID
    public var timestamp: Date
    public var kind: String
    public var fromAgent: String?
    public var toAgent: String?
    public var payloadJSON: String
    public var correlationId: UUID?

    public init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        kind: String,
        fromAgent: String? = nil,
        toAgent: String? = nil,
        payloadJSON: String = "{}",
        correlationId: UUID? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.fromAgent = fromAgent
        self.toAgent = toAgent
        self.payloadJSON = payloadJSON
        self.correlationId = correlationId
    }
}

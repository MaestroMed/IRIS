import Foundation
import SwiftData

// IRIS v0.0.4 — Persistance SwiftData d'un agent (config + état).
// Cf docs/IRIS-AGENTS-CATALOG.md (Convention commune : capabilities read/write/forbidden, llm_model).
//
// `id` matche `AgentID.rawValue` (cf App/Sources/Agents/Agent.swift et App/Sources/EventBus/IRISEvent.swift).
// On stocke en `String` plutôt qu'enum pour découpler la persistance de la couche typée Swift
// (évolution future : ajout d'agents customs sans casser le schema).
//
// `capabilitiesJSON` sérialise un objet {read:[...], write:[...], forbidden:[...]} — laissé en String
// pour souplesse v0.x. v1.x : passer à un type Codable + @Attribute(.transformable) si besoin de query.
@Model
public final class AgentModel {
    @Attribute(.unique) public var id: String
    public var displayName: String
    public var isEnabled: Bool
    public var llmModelDefault: String
    public var capabilitiesJSON: String
    public var createdAt: Date
    public var lastActivityAt: Date?

    public init(
        id: String,
        displayName: String,
        isEnabled: Bool = true,
        llmModelDefault: String,
        capabilitiesJSON: String = "{}",
        createdAt: Date = .now,
        lastActivityAt: Date? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.isEnabled = isEnabled
        self.llmModelDefault = llmModelDefault
        self.capabilitiesJSON = capabilitiesJSON
        self.createdAt = createdAt
        self.lastActivityAt = lastActivityAt
    }
}

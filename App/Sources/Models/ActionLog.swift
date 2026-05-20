import Foundation
import SwiftData

/// Log append-only des actions exécutées par les agents (cf archi §6.3 Reversibilité).
/// Jamais modifié après écriture. Source de vérité pour "undo last action" + audit trail.
///
/// `actionType` est un identifiant stable : "email.send", "github.pr.create", "file.write",
/// "skill.invoke", "shell.execute", etc.
///
/// `reversible` = true uniquement si on a un `undoPayloadJSON` qui permet de défaire l'action.
/// Pour les actions externes irréversibles (email envoyé), reversible = false et l'UI
/// montre l'action "frozen".
///
/// `executedByUserApproval` distingue les actions auto (auto-approve par capability) des
/// actions nécessitant un OK explicite (Envoy.send_email, Builder.write_outside_iris, etc.).
@Model
public final class ActionLog {
    public var id: UUID
    public var timestamp: Date
    public var agentId: String
    public var actionType: String
    public var paramsJSON: String
    public var resultJSON: String
    public var success: Bool
    public var reversible: Bool
    public var undoPayloadJSON: String?
    public var executedAt: Date
    public var executedByUserApproval: Bool

    public init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        agentId: String,
        actionType: String,
        paramsJSON: String = "{}",
        resultJSON: String = "{}",
        success: Bool,
        reversible: Bool = false,
        undoPayloadJSON: String? = nil,
        executedAt: Date = .now,
        executedByUserApproval: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.agentId = agentId
        self.actionType = actionType
        self.paramsJSON = paramsJSON
        self.resultJSON = resultJSON
        self.success = success
        self.reversible = reversible
        self.undoPayloadJSON = undoPayloadJSON
        self.executedAt = executedAt
        self.executedByUserApproval = executedByUserApproval
    }
}

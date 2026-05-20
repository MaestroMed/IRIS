import Foundation
import SwiftData

/// Rapport d'audit produit par Auditor (v0.7+).
/// `verdict` ∈ {"GREEN", "YELLOW", "RED"}, comme damage-control.
/// `findingsJSON` / `topActionsJSON` sérialisent les structures du rapport pour flexibilité.
/// `executedSkill` = nom du skill instancié (v0.7 : "mock-v0.7", v0.7.5+ : "damage-control").
@Model
public final class AuditReport {
    public var id: UUID
    public var createdAt: Date
    public var projectCodename: String
    public var verdict: String
    public var headline: String          // 1-line summary
    public var findingsJSON: String      // ["finding 1", "finding 2", ...]
    public var topActionsJSON: String    // [{action, effort, impact}, ...]
    public var modelUsed: String         // "claude-opus-4-7" | "mock-v0.7"
    public var executedSkill: String?    // "damage-control" en v0.7.5+
    public var costUSD: Double
    public var durationSeconds: Double

    public init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        projectCodename: String,
        verdict: String,
        headline: String = "",
        findingsJSON: String = "[]",
        topActionsJSON: String = "[]",
        modelUsed: String,
        executedSkill: String? = nil,
        costUSD: Double = 0,
        durationSeconds: Double = 0
    ) {
        self.id = id
        self.createdAt = createdAt
        self.projectCodename = projectCodename
        self.verdict = verdict
        self.headline = headline
        self.findingsJSON = findingsJSON
        self.topActionsJSON = topActionsJSON
        self.modelUsed = modelUsed
        self.executedSkill = executedSkill
        self.costUSD = costUSD
        self.durationSeconds = durationSeconds
    }
}

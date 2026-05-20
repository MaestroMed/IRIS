import Foundation
import SwiftData

/// Signal émis par Sentinel (cf docs/IRIS-AGENTS-CATALOG.md §2).
/// Source : "gmail", "github", "calendar", "fs", "screen".
/// Importance 1-5 (cf SignalImportance enum).
///
/// `acknowledged` = Mehdi a vu le signal. `actedOn` = action prise (draft generated, etc.).
@Model
public final class Signal {
    public var id: UUID
    public var emittedAt: Date
    public var source: String
    public var importance: Int
    public var summary: String
    public var rawLink: String?
    public var projectScope: String?
    public var acknowledged: Bool
    public var actedOn: Bool

    public init(
        id: UUID = UUID(),
        emittedAt: Date = .now,
        source: String,
        importance: Int,
        summary: String,
        rawLink: String? = nil,
        projectScope: String? = nil,
        acknowledged: Bool = false,
        actedOn: Bool = false
    ) {
        self.id = id
        self.emittedAt = emittedAt
        self.source = source
        self.importance = importance
        self.summary = summary
        self.rawLink = rawLink
        self.projectScope = projectScope
        self.acknowledged = acknowledged
        self.actedOn = actedOn
    }
}

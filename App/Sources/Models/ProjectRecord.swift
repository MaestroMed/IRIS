import Foundation
import SwiftData

/// Représentation d'un projet du portfolio de Mehdi (cf Cartographer, docs/IRIS-AGENTS-CATALOG.md §6).
/// Synchronisé avec `/Users/mehdinafaa/Iris/artefacts/PROJECTS-MAP.md` (sens DB → fichier en v0.6).
///
/// `codename` est l'identifiant stable (ex: "atelier_frisson", "az_construction", "lol_tok", "mind").
/// `status` ∈ {"active", "tiede", "dormant", "archived"}.
/// `stackJSON` sérialise les choix techniques pour query/filter facetté futur.
@Model
public final class ProjectRecord {
    @Attribute(.unique) public var codename: String
    public var displayName: String
    public var repoURL: String?
    public var localPath: String?
    public var domain: String?
    public var stackJSON: String
    public var status: String
    public var lastPushAt: Date?
    public var lastScannedAt: Date?
    public var isPrivate: Bool
    public var notes: String

    public init(
        codename: String,
        displayName: String,
        repoURL: String? = nil,
        localPath: String? = nil,
        domain: String? = nil,
        stackJSON: String = "{}",
        status: String = "active",
        lastPushAt: Date? = nil,
        lastScannedAt: Date? = nil,
        isPrivate: Bool = false,
        notes: String = ""
    ) {
        self.codename = codename
        self.displayName = displayName
        self.repoURL = repoURL
        self.localPath = localPath
        self.domain = domain
        self.stackJSON = stackJSON
        self.status = status
        self.lastPushAt = lastPushAt
        self.lastScannedAt = lastScannedAt
        self.isPrivate = isPrivate
        self.notes = notes
    }
}

// v1.339 — 3rd-party service connection fields + git live status
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

    // v1.339 — 3rd-party service connections (per-project)
    public var vercelURL: String?           // ex: "https://vercel.com/maestromed/atelier-frisson"
    public var supabaseURL: String?         // ex: "https://supabase.com/dashboard/project/abc123"
    public var cloudflareZone: String?      // ex: "atelier-frisson.com"
    public var resendDomain: String?        // ex: "atelier-frisson.com" (sender)
    public var clientEmail: String?         // ex: "contact@atelier-frisson.com"
    public var customLinksJSON: String      // CSV or JSON like [{"label":"Notion","url":"..."}], default "[]"

    // v1.339 — Live git status (set by Cartographer.refresh)
    public var gitBranch: String?           // ex: "main"
    public var gitDirtyCount: Int           // count of modified+untracked files, default 0
    public var gitAhead: Int                // ahead origin, default 0
    public var gitBehind: Int               // behind origin, default 0
    public var lastCommitAt: Date?          // last commit timestamp on current branch
    public var lastCommitMessage: String?   // last commit subject line

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
        notes: String = "",
        vercelURL: String? = nil,
        supabaseURL: String? = nil,
        cloudflareZone: String? = nil,
        resendDomain: String? = nil,
        clientEmail: String? = nil,
        customLinksJSON: String = "[]",
        gitBranch: String? = nil,
        gitDirtyCount: Int = 0,
        gitAhead: Int = 0,
        gitBehind: Int = 0,
        lastCommitAt: Date? = nil,
        lastCommitMessage: String? = nil
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
        self.vercelURL = vercelURL
        self.supabaseURL = supabaseURL
        self.cloudflareZone = cloudflareZone
        self.resendDomain = resendDomain
        self.clientEmail = clientEmail
        self.customLinksJSON = customLinksJSON
        self.gitBranch = gitBranch
        self.gitDirtyCount = gitDirtyCount
        self.gitAhead = gitAhead
        self.gitBehind = gitBehind
        self.lastCommitAt = lastCommitAt
        self.lastCommitMessage = lastCommitMessage
    }
}

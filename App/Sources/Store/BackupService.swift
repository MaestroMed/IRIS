import Foundation
import SwiftData

/// v1.9 + v1.4.A — Export/Import JSON SwiftData IRIS.
/// Export : dump complet en ~/iris-backup-<date>.json.
/// Import : restore idempotent par UUID (skip si exists).
/// MIND import : format simple {codename, verdict, headline, createdAt} → AuditReport.
public enum BackupService {
    public static let backupVersion = "1.9"

    // MARK: — Snapshots Codable (extraction Sendable des @Model)

    public struct IRISBackup: Codable, Sendable {
        public let version: String
        public let exportedAt: Date
        public let memories: [MemorySnap]
        public let signals: [SignalSnap]
        public let drafts: [DraftSnap]
        public let audits: [AuditSnap]
        public let actions: [ActionSnap]
        public let projects: [ProjectSnap]
    }

    public struct MemorySnap: Codable, Sendable {
        public let id: UUID
        public let createdAt: Date
        public let type: String
        public let name: String
        public let summary: String
        public let content: String
        public let sourceAgent: String?
        public let projectScope: String?
        public let tagsCSV: String
    }

    public struct SignalSnap: Codable, Sendable {
        public let id: UUID
        public let emittedAt: Date
        public let source: String
        public let importance: Int
        public let summary: String
        public let rawLink: String?
        public let projectScope: String?
        public let acknowledged: Bool
        public let actedOn: Bool
    }

    public struct DraftSnap: Codable, Sendable {
        public let id: UUID
        public let createdAt: Date
        public let signalId: UUID?
        public let audience: String
        public let channel: String
        public let tone: String
        public let subject: String?
        public let content: String
        public let modelUsed: String
        public let costUSD: Double
        public let status: String
        public let sentAt: Date?
        public let rejectionReason: String?
    }

    public struct AuditSnap: Codable, Sendable {
        public let id: UUID
        public let createdAt: Date
        public let projectCodename: String
        public let verdict: String
        public let headline: String
        public let findingsJSON: String
        public let topActionsJSON: String
        public let modelUsed: String
        public let executedSkill: String?
        public let costUSD: Double
        public let durationSeconds: Double
    }

    public struct ActionSnap: Codable, Sendable {
        public let id: UUID
        public let timestamp: Date
        public let agentId: String
        public let actionType: String
        public let paramsJSON: String
        public let resultJSON: String
        public let success: Bool
        public let reversible: Bool
        public let executedByUserApproval: Bool
        public let executedAt: Date
    }

    public struct ProjectSnap: Codable, Sendable {
        public let codename: String
        public let displayName: String
        public let repoURL: String?
        public let localPath: String?
        public let domain: String?
        public let stackJSON: String
        public let status: String
        public let lastPushAt: Date?
        public let isPrivate: Bool
        public let notes: String
    }

    // MARK: — Export

    /// Sérialise tout le SwiftData store en IRISBackup + write file ~/iris-backup-<iso>.json.
    /// Retourne URL du fichier créé.
    @MainActor
    public static func exportAll(container: ModelContainer, to dir: URL? = nil) throws -> URL {
        let context = container.mainContext
        let backup = IRISBackup(
            version: backupVersion,
            exportedAt: .now,
            memories: ((try? context.fetch(FetchDescriptor<Memory>())) ?? []).map { m in
                MemorySnap(
                    id: m.id, createdAt: m.createdAt, type: m.type,
                    name: m.name, summary: m.summary, content: m.content,
                    sourceAgent: m.sourceAgent, projectScope: m.projectScope, tagsCSV: m.tagsCSV
                )
            },
            signals: ((try? context.fetch(FetchDescriptor<Signal>())) ?? []).map { s in
                SignalSnap(
                    id: s.id, emittedAt: s.emittedAt, source: s.source,
                    importance: s.importance, summary: s.summary, rawLink: s.rawLink,
                    projectScope: s.projectScope, acknowledged: s.acknowledged, actedOn: s.actedOn
                )
            },
            drafts: ((try? context.fetch(FetchDescriptor<Draft>())) ?? []).map { d in
                DraftSnap(
                    id: d.id, createdAt: d.createdAt, signalId: d.signalId,
                    audience: d.audience, channel: d.channel, tone: d.tone,
                    subject: d.subject, content: d.content, modelUsed: d.modelUsed,
                    costUSD: d.costUSD, status: d.status, sentAt: d.sentAt,
                    rejectionReason: d.rejectionReason
                )
            },
            audits: ((try? context.fetch(FetchDescriptor<AuditReport>())) ?? []).map { a in
                AuditSnap(
                    id: a.id, createdAt: a.createdAt, projectCodename: a.projectCodename,
                    verdict: a.verdict, headline: a.headline,
                    findingsJSON: a.findingsJSON, topActionsJSON: a.topActionsJSON,
                    modelUsed: a.modelUsed, executedSkill: a.executedSkill,
                    costUSD: a.costUSD, durationSeconds: a.durationSeconds
                )
            },
            actions: ((try? context.fetch(FetchDescriptor<ActionLog>())) ?? []).map { a in
                ActionSnap(
                    id: a.id, timestamp: a.timestamp, agentId: a.agentId,
                    actionType: a.actionType, paramsJSON: a.paramsJSON,
                    resultJSON: a.resultJSON, success: a.success,
                    reversible: a.reversible, executedByUserApproval: a.executedByUserApproval,
                    executedAt: a.executedAt
                )
            },
            projects: ((try? context.fetch(FetchDescriptor<ProjectRecord>())) ?? []).map { p in
                ProjectSnap(
                    codename: p.codename, displayName: p.displayName,
                    repoURL: p.repoURL, localPath: p.localPath, domain: p.domain,
                    stackJSON: p.stackJSON, status: p.status, lastPushAt: p.lastPushAt,
                    isPrivate: p.isPrivate, notes: p.notes
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(backup)

        let dateStr = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
        let targetDir = dir ?? URL(fileURLWithPath: NSHomeDirectory())
        let url = targetDir.appendingPathComponent("iris-backup-\(dateStr).json")
        try data.write(to: url)
        return url
    }

    // MARK: — Import IRIS backup

    @MainActor
    public static func importBackup(container: ModelContainer, from url: URL) throws -> ImportStats {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(IRISBackup.self, from: data)

        let context = container.mainContext
        var stats = ImportStats()

        // Memory : upsert par UUID
        let existingMemIds = Set(((try? context.fetch(FetchDescriptor<Memory>())) ?? []).map(\.id))
        for snap in backup.memories where !existingMemIds.contains(snap.id) {
            let m = Memory(
                id: snap.id, createdAt: snap.createdAt, type: snap.type,
                name: snap.name, summary: snap.summary, content: snap.content,
                sourceAgent: snap.sourceAgent, projectScope: snap.projectScope,
                tagsCSV: snap.tagsCSV
            )
            context.insert(m)
            stats.memoriesAdded += 1
        }

        // Signal : upsert par UUID
        let existingSigIds = Set(((try? context.fetch(FetchDescriptor<Signal>())) ?? []).map(\.id))
        for snap in backup.signals where !existingSigIds.contains(snap.id) {
            context.insert(Signal(
                id: snap.id, emittedAt: snap.emittedAt, source: snap.source,
                importance: snap.importance, summary: snap.summary, rawLink: snap.rawLink,
                projectScope: snap.projectScope, acknowledged: snap.acknowledged, actedOn: snap.actedOn
            ))
            stats.signalsAdded += 1
        }

        // Audit : upsert par UUID
        let existingAuditIds = Set(((try? context.fetch(FetchDescriptor<AuditReport>())) ?? []).map(\.id))
        for snap in backup.audits where !existingAuditIds.contains(snap.id) {
            context.insert(AuditReport(
                id: snap.id, createdAt: snap.createdAt,
                projectCodename: snap.projectCodename, verdict: snap.verdict,
                headline: snap.headline, findingsJSON: snap.findingsJSON,
                topActionsJSON: snap.topActionsJSON, modelUsed: snap.modelUsed,
                executedSkill: snap.executedSkill, costUSD: snap.costUSD,
                durationSeconds: snap.durationSeconds
            ))
            stats.auditsAdded += 1
        }

        // Draft : upsert par UUID
        let existingDraftIds = Set(((try? context.fetch(FetchDescriptor<Draft>())) ?? []).map(\.id))
        for snap in backup.drafts where !existingDraftIds.contains(snap.id) {
            context.insert(Draft(
                id: snap.id, createdAt: snap.createdAt, signalId: snap.signalId,
                audience: snap.audience, channel: snap.channel, tone: snap.tone,
                subject: snap.subject, content: snap.content, modelUsed: snap.modelUsed,
                costUSD: snap.costUSD, status: snap.status, sentAt: snap.sentAt,
                rejectionReason: snap.rejectionReason
            ))
            stats.draftsAdded += 1
        }

        // Project : upsert par codename (unique)
        let existingProjCodes = Set(((try? context.fetch(FetchDescriptor<ProjectRecord>())) ?? []).map(\.codename))
        for snap in backup.projects where !existingProjCodes.contains(snap.codename) {
            context.insert(ProjectRecord(
                codename: snap.codename, displayName: snap.displayName,
                repoURL: snap.repoURL, localPath: snap.localPath, domain: snap.domain,
                stackJSON: snap.stackJSON, status: snap.status,
                lastPushAt: snap.lastPushAt, lastScannedAt: nil,
                isPrivate: snap.isPrivate, notes: snap.notes
            ))
            stats.projectsAdded += 1
        }

        // ActionLog : append-only par nature, upsert par UUID
        let existingActIds = Set(((try? context.fetch(FetchDescriptor<ActionLog>())) ?? []).map(\.id))
        for snap in backup.actions where !existingActIds.contains(snap.id) {
            context.insert(ActionLog(
                id: snap.id, timestamp: snap.timestamp, agentId: snap.agentId,
                actionType: snap.actionType, paramsJSON: snap.paramsJSON,
                resultJSON: snap.resultJSON, success: snap.success,
                reversible: snap.reversible, undoPayloadJSON: nil,
                executedAt: snap.executedAt, executedByUserApproval: snap.executedByUserApproval
            ))
            stats.actionsAdded += 1
        }

        try context.save()
        return stats
    }

    public struct ImportStats: Sendable {
        public var memoriesAdded = 0
        public var signalsAdded = 0
        public var draftsAdded = 0
        public var auditsAdded = 0
        public var actionsAdded = 0
        public var projectsAdded = 0

        public var total: Int {
            memoriesAdded + signalsAdded + draftsAdded + auditsAdded + actionsAdded + projectsAdded
        }

        public var summary: String {
            "+\(memoriesAdded) memories · +\(signalsAdded) signals · +\(draftsAdded) drafts · +\(auditsAdded) audits · +\(actionsAdded) actions · +\(projectsAdded) projects"
        }
    }

    // MARK: — v1.4.A MIND import

    /// Format MIND simple : array de {codename, verdict, headline, createdAt? ISO8601}.
    /// Tout est inséré comme AuditReport executedSkill="mind-import".
    public struct MINDExportEntry: Codable, Sendable {
        public let codename: String
        public let verdict: String
        public let headline: String
        public let createdAt: Date?
        public let findings: [String]?
    }

    @MainActor
    public static func importMINDExport(container: ModelContainer, from url: URL) throws -> Int {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entries = try decoder.decode([MINDExportEntry].self, from: data)

        let context = container.mainContext
        var added = 0
        for entry in entries {
            let findingsJSON = (try? JSONSerialization.data(withJSONObject: entry.findings ?? []))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            let report = AuditReport(
                createdAt: entry.createdAt ?? .now,
                projectCodename: entry.codename,
                verdict: entry.verdict,
                headline: entry.headline,
                findingsJSON: findingsJSON,
                topActionsJSON: "[]",
                modelUsed: "mind-import",
                executedSkill: "mind-import",
                costUSD: 0,
                durationSeconds: 0
            )
            context.insert(report)
            added += 1
        }
        try context.save()
        return added
    }
}

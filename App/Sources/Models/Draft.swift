import Foundation
import SwiftData

/// Draft généré par Quill en réponse à un signal Sentinel.
/// `status` évolue : pending → approved → sent (ou rejected).
/// `signalId` réfère le Signal d'origine (UUID rawValue). FK soft pour rester simple v0.4.
@Model
public final class Draft {
    public var id: UUID
    public var createdAt: Date
    public var signalId: UUID?
    public var audience: String       // "client", "internal", "public", etc.
    public var channel: String        // "email", "slack", "github_comment", etc.
    public var tone: String           // "formel-fr-client", "casual-fr-team", "tech-en-pr", etc.
    public var subject: String?       // email subject ou titre
    public var content: String
    public var modelUsed: String      // ex "claude-sonnet-4-6"
    public var costUSD: Double
    public var status: String         // "pending", "approved", "sent", "rejected", "failed"
    public var sentAt: Date?
    public var rejectionReason: String?

    public init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        signalId: UUID? = nil,
        audience: String = "client",
        channel: String = "email",
        tone: String = "formel-fr-client",
        subject: String? = nil,
        content: String,
        modelUsed: String,
        costUSD: Double = 0,
        status: String = "pending",
        sentAt: Date? = nil,
        rejectionReason: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.signalId = signalId
        self.audience = audience
        self.channel = channel
        self.tone = tone
        self.subject = subject
        self.content = content
        self.modelUsed = modelUsed
        self.costUSD = costUSD
        self.status = status
        self.sentAt = sentAt
        self.rejectionReason = rejectionReason
    }
}

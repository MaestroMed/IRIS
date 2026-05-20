import Foundation
import SwiftData

/// Mémoire long terme stockée par Scribe (cf docs/IRIS-AGENTS-CATALOG.md §3).
/// Format compatible avec les mémoires Claude existantes
/// (`~/.claude/projects/<repo>/memory/<name>.md` avec frontmatter).
///
/// `type` ∈ {"user", "feedback", "project", "reference"} — mirroir des types Claude memory.
/// `embeddingData` rempli en v0.2 par Scribe (NLEmbedding macOS NaturalLanguage framework).
/// `tagsCSV` sert au filtrage facetté du retrieval.
@Model
public final class Memory {
    public var id: UUID
    public var createdAt: Date
    public var type: String
    public var name: String
    public var summary: String
    public var content: String
    public var sourceAgent: String?
    public var projectScope: String?
    public var embeddingData: Data?
    public var tagsCSV: String

    public init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        type: String,
        name: String,
        summary: String,
        content: String,
        sourceAgent: String? = nil,
        projectScope: String? = nil,
        embeddingData: Data? = nil,
        tagsCSV: String = ""
    ) {
        self.id = id
        self.createdAt = createdAt
        self.type = type
        self.name = name
        self.summary = summary
        self.content = content
        self.sourceAgent = sourceAgent
        self.projectScope = projectScope
        self.embeddingData = embeddingData
        self.tagsCSV = tagsCSV
    }
}

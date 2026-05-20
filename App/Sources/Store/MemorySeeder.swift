import Foundation
import SwiftData

/// v1.6.1 — Pré-seed Memory depuis les 11 mémoires Claude `.md` existantes.
/// Au premier launch (ou si MemorySeeder.lastSeedAt < latest .md mtime), parse et insert.
///
/// Compatible avec format frontmatter Claude :
/// ```
/// ---
/// name: my-memory
/// description: One-liner
/// metadata:
///   type: user|feedback|project|reference
/// ---
///
/// Body markdown...
/// ```
///
/// Idempotent par `name` (skip si Memory avec ce name existe déjà — pas d'overwrite v1.6.1,
/// upsert vient v1.6.2).
public enum MemorySeeder {
    private static let memoryDir = "\(NSHomeDirectory())/.claude/projects/-Users-mehdinafaa-Iris/memory"
    private static let lastSeedKey = "iris.memorySeeder.lastSeedAt"

    @MainActor
    public static func seedIfNeeded(in context: ModelContext) async {
        let files = scanMemoryFiles()
        guard !files.isEmpty else {
            irisLog(.info, "MemorySeeder : aucun .md à seed (dossier vide ?)", category: IRISLogger.store)
            return
        }

        var seeded = 0
        var skipped = 0

        for file in files {
            guard let parsed = parseMarkdownMemory(at: file) else {
                continue
            }

            // Skip si déjà présent (idempotence v1.6.1)
            let name = parsed.name
            let existsDescriptor = FetchDescriptor<Memory>(predicate: #Predicate { $0.name == name })
            let exists = ((try? context.fetchCount(existsDescriptor)) ?? 0) > 0
            if exists {
                skipped += 1
                continue
            }

            let memory = Memory(
                type: parsed.type,
                name: parsed.name,
                summary: parsed.description,
                content: parsed.body,
                sourceAgent: "import.memory-seeder",
                projectScope: parsed.projectScope,
                tagsCSV: "imported,claude-memory"
            )

            // Use Scribe.store pour calculer embedding via NLEmbedding
            await Scribe.store(memory: memory, in: context)
            seeded += 1
        }

        UserDefaults.standard.set(Date(), forKey: lastSeedKey)
        irisLog(.info, "MemorySeeder done — seeded=\(seeded), skipped=\(skipped) (déjà existants)",
                category: IRISLogger.store)
    }

    // MARK: — Scan

    private static func scanMemoryFiles() -> [URL] {
        let dir = URL(fileURLWithPath: memoryDir)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return contents
            .filter { $0.pathExtension == "md" }
            .filter { $0.lastPathComponent != "MEMORY.md" }  // index, pas une mémoire
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    // MARK: — Parser frontmatter YAML simple

    /// Parsed memory content extracted from a .md file.
    struct ParsedMemory: Sendable {
        let name: String
        let description: String
        let type: String
        let projectScope: String?
        let body: String
    }

    private static func parseMarkdownMemory(at url: URL) -> ParsedMemory? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }

        let lines = content.components(separatedBy: "\n")
        guard lines.first == "---" else {
            // Pas de frontmatter : skip
            return nil
        }

        var frontmatter: [String: String] = [:]
        var bodyStartIdx = lines.count  // default : pas de body si frontmatter mal fermé
        var inMetadata = false

        for (i, line) in lines.dropFirst().enumerated() {
            if line == "---" {
                bodyStartIdx = i + 2  // +1 pour le drop, +1 pour passer le second ---
                break
            }
            if line.hasPrefix("metadata:") {
                inMetadata = true
                continue
            }
            if inMetadata && (line.hasPrefix("  ") || line.hasPrefix("\t")) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if let colonIdx = trimmed.firstIndex(of: ":") {
                    let key = "metadata." + String(trimmed[..<colonIdx])
                    let value = String(trimmed[trimmed.index(after: colonIdx)...])
                        .trimmingCharacters(in: .whitespaces)
                    frontmatter[key] = value
                }
            } else if !line.isEmpty, let colonIdx = line.firstIndex(of: ":") {
                let key = String(line[..<colonIdx]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
                frontmatter[key] = value
                inMetadata = false
            }
        }

        guard let name = frontmatter["name"], !name.isEmpty else {
            return nil
        }
        let description = frontmatter["description"] ?? ""
        let type = frontmatter["metadata.type"] ?? "reference"

        // Project scope : si filename commence par "project_", c'est lié à un projet
        let filename = url.deletingPathExtension().lastPathComponent
        let projectScope: String? = filename.hasPrefix("project_")
            ? String(filename.dropFirst("project_".count))
            : nil

        let body = lines.dropFirst(bodyStartIdx).joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return ParsedMemory(
            name: name,
            description: description,
            type: type,
            projectScope: projectScope,
            body: body
        )
    }
}

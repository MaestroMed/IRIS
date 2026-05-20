import Foundation
import NaturalLanguage
import SwiftData

/// Scribe v0.2 — mémoire long terme avec embeddings NLEmbedding macOS natif.
///
/// Utilise `NLEmbedding.sentenceEmbedding(for:)` (sortie 512-dim) FR + EN fallback.
/// Pas de dépendance externe (CoreML / ONNX / nomic-embed viendront en v0.2.x si besoin de qualité supérieure).
///
/// Format compatible avec les mémoires Claude existantes
/// (`~/.claude/projects/<repo>/memory/<name>.md` avec frontmatter) — voir Memory model.
///
/// Retrieval : cosine similarity top-K avec filtres facets (type, projectScope).
/// Performance v0.2 : O(N) fetch all + compute. v0.3+ : on optimisera (index annoyish) si > 10k mémoires.
public actor Scribe {
    public static let shared = Scribe()

    private let embedding: NLEmbedding?

    private init() {
        // Try FR first (langue principale Mehdi), then EN fallback.
        // Si aucun n'est dispo (rare, devrait toujours être bundled), on log et tous les ops embedding skip.
        if let fr = NLEmbedding.sentenceEmbedding(for: .french) {
            self.embedding = fr
        } else if let en = NLEmbedding.sentenceEmbedding(for: .english) {
            self.embedding = en
        } else {
            self.embedding = nil
        }
    }

    /// Calcule l'embedding 512-dim d'un texte. nil si NLEmbedding indisponible.
    public func computeEmbedding(_ text: String) -> [Double]? {
        guard let embedding else {
            irisLog(.warning, "NLEmbedding indisponible — pas de retrieval sémantique", category: IRISLogger.store)
            return nil
        }
        return embedding.vector(for: text)
    }

    /// Insère une mémoire dans le store, calcule l'embedding si pas déjà fait.
    @MainActor
    public static func store(
        memory: Memory,
        in context: ModelContext
    ) async {
        if memory.embeddingData == nil {
            if let vec = await Scribe.shared.computeEmbedding(memory.content) {
                memory.embeddingData = Self.embeddingFloatsToData(vec)
            }
        }
        context.insert(memory)
        do {
            try context.save()
        } catch {
            irisLog(.error, "Scribe store failed: \(error)", category: IRISLogger.store)
        }
    }

    /// Retrieve top-K mémoires par similarité cosine au query.
    /// Filtres optionnels : type ("user"/"feedback"/"project"/"reference") + projectScope.
    @MainActor
    public static func retrieve(
        query: String,
        topK: Int = 5,
        type: String? = nil,
        projectScope: String? = nil,
        in context: ModelContext
    ) async -> [(memory: Memory, score: Double)] {
        guard let queryVec = await Scribe.shared.computeEmbedding(query) else {
            return []
        }

        // Fetch with optional facet filters
        var descriptor = FetchDescriptor<Memory>()
        if let type, let projectScope {
            descriptor.predicate = #Predicate<Memory> { $0.type == type && $0.projectScope == projectScope }
        } else if let type {
            descriptor.predicate = #Predicate<Memory> { $0.type == type }
        } else if let projectScope {
            descriptor.predicate = #Predicate<Memory> { $0.projectScope == projectScope }
        }

        guard let memories = try? context.fetch(descriptor) else { return [] }

        let scored: [(Memory, Double)] = memories.compactMap { mem in
            guard let data = mem.embeddingData,
                  let vec = Self.dataToFloats(data),
                  vec.count == queryVec.count
            else { return nil }
            let sim = Self.cosineSimilarity(queryVec, vec)
            return (mem, sim)
        }

        return scored
            .sorted { $0.1 > $1.1 }
            .prefix(topK)
            .map { ($0.0, $0.1) }
    }

    // MARK: — Helpers (Data ↔ [Double])

    static func embeddingFloatsToData(_ floats: [Double]) -> Data {
        floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    static func dataToFloats(_ data: Data) -> [Double]? {
        let count = data.count / MemoryLayout<Double>.size
        guard count > 0 else { return nil }
        return data.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Double.self).prefix(count))
        }
    }

    static func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0
        var magA = 0.0
        var magB = 0.0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            magA += a[i] * a[i]
            magB += b[i] * b[i]
        }
        guard magA > 0, magB > 0 else { return 0 }
        return dot / (sqrt(magA) * sqrt(magB))
    }
}

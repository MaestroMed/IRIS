import Foundation
import SwiftData

/// Seeder des 10 agents par défaut au premier launch.
/// Idempotent : skip si la table AgentModel a déjà des entrées.
/// Routing modèles cohérent avec docs/IRIS-AGENTS-CATALOG.md.
public enum AgentSeeder {
    public static let defaultAgents: [(id: AgentID, llmModel: ClaudeModel)] = [
        (.conductor, .opus47),
        (.sentinel, .haiku45),
        (.scribe, .haiku45),
        (.quill, .sonnet46),
        (.auditor, .sonnet46),
        (.cartographer, .haiku45),
        (.builder, .opus47),
        (.envoy, .haiku45),
        // Witness utilise Gemini 2.5 Flash-Lite pour vision input cheap.
        // Stocké comme string raw ; non-Claude → routing géré par AgentRunner v1.5+.
        (.witness, .haiku45),  // fallback Haiku tant que multi-provider pas wired
        (.advisor, .opus47),
    ]

    @MainActor
    public static func seedIfNeeded(in context: ModelContext) {
        let descriptor = FetchDescriptor<AgentModel>()
        let existing = (try? context.fetchCount(descriptor)) ?? 0
        guard existing == 0 else { return }

        for (agentId, claudeModel) in defaultAgents {
            let agent = AgentModel(
                id: agentId.rawValue,
                displayName: agentId.descriptor.displayName,
                llmModelDefault: claudeModel.rawValue
            )
            context.insert(agent)
        }

        do {
            try context.save()
        } catch {
            // En dev on log mais on n'explose pas — le seeder est best-effort.
            irisLog(.error, "AgentSeeder save failed: \(error)", category: IRISLogger.store)
        }
    }
}

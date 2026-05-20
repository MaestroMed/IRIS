import ProjectDescription

// Module helper pour les phases futures (v0.4+).
// À v0.0.1, IRIS n'a qu'un target App monolithique.
// Quand on scindra en modules (Core/Store/Agents/UI), on listera ici.

public enum Module: String, CaseIterable {
    // Phase v0.4+ exemples (non-actifs en v0.0.1) :
    // case irisCore       = "IRISCore"        // Event bus, scheduler, types partagés
    // case irisStore      = "IRISStore"       // SwiftData models, CloudKit sync
    // case irisAgents     = "IRISAgents"      // 10 agents
    // case irisDesign     = "IRISDesign"      // Tokens Liquid Glass, components
    // case irisMCP        = "IRISMCP"         // Client MCP, process spawn manager

    case placeholder = "Placeholder"  // évite enum vide qui ferait planter le compileur
}

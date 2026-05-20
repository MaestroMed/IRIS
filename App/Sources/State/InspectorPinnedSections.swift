import Foundation
import Observation

/// v1.48 — Sections épinglées Inspector. Si un agent est épinglé, sa section dédiée
/// reste visible dans l'Inspector même si Mehdi navigue vers un autre agent.
/// Permet d'avoir e.g. Cartographer toujours visible pendant qu'on chat avec Conductor.
@MainActor
@Observable
public final class InspectorPinnedSections {
    public static let shared = InspectorPinnedSections()

    private static let pinnedKey = "iris.inspector.pinnedAgents"

    public var pinnedAgents: Set<AgentID> {
        didSet { persist() }
    }

    private init() {
        if let raw = UserDefaults.standard.array(forKey: Self.pinnedKey) as? [String] {
            self.pinnedAgents = Set(raw.compactMap { AgentID(rawValue: $0) })
        } else {
            self.pinnedAgents = []
        }
    }

    public func isPinned(_ id: AgentID) -> Bool {
        pinnedAgents.contains(id)
    }

    public func toggle(_ id: AgentID) {
        if pinnedAgents.contains(id) {
            pinnedAgents.remove(id)
        } else {
            pinnedAgents.insert(id)
        }
    }

    private func persist() {
        UserDefaults.standard.set(Array(pinnedAgents.map(\.rawValue)), forKey: Self.pinnedKey)
    }
}

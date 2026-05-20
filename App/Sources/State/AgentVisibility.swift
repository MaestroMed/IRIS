import Foundation
import Observation

/// v1.43 — Gestion de la visibilité des agents dans le sidebar.
/// Mehdi peut masquer des agents qu'il n'utilise pas pour réduire le bruit visuel.
@MainActor
@Observable
public final class AgentVisibility {
    public static let shared = AgentVisibility()

    private static let hiddenKey = "iris.agentVisibility.hidden"

    public var hiddenAgents: Set<AgentID> {
        didSet { persist() }
    }

    private init() {
        if let raw = UserDefaults.standard.array(forKey: Self.hiddenKey) as? [String] {
            self.hiddenAgents = Set(raw.compactMap { AgentID(rawValue: $0) })
        } else {
            self.hiddenAgents = []
        }
    }

    public func isHidden(_ id: AgentID) -> Bool {
        hiddenAgents.contains(id)
    }

    public func toggle(_ id: AgentID) {
        if hiddenAgents.contains(id) {
            hiddenAgents.remove(id)
        } else {
            hiddenAgents.insert(id)
        }
    }

    public var visibleAgents: [AgentID] {
        AgentID.businessAgents.filter { !hiddenAgents.contains($0) }
    }

    private func persist() {
        UserDefaults.standard.set(Array(hiddenAgents.map(\.rawValue)), forKey: Self.hiddenKey)
    }
}

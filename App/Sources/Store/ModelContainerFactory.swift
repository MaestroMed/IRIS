import Foundation
import SwiftData

/// Factory du ModelContainer SwiftData IRIS.
/// v0.0.4 — container local (sans CloudKit sync). CloudKit activé en v1.4 (sync MIND).
public enum ModelContainerFactory {
    /// Schéma complet : 6 modèles IRIS.
    public static let schema = Schema([
        AgentModel.self,
        EventLog.self,
        ActionLog.self,
        Memory.self,
        Signal.self,
        ProjectRecord.self,
    ])

    /// Container persistent local (file-backed). Utilisé par l'app en production.
    @MainActor
    public static func makeLocalContainer() -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            cloudKitDatabase: .none  // v1.4 : .automatic avec container app.iris.macos
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create local ModelContainer: \(error)")
        }
    }

    /// Container in-memory pour tests et previews SwiftUI.
    @MainActor
    public static func makeInMemoryContainer() -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create in-memory ModelContainer: \(error)")
        }
    }
}

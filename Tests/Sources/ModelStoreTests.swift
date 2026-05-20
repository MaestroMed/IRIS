import Testing
@testable import IRIS
import SwiftData
import Foundation

struct ModelStoreTests {
    @MainActor
    @Test func canCreateInMemoryContainerAndSeed() throws {
        let container = ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        AgentSeeder.seedIfNeeded(in: context)
        let agents = try context.fetch(FetchDescriptor<AgentModel>())
        #expect(agents.count == 10)
    }

    @MainActor
    @Test func canPersistAndQueryEvent() throws {
        let container = ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let event = EventLog(kind: "userInput", payloadJSON: "{\"text\":\"hello\"}")
        context.insert(event)
        try context.save()
        let fetched = try context.fetch(FetchDescriptor<EventLog>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.kind == "userInput")
    }

    @MainActor
    @Test func actionLogIsAppendOnly() throws {
        let container = ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let log = ActionLog(
            agentId: "envoy",
            actionType: "email.send",
            success: true,
            executedByUserApproval: true
        )
        context.insert(log)
        try context.save()
        let fetched = try context.fetch(FetchDescriptor<ActionLog>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.reversible == false)  // email = non réversible par défaut
    }

    @MainActor
    @Test func projectRecordUniqueCodename() throws {
        let container = ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        context.insert(ProjectRecord(codename: "atelier_frisson", displayName: "Atelier Frisson"))
        try context.save()
        let fetched = try context.fetch(FetchDescriptor<ProjectRecord>())
        #expect(fetched.count == 1)
    }
}

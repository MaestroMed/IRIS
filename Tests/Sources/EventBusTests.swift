import Testing
@testable import IRIS
import Foundation

// IRIS v0.0.3 — Tests EventBus.
// Vise : valider publish/subscribe + history. Pas de couverture exhaustive ici, on
// teste le contrat de base. v0.0.4+ ajoutera tests dispatch Conductor.

struct EventBusTests {
    @Test func publishAndSubscribe() async throws {
        let bus = EventBus.shared
        let stream = await bus.subscribe()

        // On collecte dans une Task isolée. Box mutable Sendable-safe via actor confinement.
        actor Collector {
            var events: [IRISEvent] = []
            func append(_ e: IRISEvent) { events.append(e) }
            func count() -> Int { events.count }
        }
        let collector = Collector()

        let task = Task {
            for await event in stream {
                await collector.append(event)
                if await collector.count() == 2 { break }
            }
        }

        await bus.publish(.userInput("hello", timestamp: Date()))
        await bus.publish(.systemLog(level: .info, message: "test", file: "test.swift", line: 1))

        // Laisse le temps au consumer d'absorber les events.
        try await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()

        let count = await collector.count()
        #expect(count >= 2)
    }
}

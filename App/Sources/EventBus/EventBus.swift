import Foundation

// IRIS v0.0.3 — EventBus pub/sub typé basé AsyncStream.
// Cf docs/IRIS-ARCHITECTURE.md §4 : "Tous les agents publient/écoutent via un bus pub/sub".
// Cf docs/IRIS-ARCHITECTURE.md §4 "Concepts core" : "UI Subscriber : la UI ne pull jamais, elle s'abonne".
//
// Conception :
//   - Actor pour sérialiser les mutations (`continuations`, `history`) sans data race.
//   - Singleton `shared` car bus global au process (l'UI, le Conductor et les workers
//     partagent le même bus).
//   - `subscribe()` retourne un `AsyncStream<IRISEvent>` ; chaque consommateur a un buffer
//     unbounded. Quand le stream est fini (consumer cancellé), on nettoie via
//     `onTermination`. v0.0.5+ : éventuellement passer en bounded buffer + policy.
//   - Historique conservé via `HistoryRing` (1000 derniers events) — utile pour
//     l'Inspector UI et le debug post-mortem.

public actor EventBus {
    public static let shared = EventBus()

    private var continuations: [UUID: AsyncStream<IRISEvent>.Continuation] = [:]
    private let history: HistoryRing

    private init() {
        self.history = HistoryRing(capacity: 1000)
    }

    /// Publie un événement à tous les abonnés courants + historique.
    public func publish(_ event: IRISEvent) {
        history.append(event)
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    /// Souscrit un nouveau consommateur. L'AsyncStream s'auto-nettoie à la fin
    /// (cancel / break / sortie du `for await`) via `onTermination`.
    public func subscribe() -> AsyncStream<IRISEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            self.continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                // Hop vers l'actor pour la mutation `continuations`.
                Task { await self?.unsubscribe(id) }
            }
        }
    }

    private func unsubscribe(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }

    /// Snapshot filtré des N derniers events. Utile pour l'UI Inspector / debug.
    public func recentHistory(
        filter: @Sendable (IRISEvent) -> Bool = { _ in true }
    ) -> [IRISEvent] {
        history.snapshot().filter(filter)
    }
}

/// Ring buffer thread-safe utilisé par l'EventBus.
/// `@unchecked Sendable` : on garantit la safety via `NSLock` interne.
final class HistoryRing: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: [IRISEvent] = []
    private let capacity: Int

    init(capacity: Int) { self.capacity = capacity }

    func append(_ event: IRISEvent) {
        lock.lock(); defer { lock.unlock() }
        buffer.append(event)
        if buffer.count > capacity {
            buffer.removeFirst(buffer.count - capacity)
        }
    }

    func snapshot() -> [IRISEvent] {
        lock.lock(); defer { lock.unlock() }
        return buffer
    }
}

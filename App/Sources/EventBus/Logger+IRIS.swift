import Foundation
import OSLog

// IRIS v0.0.3 — Logger structuré os_log + mirroring sur l'EventBus.
//
// Pourquoi double sortie ?
//   - os_log : visible dans Console.app (subsystem = app.iris.macos) + persistance system.
//   - EventBus : mirroré comme `.systemLog` pour que l'UI Inspector et le Conductor
//     puissent réagir aux logs internes.
//
// Conventions :
//   - Le subsystem matche le bundle id (cf Project.swift).
//   - 1 category par "couche" : conductor, bus, store, agents, ui — facile à filtrer
//     dans Console.app via `subsystem == "app.iris.macos" AND category == "..."`.
//   - Les messages sont marqués `.public` car IRIS = local-first, pas de PII traversant
//     un système distant. v0.3+ si on ajoute télémétrie distante : repasser à `.private`
//     les champs sensibles.

public enum IRISLogger {
    public static let subsystem = "app.iris.macos"

    public static let conductor = Logger(subsystem: subsystem, category: "conductor")
    public static let bus = Logger(subsystem: subsystem, category: "bus")
    public static let store = Logger(subsystem: subsystem, category: "store")
    public static let agents = Logger(subsystem: subsystem, category: "agents")
    public static let ui = Logger(subsystem: subsystem, category: "ui")
}

/// Log helper qui écrit à la fois sur `os_log` (via `Logger`) et sur l'EventBus
/// (comme `.systemLog`). Préférer ce helper au `Logger` direct pour bénéficier du
/// mirroring UI.
///
/// - Parameters:
///   - level: niveau syslog-like (debug → fault).
///   - message: message libre (sera émis en `.public`).
///   - category: catégorie os.Logger ciblée — par défaut `IRISLogger.bus`.
///   - file/line: capture auto via `#fileID` / `#line`.
public func irisLog(
    _ level: IRISEvent.LogLevel,
    _ message: String,
    category: Logger = IRISLogger.bus,
    file: String = #fileID,
    line: Int = #line
) {
    switch level {
    case .debug:   category.debug("\(message, privacy: .public)")
    case .info:    category.info("\(message, privacy: .public)")
    case .notice:  category.notice("\(message, privacy: .public)")
    case .warning: category.warning("\(message, privacy: .public)")
    case .error:   category.error("\(message, privacy: .public)")
    case .fault:   category.fault("\(message, privacy: .public)")
    }

    // Fire-and-forget vers l'actor EventBus. Les valeurs capturées sont Sendable.
    Task {
        await EventBus.shared.publish(
            .systemLog(level: level, message: message, file: file, line: line)
        )
    }
}

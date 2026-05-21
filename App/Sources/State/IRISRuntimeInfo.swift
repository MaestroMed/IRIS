import Foundation

/// v1.83 — Runtime info IRIS : version courante + bootstrap timestamp + uptime + git commit court.
/// Affiché dans Settings (info section).
public enum IRISRuntimeInfo {
    /// Version IRIS courante (mise à jour manuellement à chaque release majeure).
    /// v1.133 — 5 phases real closed : A Witness Vision · B MCP Real · C Auditor
    /// Real · D Builder Real · E Conductor Multi-Agent Dispatch (route "audit X"
    /// vers Auditor, "cherche X" vers Scribe etc. sans LLM call). Exocortex
    /// orchestré : regarde / écoute / lit / écrit / route.
    public static let appVersion = "1.133"

    /// Timestamp du bootstrap IRIS (set par IRISApp.bootstrap au launch).
    public nonisolated(unsafe) static var bootstrapAt: Date?

    /// Uptime depuis bootstrap. Nil avant bootstrap.
    public static var uptime: TimeInterval? {
        guard let bootstrapAt else { return nil }
        return Date().timeIntervalSince(bootstrapAt)
    }

    /// Format uptime humain (ex : "2h 14m" / "47s" / "3d 5h").
    public static func formatUptime(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "\(Int(seconds))s" }
        if seconds < 3600 { return "\(Int(seconds / 60))min" }
        if seconds < 86400 { return "\(Int(seconds / 3600))h \(Int(seconds.truncatingRemainder(dividingBy: 3600) / 60))min" }
        return "\(Int(seconds / 86400))j \(Int(seconds.truncatingRemainder(dividingBy: 86400) / 3600))h"
    }

    /// Build commit court (8 chars), si "IRIS_BUILD_COMMIT" env var défini au build.
    /// Sinon "—".
    public static var buildCommit: String {
        ProcessInfo.processInfo.environment["IRIS_BUILD_COMMIT"]?.prefix(8).description ?? "—"
    }
}

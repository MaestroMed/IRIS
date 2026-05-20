import Foundation
import Sentry

/// IRIS v1.0.B — Wrapper Sentry SDK pour error tracking + performance + breadcrumbs.
/// Init conditionnel : si DSN absent (ENV `SENTRY_DSN` ou Keychain), on skip silencieusement.
/// Cohérence avec MIND iOS (qui utilise déjà Sentry SDK).
public enum IRISSentry {
    private static let envVarName = "SENTRY_DSN"
    private static let keychainAccount = "sentry-dsn"

    /// Init Sentry au bootstrap (appelé depuis IRISApp dès que possible).
    /// Returns true si Sentry actif, false si skip.
    @discardableResult
    public static func start() -> Bool {
        guard let dsn = resolveDSN(), !dsn.isEmpty else {
            irisLog(.info, "Sentry skipped (no DSN dans env SENTRY_DSN ou Keychain)", category: IRISLogger.bus)
            return false
        }

        SentrySDK.start { options in
            options.dsn = dsn
            options.environment = isDebugBuild() ? "debug" : "release"
            options.releaseName = "iris@1.0.0+15"
            options.attachStacktrace = true
            options.enableAutoBreadcrumbTracking = true
            options.enableNetworkBreadcrumbs = true
            options.tracesSampleRate = 0.1   // 10% performance traces
            options.profilesSampleRate = 0.1  // 10% profiling
            options.beforeSend = { event in
                // PII scrubbing minimal
                event.request?.cookies = nil
                return event
            }
        }

        irisLog(.notice, "Sentry started — DSN configured, env=\(isDebugBuild() ? "debug" : "release")",
                category: IRISLogger.bus)
        return true
    }

    /// Breadcrumb manuel — appelable depuis le bus pour suivre les events critiques.
    public static func breadcrumb(
        category: String,
        message: String,
        level: SentryLevel = .info,
        data: [String: Any]? = nil
    ) {
        let crumb = Breadcrumb()
        crumb.category = category
        crumb.message = message
        crumb.level = level
        crumb.data = data
        SentrySDK.addBreadcrumb(crumb)
    }

    /// Capture une erreur Swift avec contexte.
    public static func captureError(_ error: Error, agent: String? = nil) {
        SentrySDK.capture(error: error) { scope in
            if let agent {
                scope.setTag(value: agent, key: "agent")
            }
        }
    }

    /// Capture un message arbitraire (warning, info).
    public static func capture(_ message: String, level: SentryLevel = .warning, tags: [String: String] = [:]) {
        SentrySDK.capture(message: message) { scope in
            scope.setLevel(level)
            for (k, v) in tags { scope.setTag(value: v, key: k) }
        }
    }

    // MARK: — DSN resolution

    private static func resolveDSN() -> String? {
        // Priorité 1 : env var (dev workflow)
        if let env = ProcessInfo.processInfo.environment[envVarName], !env.isEmpty {
            return env
        }
        // Priorité 2 : Keychain (config persistante user)
        if let stored = IRISKeychain.shared.retrieve(account: keychainAccount), !stored.isEmpty {
            return stored
        }
        return nil
    }

    /// Stocke le DSN dans le Keychain (depuis Settings v1.0.B+).
    @discardableResult
    public static func storeDSN(_ dsn: String) -> Bool {
        IRISKeychain.shared.store(value: dsn, account: keychainAccount)
    }

    private static func isDebugBuild() -> Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}

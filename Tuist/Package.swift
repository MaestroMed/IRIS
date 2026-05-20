// swift-tools-version: 6.0
import PackageDescription

#if TUIST
import struct ProjectDescription.PackageSettings

let packageSettings = PackageSettings(
    productTypes: [:]
)
#endif

let package = Package(
    name: "IRIS",
    dependencies: [
        // v1.0.B — Sentry SDK pour error tracking + performance (cohérence MIND iOS).
        // Init conditionnel : si DSN absent (env var SENTRY_DSN ou Keychain), skip init.
        .package(url: "https://github.com/getsentry/sentry-cocoa", from: "8.40.0"),
    ]
)

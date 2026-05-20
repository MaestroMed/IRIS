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
        // v0.0.1 — aucune dépendance externe.
        // Phases suivantes :
        // .package(url: "https://github.com/getsentry/sentry-cocoa", from: "8.0.0"),     // v1.0
    ]
)

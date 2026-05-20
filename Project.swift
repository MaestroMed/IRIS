import ProjectDescription
import ProjectDescriptionHelpers

// IRIS v0.0.1 — Mac native SwiftUI app, exocortex local desktop multi-agents.
// Sister project de MIND iOS (app.mind.ios) — partage la design system Liquid Glass.
// Cf docs/IRIS-VISION.md, docs/IRIS-ARCHITECTURE.md, docs/IRIS-AGENTS-CATALOG.md, docs/IRIS-ROADMAP.md.

let appBundleId = "app.iris.macos"
let appName = "IRIS"

let appTarget: Target = .target(
    name: appName,
    destinations: .macOS,
    product: .app,
    bundleId: appBundleId,
    deploymentTargets: .macOS("26.0"),
    infoPlist: .extendingDefault(with: [
        "CFBundleDisplayName": "IRIS",
        "CFBundleShortVersionString": "0.0.1",
        "CFBundleVersion": "1",
        "LSApplicationCategoryType": "public.app-category.productivity",
        "ITSAppUsesNonExemptEncryption": false,
        // v0.0.1 — minimal. Permissions Screen Recording + Camera viendront en v1.5+ (Witness).
        // MCP server spawn (Gmail / Calendar) viendra en v0.3 — process sandbox entitlement à ajouter alors.
    ]),
    sources: ["App/Sources/**"],
    resources: ["App/Resources/**"],
    entitlements: .file(path: "App/IRIS.entitlements"),
    dependencies: [
        // v0.0.1 — zéro dependencies externes. Ajout au fil des phases :
        // v0.1 : swift-anthropic OU wrapper REST Claude Opus
        // v0.2 : NaturalLanguage (système, pas externe)
        // v0.3 : Process spawn pour MCP servers (système)
        // v1.0 : Sentry (cohérence MIND)
    ],
    settings: .settings(base: [
        "SWIFT_VERSION": "6.0",
        "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    ])
)

let testTarget: Target = .target(
    name: "\(appName)Tests",
    destinations: .macOS,
    product: .unitTests,
    bundleId: "\(appBundleId).tests",
    deploymentTargets: .macOS("26.0"),
    sources: ["Tests/Sources/**"],
    dependencies: [
        .target(name: appName),
    ],
    settings: .settings(base: [
        "SWIFT_VERSION": "6.0",
    ])
)

let project = Project(
    name: appName,
    organizationName: "Numelite",
    targets: [appTarget, testTarget]
)

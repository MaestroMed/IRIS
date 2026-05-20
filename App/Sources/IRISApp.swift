import SwiftUI

// IRIS v0.0.1 — entry point.
// "Premier exocortex local desktop multi-agents avec UX visuelle dense."
// Cf /Users/mehdinafaa/Iris/docs/IRIS-VISION.md

@main
struct IRISApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 1400, height: 900)
        .commands {
            // v0.0.x — pas de commandes custom encore. Standard menu macOS.
            // v0.0.5+ — ajout commandes Conductor (Cmd+K palette, Cmd+, settings).
        }
    }
}

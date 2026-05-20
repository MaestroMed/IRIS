import SwiftUI

// IRIS v0.0.2 — ContentView = NavigationSplitView 3 colonnes (sidebar / main / inspector).
// Cf docs/IRIS-VISION.md, docs/IRIS-ARCHITECTURE.md.
// v0.0.5+ — chaque colonne sera spécialisée par agent sélectionné.

struct ContentView: View {
    @State private var appState = IRISAppState()

    var body: some View {
        @Bindable var binding = appState

        NavigationSplitView(columnVisibility: $binding.columnVisibility) {
            SidebarView()
        } content: {
            MainCanvasView()
        } detail: {
            InspectorView()
        }
        .navigationSplitViewStyle(.balanced)
        .environment(appState)
        .frame(minWidth: 1100, minHeight: 700)
    }
}

#Preview {
    ContentView()
        .frame(width: 1400, height: 900)
}

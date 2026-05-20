import SwiftUI

// IRIS v0.0.2 + v1.8 — ContentView = NavigationSplitView 3 colonnes + raccourcis clavier.
// Cf docs/IRIS-VISION.md, docs/IRIS-ARCHITECTURE.md.

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
        .onReceive(NotificationCenter.default.publisher(for: IRISCommands.selectAgentNotif)) { notif in
            if let agentId = notif.object as? AgentID {
                appState.selection = .agent(agentId)
            }
        }
    }
}

#Preview {
    ContentView()
        .frame(width: 1400, height: 900)
}

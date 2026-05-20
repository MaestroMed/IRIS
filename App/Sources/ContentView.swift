import SwiftUI
import SwiftData

// IRIS v0.0.2 + v1.8 + v1.13 — ContentView = NavigationSplitView 3 colonnes + raccourcis + toolbar stats live.

struct ContentView: View {
    @State private var appState = IRISAppState()
    @State private var showCommandPalette = false  // v1.46

    @Query(sort: \Signal.emittedAt, order: .reverse) private var allSignals: [Signal]
    @Query private var pendingDraftsQuery: [Draft]

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
        .toolbar { toolbarContent }
        .onReceive(NotificationCenter.default.publisher(for: IRISCommands.selectAgentNotif)) { notif in
            if let agentId = notif.object as? AgentID {
                appState.selection = .agent(agentId)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: IRISCommands.openCommandPaletteNotif)) { _ in
            showCommandPalette = true
        }
        .sheet(isPresented: $showCommandPalette) {
            CommandPaletteView()
                .environment(appState)
        }
    }

    // MARK: — v1.13 toolbar stats live

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            HStack(spacing: IRISTokens.spacing16) {
                // Signals 24h badge
                let signals24h = allSignals.filter { $0.emittedAt > Date().addingTimeInterval(-86400) }.count
                statsToolbarBadge(icon: "eye.circle", value: "\(signals24h)", color: IRISTokens.aquaTint, tooltip: "Signaux dernières 24h")

                // Pending drafts
                let pendingDrafts = pendingDraftsQuery.filter { $0.status == "pending" }.count
                if pendingDrafts > 0 {
                    statsToolbarBadge(icon: "pencil.and.scribble", value: "\(pendingDrafts)", color: IRISTokens.goldAccent, tooltip: "Drafts pending review")
                }

                // Pending actions
                if !appState.pendingActions.isEmpty {
                    statsToolbarBadge(
                        icon: "exclamationmark.triangle.fill",
                        value: "\(appState.pendingActions.count)",
                        color: .red,
                        tooltip: "Actions en attente d'approval"
                    )
                }

                // Cost session (v1.72 — red si limit dépassé)
                Text("$\(String(format: "%.4f", appState.sessionCostUSD))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(
                        appState.costLimitTriggered ? .red :
                        (appState.sessionCostUSD > 0.5 ? IRISTokens.goldAccent : .secondary)
                    )
                    .help(
                        appState.costLimitTriggered
                            ? "Cost limit dépassé (\(String(format: "%.2f", IRISAppState.costLimitUSD))$). Click pour reset alerte."
                            : "Coût session cumulé (Anthropic API)"
                    )
                    .onTapGesture {
                        if appState.costLimitTriggered { appState.resetCostLimitFlag() }
                    }

                // API key status
                Image(systemName: appState.hasAnthropicKey ? "key.fill" : "key.slash")
                    .font(.system(size: 12))
                    .foregroundStyle(appState.hasAnthropicKey ? .green : IRISTokens.goldAccent)
                    .help(appState.hasAnthropicKey ? "API key Anthropic configurée" : "Mode mock — ajoute clé via Cmd+,")

                // Settings shortcut
                Button {
                    NSApplication.openSettings()
                } label: {
                    Image(systemName: "gear")
                }
                .help("Settings (Cmd+,)")
            }
        }
    }

    private func statsToolbarBadge(icon: String, value: String, color: Color, tooltip: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
        }
        .help(tooltip)
    }
}

#Preview {
    ContentView()
        .frame(width: 1400, height: 900)
}

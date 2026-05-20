import SwiftUI
import SwiftData

// IRIS v0.0.2 — Sidebar gauche. Liste des 10 agents + section System.
// v1.53 — badges count signals 1h par agent.

struct SidebarView: View {
    @Environment(IRISAppState.self) private var appState

    // v1.53 — Signaux dernière heure pour badges count
    @Query(sort: \Signal.emittedAt, order: .reverse) private var recentSignals: [Signal]

    /// Map source signal → AgentID émetteur (Sentinel pour data feeds, Witness pour screen).
    private static let sourceToAgent: [String: AgentID] = [
        "gmail": .sentinel,
        "github": .sentinel,
        "calendar": .sentinel,
        "fs": .sentinel,
        "screen": .witness
    ]

    private var signalCountsLastHour: [AgentID: Int] {
        let cutoff = Date().addingTimeInterval(-3600)
        var counts: [AgentID: Int] = [:]
        for signal in recentSignals where signal.emittedAt > cutoff {
            if let agent = Self.sourceToAgent[signal.source] {
                counts[agent, default: 0] += 1
            }
        }
        return counts
    }

    var body: some View {
        @Bindable var binding = appState
        let counts = signalCountsLastHour

        List(selection: $binding.selection) {
            Section {
                ForEach(AgentVisibility.shared.visibleAgents) { agent in
                    AgentRow(
                        descriptor: agent.descriptor,
                        status: appState.agentStatus(agent),
                        signalCount1h: counts[agent] ?? 0
                    )
                        .tag(SidebarSelection.agent(agent))
                }
            } header: {
                SidebarSectionHeader(title: SidebarSection.agents.title)
            }

            Section {
                ForEach(SystemDestination.allCases) { dest in
                    SystemRow(destination: dest)
                        .tag(SidebarSelection.system(dest))
                }
            } header: {
                SidebarSectionHeader(title: SidebarSection.system.title)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(
            // Liquid Glass : .regularMaterial + léger wash sky pour rester dans la palette.
            ZStack {
                Rectangle().fill(.regularMaterial)
                IRISTokens.skyBackground.opacity(0.18)
            }
            .ignoresSafeArea()
        )
        .navigationSplitViewColumnWidth(
            min: IRISTokens.sidebarMinWidth,
            ideal: IRISTokens.sidebarIdealWidth,
            max: IRISTokens.sidebarMaxWidth
        )
        .navigationTitle("IRIS")
    }
}

// MARK: — Section header

private struct SidebarSectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .default))
            .tracking(1.4)
            .foregroundStyle(.secondary)
            .padding(.top, IRISTokens.spacing4)
    }
}

// MARK: — Ligne agent

private struct AgentRow: View {
    let descriptor: AgentDescriptor
    let status: AgentStatus
    let signalCount1h: Int  // v1.53

    var body: some View {
        HStack(spacing: IRISTokens.spacing8) {
            Image(systemName: descriptor.symbol)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(IRISTokens.irisAccent)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(descriptor.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                Text(descriptor.alias)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: IRISTokens.spacing8)

            // v1.53 — badge count signaux 1h (visible si > 0)
            if signalCount1h > 0 {
                Text("\(signalCount1h)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(IRISTokens.aquaTint)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(IRISTokens.aquaTint.opacity(0.15))
                    .clipShape(Capsule())
                    .help("\(signalCount1h) signaux dernière heure")
            }

            Circle()
                .fill(status.dotColor)
                .frame(width: 6, height: 6)
                .accessibilityLabel("Statut : \(status.rawValue)")
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

// MARK: — Ligne system

private struct SystemRow: View {
    let destination: SystemDestination

    var body: some View {
        HStack(spacing: IRISTokens.spacing8) {
            Image(systemName: destination.symbol)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            Text(destination.displayName)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.primary)

            Spacer()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

#Preview {
    SidebarView()
        .environment(IRISAppState())
        .frame(width: 280, height: 600)
}

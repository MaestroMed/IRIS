import SwiftUI

// IRIS v0.0.2 — Sidebar gauche. Liste des 10 agents + section System.
// v0.0.5+ — dot status alimenté par l'event bus, drag-reorder, badges count (signals/drafts).

struct SidebarView: View {
    @Environment(IRISAppState.self) private var appState

    var body: some View {
        @Bindable var binding = appState

        List(selection: $binding.selection) {
            Section {
                ForEach(AgentID.businessAgents) { agent in
                    AgentRow(descriptor: agent.descriptor, status: appState.agentStatus(agent))
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

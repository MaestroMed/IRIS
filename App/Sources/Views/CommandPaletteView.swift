import SwiftUI

/// v1.46 — Command palette activée par Cmd+K. Sheet avec search bar + actions rapides.
struct CommandPaletteView: View {
    @Environment(IRISAppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var search: String = ""

    struct PaletteAction: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let icon: String
        let action: () -> Void
    }

    var allActions: [PaletteAction] {
        var actions: [PaletteAction] = []

        // Switch agent actions
        for agent in AgentID.businessAgents {
            actions.append(PaletteAction(
                id: "switch.\(agent.rawValue)",
                title: "Switch → \(agent.descriptor.displayName)",
                subtitle: agent.descriptor.tagline,
                icon: agent.descriptor.symbol,
                action: {
                    appState.selection = .agent(agent)
                    dismiss()
                }
            ))
        }

        // Agent actions
        actions.append(PaletteAction(
            id: "advisor.brief",
            title: "Brief Advisor (now)",
            subtitle: "Synthèse Opus du jour",
            icon: "sunrise",
            action: {
                Task { await Advisor.shared.runBriefing(kind: .manual) }
                dismiss()
            }
        ))
        actions.append(PaletteAction(
            id: "cartographer.refresh",
            title: "Refresh Cartographer",
            subtitle: "Re-scan ~/Developer + gh repo list",
            icon: "arrow.clockwise",
            action: {
                Task { await Cartographer.shared.refresh() }
                dismiss()
            }
        ))
        actions.append(PaletteAction(
            id: "conversation.reset",
            title: "Nouvelle conversation",
            subtitle: "Reset history + transcript",
            icon: "arrow.counterclockwise",
            action: {
                Task {
                    await Conductor.shared.resetHistory()
                    appState.clearTranscript()
                }
                dismiss()
            }
        ))
        actions.append(PaletteAction(
            id: "settings",
            title: "Ouvrir Settings",
            subtitle: "Cmd+,",
            icon: "gear",
            action: {
                NSApplication.openSettings()
                dismiss()
            }
        ))
        actions.append(PaletteAction(
            id: "dashboard",
            title: "Dashboard global",
            subtitle: "Vue stats globale",
            icon: "rectangle.grid.2x2",
            action: {
                appState.selection = nil
                dismiss()
            }
        ))

        // v1.152 — Dispatch shortcuts (équivalent commands depuis input bar)
        actions.append(PaletteAction(
            id: "show.dispatch.help",
            title: "Show dispatch help (?)",
            subtitle: "Liste les 7 commands directes (audit / scaffold / cherche / etc.)",
            icon: "questionmark.circle",
            action: {
                appState.currentInput = "?"
                appState.selection = .agent(.conductor)
                dismiss()
            }
        ))
        actions.append(PaletteAction(
            id: "dispatch.audit.template",
            title: "Audit projet…",
            subtitle: "Prepare input `audit <codename>` — tu complètes",
            icon: "checkmark.shield",
            action: {
                appState.currentInput = "audit "
                appState.selection = .agent(.conductor)
                dismiss()
            }
        ))
        actions.append(PaletteAction(
            id: "dispatch.scaffold.template",
            title: "Scaffold projet…",
            subtitle: "Prepare input `scaffold <name>` — tu complètes",
            icon: "hammer",
            action: {
                appState.currentInput = "scaffold "
                appState.selection = .agent(.conductor)
                dismiss()
            }
        ))
        actions.append(PaletteAction(
            id: "dispatch.cherche.template",
            title: "Cherche dans mémoires…",
            subtitle: "Prepare input `cherche <query>` — Scribe top 5",
            icon: "magnifyingglass",
            action: {
                appState.currentInput = "cherche "
                appState.selection = .agent(.conductor)
                dismiss()
            }
        ))

        return actions
    }

    var filtered: [PaletteAction] {
        if search.isEmpty { return allActions }
        let lowSearch = search.lowercased()
        return allActions.filter {
            $0.title.lowercased().contains(lowSearch) || $0.subtitle.lowercased().contains(lowSearch)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "command")
                    .foregroundStyle(IRISTokens.irisAccent)
                TextField("Rechercher action…", text: $search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                Spacer()
                Button("Fermer") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(IRISTokens.spacing16)

            Divider()

            ScrollView {
                LazyVStack(spacing: 2) {
                    if filtered.isEmpty {
                        Text("Aucune action correspondante.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(IRISTokens.spacing24)
                    } else {
                        ForEach(filtered) { item in
                            paletteRow(item)
                        }
                    }
                }
                .padding(IRISTokens.spacing8)
            }
        }
        .frame(minWidth: 500, idealWidth: 600, minHeight: 350, idealHeight: 420)
    }

    private func paletteRow(_ item: PaletteAction) -> some View {
        Button(action: item.action) {
            HStack {
                Image(systemName: item.icon)
                    .foregroundStyle(IRISTokens.irisAccent)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .medium))
                    Text(item.subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, IRISTokens.spacing8)
            .background(RoundedRectangle(cornerRadius: 6).fill(.thinMaterial))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

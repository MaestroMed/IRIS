import SwiftUI

/// v1.46 — Command palette activée par Cmd+K. Sheet avec search bar + actions rapides.
/// v1.169 — Recent 5 actions section (persisted @AppStorage).
/// v1.178 — Cmd+1..5 keyboard shortcuts on first 5 visible rows.
/// v1.183 — Clear-recents button in RECENT section header.
/// v1.188 — Action count hint subtitle (total + filtered + active search).
/// v1.211 — Favorites star toggle (yellow), favorites sort first.
struct CommandPaletteView: View {
    @Environment(IRISAppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var search: String = ""
    @AppStorage("recentPaletteActionIds") private var recentIdsCSV: String = ""
    @AppStorage("paletteFavoriteIds") private var favoriteIdsCSV: String = ""

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

        // v1.163 — System destinations shortcuts
        actions.append(PaletteAction(
            id: "system.logs",
            title: "System > Logs",
            subtitle: "Voir les EventLog runtime",
            icon: "list.bullet.rectangle",
            action: {
                appState.selection = .system(.logs)
                dismiss()
            }
        ))
        actions.append(PaletteAction(
            id: "system.memory",
            title: "System > Memory",
            subtitle: "Browse mémoires + retrieval Scribe",
            icon: "books.vertical",
            action: {
                appState.selection = .system(.memory)
                dismiss()
            }
        ))
        actions.append(PaletteAction(
            id: "system.stats",
            title: "System > Bus Stats",
            subtitle: "Stats events par kind 1h/24h/all",
            icon: "chart.bar.fill",
            action: {
                appState.selection = .system(.stats)
                dismiss()
            }
        ))

        return actions
    }

    var recentActions: [PaletteAction] {
        let ids = recentIdsCSV.split(separator: ",").map(String.init)
        let all = allActions
        var result: [PaletteAction] = []
        for id in ids {
            if let match = all.first(where: { $0.id == id }) {
                result.append(match)
            }
            if result.count >= 5 { break }
        }
        return result
    }

    var filtered: [PaletteAction] {
        let result: [PaletteAction]
        if search.isEmpty {
            result = allActions
        } else {
            let lowSearch = search.lowercased()
            result = allActions.filter {
                $0.title.lowercased().contains(lowSearch) || $0.subtitle.lowercased().contains(lowSearch)
            }
        }
        let favs = result.filter { isFavorite($0.id) }
        let nonFavs = result.filter { !isFavorite($0.id) }
        return favs + nonFavs
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

            HStack {
                Image(systemName: "list.bullet")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary.opacity(0.6))
                Text("\(allActions.count) actions disponibles · \(filtered.count) affichées")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary.opacity(0.7))
                if !search.isEmpty {
                    Spacer()
                    Text("filter: \"\(search)\"")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(IRISTokens.aquaTint.opacity(0.8))
                }
                Spacer()
            }
            .padding(.horizontal, IRISTokens.spacing16)
            .padding(.bottom, 4)

            Divider()

            ScrollView {
                LazyVStack(spacing: 2) {
                    if filtered.isEmpty {
                        Text("Aucune action correspondante.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(IRISTokens.spacing24)
                    } else {
                        if search.isEmpty && !recentActions.isEmpty {
                            HStack {
                                Text("RECENT")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .tracking(1.4)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button {
                                    recentIdsCSV = ""
                                } label: {
                                    HStack(spacing: 3) {
                                        Image(systemName: "xmark.circle")
                                            .font(.system(size: 9))
                                        Text("Clear")
                                            .font(.system(size: 9, design: .monospaced))
                                    }
                                    .foregroundStyle(.secondary.opacity(0.7))
                                }
                                .buttonStyle(.plain)
                                .help("Effacer l'historique des actions récentes")
                            }
                            .padding(.horizontal, IRISTokens.spacing8)
                            .padding(.top, 4)
                            ForEach(Array(recentActions.enumerated()), id: \.element.id) { idx, item in
                                paletteRow(item, rank: idx + 1)
                            }
                            Divider().padding(.vertical, 4)
                            Text("ALL ACTIONS")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .tracking(1.4)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, IRISTokens.spacing8)
                                .padding(.top, 4)
                            ForEach(filtered) { item in
                                paletteRow(item)
                            }
                        } else {
                            ForEach(Array(filtered.prefix(5).enumerated()), id: \.element.id) { idx, item in
                                paletteRow(item, rank: idx + 1)
                            }
                            ForEach(filtered.dropFirst(5)) { item in
                                paletteRow(item)
                            }
                        }
                    }
                }
                .padding(IRISTokens.spacing8)
            }
        }
        .frame(minWidth: 500, idealWidth: 600, minHeight: 350, idealHeight: 420)
    }

    private func recordRecent(_ id: String) {
        var list = recentIdsCSV.split(separator: ",").map(String.init)
        list.removeAll { $0 == id }
        list.insert(id, at: 0)
        if list.count > 5 { list = Array(list.prefix(5)) }
        recentIdsCSV = list.joined(separator: ",")
    }

    private func isFavorite(_ id: String) -> Bool {
        favoriteIdsCSV
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .contains(id)
    }

    private func toggleFavorite(_ id: String) {
        var list = favoriteIdsCSV
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if let idx = list.firstIndex(of: id) {
            list.remove(at: idx)
        } else {
            list.append(id)
        }
        favoriteIdsCSV = list.joined(separator: ",")
    }

    @ViewBuilder
    private func paletteRow(_ item: PaletteAction, rank: Int? = nil) -> some View {
        let body = Button {
            recordRecent(item.id)
            item.action()
        } label: {
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
                if let rank, rank >= 1, rank <= 5 {
                    Text("⌘\(rank)")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(Color.secondary.opacity(0.4), lineWidth: 0.5)
                        )
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, IRISTokens.spacing8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        let star = Button {
            toggleFavorite(item.id)
        } label: {
            Image(systemName: isFavorite(item.id) ? "star.fill" : "star")
                .font(.system(size: 10))
                .foregroundStyle(isFavorite(item.id) ? .yellow : .secondary.opacity(0.4))
        }
        .buttonStyle(.plain)
        .help(isFavorite(item.id) ? "Unfavorite" : "Add to favorites")
        .padding(.trailing, IRISTokens.spacing8)

        let row = HStack(spacing: 0) {
            body
            star
        }
        .background(RoundedRectangle(cornerRadius: 6).fill(.thinMaterial))

        if let rank, rank >= 1, rank <= 5 {
            row.keyboardShortcut(KeyEquivalent(Character("\(rank)")), modifiers: .command)
        } else {
            row
        }
    }
}

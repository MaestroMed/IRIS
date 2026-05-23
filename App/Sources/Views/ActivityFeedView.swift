import SwiftUI
import SwiftData

// IRIS v1.351 — Activity Feed unifiée. Sous System > Activity feed.
// Merge multi-source 24h : Signal (Sentinel) + Draft (Quill) + AuditReport (Auditor) + ActionLog (Envoy).
// Affiche en ligne chronologique inversée. Filter chips multi-select par agent.
// Tap row → navigate vers l'agent qui a produit l'item.

struct ActivityFeedView: View {
    @Environment(IRISAppState.self) private var appState

    // SwiftData #Predicate ne digère pas de static property capture (Swift 6 macro limit),
    // donc on @Query desc sans filtre temporel puis on filtre en mémoire (volumes 24h OK).
    @Query(sort: \Signal.emittedAt, order: .reverse) private var allSignals: [Signal]
    @Query(sort: \Draft.createdAt, order: .reverse) private var allDrafts: [Draft]
    @Query(sort: \AuditReport.createdAt, order: .reverse) private var allAudits: [AuditReport]
    @Query(sort: \ActionLog.executedAt, order: .reverse) private var allActions: [ActionLog]

    /// Fenêtre 24h (recalculée à chaque render — assez léger pour usage UI).
    private var cutoff24h: Date {
        Date().addingTimeInterval(-86_400)
    }

    private var recentSignals: [Signal] {
        allSignals.prefix(while: { $0.emittedAt > cutoff24h }).map { $0 }
    }
    private var recentDrafts: [Draft] {
        allDrafts.prefix(while: { $0.createdAt > cutoff24h }).map { $0 }
    }
    private var recentAudits: [AuditReport] {
        allAudits.prefix(while: { $0.createdAt > cutoff24h }).map { $0 }
    }
    private var recentActions: [ActionLog] {
        allActions.prefix(while: { $0.executedAt > cutoff24h }).map { $0 }
    }

    // Filter state — multi-select. Vide = aucun filter (tout).
    @State private var selectedAgents: Set<AgentID> = []

    // Filter chips disponibles. Conductor + autres exclus car ne produisent pas ces items.
    private static let filterableAgents: [AgentID] = [
        .sentinel, .quill, .auditor, .envoy, .cartographer, .builder, .conductor
    ]

    // Source signal → AgentID (Sentinel pour data feeds, Witness pour screen).
    private static let signalSourceToAgent: [String: AgentID] = [
        "gmail": .sentinel,
        "github": .sentinel,
        "calendar": .sentinel,
        "fs": .sentinel,
        "screen": .witness
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            filterChips
            Divider()
            feedList
        }
    }

    // MARK: — Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: "waveform.path.ecg")
                .foregroundStyle(IRISTokens.aquaTint)
            Text("Activity feed")
                .font(.system(size: 22, weight: .light, design: .serif))
            Text("· 24h")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(filteredItems.count)/\(mergedItems.count) items")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, IRISTokens.spacing24)
        .padding(.vertical, IRISTokens.spacing16)
    }

    // MARK: — Filter chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                allChip
                ForEach(Self.filterableAgents) { agent in
                    chip(for: agent)
                }
            }
            .padding(.horizontal, IRISTokens.spacing16)
            .padding(.vertical, IRISTokens.spacing8)
        }
        .background(.thinMaterial)
    }

    private var allChip: some View {
        let isAll = selectedAgents.isEmpty
        return Button {
            selectedAgents.removeAll()
        } label: {
            Text("All")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(isAll ? IRISTokens.aquaTint : .secondary)
                .padding(.horizontal, IRISTokens.spacing8)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(isAll ? IRISTokens.aquaTint.opacity(0.18) : Color.secondary.opacity(0.08))
                )
                .overlay(
                    Capsule().strokeBorder(
                        isAll ? IRISTokens.aquaTint.opacity(0.5) : Color.secondary.opacity(0.25),
                        lineWidth: 0.7
                    )
                )
        }
        .buttonStyle(.plain)
        .help("Afficher tous les agents (clear filter)")
    }

    private func chip(for agent: AgentID) -> some View {
        let isSelected = selectedAgents.contains(agent)
        return Button {
            if isSelected {
                selectedAgents.remove(agent)
            } else {
                selectedAgents.insert(agent)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: agent.descriptor.symbol)
                    .font(.system(size: 10))
                Text(agent.descriptor.displayName)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(isSelected ? IRISTokens.aquaTint : .primary.opacity(0.7))
            .padding(.horizontal, IRISTokens.spacing8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(isSelected ? IRISTokens.aquaTint.opacity(0.18) : Color.secondary.opacity(0.06))
            )
            .overlay(
                Capsule().strokeBorder(
                    isSelected ? IRISTokens.aquaTint.opacity(0.5) : Color.secondary.opacity(0.2),
                    lineWidth: 0.7
                )
            )
        }
        .buttonStyle(.plain)
        .help(isSelected ? "Retirer \(agent.descriptor.displayName) du filtre" : "Ajouter \(agent.descriptor.displayName) au filtre")
    }

    // MARK: — Feed list

    @ViewBuilder
    private var feedList: some View {
        if filteredItems.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(filteredItems) { item in
                        row(item)
                    }
                }
                .padding(IRISTokens.spacing16)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: IRISTokens.spacing16) {
            Spacer()
            Image(systemName: "moon.zzz")
                .font(.system(size: 44, weight: .ultraLight))
                .foregroundStyle(IRISTokens.aquaTint.opacity(0.6))
            Text("Calme plat depuis 24h")
                .font(.system(size: 18, weight: .light, design: .serif))
                .foregroundStyle(.primary.opacity(0.8))
            Text(mergedItems.isEmpty
                ? "Aucun signal, draft, audit ou action récents."
                : "Aucun item ne match les filtres sélectionnés.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(_ item: ActivityItem) -> some View {
        Button {
            appState.selection = .agent(item.agent)
        } label: {
            HStack(alignment: .top, spacing: IRISTokens.spacing8) {
                // Agent dot coloré
                Circle()
                    .fill(IRISTokens.irisAccent)
                    .frame(width: 7, height: 7)
                    .padding(.top, 6)

                // Timestamp relatif, mono
                Text(item.timestamp, format: .relative(presentation: .named))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 90, alignment: .leading)

                // Icon + agent
                HStack(spacing: 4) {
                    Image(systemName: item.icon)
                        .font(.system(size: 11))
                        .foregroundStyle(IRISTokens.aquaTint)
                        .frame(width: 14)
                    Text(item.agent.descriptor.displayName)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)
                }
                .frame(width: 130, alignment: .leading)

                // Label kind
                Text(item.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(IRISTokens.irisAccent)
                    .frame(width: 110, alignment: .leading)

                // Summary
                Text(item.summary)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary.opacity(0.85))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, IRISTokens.spacing8)
            .background(
                RoundedRectangle(cornerRadius: IRISTokens.cornerRadiusSmall)
                    .fill(.thinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: IRISTokens.cornerRadiusSmall)
                    .strokeBorder(Color.secondary.opacity(0.12), lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Tap pour ouvrir \(item.agent.descriptor.displayName)")
    }

    // MARK: — Merge + filter

    /// Construit la timeline unifiée depuis les 4 sources @Query.
    private var mergedItems: [ActivityItem] {
        var items: [ActivityItem] = []
        items.reserveCapacity(recentSignals.count + recentDrafts.count + recentAudits.count + recentActions.count)

        for s in recentSignals {
            items.append(ActivityItem(
                id: "signal-\(s.id.uuidString)",
                timestamp: s.emittedAt,
                agent: Self.signalSourceToAgent[s.source] ?? .sentinel,
                icon: "eye.circle",
                label: "Signal \(s.source)",
                summary: s.summary
            ))
        }
        for d in recentDrafts {
            items.append(ActivityItem(
                id: "draft-\(d.id.uuidString)",
                timestamp: d.createdAt,
                agent: .quill,
                icon: "pencil.and.scribble",
                label: "Draft \(d.channel)",
                summary: d.subject ?? String(d.content.prefix(120))
            ))
        }
        for a in recentAudits {
            items.append(ActivityItem(
                id: "audit-\(a.id.uuidString)",
                timestamp: a.createdAt,
                agent: .auditor,
                icon: "checkmark.shield",
                label: "Audit \(a.verdict)",
                summary: "\(a.projectCodename) — \(a.headline.isEmpty ? "(no headline)" : a.headline)"
            ))
        }
        for act in recentActions {
            let resolvedAgent = AgentID(rawValue: act.agentId) ?? .envoy
            items.append(ActivityItem(
                id: "action-\(act.id.uuidString)",
                timestamp: act.executedAt,
                agent: resolvedAgent,
                icon: act.success ? "bolt.fill" : "exclamationmark.triangle.fill",
                label: act.success ? "Action \(act.actionType)" : "Failed \(act.actionType)",
                summary: act.success
                    ? (act.reversible ? "reversible" : "irréversible")
                    : "échec — voir resultJSON"
            ))
        }

        return items.sorted { $0.timestamp > $1.timestamp }
    }

    private var filteredItems: [ActivityItem] {
        guard !selectedAgents.isEmpty else { return mergedItems }
        return mergedItems.filter { selectedAgents.contains($0.agent) }
    }
}

// MARK: — Item modèle

/// Item unifié de timeline. Source-agnostique pour render uniforme.
struct ActivityItem: Identifiable, Hashable {
    let id: String
    let timestamp: Date
    let agent: AgentID
    let icon: String
    let label: String
    let summary: String
}

#Preview {
    ActivityFeedView()
        .environment(IRISAppState())
        .frame(width: 900, height: 600)
}

import SwiftUI
import SwiftData

// IRIS v1.10 — DashboardView : vue globale quand aucun agent sélectionné.
// 4 cards stats Liquid Glass : Memory by type, Signals 24h by source, Drafts by status, Audits by verdict + Cost session.

struct DashboardView: View {
    @Environment(IRISAppState.self) private var appState

    @Query private var allMemories: [Memory]
    @Query(sort: \Signal.emittedAt, order: .reverse) private var allSignals: [Signal]
    @Query private var allDrafts: [Draft]
    @Query private var allAudits: [AuditReport]
    @Query private var allProjects: [ProjectRecord]
    @Query(sort: \ActionLog.executedAt, order: .reverse) private var allActions: [ActionLog]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: IRISTokens.spacing24) {
                header

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: IRISTokens.spacing16),
                        GridItem(.flexible(), spacing: IRISTokens.spacing16),
                    ],
                    spacing: IRISTokens.spacing16
                ) {
                    memoryCard
                    signalsCard
                    draftsCard
                    auditsCard
                    costCard
                    portfolioCard
                }

                recentActivitySection

                Spacer()
            }
            .padding(IRISTokens.spacing24)
        }
    }

    // MARK: — Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("IRIS")
                    .font(.system(size: 36, weight: .light, design: .serif))
                    .foregroundStyle(IRISTokens.irisAccent)
                    .tracking(4)
                Text("Dashboard")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide).year())
                    .font(IRISTokens.monoFont)
                    .foregroundStyle(.secondary)
            }
            Text("Sélectionne un agent dans le sidebar pour interagir, ou utilise Cmd+1..0 pour les raccourcis.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: — Cards stats

    private var memoryCard: some View {
        dashboardCard(title: "Memory", count: allMemories.count, icon: "books.vertical", color: IRISTokens.irisAccent) {
            let groups = Dictionary(grouping: allMemories, by: \.type)
            let breakdown = groups.map { ($0.key, $0.value.count) }
                .sorted { $0.1 > $1.1 }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(breakdown.prefix(5), id: \.0) { item in
                    statBar(label: item.0, value: item.1, total: allMemories.count, color: IRISTokens.irisAccent)
                }
            }
        }
    }

    private var signalsCard: some View {
        let oneDayAgo = Date().addingTimeInterval(-86400)
        let signals24h = allSignals.filter { $0.emittedAt >= oneDayAgo }
        return dashboardCard(title: "Signals 24h", count: signals24h.count, icon: "eye.circle", color: IRISTokens.aquaTint) {
            let groups = Dictionary(grouping: signals24h, by: \.source)
            let breakdown = groups.map { ($0.key, $0.value.count) }
                .sorted { $0.1 > $1.1 }
            VStack(alignment: .leading, spacing: 4) {
                if breakdown.isEmpty {
                    Text("Aucun signal sur 24h.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                } else {
                    ForEach(breakdown.prefix(5), id: \.0) { item in
                        statBar(label: item.0, value: item.1, total: signals24h.count, color: IRISTokens.aquaTint)
                    }
                }
            }
        }
    }

    private var draftsCard: some View {
        dashboardCard(title: "Drafts", count: allDrafts.count, icon: "pencil.and.scribble", color: IRISTokens.irisAccent) {
            let groups = Dictionary(grouping: allDrafts, by: \.status)
            let breakdown = groups.map { ($0.key, $0.value.count) }
                .sorted { $0.1 > $1.1 }
            VStack(alignment: .leading, spacing: 4) {
                if breakdown.isEmpty {
                    Text("Aucun draft.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                } else {
                    ForEach(breakdown, id: \.0) { item in
                        statBar(label: item.0, value: item.1, total: allDrafts.count, color: statusColor(item.0))
                    }
                }
            }
        }
    }

    private var auditsCard: some View {
        dashboardCard(title: "Audits", count: allAudits.count, icon: "checkmark.shield", color: .green) {
            let groups = Dictionary(grouping: allAudits, by: \.verdict)
            let breakdown = ["GREEN", "YELLOW", "RED"].map { verdict in
                (verdict, groups[verdict]?.count ?? 0)
            }
            VStack(alignment: .leading, spacing: 4) {
                if allAudits.isEmpty {
                    Text("Aucun audit. Sélectionne Auditor (Cmd+5) → choisis projet.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                } else {
                    ForEach(breakdown, id: \.0) { item in
                        statBar(label: item.0, value: item.1, total: allAudits.count, color: verdictColor(item.0))
                    }
                }
            }
        }
    }

    private var costCard: some View {
        dashboardCard(title: "Cost session", count: 0, icon: "dollarsign.circle", color: IRISTokens.goldAccent) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Cumulé")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("$\(String(format: "%.4f", appState.sessionCostUSD))")
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        .foregroundStyle(appState.sessionCostUSD > 0.5 ? IRISTokens.goldAccent : .primary)
                }
                HStack {
                    Text("API key Anthropic")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: appState.hasAnthropicKey ? "checkmark.circle.fill" : "exclamationmark.triangle")
                        .font(.system(size: 11))
                        .foregroundStyle(appState.hasAnthropicKey ? .green : IRISTokens.goldAccent)
                }
                if !appState.hasAnthropicKey {
                    Text("Mode mock — ajoute clé via Cmd+,")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(IRISTokens.goldAccent)
                }
            }
        }
    }

    private var portfolioCard: some View {
        dashboardCard(title: "Portfolio", count: allProjects.count, icon: "map", color: IRISTokens.aquaTint) {
            let groups = Dictionary(grouping: allProjects, by: \.status)
            let breakdown = ["active", "tiede", "dormant", "archived"].map { status in
                (status, groups[status]?.count ?? 0)
            }
            VStack(alignment: .leading, spacing: 4) {
                if allProjects.isEmpty {
                    Text("Cartographer démarre dans 5s — refresh via Cmd+Shift+R.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                } else {
                    ForEach(breakdown.filter { $0.1 > 0 }, id: \.0) { item in
                        statBar(label: item.0, value: item.1, total: allProjects.count, color: statusColor(item.0))
                    }
                }
            }
        }
    }

    // MARK: — Recent activity section

    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: IRISTokens.spacing8) {
            Text("ACTIVITÉ RÉCENTE")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
                .tracking(1.4)

            ForEach(Array(allActions.prefix(5))) { action in
                actionRow(action)
            }

            if allActions.isEmpty {
                Text("Aucune action enregistrée pour l'instant.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func actionRow(_ action: ActionLog) -> some View {
        HStack(spacing: IRISTokens.spacing8) {
            Image(systemName: action.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(action.success ? .green : .red)
            Text(action.agentId)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(IRISTokens.irisAccent)
            Text(action.actionType)
                .font(.system(size: 11))
            Spacer()
            if action.executedByUserApproval {
                Image(systemName: "person.fill.checkmark")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            Text(action.executedAt, format: .dateTime.hour().minute().second())
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, IRISTokens.spacing8)
        .background(RoundedRectangle(cornerRadius: IRISTokens.cornerRadiusSmall).fill(.thinMaterial))
    }

    // MARK: — Helpers

    @ViewBuilder
    private func dashboardCard<Content: View>(
        title: String,
        count: Int,
        icon: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: IRISTokens.spacing8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(color)
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(.secondary)
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 18, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)
                }
            }
            Divider().opacity(0.3)
            content()
        }
        .padding(IRISTokens.spacing16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: IRISTokens.cornerRadiusMedium).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: IRISTokens.cornerRadiusMedium).strokeBorder(color.opacity(0.15), lineWidth: 0.5))
    }

    private func statBar(label: String, value: Int, total: Int, color: Color) -> some View {
        let ratio = total > 0 ? CGFloat(value) / CGFloat(total) : 0
        return HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10, design: .monospaced))
                .frame(width: 80, alignment: .leading)
                .foregroundStyle(.primary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(color.opacity(0.12))
                    RoundedRectangle(cornerRadius: 2).fill(color.opacity(0.7))
                        .frame(width: max(2, geo.size.width * ratio))
                }
            }
            .frame(height: 6)
            Text("\(value)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "sent", "active": return .green
        case "approved": return IRISTokens.aquaTint
        case "rejected", "failed": return .red
        case "tiede", "pending": return IRISTokens.goldAccent
        case "dormant", "archived": return .secondary
        default: return IRISTokens.irisAccent
        }
    }

    private func verdictColor(_ verdict: String) -> Color {
        switch verdict {
        case "GREEN": return .green
        case "YELLOW": return IRISTokens.goldAccent
        case "RED": return .red
        default: return .secondary
        }
    }
}

#Preview {
    DashboardView()
        .environment(IRISAppState())
        .frame(width: 800, height: 600)
}

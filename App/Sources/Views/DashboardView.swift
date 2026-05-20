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

    // v1.92 — Dernier briefing Advisor (EventLog kind=agentResponse fromAgent=advisor)
    @Query(
        filter: #Predicate<EventLog> { $0.kind == "agentResponse" && $0.fromAgent == "advisor" },
        sort: \EventLog.timestamp,
        order: .reverse
    ) private var advisorBriefings: [EventLog]

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
                    // v1.71 — cards clickables qui navigent vers la vue dédiée
                    memoryCard
                        .contentShape(Rectangle())
                        .onTapGesture { appState.selection = .system(.memory) }
                        .help("Cliquer → System > Memory")
                    signalsCard
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // Naviguer vers Logs avec un hint sur signalEmitted (filtre user-applied)
                            appState.selection = .system(.logs)
                        }
                        .help("Cliquer → System > Logs (filter manuel kind=signalEmitted)")
                    draftsCard
                        .contentShape(Rectangle())
                        .onTapGesture { appState.selection = .agent(.quill) }
                        .help("Cliquer → Quill (drafts dans Inspector)")
                    auditsCard
                        .contentShape(Rectangle())
                        .onTapGesture { appState.selection = .agent(.auditor) }
                        .help("Cliquer → Auditor")
                    costCard
                        .contentShape(Rectangle())
                        .onTapGesture { NSApplication.openSettings() }
                        .help("Cliquer → Settings (cost report dans backup)")
                    portfolioCard
                        .contentShape(Rectangle())
                        .onTapGesture { appState.selection = .agent(.cartographer) }
                        .help("Cliquer → Cartographer")
                }

                // v1.92 — Snippet du dernier briefing Advisor
                if let latest = advisorBriefings.first {
                    advisorBriefingCard(latest)
                }

                recentActivitySection

                Spacer()
            }
            .padding(IRISTokens.spacing24)
        }
    }

    // v1.92 — Card snippet briefing Advisor (top markdown rendering)
    private func advisorBriefingCard(_ event: EventLog) -> some View {
        let content = Self.extractContent(event.payloadJSON)
        // Take les 400 premiers chars (≈ ☀ header + 1-2 priorités)
        let snippet = String(content.prefix(400))
        return VStack(alignment: .leading, spacing: IRISTokens.spacing8) {
            HStack {
                Image(systemName: "sunrise.fill")
                    .foregroundStyle(IRISTokens.goldAccent)
                Text("LATEST ADVISOR BRIEFING")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(event.timestamp, format: .dateTime.day().month(.abbreviated).hour().minute())
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                Button {
                    Task { await Advisor.shared.runBriefing(kind: .manual) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                        .foregroundStyle(IRISTokens.goldAccent)
                }
                .buttonStyle(.plain)
                .help("Re-générer le briefing (Brief now)")
            }
            Divider().opacity(0.3)
            if let attr = try? AttributedString(markdown: snippet, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                Text(attr)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(snippet)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if content.count > 400 {
                Text("… [+\(content.count - 400) chars · open Advisor pour briefing complet]")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(IRISTokens.spacing16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: IRISTokens.cornerRadiusMedium).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: IRISTokens.cornerRadiusMedium).strokeBorder(IRISTokens.goldAccent.opacity(0.2), lineWidth: 0.5))
    }

    private static func extractContent(_ payloadJSON: String) -> String {
        guard let data = payloadJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? String else { return "(no content)" }
        return content
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
                // v1.37 — refresh Cartographer manual
                Button {
                    Task { await Cartographer.shared.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .help("Refresh Cartographer (re-scan ~/Developer + gh repo list)")
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
        // v1.75 — Sparkline 24 buckets horaires
        let buckets = Self.hourlyBuckets(signals: signals24h)
        // v1.95 — Breakdown par importance
        let importanceBreakdown = Self.importanceBreakdown(signals: signals24h)
        return dashboardCard(title: "Signals 24h", count: signals24h.count, icon: "eye.circle", color: IRISTokens.aquaTint) {
            let groups = Dictionary(grouping: signals24h, by: \.source)
            let breakdown = groups.map { ($0.key, $0.value.count) }
                .sorted { $0.1 > $1.1 }
            VStack(alignment: .leading, spacing: 6) {
                if breakdown.isEmpty {
                    Text("Aucun signal sur 24h.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                } else {
                    sparkline(buckets: buckets)
                        .frame(height: 32)
                    // v1.95 — Importance stack mini-bar (segments colorés)
                    importanceStackBar(importanceBreakdown)
                        .frame(height: 6)
                    ForEach(breakdown.prefix(5), id: \.0) { item in
                        statBar(label: item.0, value: item.1, total: signals24h.count, color: IRISTokens.aquaTint)
                    }
                }
            }
        }
    }

    // v1.95 — Compteurs par importance (1..5)
    private static func importanceBreakdown(signals: [Signal]) -> [(Int, Int)] {
        var counts: [Int: Int] = [:]
        for s in signals {
            counts[s.importance, default: 0] += 1
        }
        return (1...5).map { ($0, counts[$0] ?? 0) }
    }

    private func importanceColor(_ importance: Int) -> Color {
        switch importance {
        case 5: return .red
        case 4: return IRISTokens.goldAccent
        case 3: return IRISTokens.irisAccent
        case 2: return IRISTokens.aquaTint
        default: return .secondary.opacity(0.7)
        }
    }

    private func importanceStackBar(_ breakdown: [(Int, Int)]) -> some View {
        let total = max(1, breakdown.reduce(0) { $0 + $1.1 })
        return GeometryReader { geo in
            HStack(spacing: 1) {
                ForEach(breakdown, id: \.0) { item in
                    let ratio = CGFloat(item.1) / CGFloat(total)
                    Rectangle()
                        .fill(importanceColor(item.0))
                        .frame(width: max(0, geo.size.width * ratio))
                        .help("importance \(item.0): \(item.1)")
                }
            }
        }
    }

    // v1.75 — Sparkline helpers
    private static func hourlyBuckets(signals: [Signal]) -> [Int] {
        var buckets = Array(repeating: 0, count: 24)
        let now = Date()
        for s in signals {
            let elapsedHours = Int(now.timeIntervalSince(s.emittedAt) / 3600)
            guard elapsedHours >= 0 && elapsedHours < 24 else { continue }
            let bucketIdx = 23 - elapsedHours  // 0 = il y a 24h, 23 = maintenant
            buckets[bucketIdx] += 1
        }
        return buckets
    }

    private func sparkline(buckets: [Int]) -> some View {
        let maxVal = max(1, buckets.max() ?? 1)
        return GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 1) {
                ForEach(Array(buckets.enumerated()), id: \.offset) { _, count in
                    let ratio = CGFloat(count) / CGFloat(maxVal)
                    Rectangle()
                        .fill(IRISTokens.aquaTint.opacity(count > 0 ? 0.7 : 0.15))
                        .frame(height: max(2, geo.size.height * ratio))
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

                // v1.24 — Breakdown par modèle
                if !appState.costByModel.isEmpty {
                    Divider().padding(.vertical, 2)
                    ForEach(appState.costByModel.sorted(by: { $0.value > $1.value }), id: \.key) { model, amount in
                        HStack {
                            Text(modelShortName(model))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(modelColor(model))
                            Spacer()
                            Text("$\(String(format: "%.5f", amount))")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Divider().padding(.vertical, 2)
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

    private func modelShortName(_ raw: String) -> String {
        if raw.contains("opus") { return "Opus 4.7" }
        if raw.contains("sonnet") { return "Sonnet 4.6" }
        if raw.contains("haiku") { return "Haiku 4.5" }
        if raw.contains("gemini") { return "Gemini Flash" }
        return raw
    }

    private func modelColor(_ raw: String) -> Color {
        if raw.contains("opus") { return IRISTokens.irisAccent }
        if raw.contains("sonnet") { return IRISTokens.aquaTint }
        if raw.contains("haiku") { return .secondary }
        return .secondary
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

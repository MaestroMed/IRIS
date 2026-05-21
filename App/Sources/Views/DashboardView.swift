import SwiftUI
import SwiftData

// IRIS v1.10 — DashboardView : vue globale quand aucun agent sélectionné.
// 4 cards stats Liquid Glass : Memory by type, Signals 24h by source, Drafts by status, Audits by verdict + Cost session.
/// v1.170 — Top dispatched agents past 24h card.
/// v1.173 — Alerts last 1h card (failures + critical signals).
/// v1.180 — Weekly events trend mini-sparkline card (7d bar chart).
/// v1.186 — Memory growth past 7d mini stat card (gold).
/// v1.195 — System status banner (Witness · Sentinel · MCP) at top of dashboard.
/// v1.201 — Milestone v1.200 celebration card (auto-hides at v1.206).
/// v1.210 — Recent activity feed card (last 5 events).
/// v1.216 — Avg response time by agent card (dispatched→response delay).
/// v1.222 — Auditor cost today card (total + per-model breakdown).
/// v1.229 — Live "+N past 5min" event count badge (aqua circle pulse hint).
/// v1.234 — Failure rate past 7d card (fails/total + % color-coded green/gold/red).
/// v1.240 — Hourly avg + peak hour past 24h card (aqua + gold).
/// v1.250 — Today's signals importance stacked bar (critical/high/normal/low).
/// v1.255 — Cost stack bar inside costTodayCard (per-model colored).

struct DashboardView: View {
    @Environment(IRISAppState.self) private var appState

    @Query private var allMemories: [Memory]
    @Query(sort: \Signal.emittedAt, order: .reverse) private var allSignals: [Signal]
    @Query private var allDrafts: [Draft]
    @Query private var allAudits: [AuditReport]
    @Query private var allProjects: [ProjectRecord]
    @Query(sort: \ActionLog.executedAt, order: .reverse) private var allActions: [ActionLog]

    // v1.173 — All events pour alerts last 1h (agentFailure count)
    @Query private var allEvents: [EventLog]

    // v1.151 — agentDispatched events pour dispatch frequency analytics
    @Query(
        filter: #Predicate<EventLog> { $0.kind == "agentDispatched" },
        sort: \EventLog.timestamp,
        order: .reverse
    ) private var dispatchedEvents: [EventLog]

    // v1.92 — Dernier briefing Advisor (EventLog kind=agentResponse fromAgent=advisor)
    @Query(
        filter: #Predicate<EventLog> { $0.kind == "agentResponse" && $0.fromAgent == "advisor" },
        sort: \EventLog.timestamp,
        order: .reverse
    ) private var advisorBriefings: [EventLog]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: IRISTokens.spacing24) {
                // v1.195 — System status banner (Witness · Sentinel · MCP)
                systemStatusBanner

                // v1.201 — Milestone v1.200 celebration (auto-hides at v1.206)
                if isInMilestoneWindow {
                    milestoneCard
                }

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

                // v1.173 — Alerts last 1h (failures + critical signals)
                alertsCard

                // v1.250 — Today's signals importance stacked bar (critical/high/normal/low)
                signalsImportanceCard

                // v1.234 — Failure rate past 7d (per-agent fails/total + %)
                failureRatesCard

                // v1.222 — Auditor cost today (total + per-model breakdown)
                costTodayCard

                // v1.102 — Currently focused project (latest Witness signal with project scope)
                if let focus = latestFocusedSignal {
                    focusedProjectCard(focus)
                }

                // v1.120 — MCP sources actives banner (Phase B closure)
                mcpSourcesBanner

                // v1.135 — 5 phases real status banner (santé exocortex)
                phasesRealStatusBanner

                // v1.160 — Agent activity dots banner (10 agents live status)
                agentActivityBanner

                // v1.138 — Quick actions row (most-used)
                quickActionsRow

                // v1.151 — Dispatch frequency 24h (par agent target)
                dispatchFrequencyBanner

                // v1.170 — Top dispatched agents past 24h (top 3 podium)
                topAgentsCard

                // v1.210 — Recent activity feed (last 5 events)
                recentActivityCard

                // v1.216 — Avg response time by agent (dispatched→response delay)
                avgResponseTimeCard

                // v1.240 — Hourly avg + peak hour past 24h
                hourlyAvgCard

                // v1.180 — Weekly events trend (7d bar chart sparkline)
                weeklyTrendCard

                // v1.186 — Memory growth past 7d (gold bar chart)
                memoryGrowthCard

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

    // v1.151 — Dispatch frequency 24h (counts par agent target depuis EventLog)
    @ViewBuilder
    private var dispatchFrequencyBanner: some View {
        let oneDayAgo = Date().addingTimeInterval(-86400)
        let recent = dispatchedEvents.filter { $0.timestamp > oneDayAgo }
        let byTarget = Dictionary(grouping: recent, by: { $0.toAgent ?? "?" })
            .map { ($0.key, $0.value.count) }
            .sorted { $0.1 > $1.1 }
        if !byTarget.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundStyle(IRISTokens.irisAccent)
                        .font(.system(size: 12))
                    Text("DISPATCHES 24H (\(recent.count))")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                HStack(spacing: 6) {
                    ForEach(byTarget.prefix(8), id: \.0) { item in
                        HStack(spacing: 3) {
                            Text(item.0)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                            Text("\(item.1)")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(IRISTokens.irisAccent)
                        }
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(IRISTokens.irisAccent.opacity(0.10))
                        .clipShape(Capsule())
                    }
                }
            }
            .padding(IRISTokens.spacing16)
            .background(RoundedRectangle(cornerRadius: IRISTokens.cornerRadiusMedium).fill(.regularMaterial))
            .overlay(RoundedRectangle(cornerRadius: IRISTokens.cornerRadiusMedium).strokeBorder(IRISTokens.irisAccent.opacity(0.15), lineWidth: 0.5))
        }
    }

    // v1.170 — Top dispatched agents past 24h (top 3, horizontal mini-bars)
    private var topDispatchedAgents24h: [(agent: String, count: Int)] {
        let cutoff = Date().addingTimeInterval(-86400)
        let recent = dispatchedEvents.filter { $0.timestamp >= cutoff }
        let grouped = Dictionary(grouping: recent, by: { $0.toAgent ?? "(unknown)" })
            .map { (agent: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
        return Array(grouped.prefix(3))
    }

    private var topAgentsCard: some View {
        let top = topDispatchedAgents24h
        let maxCount = max(1, top.first?.count ?? 1)
        return VStack(alignment: .leading, spacing: 6) {
            Text("DISPATCHES PAST 24H")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(.secondary)
            if top.isEmpty {
                Text("Aucun dispatch dans les 24h.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(top.enumerated()), id: \.offset) { idx, item in
                    HStack(spacing: 6) {
                        Text("#\(idx + 1)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text(item.agent)
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text("\(item.count)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(IRISTokens.irisAccent)
                        Rectangle()
                            .fill(IRISTokens.irisAccent.opacity(0.3 + Double(item.count) / Double(maxCount) * 0.7))
                            .frame(width: max(20, CGFloat(item.count) / CGFloat(maxCount) * 80), height: 4)
                            .cornerRadius(2)
                    }
                }
            }
        }
        .padding(IRISTokens.spacing16)
        .background(RoundedRectangle(cornerRadius: IRISTokens.cornerRadiusSmall).fill(.thinMaterial))
    }

    // v1.210 — Last 5 events (allEvents sorted desc by timestamp via @Query)
    private var recentEvents: [EventLog] {
        Array(allEvents.prefix(5))
    }

    private var recentActivityCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("RECENT ACTIVITY")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(.secondary)
            if recentEvents.isEmpty {
                Text("Aucune activité.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(recentEvents) { event in
                    HStack(spacing: 6) {
                        Text(event.timestamp, format: .dateTime.hour().minute().second())
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .leading)
                        Text(event.kind)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.primary.opacity(0.85))
                            .lineLimit(1)
                        if let to = event.toAgent {
                            Text("→ \(to)")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(IRISTokens.aquaTint.opacity(0.7))
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                }
            }
        }
        .padding(IRISTokens.spacing16)
        .background(RoundedRectangle(cornerRadius: IRISTokens.cornerRadiusSmall).fill(.thinMaterial))
    }

    // v1.216 — Avg response time by agent (dispatched→response delay in seconds)
    private var avgResponseTimeByAgent: [(agent: String, avgSeconds: Double, count: Int)] {
        var dispatchedByCorrelation: [UUID: EventLog] = [:]
        for event in allEvents where event.kind == "agentDispatched" {
            if let cid = event.correlationId { dispatchedByCorrelation[cid] = event }
        }
        var pairs: [(agent: String, delay: TimeInterval)] = []
        for event in allEvents where event.kind == "agentResponse" {
            if let cid = event.correlationId, let dispatched = dispatchedByCorrelation[cid] {
                let agent = dispatched.toAgent ?? "(unknown)"
                let delay = event.timestamp.timeIntervalSince(dispatched.timestamp)
                if delay > 0 { pairs.append((agent: agent, delay: delay)) }
            }
        }
        let grouped = Dictionary(grouping: pairs, by: { $0.agent })
        let summary = grouped.map { (agent, items) -> (agent: String, avgSeconds: Double, count: Int) in
            let avg = items.reduce(0.0) { $0 + $1.delay } / Double(items.count)
            return (agent: agent, avgSeconds: avg, count: items.count)
        }
        .sorted { $0.count > $1.count }
        return Array(summary.prefix(5))
    }

    private var avgResponseTimeCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("AVG RESPONSE TIME")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(.secondary)
            if avgResponseTimeByAgent.isEmpty {
                Text("Pas assez de paires dispatched→response.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(avgResponseTimeByAgent.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 6) {
                        Text(item.agent)
                            .font(.system(size: 11, weight: .medium))
                        Spacer()
                        Text(String(format: "%.2fs", item.avgSeconds))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(IRISTokens.aquaTint)
                        Text("(\(item.count))")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary.opacity(0.6))
                    }
                }
            }
        }
        .padding(IRISTokens.spacing16)
        .background(RoundedRectangle(cornerRadius: IRISTokens.cornerRadiusSmall).fill(.thinMaterial))
    }

    // v1.180 — Events past 7 days (oldest first, today last)
    private var eventsLast7Days: [(day: Date, count: Int)] {
        let cal = Calendar.current
        let entries: [(day: Date, count: Int)] = (0..<7).map { i in
            let day = cal.startOfDay(for: Date().addingTimeInterval(-Double(i) * 86400))
            let count = allEvents.filter { cal.isDate($0.timestamp, inSameDayAs: day) }.count
            return (day: day, count: count)
        }
        return entries.reversed()
    }

    private var weeklyTrendCard: some View {
        let days = eventsLast7Days
        let total = days.reduce(0) { $0 + $1.count }
        let maxCount = max(days.map(\.count).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 6) {
            Text("EVENTS PAST 7 DAYS")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(.secondary)
            Text("\(total) total")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(IRISTokens.aquaTint)
            GeometryReader { _ in
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(Array(days.enumerated()), id: \.offset) { _, item in
                        VStack(spacing: 2) {
                            Rectangle()
                                .fill(IRISTokens.aquaTint.opacity(0.3 + (Double(item.count) / Double(maxCount)) * 0.7))
                                .frame(height: max(4, CGFloat(item.count) / CGFloat(maxCount) * 50))
                            Text(dayLabel(item.day))
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(height: 60)
        }
        .padding(IRISTokens.spacing16)
        .background(RoundedRectangle(cornerRadius: IRISTokens.cornerRadiusSmall).fill(.thinMaterial))
    }

    private func dayLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        return date.formatted(.dateTime.weekday(.abbreviated))
    }

    // v1.186 — Memories past 7 days (oldest first, today last)
    private var memoriesLast7Days: [(day: Date, count: Int)] {
        let cal = Calendar.current
        let entries: [(day: Date, count: Int)] = (0..<7).map { i in
            let day = cal.startOfDay(for: Date().addingTimeInterval(-Double(i) * 86400))
            let count = allMemories.filter { cal.isDate($0.createdAt, inSameDayAs: day) }.count
            return (day: day, count: count)
        }
        return entries.reversed()
    }

    private var memoryGrowthCard: some View {
        let days = memoriesLast7Days
        let total = days.reduce(0) { $0 + $1.count }
        let maxCount = max(days.map(\.count).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 6) {
            Text("MEMORIES PAST 7 DAYS")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(.secondary)
            Text("\(total) new")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(IRISTokens.goldAccent)
            GeometryReader { _ in
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(Array(days.enumerated()), id: \.offset) { _, item in
                        VStack(spacing: 2) {
                            Rectangle()
                                .fill(IRISTokens.goldAccent.opacity(0.3 + (Double(item.count) / Double(maxCount)) * 0.7))
                                .frame(height: max(4, CGFloat(item.count) / CGFloat(maxCount) * 50))
                            Text(dayLabel(item.day))
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(height: 60)
        }
        .padding(IRISTokens.spacing16)
        .background(RoundedRectangle(cornerRadius: IRISTokens.cornerRadiusSmall).fill(.thinMaterial))
    }

    // v1.173 — Alerts last 1h (agentFailure events + critical/high importance signals)
    private var agentFailures1h: Int {
        let cutoff = Date().addingTimeInterval(-3600)
        return allEvents.filter { $0.kind == "agentFailure" && $0.timestamp >= cutoff }.count
    }

    private var criticalSignals1h: Int {
        let cutoff = Date().addingTimeInterval(-3600)
        // Model uses Int importance (5=critical, 4=high)
        return allSignals.filter { ($0.importance >= 4) && $0.emittedAt >= cutoff }.count
    }

    private var alertsCard: some View {
        let totalAlerts = agentFailures1h + criticalSignals1h
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(totalAlerts > 0 ? .red : .secondary)
                Text("ALERTS LAST 1H")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(.secondary)
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(agentFailures1h)")
                        .font(.system(size: 22, weight: .light, design: .serif))
                        .foregroundStyle(agentFailures1h > 0 ? .red : .secondary)
                    Text("FAILURES")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(criticalSignals1h)")
                        .font(.system(size: 22, weight: .light, design: .serif))
                        .foregroundStyle(criticalSignals1h > 0 ? IRISTokens.goldAccent : .secondary)
                    Text("CRITICAL")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            if totalAlerts == 0 {
                Text("Tout va bien.")
                    .font(.system(size: 10))
                    .foregroundStyle(.green)
                    .opacity(0.7)
            }
        }
        .padding(IRISTokens.spacing16)
        .background(RoundedRectangle(cornerRadius: IRISTokens.cornerRadiusSmall).fill(.thinMaterial))
        .overlay(RoundedRectangle(cornerRadius: IRISTokens.cornerRadiusSmall).strokeBorder(totalAlerts > 0 ? Color.red.opacity(0.6) : Color.clear, lineWidth: 1.5))
    }

    // v1.250 — Today's signals importance breakdown (calendar day, critical/high/normal/low)
    private var todaysSignalImportance: (critical: Int, high: Int, normal: Int, low: Int, total: Int) {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let todays = allSignals.filter { $0.emittedAt >= startOfDay }
        var critical = 0, high = 0, normal = 0, low = 0
        for s in todays {
            switch s.importance {
            case 5: critical += 1
            case 4: high += 1
            case 3: normal += 1
            default: low += 1
            }
        }
        return (critical, high, normal, low, critical + high + normal + low)
    }

    private var signalsImportanceCard: some View {
        let t = todaysSignalImportance
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("SIGNALS TODAY")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(t.total) total")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(IRISTokens.aquaTint)
            }
            if t.total == 0 {
                Text("Aucun signal aujourd'hui.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                GeometryReader { proxy in
                    HStack(spacing: 1) {
                        if t.critical > 0 {
                            Rectangle().fill(.red)
                                .frame(width: proxy.size.width * CGFloat(t.critical) / CGFloat(max(1, t.total)))
                        }
                        if t.high > 0 {
                            Rectangle().fill(IRISTokens.goldAccent)
                                .frame(width: proxy.size.width * CGFloat(t.high) / CGFloat(max(1, t.total)))
                        }
                        if t.normal > 0 {
                            Rectangle().fill(IRISTokens.aquaTint)
                                .frame(width: proxy.size.width * CGFloat(t.normal) / CGFloat(max(1, t.total)))
                        }
                        if t.low > 0 {
                            Rectangle().fill(Color.secondary)
                                .frame(width: proxy.size.width * CGFloat(t.low) / CGFloat(max(1, t.total)))
                        }
                    }
                }
                .frame(height: 6)
                // Mini legend
                HStack(spacing: 8) {
                    legendItem(.red, "Critical", t.critical)
                    legendItem(IRISTokens.goldAccent, "High", t.high)
                    legendItem(IRISTokens.aquaTint, "Normal", t.normal)
                    legendItem(.secondary, "Low", t.low)
                }
            }
        }
        .padding(IRISTokens.spacing16)
        .background(RoundedRectangle(cornerRadius: IRISTokens.cornerRadiusSmall).fill(.thinMaterial))
    }

    private func legendItem(_ color: Color, _ label: String, _ count: Int) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text("\(label) \(count)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    // v1.240 — Hourly avg + peak past 24h (24 sliding hour buckets ending at now)
    private var hourlyAvg24h: (avg: Double, max: Int) {
        let now = Date()
        var counts: [Int] = []
        counts.reserveCapacity(24)
        for i in 0..<24 {
            let bucketEnd = now.addingTimeInterval(-Double(i) * 3600)
            let bucketStart = bucketEnd.addingTimeInterval(-3600)
            let count = allEvents.filter { $0.timestamp >= bucketStart && $0.timestamp < bucketEnd }.count
            counts.append(count)
        }
        let sum = counts.reduce(0, +)
        let avg = Double(sum) / 24.0
        let peak = counts.max() ?? 0
        return (avg: avg, max: peak)
    }

    private var hourlyAvgCard: some View {
        let stats = hourlyAvg24h
        return HStack(spacing: IRISTokens.spacing24) {
            VStack(alignment: .leading, spacing: 2) {
                Text("HOURLY AVG")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.1f", stats.avg))
                        .font(.system(size: 22, weight: .light, design: .serif))
                        .foregroundStyle(IRISTokens.aquaTint)
                    Text("ev/hour")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("PEAK HOUR")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(stats.max)")
                        .font(.system(size: 22, weight: .light, design: .serif))
                        .foregroundStyle(IRISTokens.goldAccent)
                    Text("ev")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(IRISTokens.spacing16)
        .background(RoundedRectangle(cornerRadius: IRISTokens.cornerRadiusSmall).fill(.thinMaterial))
    }

    // v1.234 — Failure rate past 7d (per-agent: fails / dispatches → %)
    private var failureRatesPast7d: [(agent: String, fails: Int, total: Int, rate: Double)] {
        let cutoff = Date().addingTimeInterval(-7 * 86400)
        let recent = allEvents.filter { $0.timestamp >= cutoff }
        let dispatchCounts = Dictionary(grouping: recent.filter { $0.kind == "agentDispatched" }, by: { $0.toAgent ?? "(unknown)" })
            .mapValues { $0.count }
        let failureCounts = Dictionary(grouping: recent.filter { $0.kind == "agentFailure" }, by: { $0.fromAgent ?? "(unknown)" })
            .mapValues { $0.count }
        let summary: [(agent: String, fails: Int, total: Int, rate: Double)] = dispatchCounts.compactMap { (agent, total) in
            guard total > 0 else { return nil }
            let fails = failureCounts[agent] ?? 0
            let rate = Double(fails) / Double(total) * 100
            return (agent: agent, fails: fails, total: total, rate: rate)
        }
        .sorted { lhs, rhs in
            if lhs.rate != rhs.rate { return lhs.rate > rhs.rate }
            return lhs.fails > rhs.fails
        }
        return Array(summary.prefix(5))
    }

    private var failureRatesCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FAILURE RATE PAST 7D")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(.secondary)
            if failureRatesPast7d.isEmpty {
                Text("Aucun dispatch/failure dans les 7 derniers jours.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(failureRatesPast7d.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 8) {
                        Text(item.agent)
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: 80, alignment: .leading)
                        Spacer()
                        Text("\(item.fails)/\(item.total)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.1f%%", item.rate))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(item.rate > 10 ? .red : (item.rate > 5 ? IRISTokens.goldAccent : .green))
                    }
                }
            }
        }
        .padding(IRISTokens.spacing16)
        .background(RoundedRectangle(cornerRadius: IRISTokens.cornerRadiusSmall).fill(.thinMaterial))
    }

    // v1.222 — Auditor cost today (AuditReport.costUSD summed for today)
    private var auditCostToday: Double {
        let start = Calendar.current.startOfDay(for: Date())
        return allAudits.filter { $0.createdAt >= start }.reduce(0.0) { $0 + $1.costUSD }
    }

    private var costTodayBreakdown: [(model: String, cost: Double)] {
        let start = Calendar.current.startOfDay(for: Date())
        let today = allAudits.filter { $0.createdAt >= start }
        let grouped = Dictionary(grouping: today, by: { $0.modelUsed })
        return grouped.map { (model: $0.key, cost: $0.value.reduce(0.0) { $0 + $1.costUSD }) }
            .sorted { $0.cost > $1.cost }
    }

    private var costTodayCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("AUDITOR COST TODAY")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "$%.3f", auditCostToday))
                    .font(.system(size: 13, weight: .light, design: .serif))
                    .foregroundStyle(IRISTokens.goldAccent)
            }
            if costTodayBreakdown.isEmpty {
                Text("Aucun audit aujourd'hui.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                // v1.255 — Stacked bar per-model cost share
                let total = costTodayBreakdown.map(\.cost).reduce(0, +)
                if total > 0 {
                    GeometryReader { proxy in
                        HStack(spacing: 1) {
                            ForEach(Array(costTodayBreakdown.enumerated()), id: \.offset) { _, item in
                                Rectangle()
                                    .fill(modelColor(item.model))
                                    .frame(width: proxy.size.width * CGFloat(item.cost / total))
                            }
                        }
                    }
                    .frame(height: 6)
                    .cornerRadius(2)
                }
                ForEach(Array(costTodayBreakdown.enumerated()), id: \.offset) { _, item in
                    HStack {
                        Text(item.model)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer()
                        Text(String(format: "$%.3f", item.cost))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(IRISTokens.aquaTint)
                    }
                }
            }
        }
        .padding(IRISTokens.spacing16)
        .background(RoundedRectangle(cornerRadius: IRISTokens.cornerRadiusSmall).fill(.thinMaterial))
    }

    // v1.160 — Agent activity dots banner (10 agents avec status dot live)
    private var agentActivityBanner: some View {
        let agents = AgentID.allCases.filter { $0 != .system }
        return VStack(alignment: .leading, spacing: IRISTokens.spacing8) {
            HStack {
                Image(systemName: "circle.hexagongrid.fill")
                    .foregroundStyle(IRISTokens.irisAccent)
                    .font(.system(size: 12))
                Text("AGENTS LIVE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            HStack(spacing: 6) {
                ForEach(agents) { agent in
                    let status = appState.agentStatus(agent)
                    HStack(spacing: 4) {
                        Image(systemName: agent.descriptor.symbol)
                            .font(.system(size: 10))
                            .foregroundStyle(.primary)
                        Text(agent.descriptor.displayName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.primary)
                        Circle()
                            .fill(status.dotColor)
                            .frame(width: 6, height: 6)
                    }
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(IRISTokens.irisAccent.opacity(0.08))
                    .clipShape(Capsule())
                    .contentShape(Capsule())
                    .onTapGesture { appState.selection = .agent(agent) }
                    .help("\(agent.descriptor.displayName) — \(status.rawValue)")
                }
                Spacer()
            }
        }
        .padding(IRISTokens.spacing16)
        .background(RoundedRectangle(cornerRadius: IRISTokens.cornerRadiusMedium).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: IRISTokens.cornerRadiusMedium).strokeBorder(IRISTokens.irisAccent.opacity(0.15), lineWidth: 0.5))
    }

    // v1.138 — Quick actions row (raccourcis aux actions les plus fréquentes)
    private var quickActionsRow: some View {
        HStack(spacing: IRISTokens.spacing8) {
            quickActionButton(icon: "sunrise.fill", label: "Brief", color: IRISTokens.goldAccent) {
                Task { await Advisor.shared.runBriefing(kind: .manual) }
            }
            quickActionButton(icon: "arrow.clockwise", label: "Refresh map", color: IRISTokens.aquaTint) {
                Task { await Cartographer.shared.refresh() }
            }
            quickActionButton(icon: "eye.square", label: "Vision now", color: IRISTokens.irisAccent) {
                Task { await Witness.shared.captureWithVision() }
            }
            quickActionButton(icon: "books.vertical", label: "Memory", color: IRISTokens.aquaTint) {
                appState.selection = .system(.memory)
            }
            quickActionButton(icon: "list.bullet.rectangle", label: "Logs", color: .secondary) {
                appState.selection = .system(.logs)
            }
            Spacer()
        }
    }

    private func quickActionButton(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
            .foregroundStyle(color)
        }
        .buttonStyle(.plain)
    }

    // v1.135 — Banner "5 phases real" status (Witness Vision / MCP Real / Auditor Real / Builder Real / Dispatch)
    private var phasesRealStatusBanner: some View {
        let visionConfigured = appState.hasAnthropicKey
        let mcpActiveCount = Sentinel.knownSources.filter { Sentinel.isMCPBackend(for: $0) }.count
        let auditorMonthly = Auditor.monthlyAutoEnabled
        let dispatchAvailable = true  // always — heuristic

        let checks: [(label: String, ok: Bool, hint: String)] = [
            ("A · Witness Vision", visionConfigured, visionConfigured ? "API key OK · Inspector eye.square pour capture" : "Pas d'API key (Settings)"),
            ("B · MCP Real", mcpActiveCount > 0, mcpActiveCount > 0 ? "\(mcpActiveCount) source(s) actif" : "Configure backend source dans Settings"),
            ("C · Auditor Real", true, "Lit fichiers réels · monthly auto-audit \(auditorMonthly ? "ON" : "OFF")"),
            ("D · Builder Real", true, "Scaffold lit SKILL.md · git init auto"),
            ("E · Dispatch", dispatchAvailable, "Tape `?` pour patterns dispo")
        ]

        return VStack(alignment: .leading, spacing: IRISTokens.spacing8) {
            HStack {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(IRISTokens.irisAccent)
                    .font(.system(size: 14))
                Text("EXOCORTEX 5 PHASES · v1.\(IRISRuntimeInfo.appVersion.split(separator: ".").last ?? "?")")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(checks.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 6) {
                        Image(systemName: item.ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(item.ok ? .green : IRISTokens.goldAccent)
                        Text(item.label)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(item.hint)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
        }
        .padding(IRISTokens.spacing16)
        .background(RoundedRectangle(cornerRadius: IRISTokens.cornerRadiusMedium).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: IRISTokens.cornerRadiusMedium).strokeBorder(IRISTokens.irisAccent.opacity(0.2), lineWidth: 0.5))
    }

    // v1.120 — Banner MCP sources avec backend réel actif
    @ViewBuilder
    private var mcpSourcesBanner: some View {
        let mcpSources = Sentinel.knownSources.filter { Sentinel.isMCPBackend(for: $0) }
        if !mcpSources.isEmpty {
            HStack(spacing: IRISTokens.spacing16) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(IRISTokens.aquaTint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("MCP BACKENDS ACTIFS (\(mcpSources.count))")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        ForEach(mcpSources, id: \.self) { source in
                            let serverName = Sentinel.mcpServerName(for: source) ?? "?"
                            let toolName = Sentinel.mcpToolName(for: source)
                            HStack(spacing: 3) {
                                Text(source)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.primary)
                                Text("→ \(serverName)\(toolName.map { ".\($0)" } ?? "")")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(IRISTokens.aquaTint.opacity(0.12))
                            .clipShape(Capsule())
                        }
                    }
                }
                Spacer()
            }
            .padding(IRISTokens.spacing16)
            .background(RoundedRectangle(cornerRadius: IRISTokens.cornerRadiusMedium).fill(.regularMaterial))
            .overlay(RoundedRectangle(cornerRadius: IRISTokens.cornerRadiusMedium).strokeBorder(IRISTokens.aquaTint.opacity(0.2), lineWidth: 0.5))
        }
    }

    // v1.102 — Latest signal from Witness (source=screen) avec project guess
    private var latestFocusedSignal: Signal? {
        allSignals.first { $0.source == "screen" && $0.emittedAt > Date().addingTimeInterval(-300) }
    }

    private func focusedProjectCard(_ signal: Signal) -> some View {
        let elapsed = Int(Date().timeIntervalSince(signal.emittedAt))
        let elapsedStr = elapsed < 60 ? "\(elapsed)s ago" : "\(elapsed/60)min ago"
        return HStack(spacing: IRISTokens.spacing16) {
            Image(systemName: "eyes")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(IRISTokens.aquaTint)
            VStack(alignment: .leading, spacing: 2) {
                Text("CURRENTLY FOCUSED")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(.secondary)
                Text(signal.summary)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                if let project = signal.projectScope {
                    Text("project: \(project)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(IRISTokens.irisAccent)
                }
            }
            Spacer()
            Text(elapsedStr)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(IRISTokens.spacing16)
        .background(RoundedRectangle(cornerRadius: IRISTokens.cornerRadiusMedium).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: IRISTokens.cornerRadiusMedium).strokeBorder(IRISTokens.aquaTint.opacity(0.2), lineWidth: 0.5))
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

    // MARK: — v1.201 Milestone celebration

    /// True iff current appVersion patch is in [200, 205]. Card auto-hides at 1.206+.
    private var isInMilestoneWindow: Bool {
        let parts = IRISRuntimeInfo.appVersion.split(separator: ".")
        guard parts.count >= 3, let patch = Int(parts[2]) else { return false }
        return patch >= 200 && patch <= 205
    }

    private var milestoneCard: some View {
        HStack(spacing: IRISTokens.spacing16) {
            Image(systemName: "star.circle.fill")
                .foregroundStyle(IRISTokens.goldAccent)
                .font(.system(size: 24))
            VStack(alignment: .leading, spacing: 2) {
                Text("MILESTONE v1.200")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(IRISTokens.goldAccent)
                Text("200 versions shipped · IRIS exocortex perso")
                    .font(.system(size: 13, weight: .light, design: .serif))
                    .foregroundStyle(.primary)
                Text("23 mega-swarm bundles · multi-agent SwiftUI · 0→200 sans interruption")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(IRISTokens.spacing16)
        .background(RoundedRectangle(cornerRadius: IRISTokens.cornerRadiusSmall).fill(IRISTokens.goldAccent.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: IRISTokens.cornerRadiusSmall).strokeBorder(IRISTokens.goldAccent.opacity(0.4), lineWidth: 1))
    }

    // MARK: — v1.195 System status banner

    /// Witness pause state — mirrors @AppStorage("witnessPaused") key added v1.187.
    private var witnessActive: Bool {
        !UserDefaults.standard.bool(forKey: "witnessPaused")
    }

    /// Sentinel active sources — knownSources minus muted (gmail/github/calendar/fs).
    private var sentinelActiveCount: Int {
        let muted = Sentinel.mutedSources
        return Sentinel.knownSources.filter { !muted.contains($0) }.count
    }

    /// MCP servers discovered/connected count. MCPManager has no live-connection accessor —
    /// `servers` reflects parsed config; 0 if discover() never ran.
    private var mcpConnectedCount: Int {
        MCPManager.shared.servers.count
    }

    // v1.229 — Live count of EventLog entries in past 5 minutes (300s)
    private var eventsPast5Min: Int {
        let cutoff = Date().addingTimeInterval(-300)
        return allEvents.filter { $0.timestamp >= cutoff }.count
    }

    @ViewBuilder
    private var live5MinBadge: some View {
        HStack(spacing: 4) {
            if eventsPast5Min > 0 {
                Circle().fill(IRISTokens.aquaTint).frame(width: 6, height: 6)
            } else {
                Circle().fill(.secondary.opacity(0.4)).frame(width: 6, height: 6)
            }
            Text("+\(eventsPast5Min)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(eventsPast5Min > 0 ? IRISTokens.aquaTint : .secondary)
            Text("past 5min")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary.opacity(0.7))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(.thinMaterial))
    }

    private var systemStatusBanner: some View {
        HStack(spacing: IRISTokens.spacing24) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .font(.system(size: 14))
            Text("SYSTEM STATUS")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(.secondary)
            // Witness pill
            HStack(spacing: 4) {
                Image(systemName: witnessActive ? "eye.fill" : "eye.slash.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(witnessActive ? .green.opacity(0.8) : .red.opacity(0.8))
                Text("Witness")
                    .font(.system(size: 10))
                Text(witnessActive ? "active" : "pause")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            // Sentinel pill
            HStack(spacing: 4) {
                Image(systemName: "sensor.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(sentinelActiveCount > 0 ? IRISTokens.aquaTint : .secondary)
                Text("Sentinel")
                    .font(.system(size: 10))
                Text("\(sentinelActiveCount) sources")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            // MCP pill
            HStack(spacing: 4) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 10))
                    .foregroundStyle(mcpConnectedCount > 0 ? IRISTokens.goldAccent : .secondary)
                Text("MCP")
                    .font(.system(size: 10))
                Text("\(mcpConnectedCount) servers")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            // v1.229 — Live "+N past 5min" event count badge
            live5MinBadge
            Spacer()
        }
        .padding(IRISTokens.spacing8)
        .background(.thinMaterial)
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

                // v1.145 — Burn rate sparkline 24h (audits + drafts persistés, par tranche horaire)
                let burnBuckets = costBurnHourlyBuckets()
                if burnBuckets.contains(where: { $0 > 0 }) {
                    costSparkline(buckets: burnBuckets)
                        .frame(height: 24)
                    HStack {
                        Text("burn 24h (audits+drafts)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("$\(String(format: "%.4f", burnBuckets.reduce(0, +)))")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(IRISTokens.goldAccent)
                    }
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

    // v1.145 — Cost burn rate sparkline 24 buckets horaires (audits + drafts persistés)
    private func costBurnHourlyBuckets() -> [Double] {
        var buckets = Array(repeating: 0.0, count: 24)
        let now = Date()
        for audit in allAudits where audit.createdAt > now.addingTimeInterval(-86400) {
            let elapsed = Int(now.timeIntervalSince(audit.createdAt) / 3600)
            guard elapsed >= 0 && elapsed < 24 else { continue }
            buckets[23 - elapsed] += audit.costUSD
        }
        for draft in allDrafts where draft.createdAt > now.addingTimeInterval(-86400) {
            let elapsed = Int(now.timeIntervalSince(draft.createdAt) / 3600)
            guard elapsed >= 0 && elapsed < 24 else { continue }
            buckets[23 - elapsed] += draft.costUSD
        }
        return buckets
    }

    private func costSparkline(buckets: [Double]) -> some View {
        let maxVal = max(0.001, buckets.max() ?? 0.001)
        return GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 1) {
                ForEach(Array(buckets.enumerated()), id: \.offset) { _, val in
                    let ratio = CGFloat(val / maxVal)
                    Rectangle()
                        .fill(IRISTokens.goldAccent.opacity(val > 0 ? 0.7 : 0.15))
                        .frame(height: max(2, geo.size.height * ratio))
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
        if raw.contains("haiku") { return IRISTokens.goldAccent }
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

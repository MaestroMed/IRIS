import SwiftUI
import SwiftData
import AppKit

// IRIS v1.36 — Panel stats Bus : compteurs events par kind sur 3 fenêtres temporelles.
// Affiché quand sidebar System > Stats sélectionné.
// IRIS v1.164 — Export bus stats snapshot to Markdown (~/iris-busstats-<ISO>.md).
/// v1.176 — Most-frequent kind past 1h insight banner.
/// v1.181 — Auto-refresh 30s timer toggle to force window stats re-eval.
/// v1.189 — CSV export per kind (1h/24h/all-time) to home dir.
/// v1.193 — Stats footer (total + avg/h + earliest event date).
/// v1.202 — Past hour delta % vs previous hour badge (arrow up/down).
/// v1.207 — Today vs yesterday comparison card (counts + delta %).
/// v1.214 — Top 3 busiest hours past 24h card with mini bars.
/// v1.217 — Active sessions badge (unique correlationIds past 1h).

struct BusStatsView: View {
    @Query(sort: \EventLog.timestamp, order: .reverse) private var allEvents: [EventLog]

    @State private var autoRefresh: Bool = false
    @State private var refreshTick: Int = 0
    @State private var exportCSVStatus: String?

    private var now: Date { Date() }
    private var oneHourAgo: Date { now.addingTimeInterval(-3600) }
    private var oneDayAgo: Date { now.addingTimeInterval(-86400) }

    private var lastHour: [EventLog] {
        let _ = refreshTick
        return allEvents.filter { $0.timestamp >= oneHourAgo }
    }
    private var lastDay: [EventLog] {
        let _ = refreshTick
        return allEvents.filter { $0.timestamp >= oneDayAgo }
    }

    private static let kindOrder = [
        "userInput", "agentResponse", "agentDispatched",
        "signalEmitted", "draftReady", "actionRequested",
        "actionApproved", "actionRejected", "actionExecuted",
        "actionLogged", "agentFailure", "systemLog", "conductorChunk"
    ]

    private var topKind1h: (kind: String, count: Int, percentage: Double)? {
        let events = lastHour
        guard !events.isEmpty else { return nil }
        let groups = Dictionary(grouping: events, by: \.kind).mapValues { $0.count }
        guard let top = groups.max(by: { $0.value < $1.value }) else { return nil }
        let total = events.count
        let percentage = Double(top.value) / Double(total) * 100
        return (top.key, top.value, percentage)
    }

    private var hourDelta: (current: Int, previous: Int, deltaPercent: Double) {
        let _ = refreshTick
        let oneHourCutoff = Date().addingTimeInterval(-3600)
        let twoHourCutoff = Date().addingTimeInterval(-7200)
        let current = allEvents.filter { $0.timestamp >= oneHourCutoff }.count
        let previous = allEvents.filter { $0.timestamp >= twoHourCutoff && $0.timestamp < oneHourCutoff }.count
        let deltaPercent: Double
        if previous > 0 {
            deltaPercent = (Double(current) - Double(previous)) / Double(previous) * 100
        } else if current > 0 {
            deltaPercent = 100
        } else {
            deltaPercent = 0
        }
        return (current, previous, deltaPercent)
    }

    private var activeSessionCount: Int {
        let _ = refreshTick
        let cutoff = Date().addingTimeInterval(-3600)
        let filtered = allEvents.filter { $0.timestamp >= cutoff }
        return Set(filtered.compactMap { $0.correlationId }).count
    }

    @ViewBuilder
    private var activeSessionsBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "link.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(IRISTokens.aquaTint)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(activeSessionCount)")
                    .font(.system(size: 16, weight: .light, design: .serif))
                    .foregroundStyle(IRISTokens.aquaTint)
                Text("ACTIVE SESSIONS 1H")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(.thinMaterial))
    }

    @ViewBuilder
    private var hourDeltaBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: hourDelta.current > hourDelta.previous ? "arrow.up.right" : (hourDelta.current < hourDelta.previous ? "arrow.down.right" : "arrow.right"))
                .font(.system(size: 10))
                .foregroundStyle(hourDelta.current > hourDelta.previous ? .green : (hourDelta.current < hourDelta.previous ? .red : .secondary))
            Text(String(format: "%+.0f%%", hourDelta.deltaPercent))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(hourDelta.current > hourDelta.previous ? .green : (hourDelta.current < hourDelta.previous ? .red : .secondary))
            Text("vs prev hour")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary.opacity(0.7))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(.thinMaterial))
    }

    private var todayVsYesterday: (today: Int, yesterday: Int) {
        let _ = refreshTick
        let cal = Calendar.current
        let today = allEvents.filter { cal.isDateInToday($0.timestamp) }.count
        let yesterday = allEvents.filter { cal.isDateInYesterday($0.timestamp) }.count
        return (today, yesterday)
    }

    @ViewBuilder
    private var todayVsYesterdayCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TODAY vs YESTERDAY")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(.secondary)
            HStack(spacing: IRISTokens.spacing24) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(todayVsYesterday.today)")
                        .font(.system(size: 22, weight: .light, design: .serif))
                        .foregroundStyle(IRISTokens.aquaTint)
                    Text("TODAY")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary.opacity(0.5))
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(todayVsYesterday.yesterday)")
                        .font(.system(size: 22, weight: .light, design: .serif))
                        .foregroundStyle(.secondary)
                    Text("YESTERDAY")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if todayVsYesterday.yesterday > 0 {
                    let diff = todayVsYesterday.today - todayVsYesterday.yesterday
                    let percent = Double(diff) / Double(todayVsYesterday.yesterday) * 100
                    HStack(spacing: 4) {
                        Image(systemName: diff > 0 ? "arrow.up.right" : (diff < 0 ? "arrow.down.right" : "minus"))
                            .font(.system(size: 12))
                            .foregroundStyle(diff > 0 ? .green : (diff < 0 ? .red : .secondary))
                        Text(String(format: "%+.0f%%", percent))
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(diff > 0 ? .green : (diff < 0 ? .red : .secondary))
                    }
                }
            }
        }
        .padding(IRISTokens.spacing16)
        .background(RoundedRectangle(cornerRadius: IRISTokens.cornerRadiusSmall).fill(.thinMaterial))
    }

    private var topBusiestHours: [(hour: Int, count: Int)] {
        let _ = refreshTick
        let cutoff = Date().addingTimeInterval(-86400)
        let recent = allEvents.filter { $0.timestamp >= cutoff }
        let groups = Dictionary(grouping: recent, by: { Calendar.current.component(.hour, from: $0.timestamp) })
            .mapValues { $0.count }
        return groups
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { (hour: $0.key, count: $0.value) }
    }

    @ViewBuilder
    private var topHoursCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TOP 3 BUSIEST HOURS (24H)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(.secondary)
            if topBusiestHours.isEmpty {
                Text("Aucune activité dans les 24h.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(topBusiestHours.enumerated()), id: \.offset) { idx, item in
                    HStack(spacing: 8) {
                        Text("#\(idx+1)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(IRISTokens.goldAccent)
                            .frame(width: 24, alignment: .leading)
                        Text(String(format: "%02d:00 - %02d:59", item.hour, item.hour))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("\(item.count) events")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(IRISTokens.aquaTint)
                        Rectangle()
                            .fill(IRISTokens.aquaTint.opacity(0.5))
                            .frame(width: max(20, CGFloat(item.count) / CGFloat(max(1, topBusiestHours.first?.count ?? 1)) * 80), height: 4)
                            .cornerRadius(2)
                    }
                }
            }
        }
        .padding(IRISTokens.spacing16)
        .background(RoundedRectangle(cornerRadius: IRISTokens.cornerRadiusSmall).fill(.thinMaterial))
    }

    private var totalStats: (total: Int, avgPerHour: Double, earliest: Date?) {
        let total = allEvents.count
        let earliest = allEvents.min { $0.timestamp < $1.timestamp }?.timestamp
        let avgPerHour: Double
        if let earliest {
            let hoursElapsed = max(1.0, Date().timeIntervalSince(earliest) / 3600)
            avgPerHour = Double(total) / hoursElapsed
        } else {
            avgPerHour = 0
        }
        return (total, avgPerHour, earliest)
    }

    private var statsFooter: some View {
        HStack(spacing: IRISTokens.spacing24) {
            VStack(alignment: .leading, spacing: 1) {
                Text("TOTAL")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text("\(totalStats.total)")
                    .font(.system(size: 14, weight: .light, design: .serif))
                    .foregroundStyle(IRISTokens.aquaTint)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("AVG/H")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(String(format: "%.1f", totalStats.avgPerHour))
                    .font(.system(size: 14, weight: .light, design: .serif))
                    .foregroundStyle(IRISTokens.irisAccent)
            }
            if let earliest = totalStats.earliest {
                VStack(alignment: .leading, spacing: 1) {
                    Text("DEPUIS")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(earliest, format: .dateTime.day().month().year().hour().minute())
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(IRISTokens.spacing16)
        .background(.thinMaterial)
    }

    @ViewBuilder
    private var topKindBanner: some View {
        if let topKind = topKind1h {
            HStack(spacing: IRISTokens.spacing8) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundStyle(IRISTokens.aquaTint)
                    .font(.system(size: 14))
                VStack(alignment: .leading, spacing: 1) {
                    Text("MOST-FREQUENT KIND PAST 1H")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Text(topKind.kind)
                            .font(.system(size: 13, weight: .medium))
                        Text("\(topKind.count) events")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text(String(format: "(%.0f%%)", topKind.percentage))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(IRISTokens.aquaTint)
                    }
                }
                Spacer()
            }
            .padding(IRISTokens.spacing16)
            .background(IRISTokens.aquaTint.opacity(0.07))
        } else {
            Text("Aucun event dans la dernière heure.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(8)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: IRISTokens.spacing24) {
                header

                topKindBanner

                todayVsYesterdayCard

                topHoursCard

                cardSection(title: "Dernière heure", total: lastHour.count, events: lastHour, accent: IRISTokens.irisAccent)
                cardSection(title: "Dernières 24h", total: lastDay.count, events: lastDay, accent: IRISTokens.aquaTint)
                cardSection(title: "Total all-time", total: allEvents.count, events: allEvents, accent: IRISTokens.goldAccent)

                Spacer()

                statsFooter
            }
            .padding(IRISTokens.spacing24)
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            if autoRefresh { refreshTick += 1 }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: "chart.bar.fill")
                .foregroundStyle(IRISTokens.irisAccent)
            Text("Bus Stats")
                .font(.system(size: 22, weight: .light, design: .serif))
            activeSessionsBadge
            hourDeltaBadge
            Button(action: exportMarkdown) {
                Label("Export MD", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Export stats current snapshot Markdown")
            Button { exportStatsCSV() } label: {
                Label("CSV", systemImage: "tablecells").font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Export stats par kind en CSV (1h/24h/all)")
            if let status = exportCSVStatus {
                Text(status)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
            Button {
                autoRefresh.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: autoRefresh ? "arrow.clockwise.circle.fill" : "arrow.clockwise.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(autoRefresh ? IRISTokens.aquaTint : .secondary)
                    Text("Auto 30s").font(.system(size: 11))
                }
            }
            .buttonStyle(.plain)
            .help("Toggle auto-refresh stats every 30s")
            Spacer()
            Text("\(allEvents.count) events tracés")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private func exportMarkdown() {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        let nowDate = Date()
        let isoStamp = isoFormatter.string(from: nowDate).replacingOccurrences(of: ":", with: "-")

        var md = "# IRIS Bus Stats — \(isoFormatter.string(from: nowDate))\n\n"
        md += renderSection(title: "1h window", events: lastHour)
        md += "\n"
        md += renderSection(title: "24h window", events: lastDay)
        md += "\n"
        md += renderSection(title: "All-time", events: allEvents)

        let home = FileManager.default.homeDirectoryForCurrentUser
        let url = home.appendingPathComponent("iris-busstats-\(isoStamp).md")
        do {
            try md.write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            NSLog("[BusStatsView] export failed: \(error)")
        }
    }

    private func exportStatsCSV() {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        let isoStamp = isoFormatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")

        let hourGroups = Dictionary(grouping: lastHour, by: \.kind).mapValues { $0.count }
        let dayGroups = Dictionary(grouping: lastDay, by: \.kind).mapValues { $0.count }
        let allGroups = Dictionary(grouping: allEvents, by: \.kind).mapValues { $0.count }

        var seen = Set<String>()
        var kinds: [String] = []
        for k in Self.kindOrder where seen.insert(k).inserted { kinds.append(k) }
        for k in hourGroups.keys where seen.insert(k).inserted { kinds.append(k) }
        for k in dayGroups.keys where seen.insert(k).inserted { kinds.append(k) }
        for k in allGroups.keys where seen.insert(k).inserted { kinds.append(k) }

        var csv = "kind,past_1h,past_24h,all_time\n"
        for kind in kinds {
            let h = hourGroups[kind] ?? 0
            let d = dayGroups[kind] ?? 0
            let a = allGroups[kind] ?? 0
            csv += "\(kind),\(h),\(d),\(a)\n"
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let url = home.appendingPathComponent("iris-busstats-\(isoStamp).csv")
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            exportCSVStatus = "✅ → \(url.lastPathComponent)"
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            exportCSVStatus = "⚠️ \(error.localizedDescription)"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            exportCSVStatus = nil
        }
    }

    private func renderSection(title: String, events: [EventLog]) -> String {
        let groups = Dictionary(grouping: events, by: \.kind)
        let lines = Self.kindOrder.compactMap { kind -> String? in
            let count = groups[kind]?.count ?? 0
            return count > 0 ? "- \(kind) : \(count)" : nil
        }
        var section = "## \(title)\n"
        if lines.isEmpty {
            section += "- (none)\n"
        } else {
            section += lines.joined(separator: "\n") + "\n"
        }
        return section
    }

    private func cardSection(title: String, total: Int, events: [EventLog], accent: Color) -> some View {
        let groups = Dictionary(grouping: events, by: \.kind)
        let breakdown = Self.kindOrder.compactMap { kind -> (String, Int)? in
            let count = groups[kind]?.count ?? 0
            return count > 0 ? (kind, count) : nil
        }

        return VStack(alignment: .leading, spacing: IRISTokens.spacing8) {
            HStack {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.4).foregroundStyle(.secondary)
                Spacer()
                Text("\(total)")
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundStyle(accent)
            }

            if breakdown.isEmpty {
                Text("Aucun event.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                ForEach(breakdown, id: \.0) { item in
                    statBar(kind: item.0, count: item.1, total: total, color: accent)
                }
            }
        }
        .padding(IRISTokens.spacing16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: IRISTokens.cornerRadiusMedium).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: IRISTokens.cornerRadiusMedium).strokeBorder(accent.opacity(0.15), lineWidth: 0.5))
    }

    private func statBar(kind: String, count: Int, total: Int, color: Color) -> some View {
        let ratio = total > 0 ? CGFloat(count) / CGFloat(total) : 0
        return HStack(spacing: 6) {
            Text(kind)
                .font(.system(size: 10, design: .monospaced))
                .frame(width: 130, alignment: .leading)
                .foregroundStyle(.primary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(color.opacity(0.12))
                    RoundedRectangle(cornerRadius: 2).fill(color.opacity(0.7))
                        .frame(width: max(2, geo.size.width * ratio))
                }
            }
            .frame(height: 6)
            Text("\(count)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
    }
}

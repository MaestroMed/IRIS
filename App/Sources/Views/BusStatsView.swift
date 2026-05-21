import SwiftUI
import SwiftData
import AppKit

// IRIS v1.36 — Panel stats Bus : compteurs events par kind sur 3 fenêtres temporelles.
// Affiché quand sidebar System > Stats sélectionné.
// IRIS v1.164 — Export bus stats snapshot to Markdown (~/iris-busstats-<ISO>.md).
/// v1.176 — Most-frequent kind past 1h insight banner.
/// v1.181 — Auto-refresh 30s timer toggle to force window stats re-eval.
/// v1.189 — CSV export per kind (1h/24h/all-time) to home dir.

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

                cardSection(title: "Dernière heure", total: lastHour.count, events: lastHour, accent: IRISTokens.irisAccent)
                cardSection(title: "Dernières 24h", total: lastDay.count, events: lastDay, accent: IRISTokens.aquaTint)
                cardSection(title: "Total all-time", total: allEvents.count, events: allEvents, accent: IRISTokens.goldAccent)

                Spacer()
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

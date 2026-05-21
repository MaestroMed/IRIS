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
/// v1.225 — 24h heatmap card (one cell per hour, aqua intensity).
/// v1.231 — Throughput card (events/min × 4 windows: 1m/5m/1h/24h).
/// v1.237 — Peak day past 7d banner (gold crown).
/// v1.242 — Period comparisons card (1h/24h/7d vs previous period of same length).
/// v1.249 — Avg events per session today card (events/sessions ratio).
/// v1.253 — Live events/sec rate badge (past 10s window).
/// v1.258 — Latest critical event timestamp badge (red if recent, green if none).
/// v1.265 — Peak hour-of-day all-time badge (gold clock).
/// v1.271 — Top agents by event count (from + to involvement) card.
/// v1.276 — Hot kinds past 1h carousel card (top 3 colored cells).
/// v1.280 — Burstiest minute past 24h card (gold bolt + count + time).
/// v1.283 — Total records in DB card (per-model counts horizontal).
/// v1.288 — Period stats selector card (1h/24h/7d/all) with live event count.
/// v1.293 — Hot kinds card: per-kind cell now shows latest event preview (timestamp + payload).
/// v1.298 — Quietest hour past 24h badge (moon.zzz aqua).
/// v1.307 — Top 3 correlation chains past 1h card.

struct BusStatsView: View {
    @Query(sort: \EventLog.timestamp, order: .reverse) private var allEvents: [EventLog]
    @Query private var allMemories: [Memory]
    @Query private var allAudits: [AuditReport]
    @Query private var allDrafts: [Draft]
    @Query private var allSignals: [Signal]
    @Query private var allProjects: [ProjectRecord]
    @Query private var allActionLogs: [ActionLog]

    @State private var autoRefresh: Bool = false
    @State private var refreshTick: Int = 0
    @State private var exportCSVStatus: String?
    @AppStorage("busStatsSelectedPeriod") private var selectedPeriodKey: String = "24h"

    private var periodFilteredEvents: [EventLog] {
        let _ = refreshTick
        switch selectedPeriodKey {
        case "1h":
            return allEvents.filter { $0.timestamp >= Date().addingTimeInterval(-3600) }
        case "24h":
            return allEvents.filter { $0.timestamp >= Date().addingTimeInterval(-86400) }
        case "7d":
            return allEvents.filter { $0.timestamp >= Date().addingTimeInterval(-7 * 86400) }
        case "all":
            return allEvents
        default:
            return allEvents
        }
    }

    @ViewBuilder
    private var periodSelectorCard: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar.badge.clock")
                .foregroundStyle(IRISTokens.aquaTint)
                .font(.system(size: 14))
            Text("PERIOD STATS")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(.secondary)
            Picker("", selection: $selectedPeriodKey) {
                Text("Past 1h").tag("1h")
                Text("Past 24h").tag("24h")
                Text("Past 7d").tag("7d")
                Text("All time").tag("all")
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(maxWidth: 100)
            .pickerStyle(.menu)
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(periodFilteredEvents.count)")
                    .font(.system(size: 18, weight: .light, design: .serif))
                    .foregroundStyle(IRISTokens.aquaTint)
                Text("events")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(IRISTokens.spacing16)
        .background(RoundedRectangle(cornerRadius: IRISTokens.cornerRadiusSmall).fill(.thinMaterial))
    }

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

    private func colorForKind(_ kind: String) -> Color {
        switch kind {
        case "userInput": return IRISTokens.irisAccent
        case "agentResponse": return IRISTokens.aquaTint
        case "agentDispatched": return .blue
        case "signalEmitted": return .purple
        case "draftReady": return .teal
        case "actionRequested": return .orange
        case "actionApproved": return .green
        case "actionRejected": return .red
        case "actionExecuted": return IRISTokens.goldAccent
        case "actionLogged": return .indigo
        case "agentFailure": return .red
        case "systemLog": return .gray
        case "conductorChunk": return .mint
        default: return .secondary
        }
    }

    private var topKinds1h: [(kind: String, count: Int, color: Color)] {
        let _ = refreshTick
        let events = lastHour
        guard !events.isEmpty else { return [] }
        let groups = Dictionary(grouping: events, by: \.kind).mapValues { $0.count }
        return groups
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { (kind: $0.key, count: $0.value, color: colorForKind($0.key)) }
    }

    private func latestEventOfKind(_ kind: String) -> EventLog? {
        let _ = refreshTick
        return allEvents.first { $0.kind == kind }
    }

    @ViewBuilder
    private var hotKindsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("HOT KINDS PAST 1H")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(.secondary)
            if topKinds1h.isEmpty {
                Text("Aucune activité dans la dernière heure.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    ForEach(Array(topKinds1h.enumerated()), id: \.offset) { idx, item in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 3) {
                                Text("#\(idx+1)")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Circle().fill(item.color).frame(width: 6, height: 6)
                            }
                            Text(item.kind)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text("\(item.count) ev")
                                .font(.system(size: 13, weight: .light, design: .serif))
                                .foregroundStyle(item.color)
                            if let latest = latestEventOfKind(item.kind) {
                                Text(latest.timestamp, format: .dateTime.hour().minute().second())
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Text(String(latest.payloadJSON.prefix(40)))
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundStyle(.secondary.opacity(0.6))
                                    .lineLimit(1)
                            }
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 4).fill(item.color.opacity(0.06)))
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(item.color.opacity(0.3), lineWidth: 0.5))
                    }
                }
            }
        }
        .padding(IRISTokens.spacing16)
        .background(RoundedRectangle(cornerRadius: IRISTokens.cornerRadiusSmall).fill(.thinMaterial))
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

    private var topCorrelationChains1h: [(correlationId: UUID, count: Int)] {
        let _ = refreshTick
        let cutoff = Date().addingTimeInterval(-3600)
        let filtered = allEvents.filter { $0.timestamp >= cutoff && $0.correlationId != nil }
        let groups = Dictionary(grouping: filtered) { $0.correlationId! }
            .mapValues { $0.count }
        return groups
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { (correlationId: $0.key, count: $0.value) }
    }

    @ViewBuilder
    private var topChainsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TOP CORRELATION CHAINS PAST 1H")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(.secondary)
            if topCorrelationChains1h.isEmpty {
                Text("Aucune chaîne corrélée 1h.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(topCorrelationChains1h.enumerated()), id: \.offset) { idx, item in
                    HStack(spacing: 6) {
                        Text("#\(idx+1)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(IRISTokens.aquaTint)
                            .frame(width: 24, alignment: .leading)
                        Image(systemName: "link.circle")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Text(item.correlationId.uuidString.prefix(8))
                            .font(.system(size: 11, design: .monospaced))
                        Spacer()
                        Text("\(item.count) events")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(IRISTokens.aquaTint)
                    }
                }
            }
        }
        .padding(IRISTokens.spacing16)
        .background(RoundedRectangle(cornerRadius: IRISTokens.cornerRadiusSmall).fill(.thinMaterial))
    }

    private var avgEventsPerSession: (events: Int, sessions: Int, avg: Double) {
        let _ = refreshTick
        let todayEvents = allEvents.filter { Calendar.current.isDateInToday($0.timestamp) }
        let events = todayEvents.count
        let sessions = Set(todayEvents.compactMap { $0.correlationId }).count
        let avg = sessions == 0 ? 0 : Double(events) / Double(sessions)
        return (events, sessions, avg)
    }

    @ViewBuilder
    private var avgPerSessionCard: some View {
        HStack(spacing: IRISTokens.spacing24) {
            VStack(alignment: .leading, spacing: 1) {
                Text("AVG EVENTS / SESSION TODAY")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.1f", avgEventsPerSession.avg))
                        .font(.system(size: 18, weight: .light, design: .serif))
                        .foregroundStyle(IRISTokens.aquaTint)
                    Text("ev/session")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text("BREAKDOWN")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                Text("\(avgEventsPerSession.events) events / \(avgEventsPerSession.sessions) sessions")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(IRISTokens.spacing16)
        .background(RoundedRectangle(cornerRadius: IRISTokens.cornerRadiusSmall).fill(.thinMaterial))
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

    private var liveRate10s: Double {
        let _ = refreshTick
        let cutoff = Date().addingTimeInterval(-10)
        let count = allEvents.filter { $0.timestamp >= cutoff }.count
        return Double(count) / 10.0
    }

    @ViewBuilder
    private var liveRateBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(liveRate10s > 0 ? IRISTokens.aquaTint : .secondary.opacity(0.4))
                .frame(width: 6, height: 6)
            Text(String(format: "%.1f", liveRate10s))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(liveRate10s > 0 ? IRISTokens.aquaTint : .secondary)
            Text("ev/sec")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary.opacity(0.7))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(.thinMaterial))
    }

    private var latestCriticalEvent: EventLog? {
        let _ = refreshTick
        return allEvents.filter { event in
            event.kind == "agentFailure"
                || event.payloadJSON.contains("\"level\":\"error\"")
                || event.payloadJSON.contains("\"level\":\"fault\"")
        }
        .sorted { $0.timestamp > $1.timestamp }
        .first
    }

    @ViewBuilder
    private var latestCriticalBadge: some View {
        if let event = latestCriticalEvent {
            let elapsed = Date().timeIntervalSince(event.timestamp)
            let elapsedStr: String = {
                if elapsed < 60 {
                    return "\(Int(elapsed))s ago"
                } else if elapsed < 3600 {
                    return "\(Int(elapsed/60))m ago"
                } else if elapsed < 86400 {
                    return "\(Int(elapsed/3600))h ago"
                } else {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy-MM-dd HH:mm"
                    return formatter.string(from: event.timestamp)
                }
            }()
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.system(size: 11))
                Text("Last critical: \(elapsedStr)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.red)
                Text("(\(event.kind))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(.red.opacity(0.08)))
        } else {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 11))
                Text("Aucun critique")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(.thinMaterial))
        }
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

    private var heatmap24h: [(hour: Int, count: Int)] {
        let _ = refreshTick
        let cutoff = Date().addingTimeInterval(-86400)
        let recent = allEvents.filter { $0.timestamp >= cutoff }
        let groups = Dictionary(grouping: recent, by: { Calendar.current.component(.hour, from: $0.timestamp) })
            .mapValues { $0.count }
        return (0..<24).map { hour in (hour: hour, count: groups[hour] ?? 0) }
    }

    @ViewBuilder
    private var heatmap24hCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("24H HEATMAP")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(.secondary)
            let maxCount = heatmap24h.map(\.count).max() ?? 1
            HStack(spacing: 2) {
                ForEach(heatmap24h, id: \.hour) { item in
                    VStack(spacing: 2) {
                        Rectangle()
                            .fill(IRISTokens.aquaTint.opacity(maxCount > 0 ? 0.15 + (Double(item.count) / Double(maxCount)) * 0.85 : 0.1))
                            .frame(height: 32)
                            .cornerRadius(2)
                        Text(String(format: "%02d", item.hour))
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(IRISTokens.spacing16)
        .background(RoundedRectangle(cornerRadius: IRISTokens.cornerRadiusSmall).fill(.thinMaterial))
    }

    private var peakDay7d: (date: Date, count: Int, weekdayName: String)? {
        let _ = refreshTick
        let cal = Calendar.current
        let cutoff = cal.startOfDay(for: Date().addingTimeInterval(-7 * 86400))
        let recent = allEvents.filter { $0.timestamp >= cutoff }
        let groups = Dictionary(grouping: recent, by: { cal.startOfDay(for: $0.timestamp) })
            .mapValues { $0.count }
        guard let top = groups.max(by: { $0.value < $1.value }), top.value > 0 else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        let weekdayName = formatter.string(from: top.key)
        return (date: top.key, count: top.value, weekdayName: weekdayName)
    }

    @ViewBuilder
    private var peakDayBadge: some View {
        if let peak = peakDay7d {
            HStack(spacing: 6) {
                Image(systemName: "crown.fill")
                    .foregroundStyle(IRISTokens.goldAccent)
                    .font(.system(size: 12))
                VStack(alignment: .leading, spacing: 1) {
                    Text("PEAK DAY PAST 7D")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Text(peak.weekdayName)
                            .font(.system(size: 13, weight: .medium))
                        Text(peak.date, format: .dateTime.day().month())
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text("\(peak.count) events")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(IRISTokens.goldAccent)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, IRISTokens.spacing16)
            .padding(.vertical, 6)
            .background(IRISTokens.goldAccent.opacity(0.05))
        } else {
            EmptyView()
        }
    }

    private var peakHourAllTime: (hour: Int, count: Int)? {
        let _ = refreshTick
        var counts: [Int: Int] = [:]
        for event in allEvents {
            let hour = Calendar.current.component(.hour, from: event.timestamp)
            counts[hour, default: 0] += 1
        }
        guard let top = counts.max(by: { $0.value < $1.value }), top.value > 0 else { return nil }
        return (hour: top.key, count: top.value)
    }

    @ViewBuilder
    private var peakHourAllTimeBadge: some View {
        if let peak = peakHourAllTime {
            HStack(spacing: 4) {
                Image(systemName: "clock.badge.checkmark")
                    .foregroundStyle(IRISTokens.goldAccent)
                    .font(.system(size: 12))
                VStack(alignment: .leading, spacing: 1) {
                    Text("PEAK HOUR-OF-DAY (ALL-TIME)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Text(String(format: "%02d:00 - %02d:59", peak.hour, peak.hour))
                            .font(.system(size: 13, weight: .medium))
                        Text("\(peak.count) events")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(IRISTokens.goldAccent)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, IRISTokens.spacing16)
            .padding(.vertical, 6)
            .background(IRISTokens.goldAccent.opacity(0.05))
        } else {
            EmptyView()
        }
    }

    private var quietestHour24h: (hour: Int, count: Int)? {
        let _ = refreshTick
        let cutoff = Date().addingTimeInterval(-86400)
        let recent = allEvents.filter { $0.timestamp >= cutoff }
        guard !recent.isEmpty else { return nil }
        var counts: [Int: Int] = [:]
        for event in recent {
            let hour = Calendar.current.component(.hour, from: event.timestamp)
            counts[hour, default: 0] += 1
        }
        guard !counts.isEmpty else { return nil }
        var minHour: Int? = nil
        var minCount: Int = Int.max
        for hour in 0..<24 {
            if let count = counts[hour], count < minCount {
                minCount = count
                minHour = hour
            }
        }
        guard let h = minHour else { return nil }
        return (hour: h, count: minCount)
    }

    @ViewBuilder
    private var quietestHourBadge: some View {
        if quietestHour24h == nil {
            EmptyView()
        } else {
            let q = quietestHour24h!
            HStack(spacing: 4) {
                Image(systemName: "moon.zzz.fill")
                    .foregroundStyle(IRISTokens.aquaTint)
                    .font(.system(size: 11))
                Text("QUIETEST HOUR")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                Text(String(format: "%02d:00", q.hour))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                Text("(\(q.count) ev)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(.thinMaterial))
        }
    }

    private var burstiestMinute24h: (start: Date, count: Int)? {
        let _ = refreshTick
        let cutoff = Date().addingTimeInterval(-86400)
        let recent = allEvents.filter { $0.timestamp >= cutoff }
        guard !recent.isEmpty else { return nil }
        var counts: [Int: Int] = [:]
        for event in recent {
            let bucket = Int(event.timestamp.timeIntervalSinceReferenceDate / 60)
            counts[bucket, default: 0] += 1
        }
        guard let top = counts.max(by: { $0.value < $1.value }), top.value > 0 else { return nil }
        let start = Date(timeIntervalSinceReferenceDate: Double(top.key) * 60)
        return (start: start, count: top.value)
    }

    @ViewBuilder
    private var burstiestMinuteCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("BURSTIEST MINUTE PAST 24H")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(.secondary)
            if burstiestMinute24h == nil {
                Text("Aucune activité 24h.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                let b = burstiestMinute24h!
                HStack(spacing: 8) {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(IRISTokens.goldAccent)
                        .font(.system(size: 16))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(b.start, format: .dateTime.hour().minute())
                            .font(.system(size: 14, weight: .medium))
                        Text(b.start, format: .dateTime.day().month())
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(b.count)")
                        .font(.system(size: 24, weight: .light, design: .serif))
                        .foregroundStyle(IRISTokens.goldAccent)
                    Text("events")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(IRISTokens.spacing16)
        .background(RoundedRectangle(cornerRadius: IRISTokens.cornerRadiusSmall).fill(.thinMaterial))
    }

    private var throughputStats: [(window: String, count: Int, rate: Double)] {
        let _ = refreshTick
        let nowDate = Date()
        let windows: [(String, TimeInterval, Double)] = [
            ("1m", 60, 1.0),
            ("5m", 300, 5.0),
            ("1h", 3600, 60.0),
            ("24h", 86400, 1440.0)
        ]
        return windows.map { label, seconds, minutes in
            let cutoff = nowDate.addingTimeInterval(-seconds)
            let count = allEvents.filter { $0.timestamp >= cutoff }.count
            return (window: label, count: count, rate: Double(count) / minutes)
        }
    }

    @ViewBuilder
    private var throughputCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("THROUGHPUT (events/min)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(.secondary)
            HStack(spacing: IRISTokens.spacing24) {
                ForEach(Array(throughputStats.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(String(format: "%.1f", item.rate))
                            .font(.system(size: 16, weight: .light, design: .serif))
                            .foregroundStyle(IRISTokens.aquaTint)
                        HStack(spacing: 3) {
                            Text(item.window)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text("\(item.count) ev")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.secondary.opacity(0.7))
                        }
                    }
                }
                Spacer()
            }
        }
        .padding(IRISTokens.spacing16)
        .background(RoundedRectangle(cornerRadius: IRISTokens.cornerRadiusSmall).fill(.thinMaterial))
    }

    private var windowTrends: [(window: String, current: Int, previous: Int, deltaPercent: Double)] {
        let _ = refreshTick
        let nowDate = Date()
        let windows: [(String, TimeInterval)] = [
            ("1h", 3600),
            ("24h", 86400),
            ("7d", 7 * 86400)
        ]
        return windows.map { label, seconds in
            let currentCutoff = nowDate.addingTimeInterval(-seconds)
            let previousCutoff = nowDate.addingTimeInterval(-2 * seconds)
            let current = allEvents.filter { $0.timestamp >= currentCutoff }.count
            let previous = allEvents.filter { $0.timestamp >= previousCutoff && $0.timestamp < currentCutoff }.count
            let deltaPercent: Double
            if previous > 0 {
                deltaPercent = (Double(current) - Double(previous)) / Double(previous) * 100
            } else if current > 0 {
                deltaPercent = 100
            } else {
                deltaPercent = 0
            }
            return (window: label, current: current, previous: previous, deltaPercent: deltaPercent)
        }
    }

    @ViewBuilder
    private var windowTrendsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PERIOD COMPARISONS")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(.secondary)
            ForEach(Array(windowTrends.enumerated()), id: \.offset) { _, item in
                HStack {
                    Text(item.window)
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 40, alignment: .leading)
                    Text("\(item.current)")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(IRISTokens.aquaTint)
                    Text("vs \(item.previous)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    HStack(spacing: 3) {
                        Image(systemName: item.current > item.previous ? "arrow.up.right" : (item.current < item.previous ? "arrow.down.right" : "minus"))
                            .font(.system(size: 10))
                        Text(String(format: "%+.0f%%", item.deltaPercent))
                            .font(.system(size: 11, design: .monospaced))
                    }
                    .foregroundStyle(item.current > item.previous ? .green : (item.current < item.previous ? .red : .secondary))
                }
            }
        }
        .padding(IRISTokens.spacing16)
        .background(RoundedRectangle(cornerRadius: IRISTokens.cornerRadiusSmall).fill(.thinMaterial))
    }

    private var topAgentsByEventCount: [(agent: String, count: Int)] {
        let _ = refreshTick
        var counts: [String: Int] = [:]
        for event in allEvents {
            var seen = Set<String>()
            if let from = event.fromAgent { seen.insert(from) }
            if let to = event.toAgent { seen.insert(to) }
            for agent in seen {
                counts[agent, default: 0] += 1
            }
        }
        return counts
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { (agent: $0.key, count: $0.value) }
    }

    @ViewBuilder
    private var topAgentsByEventCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TOP AGENTS BY EVENTS")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(.secondary)
            if topAgentsByEventCount.isEmpty {
                Text("Aucun event avec agent attribué.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(topAgentsByEventCount.enumerated()), id: \.offset) { idx, item in
                    HStack(spacing: 8) {
                        Text("#\(idx+1)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(IRISTokens.aquaTint)
                            .frame(width: 24, alignment: .leading)
                        Text(item.agent)
                            .font(.system(size: 11, weight: .medium))
                        Spacer()
                        Text("\(item.count)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Rectangle()
                            .fill(IRISTokens.aquaTint.opacity(0.4))
                            .frame(width: max(20, CGFloat(item.count) / CGFloat(max(1, topAgentsByEventCount.first?.count ?? 1)) * 100), height: 4)
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

    @ViewBuilder
    private var totalRecordsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("RECORDS IN DB")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(.secondary)
            HStack(spacing: IRISTokens.spacing16) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("EVENTS")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("\(allEvents.count)")
                        .font(.system(size: 14, weight: .light, design: .serif))
                        .foregroundStyle(IRISTokens.aquaTint)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("MEMORIES")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("\(allMemories.count)")
                        .font(.system(size: 14, weight: .light, design: .serif))
                        .foregroundStyle(IRISTokens.aquaTint)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("AUDITS")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("\(allAudits.count)")
                        .font(.system(size: 14, weight: .light, design: .serif))
                        .foregroundStyle(IRISTokens.aquaTint)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("DRAFTS")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("\(allDrafts.count)")
                        .font(.system(size: 14, weight: .light, design: .serif))
                        .foregroundStyle(IRISTokens.aquaTint)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("SIGNALS")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("\(allSignals.count)")
                        .font(.system(size: 14, weight: .light, design: .serif))
                        .foregroundStyle(IRISTokens.aquaTint)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("PROJECTS")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("\(allProjects.count)")
                        .font(.system(size: 14, weight: .light, design: .serif))
                        .foregroundStyle(IRISTokens.aquaTint)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("ACTIONS")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("\(allActionLogs.count)")
                        .font(.system(size: 14, weight: .light, design: .serif))
                        .foregroundStyle(IRISTokens.aquaTint)
                }
                Spacer()
            }
        }
        .padding(IRISTokens.spacing16)
        .background(RoundedRectangle(cornerRadius: IRISTokens.cornerRadiusSmall).fill(.thinMaterial))
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

                periodSelectorCard

                topKindBanner

                hotKindsCard

                throughputCard

                topChainsCard

                todayVsYesterdayCard

                windowTrendsCard

                topHoursCard

                peakDayBadge

                peakHourAllTimeBadge

                quietestHourBadge

                burstiestMinuteCard

                heatmap24hCard

                avgPerSessionCard

                topAgentsByEventCard

                cardSection(title: "Dernière heure", total: lastHour.count, events: lastHour, accent: IRISTokens.irisAccent)
                cardSection(title: "Dernières 24h", total: lastDay.count, events: lastDay, accent: IRISTokens.aquaTint)
                cardSection(title: "Total all-time", total: allEvents.count, events: allEvents, accent: IRISTokens.goldAccent)

                Spacer()

                statsFooter

                totalRecordsCard
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
            liveRateBadge
            latestCriticalBadge
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

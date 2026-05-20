import SwiftUI
import SwiftData

// IRIS v1.36 — Panel stats Bus : compteurs events par kind sur 3 fenêtres temporelles.
// Affiché quand sidebar System > Stats sélectionné.

struct BusStatsView: View {
    @Query(sort: \EventLog.timestamp, order: .reverse) private var allEvents: [EventLog]

    private var now: Date { Date() }
    private var oneHourAgo: Date { now.addingTimeInterval(-3600) }
    private var oneDayAgo: Date { now.addingTimeInterval(-86400) }

    private var lastHour: [EventLog] { allEvents.filter { $0.timestamp >= oneHourAgo } }
    private var lastDay: [EventLog] { allEvents.filter { $0.timestamp >= oneDayAgo } }

    private static let kindOrder = [
        "userInput", "agentResponse", "agentDispatched",
        "signalEmitted", "draftReady", "actionRequested",
        "actionApproved", "actionRejected", "actionExecuted",
        "actionLogged", "agentFailure", "systemLog", "conductorChunk"
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: IRISTokens.spacing24) {
                header

                cardSection(title: "Dernière heure", total: lastHour.count, events: lastHour, accent: IRISTokens.irisAccent)
                cardSection(title: "Dernières 24h", total: lastDay.count, events: lastDay, accent: IRISTokens.aquaTint)
                cardSection(title: "Total all-time", total: allEvents.count, events: allEvents, accent: IRISTokens.goldAccent)

                Spacer()
            }
            .padding(IRISTokens.spacing24)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: "chart.bar.fill")
                .foregroundStyle(IRISTokens.irisAccent)
            Text("Bus Stats")
                .font(.system(size: 22, weight: .light, design: .serif))
            Spacer()
            Text("\(allEvents.count) events tracés")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
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

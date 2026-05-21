import SwiftUI
import SwiftData

// IRIS v1.16 — Panel logs runtime affiché quand sidebar System > Logs sélectionné.
// @Query EventLog sorted desc + filtres par agent + kind + search.
// v1.168 — Severity color left-border per row (red/gold/aqua/green).
// v1.175 — Pause toggle freezes log view to a snapshot (logs accumulate but display stays).
// v1.184 — Failures-only quick filter button (sets filterKind=agentFailure).
// v1.191 — Horizontal stacked breakdown bar (kind colors) above logsList.
// v1.197 — Cmd+L keyboard shortcut on Clear filters button.
// v1.203 — CSV export filtered events button (next to Export MD).
// v1.206 — Past hour quick filter toggle (60min window).
// v1.219 — Cmd+F keyboard shortcut focuses search TextField.
// v1.224 — Paste UUID TextField for direct correlation chain filter.
// v1.230 — Burst detector banner (red alert if >50 events past 60s).
// v1.235 — Active filters summary chip row (each removable, with color per filter type).
// v1.238 — Burst threshold now configurable via @AppStorage burstAlertThreshold.
// v1.243 — Since-launch stat in header (uptime + events since bootstrap).
// v1.252 — Max display events configurable via @AppStorage logsMaxDisplay.
// v1.256 — JSON export filtered events button.
// v1.263 — Sort direction toggle (asc/desc) via @State sortAscending.
// v1.270 — Per-row "filter by correlation" link button.
// v1.278 — Search history dropdown (last 10 persisted via @AppStorage).

struct LogsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \EventLog.timestamp, order: .reverse) private var allEvents: [EventLog]

    @AppStorage("burstAlertThreshold") private var burstAlertThreshold: Int = 50  // v1.238
    @AppStorage("logsMaxDisplay") private var logsMaxDisplay: Int = 500  // v1.252
    @AppStorage("logsSearchHistoryCSV") private var searchHistoryCSV: String = ""  // v1.278

    @State private var filterAgent: String = ""
    @State private var filterKind: String = ""
    @State private var filterLevel: String = ""
    @State private var filterCorrelationId: UUID? = nil  // v1.70
    @State private var searchText: String = ""
    @State private var exportStatus: String?

    // v1.175 — Pause freeze
    @State private var isPaused: Bool = false
    @State private var pausedSnapshot: [EventLog] = []

    // v1.206 — Past-hour quick filter
    @State private var pastHourOnly: Bool = false

    // v1.263 — Sort direction toggle (default desc to preserve existing behavior)
    @State private var sortAscending: Bool = false

    // v1.219 — Cmd+F focuses search TextField
    @FocusState private var searchFieldFocused: Bool

    // v1.224 — Paste UUID buffer for direct correlation chain filter
    @State private var correlationPaste: String = ""

    private static let kindOrder = [
        "userInput", "agentDispatched", "agentResponse",
        "signalEmitted", "draftReady", "actionRequested",
        "actionApproved", "actionRejected", "actionExecuted",
        "actionLogged", "agentFailure", "systemLog", "conductorChunk"
    ]

    private static let levelOrder = ["debug", "info", "notice", "warning", "error", "fault"]

    var filtered: [EventLog] {
        let source: [EventLog] = (isPaused && !pausedSnapshot.isEmpty) ? pausedSnapshot : allEvents
        let arr: [EventLog] = Array(source.lazy
            .filter { filterAgent.isEmpty || $0.fromAgent == filterAgent || $0.toAgent == filterAgent }
            .filter { filterKind.isEmpty || $0.kind == filterKind }
            .filter { filterLevel.isEmpty || $0.payloadJSON.contains("\"level\":\"\(filterLevel)\"") }
            .filter { filterCorrelationId == nil || $0.correlationId == filterCorrelationId }
            .filter { !pastHourOnly || $0.timestamp >= Date().addingTimeInterval(-3600) }
            .filter { searchText.isEmpty || $0.payloadJSON.localizedCaseInsensitiveContains(searchText) || $0.kind.localizedCaseInsensitiveContains(searchText) }
            .prefix(logsMaxDisplay))
        return sortAscending ? arr.reversed() : arr
    }

    // v1.278 — Search history
    private var searchHistory: [String] {
        searchHistoryCSV
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func recordSearch(_ text: String) {
        guard !text.isEmpty else { return }
        var list = searchHistory
        list.removeAll { $0 == text }
        list.insert(text, at: 0)
        if list.count > 10 { list = Array(list.prefix(10)) }
        searchHistoryCSV = list.joined(separator: ",")
    }

    private func togglePause() {
        if isPaused {
            pausedSnapshot = []
            isPaused = false
        } else {
            pausedSnapshot = allEvents
            isPaused = true
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // v1.219 — Hidden button hosting Cmd+F shortcut (focuses search field)
            Button("") { searchFieldFocused = true }
                .keyboardShortcut(KeyEquivalent("f"), modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
            header
            activeFiltersChips
            burstBanner
            Divider()
            filtersBar
            Divider()
            if !filtered.isEmpty {
                kindBreakdownBar
                Divider()
            }
            logsList
        }
    }

    // v1.191 — Color helper for kind (mirrors kindBadge switch)
    private func colorForKind(_ kind: String) -> Color {
        switch kind {
        case "userInput": return IRISTokens.aquaTint
        case "agentDispatched": return IRISTokens.irisAccent
        case "agentResponse": return .green
        case "signalEmitted": return IRISTokens.goldAccent
        case "draftReady": return IRISTokens.irisAccent
        case "actionRequested": return IRISTokens.goldAccent
        case "actionApproved": return .green
        case "actionRejected": return .red
        case "actionExecuted": return .green
        case "agentFailure": return .red
        case "systemLog": return .secondary
        default: return .secondary
        }
    }

    // v1.191 — Breakdown of currently-filtered events by kind
    var kindBreakdown: [(kind: String, count: Int, color: Color)] {
        Self.kindOrder
            .map { kind in
                (kind: kind, count: filtered.filter { $0.kind == kind }.count, color: colorForKind(kind))
            }
            .filter { $0.count > 0 }
            .sorted { $0.count > $1.count }
    }

    private var kindBreakdownBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("BREAKDOWN")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(filtered.count) events")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            // Horizontal stacked bar
            GeometryReader { proxy in
                HStack(spacing: 1) {
                    ForEach(Array(kindBreakdown.enumerated()), id: \.offset) { _, item in
                        Rectangle()
                            .fill(item.color)
                            .frame(width: max(2, proxy.size.width * CGFloat(item.count) / CGFloat(max(1, filtered.count))))
                    }
                }
            }
            .frame(height: 6)
            // Mini legend (max 6 most-common kinds)
            HStack(spacing: 8) {
                ForEach(Array(kindBreakdown.prefix(6).enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 3) {
                        Circle()
                            .fill(item.color)
                            .frame(width: 6, height: 6)
                        Text("\(item.kind) (\(item.count))")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, IRISTokens.spacing16)
        .padding(.vertical, 6)
        .background(.thinMaterial)
    }

    // v1.230 — Burst detector: count events within past 60s
    var burstCount60s: Int {
        allEvents.filter { $0.timestamp >= Date().addingTimeInterval(-60) }.count
    }

    @ViewBuilder
    private var burstBanner: some View {
        if burstCount60s > burstAlertThreshold {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .foregroundStyle(.red)
                    .font(.system(size: 14))
                VStack(alignment: .leading, spacing: 1) {
                    Text("BURST DETECTED")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(.red)
                    Text("\(burstCount60s) events past 60s (threshold: \(burstAlertThreshold)) — bus possibly overloaded")
                        .font(.system(size: 11))
                        .foregroundStyle(.primary.opacity(0.85))
                }
                Spacer()
                Text("\(burstCount60s)/min")
                    .font(.system(size: 14, weight: .light, design: .serif))
                    .foregroundStyle(.red)
            }
            .padding(IRISTokens.spacing16)
            .background(RoundedRectangle(cornerRadius: IRISTokens.cornerRadiusSmall).fill(Color.red.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: IRISTokens.cornerRadiusSmall).strokeBorder(Color.red.opacity(0.4), lineWidth: 1.5))
            .padding(.horizontal, IRISTokens.spacing16)
            .padding(.vertical, 4)
        }
    }

    // v1.235 — Active filters chip row (removable per chip)
    @ViewBuilder
    private var activeFiltersChips: some View {
        let hasActiveFilters: Bool = !filterAgent.isEmpty || !filterKind.isEmpty || !filterLevel.isEmpty || filterCorrelationId != nil || !searchText.isEmpty || pastHourOnly
        if hasActiveFilters {
            HStack(spacing: 6) {
                Text("Active:")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                if !filterAgent.isEmpty {
                    filterChip("agent: \(filterAgent)", color: IRISTokens.irisAccent) { filterAgent = "" }
                }
                if !filterKind.isEmpty {
                    filterChip("kind: \(filterKind)", color: IRISTokens.aquaTint) { filterKind = "" }
                }
                if !filterLevel.isEmpty {
                    filterChip("level: \(filterLevel)", color: .secondary) { filterLevel = "" }
                }
                if let cid = filterCorrelationId {
                    filterChip("corr: \(cid.uuidString.prefix(8))", color: IRISTokens.aquaTint) { filterCorrelationId = nil }
                }
                if !searchText.isEmpty {
                    filterChip("search: \(searchText)", color: .secondary) { searchText = "" }
                }
                if pastHourOnly {
                    filterChip("past 1h", color: IRISTokens.aquaTint) { pastHourOnly = false }
                }
                Spacer()
            }
            .padding(.horizontal, IRISTokens.spacing16)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.05))
        }
    }

    private func filterChip(_ label: String, color: Color, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(color.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(Capsule().fill(color.opacity(0.12)))
    }

    // v1.243 — Since launch: uptime + event count since bootstrap
    var sinceLaunchStats: (uptime: String, eventCount: Int) {
        guard let bootstrapAt = IRISRuntimeInfo.bootstrapAt else {
            return ("—", 0)
        }
        let uptime = Date().timeIntervalSince(bootstrapAt)
        let formatted: String
        if uptime < 60 {
            formatted = "\(Int(uptime))s"
        } else if uptime < 3600 {
            formatted = "\(Int(uptime / 60))m \(Int(uptime.truncatingRemainder(dividingBy: 60)))s"
        } else {
            formatted = "\(Int(uptime / 3600))h \(Int((uptime.truncatingRemainder(dividingBy: 3600)) / 60))m"
        }
        let count = allEvents.filter { $0.timestamp >= bootstrapAt }.count
        return (formatted, count)
    }

    @ViewBuilder
    private var sinceLaunchBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "power")
                .font(.system(size: 10))
                .foregroundStyle(IRISTokens.aquaTint.opacity(0.7))
            Text("Since launch: \(sinceLaunchStats.uptime) · \(sinceLaunchStats.eventCount) events")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: "list.bullet.rectangle")
                .foregroundStyle(.secondary)
            Text("Logs runtime")
                .font(.system(size: 22, weight: .light, design: .serif))
            Spacer()
            Text("\(filtered.count)/\(allEvents.count)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            sinceLaunchBadge
            if isPaused {
                Text("PAUSED")
                    .font(.system(size: 9, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(IRISTokens.goldAccent)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(IRISTokens.goldAccent.opacity(0.15)))
            }
        }
        .padding(.horizontal, IRISTokens.spacing24)
        .padding(.vertical, IRISTokens.spacing16)
    }

    private var filtersBar: some View {
        HStack(spacing: IRISTokens.spacing8) {
            Picker("Agent", selection: $filterAgent) {
                Text("Tous agents").tag("")
                ForEach(AgentID.allCases, id: \.rawValue) { agent in
                    Text(agent.descriptor.displayName).tag(agent.rawValue)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(maxWidth: 180)

            Picker("Kind", selection: $filterKind) {
                Text("Tous events").tag("")
                ForEach(Self.kindOrder, id: \.self) { kind in
                    Text(kind).tag(kind)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(maxWidth: 180)

            // v1.28 — Filter par level (applies aux systemLog events principalement)
            Picker("Level", selection: $filterLevel) {
                Text("Tous levels").tag("")
                ForEach(Self.levelOrder, id: \.self) { level in
                    Text(level).tag(level)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(maxWidth: 120)

            HStack(spacing: 4) {
                TextField("Search payload / kind…", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .focused($searchFieldFocused)
                    .frame(maxWidth: 300)
                    .onSubmit { recordSearch(searchText) }  // v1.278
                // v1.278 — Recent searches dropdown
                Menu {
                    if searchHistory.isEmpty {
                        Text("Pas d'historique").disabled(true)
                    } else {
                        ForEach(searchHistory, id: \.self) { item in
                            Button(item) { searchText = item }
                        }
                        Divider()
                        Button("Clear history") { searchHistoryCSV = "" }
                    }
                } label: {
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 11))
                }
                .controlSize(.small)
                .menuStyle(.borderlessButton)
                .frame(width: 24)
                .help("Historique des recherches récentes")
                Text("⌘F")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary.opacity(0.5))
            }

            // v1.224 — Paste UUID inline TextField → set filterCorrelationId on Enter
            TextField("Paste UUID", text: $correlationPaste)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .frame(maxWidth: 90)
                .onSubmit {
                    let trimmed = correlationPaste.trimmingCharacters(in: .whitespaces)
                    if let uuid = UUID(uuidString: trimmed) {
                        filterCorrelationId = uuid
                        correlationPaste = ""
                    }
                }
                .help("Paste un correlation UUID + Enter pour filter sur cette chaîne")

            // v1.70 — Correlation badge si actif
            if let cid = filterCorrelationId {
                HStack(spacing: 3) {
                    Image(systemName: "link")
                        .font(.system(size: 10))
                        .foregroundStyle(IRISTokens.aquaTint)
                    Text(cid.uuidString.prefix(8))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(IRISTokens.aquaTint)
                    Button {
                        filterCorrelationId = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(IRISTokens.aquaTint.opacity(0.12))
                .clipShape(Capsule())
            }

            Button {
                filterAgent = ""
                filterKind = ""
                filterLevel = ""
                filterCorrelationId = nil
                searchText = ""
                pastHourOnly = false
            } label: {
                HStack(spacing: 4) {
                    Text("Clear")
                    Text("⌘L")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary.opacity(0.7))
                        .padding(.horizontal, 3)
                        .padding(.vertical, 0.5)
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .strokeBorder(Color.secondary.opacity(0.4), lineWidth: 0.5)
                        )
                }
            }
            .controlSize(.small)
            .disabled(filterAgent.isEmpty && filterKind.isEmpty && filterLevel.isEmpty && filterCorrelationId == nil && searchText.isEmpty && !pastHourOnly)
            .keyboardShortcut(KeyEquivalent("l"), modifiers: .command)
            .help("Reset tous les filtres (Cmd+L)")

            // v1.175 — Pause toggle (freeze view to snapshot)
            Button {
                togglePause()
            } label: {
                Label(isPaused ? "Resume" : "Pause", systemImage: isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 11))
            }
            .controlSize(.small)
            .tint(isPaused ? IRISTokens.goldAccent : .secondary)
            .help(isPaused ? "Resume live log updates" : "Pause les logs au snapshot actuel (figer la vue)")

            // v1.161 — Dispatches quick filter
            Button {
                filterKind = "agentDispatched"
            } label: {
                Label("Dispatches", systemImage: "arrow.right.circle")
                    .font(.system(size: 11))
            }
            .controlSize(.small)
            .tint(IRISTokens.irisAccent)
            .help("Filter rapide : show only agentDispatched events")

            // v1.184 — Failures-only quick filter
            Button {
                filterKind = "agentFailure"
            } label: {
                Label("Failures", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
            }
            .controlSize(.small)
            .tint(.red)
            .help("Filter rapide : show only agentFailure events")

            // v1.206 — Past hour quick filter
            Button {
                pastHourOnly.toggle()
            } label: {
                Label(pastHourOnly ? "All time" : "Past 1h", systemImage: pastHourOnly ? "clock.arrow.circlepath" : "clock")
                    .font(.system(size: 11))
            }
            .controlSize(.small)
            .tint(pastHourOnly ? IRISTokens.aquaTint : .secondary)
            .help(pastHourOnly ? "Show all-time events" : "Limit to past 60 minutes")

            // v1.263 — Sort direction toggle
            Button {
                sortAscending.toggle()
            } label: {
                Label(sortAscending ? "Asc" : "Desc", systemImage: sortAscending ? "arrow.up" : "arrow.down")
                    .font(.system(size: 11))
            }
            .controlSize(.small)
            .tint(.secondary)
            .help(sortAscending ? "Sort oldest first → newest" : "Sort newest first → oldest")

            // v1.39 — Export filtered logs Markdown
            Button {
                exportFilteredLogs()
            } label: {
                Label("Export MD", systemImage: "square.and.arrow.up")
                    .font(.system(size: 11))
            }
            .controlSize(.small)
            .help("Export les events filtrés en Markdown")

            // v1.203 — Export filtered logs CSV
            Button {
                exportFilteredLogsCSV()
            } label: {
                Label("CSV", systemImage: "tablecells")
                    .font(.system(size: 11))
            }
            .controlSize(.small)
            .help("Export filtered events en CSV (timestamp,kind,from,to,correlationId,payload)")

            // v1.256 — Export filtered logs JSON
            Button {
                exportFilteredLogsJSON()
            } label: {
                Label("JSON", systemImage: "doc.text")
                    .font(.system(size: 11))
            }
            .controlSize(.small)
            .help("Export filtered events en JSON array")

            if let status = exportStatus {
                Text(status)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(status.hasPrefix("✅") ? .green : .red)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, IRISTokens.spacing16)
        .padding(.vertical, IRISTokens.spacing8)
        .background(.thinMaterial)
    }

    private var logsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                if filtered.isEmpty {
                    Text(allEvents.isEmpty
                        ? "Aucun event pour l'instant. Le bus s'alimente au fil de l'activité agents."
                        : "Aucun event ne match les filtres.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(IRISTokens.spacing24)
                } else {
                    ForEach(filtered) { event in
                        logRow(event)
                    }
                }
            }
            .padding(IRISTokens.spacing8)
        }
    }

    private func logRow(_ event: EventLog) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Rectangle()
                .fill(severityColor(for: event))
                .frame(width: 3)
                .cornerRadius(1.5)
            Text(event.timestamp, format: .dateTime.hour().minute().second())
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)

            kindBadge(event.kind)
                .frame(width: 120, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    if let from = event.fromAgent {
                        Text(from)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(IRISTokens.irisAccent)
                    }
                    if let to = event.toAgent {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                        Text(to)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(IRISTokens.aquaTint)
                    }
                    // v1.70 — Correlation badge clickable
                    if let cid = event.correlationId {
                        Spacer()
                        Button {
                            filterCorrelationId = cid
                        } label: {
                            HStack(spacing: 2) {
                                Image(systemName: "link")
                                Text(cid.uuidString.prefix(8))
                            }
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(IRISTokens.aquaTint.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        .help("Filter par cette correlation chain")
                    }
                }
                Text(payloadPreview(event.payloadJSON))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.75))
                    .lineLimit(2)
                    .textSelection(.enabled)
            }

            Spacer()

            // v1.270 — Per-row filter-by-correlation link button (right edge)
            if let cid = event.correlationId {
                Button {
                    filterCorrelationId = cid
                } label: {
                    Image(systemName: "link")
                        .font(.system(size: 9))
                        .foregroundStyle(filterCorrelationId == cid ? IRISTokens.aquaTint : .secondary.opacity(0.4))
                }
                .buttonStyle(.plain)
                .help("Filter logs to this correlation chain")
                .disabled(filterCorrelationId == cid)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 4).fill(.thinMaterial))
    }

    private func kindBadge(_ kind: String) -> some View {
        let (color, icon): (Color, String) = {
            switch kind {
            case "userInput": return (IRISTokens.aquaTint, "person.fill")
            case "agentDispatched": return (IRISTokens.irisAccent, "arrow.right.circle")
            case "agentResponse": return (.green, "checkmark.circle")
            case "signalEmitted": return (IRISTokens.goldAccent, "eye.circle")
            case "draftReady": return (IRISTokens.irisAccent, "pencil.and.scribble")
            case "actionRequested": return (IRISTokens.goldAccent, "hand.raised")
            case "actionApproved": return (.green, "checkmark.shield")
            case "actionRejected": return (.red, "xmark.shield")
            case "actionExecuted": return (.green, "bolt.fill")
            case "agentFailure": return (.red, "exclamationmark.triangle.fill")
            case "systemLog": return (.secondary, "doc.text")
            default: return (.secondary, "circle")
            }
        }()
        return HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(color)
            Text(kind)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
        }
    }

    private func severityColor(for event: EventLog) -> Color {
        if event.kind == "agentFailure" { return .red }
        if event.kind == "actionRejected" { return .red }
        if event.kind == "actionApproved" || event.kind == "actionExecuted" { return .green }
        if event.kind == "signalEmitted" { return IRISTokens.goldAccent }
        if event.payloadJSON.contains("\"level\":\"error\"") || event.payloadJSON.contains("\"level\":\"fault\"") { return .red }
        if event.payloadJSON.contains("\"level\":\"warning\"") { return IRISTokens.goldAccent }
        if event.payloadJSON.contains("\"level\":\"notice\"") { return IRISTokens.aquaTint }
        return .clear
    }

    private func payloadPreview(_ json: String) -> String {
        // Cap à 200 chars, strip multiline pour rester compact
        let trimmed = json.replacingOccurrences(of: "\n", with: " ")
        return String(trimmed.prefix(200))
    }

    private func exportFilteredLogs() {
        do {
            let url = try BackupService.exportEventLogsAsMarkdown(filtered)
            exportStatus = "✅ → \(url.lastPathComponent)"
            // Clear status après 5s
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                exportStatus = nil
            }
        } catch {
            exportStatus = "⚠️ \(error.localizedDescription)"
        }
    }

    // v1.203 — CSV export of currently-filtered events
    private func exportFilteredLogsCSV() {
        let iso = ISO8601DateFormatter()
        var csv = "timestamp,kind,from_agent,to_agent,correlation_id,payload_short\n"
        for event in filtered {
            let ts = iso.string(from: event.timestamp)
            let payloadEscaped = String(event.payloadJSON.prefix(200))
                .replacingOccurrences(of: "\"", with: "\"\"")
                .replacingOccurrences(of: "\n", with: " ")
            csv += "\(ts),\(event.kind),\(event.fromAgent ?? ""),\(event.toAgent ?? ""),\(event.correlationId?.uuidString ?? ""),\"\(payloadEscaped)\"\n"
        }
        let isoSafe = iso.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("iris-logs-\(isoSafe).csv")
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            exportStatus = "✅ → \(url.lastPathComponent)"
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                exportStatus = nil
            }
        } catch {
            exportStatus = "⚠️ \(error.localizedDescription)"
        }
    }

    // v1.256 — JSON export of currently-filtered events (JSON array of objects)
    private func exportFilteredLogsJSON() {
        let iso = ISO8601DateFormatter()
        let jsonArray = filtered.map { event -> [String: Any] in
            var dict: [String: Any] = [
                "timestamp": iso.string(from: event.timestamp),
                "kind": event.kind
            ]
            if let from = event.fromAgent { dict["fromAgent"] = from }
            if let to = event.toAgent { dict["toAgent"] = to }
            if let cid = event.correlationId { dict["correlationId"] = cid.uuidString }
            if !event.payloadJSON.isEmpty { dict["payloadJSON"] = event.payloadJSON }
            return dict
        }
        let isoSafe = iso.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("iris-logs-\(isoSafe).json")
        do {
            let data = try JSONSerialization.data(withJSONObject: jsonArray, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: .atomic)
            exportStatus = "✅ → \(url.lastPathComponent)"
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                exportStatus = nil
            }
        } catch {
            exportStatus = "⚠️ \(error.localizedDescription)"
        }
    }
}

#Preview {
    LogsView()
        .frame(width: 800, height: 500)
}

import SwiftUI
import SwiftData

// IRIS v1.16 — Panel logs runtime affiché quand sidebar System > Logs sélectionné.
// @Query EventLog sorted desc + filtres par agent + kind + search.

struct LogsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \EventLog.timestamp, order: .reverse) private var allEvents: [EventLog]

    @State private var filterAgent: String = ""
    @State private var filterKind: String = ""
    @State private var filterLevel: String = ""
    @State private var searchText: String = ""

    private static let kindOrder = [
        "userInput", "agentDispatched", "agentResponse",
        "signalEmitted", "draftReady", "actionRequested",
        "actionApproved", "actionRejected", "actionExecuted",
        "actionLogged", "agentFailure", "systemLog", "conductorChunk"
    ]

    private static let levelOrder = ["debug", "info", "notice", "warning", "error", "fault"]

    var filtered: [EventLog] {
        allEvents.lazy
            .filter { filterAgent.isEmpty || $0.fromAgent == filterAgent || $0.toAgent == filterAgent }
            .filter { filterKind.isEmpty || $0.kind == filterKind }
            .filter { filterLevel.isEmpty || $0.payloadJSON.contains("\"level\":\"\(filterLevel)\"") }
            .filter { searchText.isEmpty || $0.payloadJSON.localizedCaseInsensitiveContains(searchText) || $0.kind.localizedCaseInsensitiveContains(searchText) }
            .prefix(500)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            filtersBar
            Divider()
            logsList
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

            TextField("Search payload / kind…", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .frame(maxWidth: 300)

            Button("Clear") {
                filterAgent = ""
                filterKind = ""
                filterLevel = ""
                searchText = ""
            }
            .controlSize(.small)
            .disabled(filterAgent.isEmpty && filterKind.isEmpty && filterLevel.isEmpty && searchText.isEmpty)

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
                }
                Text(payloadPreview(event.payloadJSON))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.75))
                    .lineLimit(2)
                    .textSelection(.enabled)
            }

            Spacer()
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

    private func payloadPreview(_ json: String) -> String {
        // Cap à 200 chars, strip multiline pour rester compact
        let trimmed = json.replacingOccurrences(of: "\n", with: " ")
        return String(trimmed.prefix(200))
    }
}

#Preview {
    LogsView()
        .frame(width: 800, height: 500)
}

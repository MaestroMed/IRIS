import SwiftUI
import SwiftData

// IRIS v0.5 — Inspector droit avec sections : Actions en attente, Drafts récents, Signals récents, Agent détail.

struct InspectorView: View {
    @Environment(IRISAppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Draft.createdAt, order: .reverse) private var allDrafts: [Draft]
    @Query(sort: \Signal.emittedAt, order: .reverse) private var allSignals: [Signal]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: IRISTokens.spacing24) {
                if !appState.pendingActions.isEmpty {
                    pendingActionsSection
                }

                draftsSection

                signalsSection

                if appState.selectedAgent != nil {
                    Divider().padding(.vertical, IRISTokens.spacing4)
                    agentSelectionDetails
                }

                Spacer(minLength: 0)
            }
            .padding(IRISTokens.spacing16)
        }
        .scrollContentBackground(.hidden)
        .background(
            ZStack {
                Rectangle().fill(.regularMaterial)
                IRISTokens.skyBackground.opacity(0.18)
            }
            .ignoresSafeArea()
        )
        .navigationSplitViewColumnWidth(
            min: IRISTokens.inspectorMinWidth,
            ideal: IRISTokens.inspectorIdealWidth,
            max: IRISTokens.inspectorMaxWidth
        )
    }

    // MARK: — Pending actions

    private var pendingActionsSection: some View {
        VStack(alignment: .leading, spacing: IRISTokens.spacing8) {
            sectionHeader("Actions en attente", count: appState.pendingActions.count, accent: .red)

            ForEach(appState.pendingActions) { action in
                pendingActionCard(action)
            }
        }
    }

    private func pendingActionCard(_ action: PendingActionUI) -> some View {
        VStack(alignment: .leading, spacing: IRISTokens.spacing8) {
            HStack(spacing: 4) {
                Image(systemName: action.isReversible ? "arrow.uturn.left.circle" : "exclamationmark.triangle.fill")
                    .foregroundStyle(action.isReversible ? IRISTokens.aquaTint : IRISTokens.goldAccent)
                Text(action.agentName)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(action.isReversible ? "réversible" : "irréversible")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(action.isReversible ? .secondary : IRISTokens.goldAccent)
            }

            Text(action.summary)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: IRISTokens.spacing8) {
                Button("Approve") {
                    Task {
                        await EventBus.shared.publish(
                            .actionApproved(actionId: action.actionId, approvedAt: .now)
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(IRISTokens.irisAccent)

                Button("Reject") {
                    Task {
                        await EventBus.shared.publish(
                            .actionRejected(actionId: action.actionId, reason: nil)
                        )
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.red)

                Spacer()
            }
        }
        .padding(IRISTokens.spacing12OrFallback)
        .background(
            RoundedRectangle(cornerRadius: IRISTokens.cornerRadiusMedium)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: IRISTokens.cornerRadiusMedium)
                .strokeBorder(IRISTokens.goldAccent.opacity(0.3), lineWidth: 0.5)
        )
    }

    // MARK: — Drafts

    private var draftsSection: some View {
        let drafts = Array(allDrafts.prefix(5))
        return VStack(alignment: .leading, spacing: IRISTokens.spacing8) {
            sectionHeader("Drafts récents", count: drafts.count, accent: .secondary)

            if drafts.isEmpty {
                Text("Pas encore de drafts.\nQuill se déclenche sur signaux ≥ high.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(drafts) { draft in
                    draftRow(draft)
                }
            }
        }
    }

    private func draftRow(_ draft: Draft) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: channelIcon(draft.channel))
                    .font(.system(size: 11))
                    .foregroundStyle(IRISTokens.irisAccent)
                Text(draft.subject ?? draft.content.prefix(50).description)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Spacer()
                statusBadge(draft.status)
            }
            HStack(spacing: IRISTokens.spacing8) {
                Text(draft.tone)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(draft.createdAt, format: .dateTime.hour().minute().second())
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("$\(String(format: "%.5f", draft.costUSD))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, IRISTokens.spacing8)
        .background(
            RoundedRectangle(cornerRadius: IRISTokens.cornerRadiusSmall)
                .fill(.thinMaterial)
        )
    }

    // MARK: — Signals

    private var signalsSection: some View {
        let signals = Array(allSignals.prefix(8))
        return VStack(alignment: .leading, spacing: IRISTokens.spacing8) {
            sectionHeader("Signals récents (Sentinel)", count: signals.count, accent: .secondary)

            if signals.isEmpty {
                Text("Sentinel démarre dans quelques secondes…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(signals) { signal in
                    signalRow(signal)
                }
            }
        }
    }

    private func signalRow(_ signal: Signal) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: IRISTokens.spacing8) {
            importanceDot(signal.importance)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(signal.source.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    if let project = signal.projectScope {
                        Text("· \(project)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(IRISTokens.irisAccent)
                    }
                    Spacer()
                    Text(signal.emittedAt, format: .dateTime.hour().minute().second())
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Text(signal.summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: — Agent selected

    private var agentSelectionDetails: some View {
        Group {
            if let agentId = appState.selectedAgent {
                let descriptor = agentId.descriptor
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: descriptor.symbol)
                            .foregroundStyle(IRISTokens.irisAccent)
                        Text(descriptor.displayName)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    Text(descriptor.alias).font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(descriptor.tagline).font(.system(size: 11)).foregroundStyle(.primary.opacity(0.8))
                }
            } else {
                EmptyView()
            }
        }
    }

    // MARK: — Helpers

    private func sectionHeader(_ title: String, count: Int, accent: Color) -> some View {
        HStack(spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(.secondary)
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(accent)
            }
            Spacer()
        }
        .padding(.horizontal, IRISTokens.spacing4)
    }

    private func channelIcon(_ channel: String) -> String {
        switch channel {
        case "email": return "envelope"
        case "slack": return "bubble.left.and.bubble.right"
        case "github_comment": return "bubble.left.circle"
        default: return "doc.text"
        }
    }

    private func statusBadge(_ status: String) -> some View {
        let color: Color = {
            switch status {
            case "sent": return .green
            case "approved": return IRISTokens.aquaTint
            case "rejected", "failed": return .red
            default: return .secondary
            }
        }()
        return Text(status)
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func importanceDot(_ importance: Int) -> some View {
        let color: Color = {
            switch importance {
            case 5: return .red
            case 4: return IRISTokens.goldAccent
            case 3: return IRISTokens.irisAccent
            case 2: return IRISTokens.aquaTint
            default: return .secondary
            }
        }()
        return Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .padding(.top, 4)
    }
}

extension IRISTokens {
    /// Fallback alias pour ancien naming `spacing12` (n'existe pas dans la grille 4/8/16/24/32/48).
    /// Mappé sur spacing16 pour cohérence visuelle.
    public static let spacing12OrFallback: CGFloat = spacing16 * 0.75
}

#Preview {
    InspectorView()
        .environment(IRISAppState())
        .frame(width: 320, height: 600)
}

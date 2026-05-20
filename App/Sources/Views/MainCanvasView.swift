import SwiftUI
import SwiftData

// IRIS v0.0.5 + v1.7 — main canvas central avec Conductor live (TextField + transcript).
// Si un agent est sélectionné dans la sidebar (autre que Conductor), affiche placeholder spécifique.
// Sinon, affiche la conversation Conductor.
// v1.7 : footer compteurs live (Memory + Signal + Draft + ProjectRecord + AuditReport).

struct MainCanvasView: View {
    @Environment(IRISAppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    @Query private var allMemories: [Memory]
    @Query private var allSignalsCount: [Signal]
    @Query private var allDraftsCount: [Draft]
    @Query private var allProjectsCount: [ProjectRecord]
    @Query private var allAuditsCount: [AuditReport]

    var body: some View {
        ZStack {
            Color.clear

            VStack(spacing: 0) {
                header

                Divider()

                content

                Divider()

                footerStats
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("")
        .toolbarBackground(.hidden, for: .windowToolbar)
    }

    // MARK: — v1.7 Footer compteurs live

    private var footerStats: some View {
        HStack(spacing: IRISTokens.spacing16) {
            statBadge(label: "memories", count: allMemories.count, icon: "books.vertical", color: IRISTokens.irisAccent)
            statBadge(label: "signals", count: allSignalsCount.count, icon: "eye.circle", color: IRISTokens.aquaTint)
            statBadge(label: "drafts", count: allDraftsCount.count, icon: "pencil.and.scribble", color: IRISTokens.irisAccent)
            statBadge(label: "projects", count: allProjectsCount.count, icon: "map", color: IRISTokens.goldAccent)
            statBadge(label: "audits", count: allAuditsCount.count, icon: "checkmark.shield", color: .green)
            Spacer()
            Text("IRIS v1.7 · 10 agents")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, IRISTokens.spacing16)
        .padding(.vertical, IRISTokens.spacing8)
        .background(.thinMaterial)
    }

    private func statBadge(label: String, count: Int, icon: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(color)
            Text("\(count)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: — Header (titre + agent actif + cost)

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("IRIS")
                .font(.system(size: 28, weight: .light, design: .serif))
                .foregroundStyle(IRISTokens.irisAccent)
                .tracking(4)

            if let agent = appState.selectedAgent {
                Text("·")
                    .foregroundStyle(.secondary.opacity(0.5))
                Text(agent.descriptor.displayName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                Text(agent.descriptor.alias)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if appState.isProcessing {
                ProgressView()
                    .controlSize(.small)
            }

            if appState.hasAnthropicKey {
                Label("Claude Opus 4.7", systemImage: "sparkle")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else {
                Label("Mode mock — pas d'API key", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(IRISTokens.goldAccent)
            }

            Text("$\(String(format: "%.4f", appState.sessionCostUSD))")
                .font(IRISTokens.monoFont)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, IRISTokens.spacing24)
        .padding(.vertical, IRISTokens.spacing16)
    }

    // MARK: — Content (placeholder par agent, ou conversation Conductor, ou dashboard global)

    @ViewBuilder
    private var content: some View {
        switch appState.selection {
        case .some(.agent(.conductor)):
            conductorConversation
        case .none:
            // v1.10 — aucun agent sélectionné = dashboard global stats
            DashboardView()
        case .some(.agent(let agent)):
            agentPlaceholder(agent.descriptor)
        case .some(.system(let dest)):
            systemPanel(dest)
        }
    }

    private var conductorConversation: some View {
        VStack(spacing: 0) {
            transcriptView
            Divider()
            inputBar
        }
    }

    private var transcriptView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: IRISTokens.spacing16) {
                    if appState.transcript.isEmpty && appState.streamingText.isEmpty {
                        emptyTranscriptHint
                    }
                    ForEach(appState.transcript) { entry in
                        TranscriptRow(entry: entry)
                            .id(entry.id)
                    }
                    // v1.17 — entry streaming live (en cours de génération)
                    if !appState.streamingText.isEmpty {
                        TranscriptRow(entry: TranscriptEntry(
                            role: .agent(.conductor),
                            content: appState.streamingText
                        ))
                        .opacity(0.85)
                        .overlay(alignment: .trailing) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11))
                                .foregroundStyle(IRISTokens.irisAccent)
                                .symbolEffect(.pulse, options: .repeating)
                                .padding(.trailing, IRISTokens.spacing8)
                        }
                        .id("streaming-entry")
                    }
                }
                .padding(IRISTokens.spacing24)
            }
            .onChange(of: appState.transcript.last?.id) { _, lastId in
                if let lastId {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
            .onChange(of: appState.streamingText.count) { _, _ in
                if !appState.streamingText.isEmpty {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("streaming-entry", anchor: .bottom)
                    }
                }
            }
        }
    }

    private var emptyTranscriptHint: some View {
        VStack(spacing: IRISTokens.spacing8) {
            Image(systemName: "wand.and.rays")
                .font(.system(size: 32, weight: .ultraLight))
                .foregroundStyle(IRISTokens.irisAccent.opacity(0.6))
            Text("Conductor en attente.")
                .font(.system(size: 16, weight: .light, design: .serif))
                .foregroundStyle(.primary.opacity(0.8))
            Text(appState.hasAnthropicKey
                ? "Tape ton intent en bas. Conductor route via Claude Opus 4.7."
                : "Pas de clé Anthropic. Settings → ajoute ta clé pour activer le LLM. Sans clé, échantillon mock."
            )
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, IRISTokens.spacing48)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var inputBar: some View {
        @Bindable var binding = appState

        HStack(alignment: .center, spacing: IRISTokens.spacing8) {
            TextField("Tape ton intent (Cmd+Enter pour envoyer)…", text: $binding.currentInput, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .lineLimit(1...5)
                .onSubmit(submitInput)
                .padding(IRISTokens.spacing16)
                .background(
                    RoundedRectangle(cornerRadius: IRISTokens.cornerRadiusMedium)
                        .fill(.regularMaterial)
                )

            Button(action: submitInput) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(canSubmit ? IRISTokens.irisAccent : .secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!canSubmit)
        }
        .padding(IRISTokens.spacing16)
    }

    private var canSubmit: Bool {
        !appState.currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !appState.isProcessing
    }

    private func submitInput() {
        let text = appState.currentInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !appState.isProcessing else { return }

        appState.appendEntry(TranscriptEntry(role: .user, content: text))
        appState.currentInput = ""
        appState.isProcessing = true

        Task {
            await EventBus.shared.publish(.userInput(text, timestamp: Date()))
        }
    }

    // MARK: — Placeholders agents non-Conductor

    private func agentPlaceholder(_ descriptor: AgentDescriptor) -> some View {
        VStack(spacing: IRISTokens.spacing16) {
            Spacer()
            Image(systemName: descriptor.symbol)
                .font(.system(size: 44, weight: .ultraLight))
                .foregroundStyle(IRISTokens.irisAccent)
            Text(descriptor.displayName)
                .font(.system(size: 28, weight: .light, design: .serif))
                .foregroundStyle(.primary)
            Text(descriptor.tagline)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("Runtime à venir — \(plannedVersion(for: descriptor.id))")
                .font(IRISTokens.monoFont)
                .foregroundStyle(IRISTokens.goldAccent.opacity(0.85))
                .padding(.top, IRISTokens.spacing8)
            Spacer()
        }
        .padding(IRISTokens.spacing32)
    }

    private func plannedVersion(for id: AgentID) -> String {
        switch id {
        case .conductor: return "v0.1 (live)"
        case .scribe: return "v0.2"
        case .sentinel: return "v0.3"
        case .quill: return "v0.4"
        case .envoy: return "v0.5"
        case .cartographer: return "v0.6"
        case .auditor: return "v0.7"
        case .builder: return "v0.8"
        case .advisor: return "v0.9"
        case .witness: return "v1.5"
        case .system: return "—"
        }
    }

    // MARK: — System panel

    @ViewBuilder
    private func systemPanel(_ destination: SystemDestination) -> some View {
        switch destination {
        case .logs:
            // v1.16 — vraie panel logs runtime (EventLog SwiftData query)
            LogsView()
        }
    }
}

// MARK: — Transcript row

struct TranscriptRow: View {
    let entry: TranscriptEntry
    var compact: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: IRISTokens.spacing8) {
            roleBadge

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: IRISTokens.spacing8) {
                    Text(entry.role.displayName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(roleColor)
                    Text(entry.timestamp, format: .dateTime.hour().minute().second())
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Text(entry.content)
                    .font(.system(size: compact ? 12 : 14))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, compact ? 0 : IRISTokens.spacing4)
    }

    private var roleBadge: some View {
        Circle()
            .fill(roleColor)
            .frame(width: 6, height: 6)
            .padding(.top, 6)
    }

    private var roleColor: Color {
        switch entry.role {
        case .user: return IRISTokens.aquaTint
        case .agent: return IRISTokens.irisAccent
        case .system(let level):
            return level.contains("error") ? .red : .secondary
        }
    }
}

#Preview {
    MainCanvasView()
        .environment(IRISAppState())
        .frame(width: 800, height: 600)
}

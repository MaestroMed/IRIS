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

    @State private var placeholderIndex: Int = 0  // v1.146
    private let placeholderTimer = Timer.publish(every: 4, on: .main, in: .common).autoconnect()

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
        // v1.146 — Cycle placeholder examples toutes les 4s
        .onReceive(placeholderTimer) { _ in
            placeholderIndex = (placeholderIndex + 1) % Self.rotatingPlaceholders.count
        }
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
                // v1.54 — Stop generation button (cancel SSE stream)
                Button {
                    Task { await Conductor.shared.cancelCurrentResponse() }
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Arrêter la génération en cours")
                .keyboardShortcut(".", modifiers: .command)
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

            // v1.57 — Régénérer la dernière réponse
            Button {
                Task { _ = await Conductor.shared.regenerateLastResponse() }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .help("Régénérer la dernière réponse Conductor")
            .disabled(appState.transcript.count < 2 || appState.isProcessing)

            // v1.76 — Save conversation comme Memory
            Button {
                saveConversationAsMemory()
            } label: {
                Image(systemName: "bookmark.circle")
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .help("Sauver la conversation comme Memory (indexée Scribe)")
            .disabled(appState.transcript.isEmpty)

            // v1.19 — Bouton clear conversation (Nouvelle session)
            Button {
                Task {
                    await Conductor.shared.resetHistory()
                    appState.clearTranscript()
                }
            } label: {
                Image(systemName: "arrow.counterclockwise.circle")
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .help("Nouvelle conversation (clear history + transcript)")
            .disabled(appState.transcript.isEmpty)
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

            // v1.132 — Hint dispatch help
            Text("Tape `?` pour voir les commands directes (audit / scaffold / cherche / briefing…)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(IRISTokens.aquaTint.opacity(0.8))
                .padding(.top, IRISTokens.spacing4)
        }
        .padding(.vertical, IRISTokens.spacing48)
        .frame(maxWidth: .infinity)
    }

    // v1.146 — Placeholder qui cycle entre exemples de commandes (4s intervalle)
    private static let rotatingPlaceholders: [String] = [
        "Tape ton intent (Cmd+Enter)…",
        "? — voir les commandes directes",
        "audit atelier_frisson — déclenche Auditor",
        "cherche Numelite — Scribe top 5",
        "drafte réponse Odelie — Quill draft",
        "scaffold nouveau_projet — Builder",
        "briefing — Advisor Opus maintenant",
        "snapshot — Witness vision capture",
        "/clear — reset conversation"
    ]

    @ViewBuilder
    private var inputBar: some View {
        @Bindable var binding = appState

        HStack(alignment: .center, spacing: IRISTokens.spacing8) {
            TextField(Self.rotatingPlaceholders[placeholderIndex], text: $binding.currentInput, axis: .vertical)
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

            // v1.90 — Clear input (Cmd+Backspace shortcut hidden button)
            Button {
                appState.currentInput = ""
            } label: {
                EmptyView()
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(appState.currentInput.isEmpty)
            .opacity(0)
            .frame(width: 0, height: 0)
        }
        .padding(IRISTokens.spacing16)
    }

    private var canSubmit: Bool {
        !appState.currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !appState.isProcessing
    }

    // v1.76 — Save conversation comme Memory persistante (indexée Scribe)
    private func saveConversationAsMemory() {
        guard !appState.transcript.isEmpty else { return }
        let entries = appState.transcript
        let firstUser = entries.first(where: { if case .user = $0.role { return true } else { return false } })?.content ?? "(no user input)"
        let summary = String(firstUser.prefix(120))

        var content = ""
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd HH:mm"
        content += "# Conversation \(dateFmt.string(from: Date()))\n\n"
        for entry in entries {
            let role: String = {
                switch entry.role {
                case .user: return "User"
                case .agent(let agentId): return agentId.descriptor.displayName
                case .system(let level): return "System(\(level))"
                }
            }()
            content += "**\(role)** : \(entry.content)\n\n"
        }

        let memory = Memory(
            type: "conversation-summary",
            name: "conv-summary-\(Int(Date().timeIntervalSince1970))",
            summary: summary,
            content: content,
            sourceAgent: AgentID.conductor.rawValue,
            projectScope: nil,
            tagsCSV: "conversation-summary,manual-save,conductor"
        )

        Task {
            await Scribe.store(memory: memory, in: modelContext)
        }
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
        case .stats:
            // v1.36 — stats Bus events par kind sur 3 fenêtres temporelles
            BusStatsView()
        case .memory:
            // v1.56 — browse Memory + ad-hoc retrieval Scribe
            MemoryBrowserView()
        }
    }
}

// MARK: — Transcript row

struct TranscriptRow: View {
    let entry: TranscriptEntry
    var compact: Bool = false

    var body: some View {
        // v1.139 — Dispatch ack detection : si content commence par un emoji dispatch
        let isDispatchAck = TranscriptRow.startsWithDispatchEmoji(entry.content)
        return HStack(alignment: .top, spacing: IRISTokens.spacing8) {
            roleBadge

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: IRISTokens.spacing8) {
                    Text(entry.role.displayName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(roleColor)
                    if isDispatchAck {
                        Text("dispatch")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(IRISTokens.aquaTint)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(IRISTokens.aquaTint.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    Text(entry.timestamp, format: .dateTime.hour().minute().second())
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                // v1.87 — Render markdown si content contient des marqueurs (#, *, `, [).
                Group {
                    if TranscriptRow.looksLikeMarkdown(entry.content),
                       let attr = try? AttributedString(
                            markdown: entry.content,
                            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
                       ) {
                        Text(attr)
                    } else {
                        Text(entry.content)
                    }
                }
                .font(.system(size: compact ? 12 : 14))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                // v1.139 — Background subtil aqua si dispatch ack
                .padding(isDispatchAck ? 8 : 0)
                .background(
                    isDispatchAck
                        ? RoundedRectangle(cornerRadius: 6).fill(IRISTokens.aquaTint.opacity(0.06))
                        : nil
                )
            }
        }
        .padding(.horizontal, compact ? 0 : IRISTokens.spacing4)
    }

    /// v1.139 — Détecte les ack de dispatch (commencent par emoji spécifique).
    static func startsWithDispatchEmoji(_ s: String) -> Bool {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        let dispatchEmojis = ["📋", "🔨", "☀️", "🗺️", "🧠", "👁️", "✍️", "🧭"]
        return dispatchEmojis.contains(where: { trimmed.hasPrefix($0) })
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

    /// v1.87 — Heuristique légère pour détecter markdown (évite parse cost sur user input plain).
    static func looksLikeMarkdown(_ s: String) -> Bool {
        // Hits typiques : header ##, bullet -/*, fence ```, bold/italic **, lien []()
        return s.contains("##") || s.contains("```") || s.contains("**") ||
               s.contains("\n- ") || s.contains("\n* ") || s.contains("](")
    }
}

#Preview {
    MainCanvasView()
        .environment(IRISAppState())
        .frame(width: 800, height: 600)
}

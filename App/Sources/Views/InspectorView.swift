import SwiftUI
import SwiftData
import AppKit

// IRIS v1.0.A — Inspector dédié par agent sélectionné. Sections globales (pending actions / drafts / signals) toujours visibles.
// + Sections agent-spécifiques quand sélectionné : Cartographer / Auditor / Builder / Advisor.
/// v1.172 — Drafts today counter badge in Quill section header.
/// v1.179 — Witness "Block this app" quick action (appends to blocklist UserDefaults).
/// v1.185 — Export today's drafts MD button in Quill section header.
/// v1.192 — Copy verdict mini button on audit row (NSPasteboard).
/// v1.199 — Drafts past 7d badge (gold calendar.badge.clock) in Quill section header.
/// v1.204 — Cartographer section search field (codename/path/repo).
/// v1.209 — Auditor cost-today badge (gold dollar) in Auditor section header.
/// v1.213 — Audit-now button per Cartographer project row (Auditor.runAudit).
/// v1.218 — Auditor verdict counts past 30d badge (green/yellow/red dots + counts).
/// v1.223 — Bulk "Audit all" button in Cartographer header (sequential 2s delay).
/// v1.228 — Per-draft model tag (Opus/Sonnet/Haiku capsule color-coded).
/// v1.236 — Advisor briefings past 7d count badge (iris sun.max).
/// v1.241 — Witness today captures count badge (aqua eye).
/// v1.244 — Cartographer audited/total badge in section header.
/// v1.247 — Drafts past 30d badge (aqua calendar) after the today/7d badges.
/// v1.248 — Auditor "RED only" quick filter toggle (.red capsule when active).
/// v1.254 — Builder total scaffolds count badge (gold hammer).
/// v1.257 — Envoy pending actions count badge (gold hourglass).
/// v1.260 — Export all audits MD button in Auditor section header.
/// v1.266 — Most audited project badge (gold flame).
/// v1.272 — Drafts/hour avg today badge (aqua speedometer).
/// v1.277 — Scribe retrievals today count badge (aqua magnifyingglass).
/// v1.279 — Scribe "last memory written" relative timestamp row.
/// v1.284 — Quill cost today badge (gold dollar) in section header.
/// v1.290 — Cartographer per-project audit count + latest verdict color dot inline.
/// v1.294 — Cartographer project status Picker (All/Active/Archived/Experimental).
/// v1.299 — Witness most-used app today badge (iris app.fill).
/// v1.305 — Compact mode toggle for InspectorView (collapse all section bodies).
/// v1.311 — Auditor verdict trend stacked bar (30d green/yellow/red ratio).
/// v1.320 — Auditor verdict timeline (chronological dots last 20 audits 30d).
/// v1.326 — Witness "Now:" current frontmost row at top of section.
/// v1.330 — Conductor today stats row (count + last query timestamp).
/// v1.333 — Auditor lifetime cost badge (iris infinity) complement v1.209 today.

struct InspectorView: View {
    @Environment(IRISAppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @State private var pinned = InspectorPinnedSections.shared  // v1.48

    @Query(sort: \Draft.createdAt, order: .reverse) private var allDrafts: [Draft]
    @Query(sort: \Signal.emittedAt, order: .reverse) private var allSignals: [Signal]
    @Query(sort: \ProjectRecord.lastPushAt, order: .reverse) private var allProjects: [ProjectRecord]
    @Query(sort: \AuditReport.createdAt, order: .reverse) private var allAudits: [AuditReport]
    @Query(sort: \ActionLog.executedAt, order: .reverse) private var allActionLogs: [ActionLog]  // v1.97
    @Query private var allMemoriesForScribe: [Memory]  // v1.105
    // v1.32 — derniers briefings Advisor depuis EventLog (kind=agentResponse, fromAgent=advisor)
    @Query(
        filter: #Predicate<EventLog> { $0.kind == "agentResponse" && $0.fromAgent == "advisor" },
        sort: \EventLog.timestamp,
        order: .reverse
    ) private var advisorBriefings: [EventLog]

    // v1.257 — Envoy action lifecycle events (actionRequested/actionApproved/actionRejected)
    // pour calculer le nombre d'actions encore en attente de décision.
    // NB: prédicat `kind.starts(with: "action")` au lieu de `||` triple — `#Predicate` ne digère
    // pas bien la chaîne OR sur SwiftData EventLog.
    @Query(
        filter: #Predicate<EventLog> { $0.kind.starts(with: "action") },
        sort: \EventLog.timestamp,
        order: .reverse
    ) private var allEnvoyEvents: [EventLog]

    // v1.330 — All EventLog entries (used for conductorTodayStats userInput filter)
    @Query(sort: \EventLog.timestamp, order: .reverse) private var allEvents: [EventLog]

    @State private var scaffoldProjectName: String = ""
    @State private var scaffoldSelectedSkill: String = "doc-first-project-scaffolding"
    @State private var auditPickedProject: String = ""
    @State private var auditRedOnly: Bool = false        // v1.248 — Auditor "RED only" quick filter
    @State private var expandedAuditIds: Set<UUID> = []  // v1.62
    @State private var editingDraftId: UUID? = nil       // v1.63
    @State private var draftEditBuffer: String = ""
    @State private var draftStatusFilter: String = ""    // v1.78
    @State private var projectStatusFilter: String = ""  // v1.79
    @State private var showComposeDraft: Bool = false    // v1.85
    @State private var composeSubject: String = ""
    @State private var composeBody: String = ""
    @State private var composeChannel: String = "email"
    @State private var composeTone: String = "formel-fr-client"
    @State private var blockStatus: String? = nil        // v1.179 — Witness block transient feedback
    @State private var exportDraftsStatus: String? = nil // v1.185 — Export today drafts transient feedback
    @State private var copyVerdictStatus: String? = nil  // v1.192 — Copy verdict transient feedback
    @State private var cartographerSearch: String = ""   // v1.204 — Cartographer search field
    @State private var cartoStatusFilter: String = ""    // v1.294 — Cartographer status Picker (All/Active/Archived/Experimental)
    @State private var exportAuditsStatus: String? = nil // v1.260 — Export all audits MD transient feedback
    @AppStorage("inspectorCompactMode") private var compactMode: Bool = false  // v1.305 — collapse all section bodies
    // TODO: wire compactMode to per-section body conditionals

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: IRISTokens.spacing24) {
                HStack {
                    Button {
                        compactMode.toggle()
                    } label: {
                        Label(
                            compactMode ? "Show details" : "Collapse all",
                            systemImage: compactMode ? "rectangle.expand.vertical" : "rectangle.compress.vertical"
                        )
                        .font(.system(size: 11))
                    }
                    .controlSize(.small)
                    .tint(.secondary)
                    .help(compactMode ? "Afficher détails de toutes les sections" : "Cacher les corps de sections (mode compact)")
                    Spacer()
                }
                .padding(.horizontal, IRISTokens.spacing16)
                .padding(.vertical, 4)

                if !appState.pendingActions.isEmpty {
                    pendingActionsSection
                }

                // v1.48 — pinned sections d'abord, puis sélection courante (si non pinned)
                ForEach(pinnedSectionsList, id: \.self) { agentId in
                    agentSectionView(for: agentId)
                }

                if let current = appState.selectedAgent, !pinned.isPinned(current) {
                    agentSectionView(for: current)
                }

                draftsSection

                signalsSection

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
        // v1.85 — Compose draft sheet
        .sheet(isPresented: $showComposeDraft) {
            composeDraftSheet
        }
    }

    // v1.85 — Manual draft compose (bypass Quill LLM call)
    private var composeDraftSheet: some View {
        VStack(alignment: .leading, spacing: IRISTokens.spacing16) {
            HStack {
                Text("Compose draft (manual)")
                    .font(.system(size: 18, weight: .light, design: .serif))
                    .foregroundStyle(IRISTokens.irisAccent)
                Spacer()
                Button("Annuler") { showComposeDraft = false }
                    .keyboardShortcut(.cancelAction)
            }

            HStack(spacing: IRISTokens.spacing8) {
                Picker("Channel", selection: $composeChannel) {
                    Text("email").tag("email")
                    Text("slack").tag("slack")
                    Text("github_comment").tag("github_comment")
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(maxWidth: 140)

                Picker("Tone", selection: $composeTone) {
                    Text("formel-fr-client").tag("formel-fr-client")
                    Text("tech-en-pr").tag("tech-en-pr")
                    Text("casual-fr-team").tag("casual-fr-team")
                    Text("marketing-fr-public").tag("marketing-fr-public")
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(maxWidth: 180)
                Spacer()
            }

            TextField("Subject…", text: $composeSubject)
                .textFieldStyle(.roundedBorder)

            TextEditor(text: $composeBody)
                .font(.system(size: 12, design: .monospaced))
                .frame(minHeight: 180, maxHeight: 360)
                .background(RoundedRectangle(cornerRadius: IRISTokens.cornerRadiusSmall).fill(.thinMaterial))

            HStack {
                Spacer()
                Button("Sauvegarder") {
                    saveComposedDraft()
                    showComposeDraft = false
                }
                .buttonStyle(.borderedProminent)
                .tint(IRISTokens.irisAccent)
                .disabled(composeBody.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(IRISTokens.spacing24)
        .frame(minWidth: 560, minHeight: 480)
    }

    private func saveComposedDraft() {
        let body = composeBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        let subject = composeSubject.trimmingCharacters(in: .whitespaces)
        let draftId = UUID()
        let draft = Draft(
            id: draftId,
            signalId: nil,
            audience: "manual",
            channel: composeChannel,
            tone: composeTone,
            subject: subject.isEmpty ? nil : subject,
            content: body,
            modelUsed: "manual",
            costUSD: 0,
            status: "pending"
        )
        modelContext.insert(draft)
        try? modelContext.save()
        // Reset compose fields
        composeSubject = ""
        composeBody = ""
        // Publish draftReady event pour traçabilité (no signal, mais Envoy peut traiter)
        Task {
            await EventBus.shared.publish(
                .draftReady(draftId: draftId, signalId: nil, channel: composeChannel, summary: subject.isEmpty ? String(body.prefix(80)) : subject)
            )
        }
    }

    // MARK: — Section par agent sélectionné

    // v1.48 — Liste ordonnée des agents épinglés (ordre AgentID.businessAgents pour stabilité)
    private var pinnedSectionsList: [AgentID] {
        AgentID.businessAgents.filter { pinned.isPinned($0) }
    }

    @ViewBuilder
    private func agentSectionView(for id: AgentID) -> some View {
        switch id {
        case .cartographer:
            cartographerSection
        case .auditor:
            auditorSection
        case .builder:
            builderSection
        case .advisor:
            advisorSection
        case .witness:
            witnessSection
        case .conductor:
            conductorSection  // v1.38
        case .quill:
            quillSection  // v1.101
        case .envoy:
            envoySection  // v1.104
        case .scribe:
            scribeSection  // v1.105
        default:
            simpleAgentSection(id)
        }
    }

    // v1.257 — Compte les actionRequested non résolus (pas de actionApproved/actionRejected matchant le correlationId).
    private var envoyPendingCount: Int {
        let resolvedIds: Set<UUID> = Set(
            allEnvoyEvents
                .filter { $0.kind == "actionApproved" || $0.kind == "actionRejected" }
                .compactMap { $0.correlationId }
        )
        return allEnvoyEvents.reduce(into: 0) { count, event in
            guard event.kind == "actionRequested", let cid = event.correlationId else { return }
            if !resolvedIds.contains(cid) {
                count += 1
            }
        }
    }

    // v1.257 — Badge "X pending" inline pour Envoy section header (gold hourglass)
    @ViewBuilder
    private var envoyPendingBadge: some View {
        if envoyPendingCount > 0 {
            HStack(spacing: 3) {
                Image(systemName: "hourglass")
                    .font(.system(size: 8))
                    .foregroundStyle(IRISTokens.goldAccent)
                Text("\(envoyPendingCount) pending")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(IRISTokens.goldAccent)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Capsule().fill(IRISTokens.goldAccent.opacity(0.12)))
        }
    }

    // v1.104 — Envoy dedicated section : pending actions + executed history
    // v1.257 — Inlined section header to inject "X pending" badge between title/count and pin buttons
    private var envoySection: some View {
        let envoyActions = allActionLogs.filter { $0.agentId == AgentID.envoy.rawValue }
        let total = envoyActions.count
        let successful = envoyActions.filter { $0.success }.count
        let approved = envoyActions.filter { $0.executedByUserApproval }.count
        return VStack(alignment: .leading, spacing: IRISTokens.spacing8) {
            HStack(spacing: 4) {
                Text("ENVOY")
                    .font(.system(size: 10, weight: .semibold)).tracking(1.4).foregroundStyle(.secondary)
                if total > 0 {
                    Text("\(total)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(IRISTokens.irisAccent)
                }
                envoyPendingBadge
                Spacer()
                Button {
                    copyAgentSummary(for: .envoy, count: total)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Copy \(AgentID.envoy.descriptor.displayName) summary Markdown")
                Button {
                    pinned.toggle(.envoy)
                } label: {
                    Image(systemName: pinned.isPinned(.envoy) ? "pin.fill" : "pin")
                        .font(.system(size: 10))
                        .foregroundStyle(pinned.isPinned(.envoy) ? IRISTokens.irisAccent : .secondary)
                }
                .buttonStyle(.plain)
                .help(pinned.isPinned(.envoy) ? "Désépingler section" : "Épingler section (toujours visible)")
            }
            .padding(.horizontal, IRISTokens.spacing4)

            HStack(spacing: 4) {
                Image(systemName: AgentID.envoy.descriptor.symbol)
                    .foregroundStyle(IRISTokens.irisAccent)
                Text(AgentID.envoy.descriptor.alias)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(appState.pendingActions.count) pending")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(appState.pendingActions.isEmpty ? .secondary : IRISTokens.goldAccent)
            }

            Text("Listen draftReady → propose actionRequested → wait approval → execute.")
                .font(.system(size: 10))
                .foregroundStyle(.primary.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 4) {
                statPill(label: "exec", value: "\(total)", color: .secondary)
                statPill(label: "ok", value: "\(successful)", color: .green)
                statPill(label: "approved", value: "\(approved)", color: IRISTokens.aquaTint)
            }

            if !envoyActions.isEmpty {
                Divider().padding(.vertical, 2)
                Text("HISTORIQUE EXÉCUTIONS")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                ForEach(Array(envoyActions.prefix(8))) { action in
                    envoyActionRow(action)
                }
            }
        }
    }

    private func envoyActionRow(_ action: ActionLog) -> some View {
        HStack(spacing: 4) {
            Image(systemName: action.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(action.success ? .green : .red)
            Text(action.actionType)
                .font(.system(size: 11, weight: .medium))
            Spacer()
            if action.reversible {
                Image(systemName: "arrow.uturn.left.circle")
                    .font(.system(size: 9))
                    .foregroundStyle(IRISTokens.aquaTint)
                    .help("Réversible")
            }
            Text(action.executedAt, format: .dateTime.day().month(.abbreviated).hour().minute())
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3).padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 4).fill(.thinMaterial))
    }

    // v1.277 — Scribe retrievals aujourd'hui.
    // NB: Scribe.retrieve / Scribe.store ne loggent pas dans EventLog (cf Agents/Scribe.swift) ;
    // pas de data source actuelle => fallback 0 en attendant que Scribe émette ses propres events.
    private var scribeRetrievalsToday: Int {
        0
    }

    // v1.277 — Badge "X today" inline pour Scribe section header (aqua magnifyingglass)
    @ViewBuilder
    private var scribeBadge: some View {
        if scribeRetrievalsToday > 0 {
            HStack(spacing: 3) {
                Image(systemName: "magnifyingglass.circle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(IRISTokens.aquaTint)
                Text("\(scribeRetrievalsToday) today")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(IRISTokens.aquaTint)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Capsule().fill(IRISTokens.aquaTint.opacity(0.12)))
        }
    }

    // v1.279 — Relative timestamp for the most recent memory (allMemoriesForScribe is unsorted,
    // so reduce-by-max instead of trusting .first).
    private var scribeLastMemoryAgo: String? {
        guard let latest = allMemoriesForScribe.max(by: { $0.createdAt < $1.createdAt }) else {
            return nil
        }
        let elapsed = Date().timeIntervalSince(latest.createdAt)
        if elapsed < 60 {
            return "\(Int(elapsed))s ago"
        } else if elapsed < 3600 {
            return "\(Int(elapsed / 60))m ago"
        } else if elapsed < 86400 {
            return "\(Int(elapsed / 3600))h ago"
        } else if elapsed < 604800 {
            return "\(Int(elapsed / 86400))d ago"
        } else {
            return latest.createdAt.formatted(.dateTime.day().month().year())
        }
    }

    // v1.279 — "Dernière memory: Xs ago" row, displayed near top of Scribe section.
    @ViewBuilder
    private var scribeLastMemoryRow: some View {
        if let ago = scribeLastMemoryAgo {
            HStack(spacing: 6) {
                Image(systemName: "memorychip")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary.opacity(0.7))
                Text("Dernière memory: \(ago)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, IRISTokens.spacing8)
            .padding(.vertical, 3)
        }
    }

    // v1.105 — Scribe dedicated section : memory breakdown by type + latest stored
    // v1.277 — Inlined header pour insérer scribeBadge à côté du titre.
    private var scribeSection: some View {
        let types = Dictionary(grouping: allMemoriesForScribe, by: \.type)
            .map { ($0.key, $0.value.count) }
            .sorted { $0.1 > $1.1 }
        let totalMemories = allMemoriesForScribe.count
        return VStack(alignment: .leading, spacing: IRISTokens.spacing8) {
            HStack(spacing: 4) {
                Text("SCRIBE")
                    .font(.system(size: 10, weight: .semibold)).tracking(1.4).foregroundStyle(.secondary)
                if totalMemories > 0 {
                    Text("\(totalMemories)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(IRISTokens.irisAccent)
                }
                scribeBadge
                Spacer()
                Button {
                    copyAgentSummary(for: .scribe, count: totalMemories)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Copy Scribe summary Markdown")
                Button {
                    pinned.toggle(.scribe)
                } label: {
                    Image(systemName: pinned.isPinned(.scribe) ? "pin.fill" : "pin")
                        .font(.system(size: 10))
                        .foregroundStyle(pinned.isPinned(.scribe) ? IRISTokens.irisAccent : .secondary)
                }
                .buttonStyle(.plain)
                .help(pinned.isPinned(.scribe) ? "Désépingler section" : "Épingler section (toujours visible)")
            }
            .padding(.horizontal, IRISTokens.spacing4)

            scribeLastMemoryRow  // v1.279

            HStack(spacing: 4) {
                Image(systemName: AgentID.scribe.descriptor.symbol)
                    .foregroundStyle(IRISTokens.irisAccent)
                Text(AgentID.scribe.descriptor.alias)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    appState.selection = .system(.memory)
                } label: {
                    Image(systemName: "books.vertical")
                        .font(.system(size: 10))
                        .foregroundStyle(IRISTokens.aquaTint)
                }
                .buttonStyle(.plain)
                .help("Ouvrir System > Memory pour browse + retrieval")
            }

            Text("NLEmbedding semantic retrieval. Auto-store conversations Conductor, manual via UI.")
                .font(.system(size: 10))
                .foregroundStyle(.primary.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)

            if !types.isEmpty {
                Divider().padding(.vertical, 2)
                Text("BREAKDOWN PAR TYPE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                ForEach(types.prefix(6), id: \.0) { item in
                    HStack {
                        Text(item.0)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("\(item.1)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2).padding(.horizontal, 6)
                    .background(RoundedRectangle(cornerRadius: 4).fill(.thinMaterial))
                }
            }
        }
    }

    // v1.172 — Drafts créés aujourd'hui (filter Quill section badge)
    private var draftsToday: Int {
        allDrafts.filter { Calendar.current.isDateInToday($0.createdAt) }.count
    }

    // v1.172 — Badge "X today" inline pour Quill section header
    @ViewBuilder
    private var draftsTodayBadge: some View {
        if draftsToday > 0 {
            HStack(spacing: 3) {
                Image(systemName: "sun.max")
                    .font(.system(size: 8))
                    .foregroundStyle(IRISTokens.irisAccent)
                Text("\(draftsToday) today")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(IRISTokens.irisAccent)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Capsule().fill(IRISTokens.irisAccent.opacity(0.12)))
        }
    }

    // v1.199 — Drafts créés sur les 7 derniers jours (rolling window)
    private var draftsPast7d: Int {
        let cutoff = Date().addingTimeInterval(-7 * 86400)
        return allDrafts.filter { $0.createdAt >= cutoff }.count
    }

    // v1.199 — Badge "X past 7d" inline pour Quill section header (gold, n'apparaît que si > today)
    @ViewBuilder
    private var draftsPast7dBadge: some View {
        if draftsPast7d > 0 && draftsPast7d != draftsToday {
            HStack(spacing: 3) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 8))
                    .foregroundStyle(IRISTokens.goldAccent)
                Text("\(draftsPast7d) past 7d")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(IRISTokens.goldAccent)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Capsule().fill(IRISTokens.goldAccent.opacity(0.12)))
        }
    }

    // v1.247 — Drafts créés sur les 30 derniers jours (rolling window)
    private var draftsPast30d: Int {
        let cutoff = Date().addingTimeInterval(-30 * 86400)
        return allDrafts.filter { $0.createdAt >= cutoff }.count
    }

    // v1.247 — Badge "X past 30d" inline pour Quill section header (aqua calendar, n'apparaît que si > past 7d)
    @ViewBuilder
    private var draftsPast30dBadge: some View {
        if draftsPast30d > 0 && draftsPast30d != draftsPast7d {
            HStack(spacing: 3) {
                Image(systemName: "calendar")
                    .font(.system(size: 8))
                    .foregroundStyle(IRISTokens.aquaTint)
                Text("\(draftsPast30d) past 30d")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(IRISTokens.aquaTint)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Capsule().fill(IRISTokens.aquaTint.opacity(0.12)))
        }
    }

    // v1.272 — Drafts/hour moyen aujourd'hui (depuis le premier draft du jour)
    private var draftsPerHourToday: Double? {
        let todays = allDrafts.filter { Calendar.current.isDateInToday($0.createdAt) }
        let count = todays.count
        if count == 0 { return nil }
        guard let earliest = todays.map({ $0.createdAt }).min() else { return nil }
        let hoursElapsed = max(1.0, Date().timeIntervalSince(earliest) / 3600)
        return Double(count) / hoursElapsed
    }

    // v1.272 — Badge "X.X/h" inline pour Quill section header (aqua speedometer)
    @ViewBuilder
    private var draftsRateBadge: some View {
        if let rate = draftsPerHourToday, rate > 0 {
            HStack(spacing: 3) {
                Image(systemName: "speedometer")
                    .font(.system(size: 8))
                    .foregroundStyle(IRISTokens.aquaTint)
                Text(String(format: "%.1f/h", rate))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(IRISTokens.aquaTint)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Capsule().fill(IRISTokens.aquaTint.opacity(0.12)))
        }
    }

    // v1.284 — Quill cost today grouped by model (sum costUSD per modelUsed, desc)
    private var quillCostTodayByModel: [(model: String, cost: Double)] {
        let todays = allDrafts.filter { Calendar.current.isDateInToday($0.createdAt) }
        let grouped = Dictionary(grouping: todays, by: { $0.modelUsed })
            .mapValues { $0.reduce(0) { $0 + $1.costUSD } }
        return grouped
            .map { (model: $0.key, cost: $0.value) }
            .sorted { $0.cost > $1.cost }
    }

    // v1.284 — Total Quill cost today (sum costUSD from today's drafts)
    private var quillCostTodayTotal: Double {
        allDrafts
            .filter { Calendar.current.isDateInToday($0.createdAt) }
            .reduce(0) { $0 + $1.costUSD }
    }

    // v1.284 — Badge "$X.XXX" inline pour Quill section header (gold dollar)
    @ViewBuilder
    private var quillCostBadge: some View {
        if quillCostTodayTotal > 0 {
            HStack(spacing: 3) {
                Image(systemName: "dollarsign.circle")
                    .font(.system(size: 8))
                    .foregroundStyle(IRISTokens.goldAccent)
                Text(String(format: "$%.3f", quillCostTodayTotal))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(IRISTokens.goldAccent)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Capsule().fill(IRISTokens.goldAccent.opacity(0.12)))
        }
    }

    // v1.236 — Briefings Advisor créés sur les 7 derniers jours (rolling window)
    private var briefingsPast7d: Int {
        let cutoff = Date().addingTimeInterval(-7 * 86400)
        return advisorBriefings.filter { $0.timestamp >= cutoff }.count
    }

    // v1.236 — Badge "X past 7d" inline pour Advisor section header (iris sun.max)
    @ViewBuilder
    private var briefingsCountBadge: some View {
        if briefingsPast7d > 0 {
            HStack(spacing: 3) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(IRISTokens.irisAccent)
                Text("\(briefingsPast7d) past 7d")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(IRISTokens.irisAccent)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Capsule().fill(IRISTokens.irisAccent.opacity(0.12)))
        }
    }

    // v1.241 — Captures Witness émises aujourd'hui (source="screen" ou "screen-vision")
    private var witnessTodayCount: Int {
        allSignals.filter {
            ($0.source == "screen" || $0.source == "screen-vision")
                && Calendar.current.isDateInToday($0.emittedAt)
        }.count
    }

    // v1.241 — Badge "X today" inline pour Witness section header (aqua eye)
    @ViewBuilder
    private var witnessTodayBadge: some View {
        if witnessTodayCount > 0 {
            HStack(spacing: 3) {
                Image(systemName: "eye.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(IRISTokens.aquaTint)
                Text("\(witnessTodayCount) today")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(IRISTokens.aquaTint)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Capsule().fill(IRISTokens.aquaTint.opacity(0.12)))
        }
    }

    // v1.299 — Most-used app today from Witness signals (parse summary "Mehdi sur AppName · ...")
    private var witnessTopAppToday: (appName: String, count: Int)? {
        let todaySignals = allSignals.filter {
            ($0.source == "screen" || $0.source == "screen-vision")
                && Calendar.current.isDateInToday($0.emittedAt)
        }
        var counts: [String: Int] = [:]
        for signal in todaySignals {
            let summary = signal.summary
            let parts = summary.components(separatedBy: " sur ")
            guard parts.count >= 2,
                  let afterSur = parts.last,
                  let appName = afterSur.components(separatedBy: " · ").first else { continue }
            let trimmed = appName.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            counts[trimmed, default: 0] += 1
        }
        guard let top = counts.max(by: { $0.value < $1.value }) else { return nil }
        return (appName: top.key, count: top.value)
    }

    // v1.299 — Badge "AppName (X)" inline pour Witness section header (iris app.fill)
    @ViewBuilder
    private var witnessTopAppBadge: some View {
        if let top = witnessTopAppToday {
            HStack(spacing: 3) {
                Image(systemName: "app.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(IRISTokens.irisAccent)
                Text(top.appName)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(IRISTokens.irisAccent)
                    .lineLimit(1)
                Text("(\(top.count))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Capsule().fill(IRISTokens.irisAccent.opacity(0.12)))
        }
    }

    // v1.326 — Latest Witness capture (screen or screen-vision) sorted desc by emittedAt
    private var witnessLatest: Signal? {
        allSignals
            .filter { $0.source == "screen" || $0.source == "screen-vision" }
            .sorted { $0.emittedAt > $1.emittedAt }
            .first
    }

    // v1.326 — "Now:" inline row showing latest Witness capture summary + timestamp
    @ViewBuilder
    private var witnessLatestRow: some View {
        if let latest = witnessLatest {
            HStack(spacing: 6) {
                Image(systemName: "eye.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(IRISTokens.aquaTint)
                Text("Now:")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(latest.summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                Text(latest.emittedAt, format: .dateTime.hour().minute().second())
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, IRISTokens.spacing8)
            .padding(.vertical, 4)
            .background(IRISTokens.aquaTint.opacity(0.05))
        } else {
            EmptyView()
        }
    }

    // v1.254 — Total scaffolds run via Builder (ActionLog actionType contains "scaffold")
    private var builderScaffoldCount: Int {
        allActionLogs.filter { $0.actionType.contains("scaffold") }.count
    }

    // v1.254 — Badge "X total" inline pour Builder section header (gold hammer)
    @ViewBuilder
    private var builderCountBadge: some View {
        if builderScaffoldCount > 0 {
            HStack(spacing: 3) {
                Image(systemName: "hammer.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(IRISTokens.goldAccent)
                Text("\(builderScaffoldCount) total")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(IRISTokens.goldAccent)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Capsule().fill(IRISTokens.goldAccent.opacity(0.12)))
        }
    }

    // v1.101 — Quill dedicated section : last drafts + Sonnet routing badge + cost-this-session
    // v1.172 — Inlined section header to inject "X today" badge between title/count and pin buttons
    private var quillSection: some View {
        let recentDrafts = Array(allDrafts.prefix(8))
        let totalDrafts = allDrafts.count
        let pendingDrafts = allDrafts.filter { $0.status == "pending" }.count
        let sonnetCost = appState.costByModel["claude-sonnet-4-6"] ?? 0
        return VStack(alignment: .leading, spacing: IRISTokens.spacing8) {
            HStack(spacing: 4) {
                Text("QUILL")
                    .font(.system(size: 10, weight: .semibold)).tracking(1.4).foregroundStyle(.secondary)
                if totalDrafts > 0 {
                    Text("\(totalDrafts)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(IRISTokens.irisAccent)
                }
                draftsTodayBadge
                Spacer().frame(width: 3)
                draftsPast7dBadge
                Spacer().frame(width: 3)
                draftsPast30dBadge
                Spacer().frame(width: 3)
                draftsRateBadge
                Spacer().frame(width: 3)
                quillCostBadge
                Spacer()
                // v1.185 — Export today's drafts as Markdown
                Button {
                    exportTodaysDrafts()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 9))
                }
                .buttonStyle(.plain)
                .foregroundStyle(IRISTokens.aquaTint.opacity(0.7))
                .help("Export les drafts d'aujourd'hui en Markdown")
                .disabled(draftsToday == 0)
                if let exportDraftsStatus {
                    Text(exportDraftsStatus)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(exportDraftsStatus.hasPrefix("✅") ? .green : .red)
                        .lineLimit(1)
                }
                Button {
                    copyAgentSummary(for: .quill, count: totalDrafts)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Copy \(AgentID.quill.descriptor.displayName) summary Markdown")
                Button {
                    pinned.toggle(.quill)
                } label: {
                    Image(systemName: pinned.isPinned(.quill) ? "pin.fill" : "pin")
                        .font(.system(size: 10))
                        .foregroundStyle(pinned.isPinned(.quill) ? IRISTokens.irisAccent : .secondary)
                }
                .buttonStyle(.plain)
                .help(pinned.isPinned(.quill) ? "Désépingler section" : "Épingler section (toujours visible)")
            }
            .padding(.horizontal, IRISTokens.spacing4)

            HStack(spacing: 4) {
                Image(systemName: AgentID.quill.descriptor.symbol)
                    .foregroundStyle(IRISTokens.irisAccent)
                Text(AgentID.quill.descriptor.alias)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Sonnet session: $\(String(format: "%.4f", sonnetCost))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Text("Subscribe signals ≥ high (Sentinel + manual) → draft via Sonnet 4.6")
                .font(.system(size: 10))
                .foregroundStyle(.primary.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)

            // Mini stats
            HStack(spacing: 4) {
                statPill(label: "total", value: "\(totalDrafts)", color: .secondary)
                statPill(label: "pending", value: "\(pendingDrafts)", color: pendingDrafts > 0 ? IRISTokens.goldAccent : .secondary)
            }

            Divider().padding(.vertical, 2)

            if recentDrafts.isEmpty {
                Text("Aucun draft. Forge un signal high importance pour tester.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                Text("DERNIERS DRAFTS")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                ForEach(recentDrafts) { draft in
                    draftRow(draft)
                }
            }
        }
    }

    private func statPill(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
        .foregroundStyle(color)
    }

    // v1.330 — Today's userInput events count + most recent timestamp
    private var conductorTodayStats: (count: Int, lastQuery: Date?) {
        let today = allEvents.filter {
            $0.kind == "userInput" && Calendar.current.isDateInToday($0.timestamp)
        }
        let last = today.map { $0.timestamp }.max()
        return (today.count, last)
    }

    // v1.330 — Inline row at top of Conductor section (queries today + last timestamp)
    @ViewBuilder
    private var conductorStatsRow: some View {
        if conductorTodayStats.count > 0 {
            HStack(spacing: 6) {
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(IRISTokens.aquaTint)
                Text("\(conductorTodayStats.count) queries today")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(IRISTokens.aquaTint)
                if let last = conductorTodayStats.lastQuery {
                    Text("last: \(last, format: .dateTime.hour().minute())")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, IRISTokens.spacing8)
            .padding(.vertical, 3)
            .background(IRISTokens.aquaTint.opacity(0.06))
        }
    }

    // MARK: — v1.38 Conductor session stats

    private var conductorSection: some View {
        let messageCount = appState.transcript.count
        let opusCost = appState.costByModel["claude-opus-4-7"] ?? 0
        let userMessages = appState.transcript.filter {
            if case .user = $0.role { return true } else { return false }
        }.count
        let agentResponses = appState.transcript.filter {
            if case .agent(.conductor) = $0.role { return true } else { return false }
        }.count

        return VStack(alignment: .leading, spacing: IRISTokens.spacing8) {
            sectionHeader("Conductor", count: messageCount, accent: IRISTokens.irisAccent, pinnable: .conductor)

            conductorStatsRow  // v1.330

            VStack(alignment: .leading, spacing: 4) {
                conductorStatRow(label: "Messages user", value: "\(userMessages)", color: IRISTokens.aquaTint)
                conductorStatRow(label: "Réponses Conductor", value: "\(agentResponses)", color: IRISTokens.irisAccent)
                Divider().padding(.vertical, 2)
                conductorStatRow(label: "Cost Opus session", value: "$\(String(format: "%.4f", opusCost))", color: IRISTokens.goldAccent)
                conductorStatRow(label: "API key", value: appState.hasAnthropicKey ? "✓ active" : "⚠️ mock", color: appState.hasAnthropicKey ? .green : IRISTokens.goldAccent)
            }
            .padding(.vertical, IRISTokens.spacing4)

            Divider().padding(.vertical, 2)

            HStack(spacing: IRISTokens.spacing8) {
                Button {
                    Task {
                        await Conductor.shared.resetHistory()
                        appState.clearTranscript()
                    }
                } label: {
                    Label("Nouvelle conversation", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(appState.transcript.isEmpty)
                // v1.89 — Export transcript MD
                Button {
                    exportTranscriptMarkdown()
                } label: {
                    Label("Export MD", systemImage: "square.and.arrow.up")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(appState.transcript.isEmpty)
                .help("Export la conversation en Markdown vers ~/iris-conv-<timestamp>.md")
                Spacer()
            }
        }
    }

    // v1.89 — Export transcript as Markdown file
    private func exportTranscriptMarkdown() {
        let entries = appState.transcript
        guard !entries.isEmpty else { return }
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var md = "# IRIS Conductor transcript — \(dateFmt.string(from: Date()))\n\n"
        for entry in entries {
            let role: String = {
                switch entry.role {
                case .user: return "User"
                case .agent(let id): return id.descriptor.displayName
                case .system(let lvl): return "System(\(lvl))"
                }
            }()
            md += "## \(role) · \(entry.timestamp.formatted(date: .omitted, time: .standard))\n\n"
            md += "\(entry.content)\n\n"
        }
        let isoNow = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("iris-conv-\(isoNow).md")
        try? md.write(to: url, atomically: true, encoding: .utf8)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func conductorStatRow(label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(color)
        }
    }

    // MARK: — Witness (v1.7.B)

    private var witnessSection: some View {
        let screenSignals = allSignals.filter { $0.source == "screen" }.prefix(5)
        // v1.153 — Vision history (source="screen-vision" depuis captureWithVision)
        let visionSignals = allSignals.filter { $0.source == "screen-vision" }.prefix(5)
        return VStack(alignment: .leading, spacing: IRISTokens.spacing8) {
            // v1.241 — Inlined section header to inject "X today" Witness captures badge
            HStack(spacing: 4) {
                Text("WITNESS")
                    .font(.system(size: 10, weight: .semibold)).tracking(1.4).foregroundStyle(.secondary)
                if screenSignals.count > 0 {
                    Text("\(screenSignals.count)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(IRISTokens.irisAccent)
                }
                witnessTodayBadge
                witnessTopAppBadge
                Spacer()
                Button {
                    copyAgentSummary(for: .witness, count: screenSignals.count)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Copy Witness summary Markdown")
                Button {
                    pinned.toggle(.witness)
                } label: {
                    Image(systemName: pinned.isPinned(.witness) ? "pin.fill" : "pin")
                        .font(.system(size: 10))
                        .foregroundStyle(pinned.isPinned(.witness) ? IRISTokens.irisAccent : .secondary)
                }
                .buttonStyle(.plain)
                .help(pinned.isPinned(.witness) ? "Désépingler section" : "Épingler section (toujours visible)")
            }
            .padding(.horizontal, IRISTokens.spacing4)

            // v1.326 — "Now:" current frontmost preview at top of section
            witnessLatestRow

            // v1.179 — transient block confirmation feedback
            if let status = blockStatus {
                Text(status)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.green)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "eyes")
                        .foregroundStyle(IRISTokens.irisAccent)
                    Text("Témoin")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    // v1.80 — Snapshot now (force capture immédiate)
                    Button {
                        Task { await Witness.shared.triggerSnapshotNow() }
                    } label: {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 12))
                            .foregroundStyle(IRISTokens.aquaTint)
                    }
                    .buttonStyle(.plain)
                    .help("Snapshot frontmost maintenant (bypass debounce)")
                    // v1.109 — Snapshot + Vision (screenshot → Claude Haiku 4.5 → description)
                    Button {
                        Task { await Witness.shared.captureWithVision() }
                    } label: {
                        Image(systemName: "eye.square")
                            .font(.system(size: 12))
                            .foregroundStyle(IRISTokens.irisAccent)
                    }
                    .buttonStyle(.plain)
                    .help("Snapshot + Vision Haiku 4.5 (~$0.002, requiert Screen Recording)")
                    // v1.27 — Pause/Resume Witness
                    Button {
                        Task {
                            let isPaused = await Witness.shared.isPaused
                            await Witness.shared.setPaused(!isPaused)
                        }
                    } label: {
                        Image(systemName: "pause.circle")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Pause/Resume Witness (stop capture frontmost)")
                }
                Text("Capture NSWorkspace frontmost (debounce 10s). Vision Gemini en v1.5.B+.")
                    .font(.system(size: 11))
                    .foregroundStyle(.primary.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, IRISTokens.spacing8)

            if screenSignals.isEmpty {
                Text("Pas encore de capture. Première arrive dans ~10s.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                Text("DERNIERS CONTEXTES (frontmost)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                ForEach(Array(screenSignals)) { signal in
                    witnessRow(signal)
                }
            }

            // v1.153 — Vision history (séparée car coût $$ par capture)
            if !visionSignals.isEmpty {
                Divider().padding(.vertical, 2)
                Text("DERNIÈRES VISIONS (Haiku 4.5)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                ForEach(Array(visionSignals)) { signal in
                    visionRow(signal)
                }
            }
        }
    }

    // v1.153 — Vision row distincte (eye.fill iris vs rectangle.on.rectangle aqua)
    private func visionRow(_ signal: Signal) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .top) {
                Image(systemName: "eye.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(IRISTokens.irisAccent)
                Text(signal.summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Text(signal.emittedAt, format: .dateTime.hour().minute())
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3).padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(IRISTokens.irisAccent.opacity(0.06)))
    }

    private func witnessRow(_ signal: Signal) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                Image(systemName: "rectangle.on.rectangle")
                    .font(.system(size: 10))
                    .foregroundStyle(IRISTokens.aquaTint)
                Text(signal.summary)
                    .font(.system(size: 11)).lineLimit(1)
                Spacer()
                Text(signal.emittedAt, format: .dateTime.hour().minute().second())
                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                // v1.179 — Block this app quick action (parse appName from summary, resolve bundleId)
                Button {
                    blockApp(bundleId: Self.bundleIdFromSummary(signal.summary))
                } label: {
                    Image(systemName: "nosign")
                        .font(.system(size: 10))
                        .foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Bloquer cette app (ajoute bundleId à la blocklist Witness)")
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(.thinMaterial))
    }

    // v1.179 — Extract appName from Witness summary ("Mehdi sur \(appName) · ..." or "Mehdi sur \(appName)")
    // then resolve bundleId via NSWorkspace.runningApplications.
    private static func bundleIdFromSummary(_ summary: String) -> String? {
        let prefix = "Mehdi sur "
        guard summary.hasPrefix(prefix) else { return nil }
        let afterPrefix = String(summary.dropFirst(prefix.count))
        let appName = afterPrefix.split(separator: "·", maxSplits: 1).first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? afterPrefix
        guard !appName.isEmpty else { return nil }
        let match = NSWorkspace.shared.runningApplications.first {
            ($0.localizedName ?? "") == appName
        }
        return match?.bundleIdentifier
    }

    // v1.179 — Append bundleId to Witness blocklist (UserDefaults via Witness.addBlocked),
    // skip if already present, show transient confirmation 3s.
    private func blockApp(bundleId: String?) {
        guard let bundleId, !bundleId.isEmpty else {
            blockStatus = "⚠️ bundleId introuvable"
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                if blockStatus == "⚠️ bundleId introuvable" { blockStatus = nil }
            }
            return
        }
        if Witness.blockedBundleIds.contains(bundleId) {
            blockStatus = "ℹ️ Déjà bloqué: \(bundleId)"
        } else {
            Witness.addBlocked(bundleId)
            blockStatus = "✅ Bloqué: \(bundleId)"
        }
        let snapshot = blockStatus
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if blockStatus == snapshot { blockStatus = nil }
        }
    }

    // MARK: — Cartographer

    private var filteredProjects: [ProjectRecord] {
        let q = cartographerSearch
        let searched: [ProjectRecord]
        if q.isEmpty {
            searched = Array(allProjects)
        } else {
            searched = allProjects.filter {
                $0.codename.localizedCaseInsensitiveContains(q)
                    || ($0.localPath?.localizedCaseInsensitiveContains(q) ?? false)
                    || ($0.repoURL?.localizedCaseInsensitiveContains(q) ?? false)
            }
        }
        // v1.294 — chain Cartographer status Picker filter (status field on ProjectRecord)
        guard !cartoStatusFilter.isEmpty else { return searched }
        return searched.filter { $0.status == cartoStatusFilter }
    }

    // v1.244 — Cartographer audited/total ratio (projects with ≥1 AuditReport).
    private var auditedProjectCount: (audited: Int, total: Int) {
        let auditedCodenames = Set(allAudits.map(\.projectCodename))
        let audited = allProjects.filter { auditedCodenames.contains($0.codename) }.count
        return (audited: audited, total: allProjects.count)
    }

    // v1.244 — Badge "X/Y audited" inline pour Cartographer section header (aqua shield)
    @ViewBuilder
    private var auditedBadge: some View {
        if auditedProjectCount.total > 0 {
            HStack(spacing: 3) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(IRISTokens.aquaTint)
                Text("\(auditedProjectCount.audited)/\(auditedProjectCount.total) audited")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(IRISTokens.aquaTint)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Capsule().fill(IRISTokens.aquaTint.opacity(0.12)))
        }
    }

    // v1.266 — Most audited project (clear leader only; nil if tie or max <= 1).
    private var mostAuditedProject: (codename: String, count: Int)? {
        let counts = Dictionary(grouping: allAudits, by: { $0.projectCodename })
            .mapValues { $0.count }
        guard let maxCount = counts.values.max(), maxCount > 1 else { return nil }
        let leaders = counts.filter { $0.value == maxCount }
        guard leaders.count == 1, let leader = leaders.first else { return nil }
        return (codename: leader.key, count: leader.value)
    }

    // v1.266 — Badge "Top: <codename> (<count>)" inline pour Cartographer section header (gold flame)
    @ViewBuilder
    private var mostAuditedBadge: some View {
        if mostAuditedProject == nil {
            EmptyView()
        } else {
            let m = mostAuditedProject!
            HStack(spacing: 3) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(IRISTokens.goldAccent)
                Text("Top: \(m.codename) (\(m.count))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(IRISTokens.goldAccent)
                    .lineLimit(1)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Capsule().fill(IRISTokens.goldAccent.opacity(0.12)))
        }
    }

    // v1.290 — Per-project audit stats (count + latest verdict + latest date)
    private var auditsByCodename: [String: (count: Int, latestVerdict: String, latestDate: Date)] {
        var dict: [String: (count: Int, latestVerdict: String, latestDate: Date)] = [:]
        for audit in allAudits { // allAudits is already sorted desc by createdAt
            if let existing = dict[audit.projectCodename] {
                dict[audit.projectCodename] = (count: existing.count + 1, latestVerdict: existing.latestVerdict, latestDate: existing.latestDate)
            } else {
                dict[audit.projectCodename] = (count: 1, latestVerdict: audit.verdict, latestDate: audit.createdAt)
            }
        }
        return dict
    }

    // v1.290 — Map verdict string to color for inline dot.
    private func verdictColor(_ verdict: String) -> Color {
        switch verdict {
        case "GREEN": return .green
        case "YELLOW": return IRISTokens.goldAccent
        case "RED": return .red
        default: return Color.secondary
        }
    }

    private var cartographerSection: some View {
        // v1.79 — filter status
        let availableStatuses = Array(Set(allProjects.map(\.status))).sorted()
        let searchScoped = filteredProjects
        let filtered = projectStatusFilter.isEmpty
            ? searchScoped
            : searchScoped.filter { $0.status == projectStatusFilter }
        let limited = Array(filtered.prefix(8))
        return VStack(alignment: .leading, spacing: IRISTokens.spacing8) {
            // v1.244 — Inlined header to inject "X/Y audited" badge next to title
            HStack(spacing: 4) {
                Text("CARTOGRAPHER")
                    .font(.system(size: 10, weight: .semibold)).tracking(1.4).foregroundStyle(.secondary)
                if filtered.count > 0 {
                    Text("\(filtered.count)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(IRISTokens.irisAccent)
                }
                auditedBadge
                mostAuditedBadge
                Spacer()
                // v1.223 — Bulk audit all visible projects
                Button { auditAllProjects() } label: {
                    Label("Audit all", systemImage: "checkmark.shield.fill")
                        .font(.system(size: 11))
                }
                .controlSize(.small)
                .tint(IRISTokens.aquaTint)
                .help("Lancer un audit sur tous les projets visibles (filteredProjects, force: true)")
                .disabled(filteredProjects.isEmpty)
                // v1.158 — Copy stats summary to clipboard (Markdown)
                Button {
                    copyAgentSummary(for: .cartographer, count: filtered.count)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Copy Cartographer summary Markdown")
                Button {
                    pinned.toggle(.cartographer)
                } label: {
                    Image(systemName: pinned.isPinned(.cartographer) ? "pin.fill" : "pin")
                        .font(.system(size: 10))
                        .foregroundStyle(pinned.isPinned(.cartographer) ? IRISTokens.irisAccent : .secondary)
                }
                .buttonStyle(.plain)
                .help(pinned.isPinned(.cartographer) ? "Désépingler section" : "Épingler section (toujours visible)")
            }
            .padding(.horizontal, IRISTokens.spacing4)

            HStack(spacing: IRISTokens.spacing4) {
                TextField("Filter projects by codename/path…", text: $cartographerSearch)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                // v1.294 — Cartographer status Picker (All/Active/Archived/Experimental)
                Picker("Status", selection: $cartoStatusFilter) {
                    Text("All").tag("")
                    Text("Active").tag("active")
                    Text("Archived").tag("archived")
                    Text("Experimental").tag("experimental")
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(maxWidth: 100)
                .pickerStyle(.menu)
            }
            .padding(.horizontal, IRISTokens.spacing8)

            HStack {
                Button {
                    Task { await Cartographer.shared.refresh() }
                } label: {
                    Label("Refresh now", systemImage: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                // v1.94 — Local-only refresh (skip GitHub poll, faster)
                Button {
                    Task { await Cartographer.shared.refresh(localOnly: true) }
                } label: {
                    Label("Local only", systemImage: "internaldrive")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Re-scan ~/Developer seulement (skip gh repo list)")

                Spacer()

                if !availableStatuses.isEmpty {
                    Picker("", selection: $projectStatusFilter) {
                        Text("all").tag("")
                        ForEach(availableStatuses, id: \.self) { s in
                            Text(s).tag(s)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.mini)
                    .frame(maxWidth: 100)
                }
            }

            ForEach(limited) { project in
                projectRow(project)
            }

            if filtered.count > 8 {
                Text("… +\(filtered.count - 8) autres")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func projectRow(_ project: ProjectRecord) -> some View {
        HStack(alignment: .top, spacing: 6) {
            statusBadge(project.status)
            VStack(alignment: .leading, spacing: 1) {
                Text(project.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                if let url = project.repoURL {
                    Text(url.replacingOccurrences(of: "https://github.com/", with: ""))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            // v1.290 — Per-project audit stats badge (count + latest verdict color dot)
            if let stats = auditsByCodename[project.codename] {
                HStack(spacing: 4) {
                    Circle()
                        .fill(verdictColor(stats.latestVerdict))
                        .frame(width: 6, height: 6)
                    Text("\(stats.count) audits")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Capsule().fill(.thinMaterial))
                .help("Dernier verdict: \(stats.latestVerdict)")
            }
            if project.isPrivate {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            // v1.68 — Open in Finder (si localPath)
            if let path = project.localPath, !path.isEmpty {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 9))
                        .foregroundStyle(IRISTokens.aquaTint)
                }
                .buttonStyle(.plain)
                .help("Reveal \(path) dans Finder")
            }
            // v1.68 — Open repo dans browser (si repoURL)
            if let urlStr = project.repoURL, let url = URL(string: urlStr) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 9))
                        .foregroundStyle(IRISTokens.irisAccent)
                }
                .buttonStyle(.plain)
                .help("Ouvrir \(urlStr) dans le navigateur")
            }
            // v1.86 — Open in IDE (Cursor → Xcode → fallback Finder)
            if let path = project.localPath, !path.isEmpty {
                Button {
                    openProjectInIDE(path: path)
                } label: {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 9))
                        .foregroundStyle(IRISTokens.irisAccent.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Ouvrir dans IDE (Cursor / Xcode auto-detect)")
            }
            // v1.81 — Archive / unarchive project (toggle status)
            Button {
                project.status = (project.status == "archived") ? "active" : "archived"
                try? modelContext.save()
            } label: {
                Image(systemName: project.status == "archived" ? "archivebox.fill" : "archivebox")
                    .font(.system(size: 9))
                    .foregroundStyle(project.status == "archived" ? .secondary : IRISTokens.goldAccent.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help(project.status == "archived" ? "Désarchiver (→ active)" : "Archiver le projet")
            // v1.213 — Audit-now quick action
            Button {
                triggerAudit(project)
            } label: {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 10))
                    .foregroundStyle(IRISTokens.aquaTint.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help("Lancer un audit Auditor sur ce projet")
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(.thinMaterial))
    }

    // v1.213 — Fire-and-forget audit trigger from Cartographer row.
    private func triggerAudit(_ project: ProjectRecord) {
        guard !project.codename.isEmpty else { return }
        Task { await Auditor.shared.auditProject(codename: project.codename, force: true) }
    }

    // v1.223 — Sequential audit-all over filteredProjects, 2s spacing to avoid API hammering.
    private func auditAllProjects() {
        let projects = filteredProjects
        Task {
            for project in projects {
                guard !project.codename.isEmpty else { continue }
                await Auditor.shared.auditProject(codename: project.codename, force: true)
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s
            }
        }
    }

    // MARK: — Auditor

    // v1.209 — Sum costUSD des AuditReport créés today (calendrier user, startOfDay).
    private var auditorCostToday: Double {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return allAudits
            .filter { $0.createdAt >= startOfDay }
            .reduce(0.0) { $0 + $1.costUSD }
    }

    // v1.333 — Sum costUSD across all AuditReport (lifetime, no date filter).
    private var auditorCostLifetime: Double {
        allAudits.reduce(0.0) { $0 + $1.costUSD }
    }

    // v1.248 — Quick filter: when auditRedOnly is true, only show audits with verdict "RED".
    private var filteredAudits: [AuditReport] {
        auditRedOnly ? allAudits.filter { $0.verdict == "RED" } : allAudits
    }

    // v1.218 — Counts AuditReport verdicts (GREEN/YELLOW/RED) over past 30 days.
    private var verdictCounts: (green: Int, yellow: Int, red: Int) {
        let cutoff = Date().addingTimeInterval(-30 * 86400)
        let recent = allAudits.filter { $0.createdAt >= cutoff }
        var green = 0, yellow = 0, red = 0
        for audit in recent {
            switch audit.verdict {
            case "GREEN": green += 1
            case "YELLOW": yellow += 1
            case "RED": red += 1
            default: break
            }
        }
        return (green, yellow, red)
    }

    // v1.218 — Mini stat row badge with colored dots + counts for verdicts past 30d.
    @ViewBuilder
    private var verdictCountsBadge: some View {
        let counts = verdictCounts
        if counts.green + counts.yellow + counts.red > 0 {
            HStack(spacing: 6) {
                HStack(spacing: 3) {
                    Circle().fill(.green).frame(width: 6, height: 6)
                    Text("\(counts.green)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.green)
                }
                HStack(spacing: 3) {
                    Circle().fill(IRISTokens.goldAccent).frame(width: 6, height: 6)
                    Text("\(counts.yellow)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(IRISTokens.goldAccent)
                }
                HStack(spacing: 3) {
                    Circle().fill(.red).frame(width: 6, height: 6)
                    Text("\(counts.red)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(.thinMaterial))
        }
    }

    // v1.311 — Horizontal stacked bar visualizing GREEN/YELLOW/RED ratio over past 30d.
    @ViewBuilder
    private var verdictTrendBar: some View {
        let total = verdictCounts.green + verdictCounts.yellow + verdictCounts.red
        if total > 0 {
            GeometryReader { proxy in
                HStack(spacing: 1) {
                    if verdictCounts.green > 0 {
                        Rectangle()
                            .fill(.green)
                            .frame(width: proxy.size.width * CGFloat(verdictCounts.green) / CGFloat(total))
                    }
                    if verdictCounts.yellow > 0 {
                        Rectangle()
                            .fill(IRISTokens.goldAccent)
                            .frame(width: proxy.size.width * CGFloat(verdictCounts.yellow) / CGFloat(total))
                    }
                    if verdictCounts.red > 0 {
                        Rectangle()
                            .fill(.red)
                            .frame(width: proxy.size.width * CGFloat(verdictCounts.red) / CGFloat(total))
                    }
                }
            }
            .frame(height: 4)
            .cornerRadius(2)
        } else {
            EmptyView()
        }
    }

    // v1.320 — Chronological list of past-30d audits (oldest→newest, capped at 20).
    private var verdictTimeline30d: [AuditReport] {
        let cutoff = Date().addingTimeInterval(-30 * 86400)
        let recent = allAudits
            .filter { $0.createdAt >= cutoff }
            .sorted { $0.createdAt < $1.createdAt }
        return Array(recent.suffix(20))
    }

    // v1.320 — Mini timeline of verdict dots (oldest left, newest right).
    @ViewBuilder
    private var verdictTimelineBar: some View {
        if verdictTimeline30d.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 2) {
                ForEach(verdictTimeline30d) { audit in
                    Circle()
                        .fill(verdictColor(audit.verdict))
                        .frame(width: 8, height: 8)
                        .help("\(audit.verdict) · \(audit.projectCodename) · \(audit.createdAt.formatted(date: .abbreviated, time: .shortened))")
                }
                Spacer()
            }
        }
    }

    // v1.209 — Badge "$X.XXX today" inline pour Auditor section header (gold, n'apparaît que si > 0).
    @ViewBuilder
    private var auditorCostBadge: some View {
        if auditorCostToday > 0 {
            HStack(spacing: 3) {
                Image(systemName: "dollarsign.circle")
                    .font(.system(size: 8))
                    .foregroundStyle(IRISTokens.goldAccent)
                Text(String(format: "$%.3f today", auditorCostToday))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(IRISTokens.goldAccent)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Capsule().fill(IRISTokens.goldAccent.opacity(0.12)))
        }
    }

    // v1.333 — Badge "$X.XX lifetime" inline pour Auditor section header (iris infinity, n'apparaît que si > 0).
    @ViewBuilder
    private var auditorCostLifetimeBadge: some View {
        if auditorCostLifetime > 0 {
            HStack(spacing: 3) {
                Image(systemName: "infinity")
                    .font(.system(size: 8))
                    .foregroundStyle(IRISTokens.irisAccent)
                Text(String(format: "$%.2f lifetime", auditorCostLifetime))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(IRISTokens.irisAccent)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Capsule().fill(IRISTokens.irisAccent.opacity(0.12)))
        }
    }

    private var auditorSection: some View {
        VStack(alignment: .leading, spacing: IRISTokens.spacing8) {
            // v1.209 — inlined section header to inject cost-today badge near title/count.
            // v1.311 — Header + verdict trend bar wrapped in VStack so bar sits under badges row.
            VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text("AUDITOR")
                    .font(.system(size: 10, weight: .semibold)).tracking(1.4).foregroundStyle(.secondary)
                if allAudits.count > 0 {
                    Text("\(allAudits.count)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(IRISTokens.irisAccent)
                }
                auditorCostBadge
                auditorCostLifetimeBadge
                verdictCountsBadge
                // v1.248 — Auditor "RED only" quick filter toggle
                Button { auditRedOnly.toggle() } label: {
                    HStack(spacing: 3) {
                        Image(systemName: auditRedOnly ? "circle.fill" : "circle")
                            .font(.system(size: 8))
                            .foregroundStyle(.red)
                        Text("RED only")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(auditRedOnly ? .red : .secondary)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Capsule().fill(auditRedOnly ? .red.opacity(0.15) : Color.clear))
                .help(auditRedOnly ? "Show all audits" : "Show only RED audits")
                Spacer()
                // v1.260 — Export all audits in one Markdown file (home dir)
                Button { exportAllAuditsMD() } label: {
                    Image(systemName: "square.and.arrow.up.on.square")
                        .font(.system(size: 9))
                        .foregroundStyle(IRISTokens.aquaTint.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Export TOUS les audits en un Markdown unique")
                .disabled(allAudits.isEmpty)
                if let exportAuditsStatus {
                    Text(exportAuditsStatus)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(exportAuditsStatus.hasPrefix("✅") ? .green : .red)
                        .lineLimit(1)
                }
                Button {
                    copyAgentSummary(for: .auditor, count: allAudits.count)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Copy \(AgentID.auditor.descriptor.displayName) summary Markdown")
                Button {
                    pinned.toggle(.auditor)
                } label: {
                    Image(systemName: pinned.isPinned(.auditor) ? "pin.fill" : "pin")
                        .font(.system(size: 10))
                        .foregroundStyle(pinned.isPinned(.auditor) ? IRISTokens.irisAccent : .secondary)
                }
                .buttonStyle(.plain)
                .help(pinned.isPinned(.auditor) ? "Désépingler section" : "Épingler section (toujours visible)")
            }
            .padding(.horizontal, IRISTokens.spacing4)
            VStack(alignment: .leading, spacing: 3) {
                verdictTrendBar
                verdictTimelineBar
            }
            .padding(.horizontal, IRISTokens.spacing4)
            }

            HStack(spacing: IRISTokens.spacing8) {
                Picker("Projet", selection: $auditPickedProject) {
                    Text("— choisir —").tag("")
                    ForEach(allProjects.prefix(20)) { p in
                        Text(p.codename).tag(p.codename)
                    }
                }
                .labelsHidden()
                .controlSize(.small)

                Button("Audit") {
                    let target = auditPickedProject
                    guard !target.isEmpty else { return }
                    Task { await Auditor.shared.auditProject(codename: target) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(IRISTokens.irisAccent)
                .disabled(auditPickedProject.isEmpty)
            }

            ForEach(Array(filteredAudits.prefix(5))) { audit in
                auditRow(audit)
            }
        }
    }

    private func auditRow(_ audit: AuditReport) -> some View {
        let isExpanded = expandedAuditIds.contains(audit.id)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                verdictBadge(audit.verdict)
                Text(audit.projectCodename)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text(audit.createdAt, format: .dateTime.day().month(.abbreviated).hour().minute())
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            Text(audit.headline)
                .font(.system(size: 11))
                .foregroundStyle(.primary.opacity(0.8))
                .lineLimit(isExpanded ? nil : 2)

            // v1.62 — Expanded : findings + topActions parsed
            if isExpanded {
                let findings = Self.parseStringArray(audit.findingsJSON)
                let topActions = Self.parseActionObjects(audit.topActionsJSON)

                if !findings.isEmpty {
                    Divider().padding(.vertical, 2)
                    Text("FINDINGS (\(findings.count))")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    ForEach(Array(findings.enumerated()), id: \.offset) { _, f in
                        HStack(alignment: .top, spacing: 4) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 4))
                                .foregroundStyle(.secondary)
                                .padding(.top, 6)
                            Text(f)
                                .font(.system(size: 10))
                                .foregroundStyle(.primary.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if !topActions.isEmpty {
                    Divider().padding(.vertical, 2)
                    Text("TOP ACTIONS (\(topActions.count))")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    ForEach(Array(topActions.enumerated()), id: \.offset) { _, a in
                        HStack(alignment: .top, spacing: 4) {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 9))
                                .foregroundStyle(IRISTokens.irisAccent)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(a.action)
                                    .font(.system(size: 10, weight: .medium))
                                    .fixedSize(horizontal: false, vertical: true)
                                HStack(spacing: 6) {
                                    Text("effort: \(a.effort)").foregroundStyle(IRISTokens.goldAccent)
                                    Text("impact: \(a.impact)").foregroundStyle(IRISTokens.aquaTint)
                                }
                                .font(.system(size: 8, design: .monospaced))
                            }
                        }
                    }
                }

                Divider().padding(.vertical, 2)
                HStack(spacing: IRISTokens.spacing8) {
                    Text("model: \(audit.modelUsed)")
                    Text("cost: $\(String(format: "%.4f", audit.costUSD))")
                    Text("\(Int(audit.durationSeconds))s")
                    Spacer()
                    // v1.77 + v1.124 — Rerun audit avec force=true pour bypass fingerprint cache
                    Button {
                        let codename = audit.projectCodename
                        Task { await Auditor.shared.auditProject(codename: codename, force: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                            .foregroundStyle(IRISTokens.aquaTint)
                    }
                    .buttonStyle(.plain)
                    .help("Re-audit ce projet (force bypass fingerprint cache)")
                    // v1.166 — Compare with previous audit
                    Button {
                        let diff = Self.diffWithPreviousAudit(current: audit, allAudits: allAudits)
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(diff, forType: .string)
                    } label: {
                        Image(systemName: "arrow.left.arrow.right.square")
                            .font(.system(size: 10))
                            .foregroundStyle(IRISTokens.goldAccent)
                    }
                    .buttonStyle(.plain)
                    .help("Comparer cette audit avec le précédent du même projet (diff verdict + findings count)")
                    // v1.192 — Copy verdict text only
                    Button { copyVerdict(audit) } label: {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 9))
                            .foregroundStyle(IRISTokens.aquaTint.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .help("Copier la verdict text dans presse-papier")
                    if let status = copyVerdictStatus {
                        Text(status)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(status == "✅" ? .green : .secondary)
                    }
                    // v1.73 — Copy markdown
                    Button {
                        let md = Self.formatAuditAsMarkdown(audit)
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(md, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Copy l'audit complet en Markdown")
                }
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(.thinMaterial))
        .contentShape(Rectangle())
        .onTapGesture {
            if isExpanded {
                expandedAuditIds.remove(audit.id)
            } else {
                expandedAuditIds.insert(audit.id)
            }
        }
    }

    // v1.192 — Copy verdict text only to pasteboard
    private func copyVerdict(_ audit: AuditReport) {
        guard !audit.verdict.isEmpty else {
            copyVerdictStatus = "⚠️ vide"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copyVerdictStatus = nil }
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(audit.verdict, forType: .string)
        copyVerdictStatus = "✅"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copyVerdictStatus = nil }
    }

    // v1.62 — JSON parsing helpers pour AuditReport
    private struct ActionItem {
        let action: String
        let effort: String
        let impact: String
    }

    private static func parseStringArray(_ json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [String]
        else { return [] }
        return arr
    }

    // v1.166 — Diff audit avec le précédent du même projet
    private static func diffWithPreviousAudit(current: AuditReport, allAudits: [AuditReport]) -> String {
        let previous = allAudits
            .filter { $0.projectCodename == current.projectCodename && $0.createdAt < current.createdAt }
            .sorted { $0.createdAt > $1.createdAt }
            .first
        guard let prev = previous else {
            return "Pas d'audit précédent pour \(current.projectCodename)."
        }
        let prevFindings = parseStringArray(prev.findingsJSON).count
        let curFindings = parseStringArray(current.findingsJSON).count
        let delta = curFindings - prevFindings
        let findingsLine: String
        if delta > 0 {
            findingsLine = "+\(delta) finding\(delta == 1 ? "" : "s")"
        } else if delta < 0 {
            let absD = -delta
            findingsLine = "-\(absD) finding\(absD == 1 ? "" : "s")"
        } else {
            findingsLine = "(stable)"
        }
        let verdictLine = prev.verdict == current.verdict
            ? "(verdict stable: \(current.verdict))"
            : "\(prev.verdict) → \(current.verdict)"
        var md = "# Diff audit — \(current.projectCodename)\n\n"
        md += "**Verdict** : \(verdictLine)\n"
        md += "**Findings** : \(findingsLine) (\(prevFindings) → \(curFindings))\n\n"
        md += "**Previous headline** : \(prev.headline)\n"
        md += "**Current headline** : \(current.headline)\n"
        return md
    }

    // v1.73 — Audit → Markdown formaté
    private static func formatAuditAsMarkdown(_ audit: AuditReport) -> String {
        let findings = parseStringArray(audit.findingsJSON)
        let topActions = parseActionObjects(audit.topActionsJSON)
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd HH:mm"

        var md = "# Audit — \(audit.projectCodename) — \(audit.verdict)\n\n"
        md += "**Date** : \(dateFmt.string(from: audit.createdAt))  \n"
        md += "**Model** : `\(audit.modelUsed)` · `$\(String(format: "%.4f", audit.costUSD))` · `\(Int(audit.durationSeconds))s`\n\n"
        md += "## Headline\n\n\(audit.headline)\n\n"

        if !findings.isEmpty {
            md += "## Findings (\(findings.count))\n\n"
            for f in findings {
                md += "- \(f)\n"
            }
            md += "\n"
        }

        if !topActions.isEmpty {
            md += "## Top actions (\(topActions.count))\n\n"
            for a in topActions {
                md += "- **\(a.action)** _(effort: \(a.effort) · impact: \(a.impact))_\n"
            }
            md += "\n"
        }

        md += "---\n\n*Exported from IRIS auditor — \(dateFmt.string(from: Date()))*\n"
        return md
    }

    private static func parseActionObjects(_ json: String) -> [ActionItem] {
        guard let data = json.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        return arr.compactMap { dict in
            guard let action = dict["action"] as? String else { return nil }
            return ActionItem(
                action: action,
                effort: (dict["effort"] as? String) ?? "—",
                impact: (dict["impact"] as? String) ?? "—"
            )
        }
    }

    // MARK: — Builder

    private var builderSection: some View {
        VStack(alignment: .leading, spacing: IRISTokens.spacing8) {
            // v1.254 — Inlined section header to inject "X total" scaffolds badge
            HStack(spacing: 4) {
                Text("BUILDER")
                    .font(.system(size: 10, weight: .semibold)).tracking(1.4).foregroundStyle(.secondary)
                if Builder.availableSkills.count > 0 {
                    Text("\(Builder.availableSkills.count)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(IRISTokens.irisAccent)
                }
                builderCountBadge
                Spacer()
                Button {
                    copyAgentSummary(for: .builder, count: Builder.availableSkills.count)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Copy Builder summary Markdown")
                Button {
                    pinned.toggle(.builder)
                } label: {
                    Image(systemName: pinned.isPinned(.builder) ? "pin.fill" : "pin")
                        .font(.system(size: 10))
                        .foregroundStyle(pinned.isPinned(.builder) ? IRISTokens.irisAccent : .secondary)
                }
                .buttonStyle(.plain)
                .help(pinned.isPinned(.builder) ? "Désépingler section" : "Épingler section (toujours visible)")
            }
            .padding(.horizontal, IRISTokens.spacing4)

            Picker("Skill", selection: $scaffoldSelectedSkill) {
                ForEach(Builder.availableSkills) { skill in
                    Text(skill.name).tag(skill.name)
                }
            }
            .labelsHidden()
            .controlSize(.small)

            TextField("nom du projet (ex: nouveau_client_v0)", text: $scaffoldProjectName)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .controlSize(.small)

            HStack(spacing: IRISTokens.spacing8) {
                Button {
                    let name = scaffoldProjectName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    Task {
                        await Builder.shared.scaffold(
                            skillName: scaffoldSelectedSkill,
                            projectName: name,
                            targetDirectory: nil
                        )
                    }
                    scaffoldProjectName = ""
                } label: {
                    Label("Scaffold", systemImage: "hammer")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(scaffoldProjectName.trimmingCharacters(in: .whitespaces).isEmpty)

                Button {
                    let name = scaffoldProjectName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    Task {
                        await Builder.shared.scaffoldWithGitPush(
                            skillName: scaffoldSelectedSkill,
                            projectName: name
                        )
                    }
                    scaffoldProjectName = ""
                } label: {
                    Label("Scaffold + Push", systemImage: "arrow.up.circle.fill")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(IRISTokens.irisAccent)
                .disabled(scaffoldProjectName.trimmingCharacters(in: .whitespaces).isEmpty)
                .help("Scaffold + git init + commit + gh repo create + push (action git nécessite approval)")

                // v1.137 — Scaffold + Open in IDE (1-click workflow)
                Button {
                    let name = scaffoldProjectName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    Task {
                        await Builder.shared.scaffoldAndOpen(
                            skillName: scaffoldSelectedSkill,
                            projectName: name
                        )
                    }
                    scaffoldProjectName = ""
                } label: {
                    Label("Scaffold + Open", systemImage: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(IRISTokens.aquaTint)
                .disabled(scaffoldProjectName.trimmingCharacters(in: .whitespaces).isEmpty)
                .help("Scaffold + ouvre dans Cursor/Xcode immédiatement")
            }

            Divider().padding(.vertical, 2)

            Text("Skill sélectionné")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)

            if let adapter = Builder.availableSkills.first(where: { $0.name == scaffoldSelectedSkill }),
               let entry = SkillRegistry.shared.allSkills.first(where: { $0.name == adapter.name }) {
                // v1.144 — Badges priorité + source + path
                HStack(spacing: 4) {
                    Text(entry.priority.rawValue)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(skillPriorityColor(entry.priority))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(skillPriorityColor(entry.priority).opacity(0.15))
                        .clipShape(Capsule())
                    Text(entry.source.rawValue)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    // v1.144 — Bouton reveal SKILL.md dans Finder
                    Button {
                        let path = ("~/.claude/skills/\(entry.name)/SKILL.md" as NSString).expandingTildeInPath
                        if FileManager.default.fileExists(atPath: path) {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                        }
                    } label: {
                        Image(systemName: "folder")
                            .font(.system(size: 10))
                            .foregroundStyle(IRISTokens.aquaTint)
                    }
                    .buttonStyle(.plain)
                    .help("Reveal SKILL.md dans Finder")
                }
                Text(adapter.summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func skillPriorityColor(_ priority: SkillPriority) -> Color {
        switch priority {
        case .high: return IRISTokens.irisAccent
        case .medium: return IRISTokens.aquaTint
        case .low: return .secondary
        }
    }

    // MARK: — Advisor

    private var advisorSection: some View {
        let recent = Array(advisorBriefings.prefix(3))
        let opusCost = appState.costByModel["claude-opus-4-7"] ?? 0
        return VStack(alignment: .leading, spacing: IRISTokens.spacing8) {
            // v1.236 — Inlined section header to inject "X past 7d" briefings badge
            HStack(spacing: 4) {
                Text("ADVISOR")
                    .font(.system(size: 10, weight: .semibold)).tracking(1.4).foregroundStyle(.secondary)
                if recent.count > 0 {
                    Text("\(recent.count)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(IRISTokens.irisAccent)
                }
                briefingsCountBadge
                Spacer()
                Button {
                    copyAgentSummary(for: .advisor, count: recent.count)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Copy Advisor summary Markdown")
                Button {
                    pinned.toggle(.advisor)
                } label: {
                    Image(systemName: pinned.isPinned(.advisor) ? "pin.fill" : "pin")
                        .font(.system(size: 10))
                        .foregroundStyle(pinned.isPinned(.advisor) ? IRISTokens.irisAccent : .secondary)
                }
                .buttonStyle(.plain)
                .help(pinned.isPinned(.advisor) ? "Désépingler section" : "Épingler section (toujours visible)")
            }
            .padding(.horizontal, IRISTokens.spacing4)

            HStack(spacing: IRISTokens.spacing8) {
                Button {
                    Task { await Advisor.shared.runBriefing(kind: .manual) }
                } label: {
                    Label("Brief now", systemImage: "sunrise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(IRISTokens.irisAccent)

                Spacer()

                Text("Opus session: $\(String(format: "%.4f", opusCost))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Text("Briefing scheduled : 8h00 chaque matin")
                .font(.system(size: 10)).foregroundStyle(.secondary)

            // v1.32 — derniers briefings
            if !recent.isEmpty {
                Divider().padding(.vertical, 2)
                Text("DERNIERS BRIEFINGS")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                ForEach(recent) { event in
                    advisorBriefingRow(event)
                }
            }
        }
    }

    private func advisorBriefingRow(_ event: EventLog) -> some View {
        // Extract preview de content depuis payloadJSON
        let preview = extractContent(event.payloadJSON).prefix(120)
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: "sunrise.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(IRISTokens.goldAccent)
                Text(event.timestamp, format: .dateTime.day().month().hour().minute())
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Text(String(preview))
                .font(.system(size: 10))
                .foregroundStyle(.primary.opacity(0.8))
                .lineLimit(3)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(.thinMaterial))
    }

    private func extractContent(_ payloadJSON: String) -> String {
        guard let data = payloadJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? String else { return "(no content)" }
        return content
    }

    // MARK: — Simple agent (Conductor / Sentinel / Scribe / Quill / Envoy / Witness)

    private func simpleAgentSection(_ id: AgentID) -> some View {
        let descriptor = id.descriptor
        return VStack(alignment: .leading, spacing: IRISTokens.spacing8) {
            sectionHeader(descriptor.displayName, count: 0, accent: IRISTokens.irisAccent, pinnable: id)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: descriptor.symbol)
                        .foregroundStyle(IRISTokens.irisAccent)
                    Text(descriptor.alias)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Text(descriptor.tagline)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Runtime live (auto).")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.green)

                // v1.91 — Sentinel snooze status badges (si id == sentinel)
                if id == .sentinel {
                    sentinelSnoozeBadges
                    // v1.156 — Sentinel last poll timestamps
                    sentinelLastPollBadges
                }

                // v1.97 — ActionLog history (5 derniers par agent)
                actionLogHistorySection(for: id)
            }
        }
    }

    // v1.97 — Affiche les 5 dernières ActionLog pour un agent donné
    @ViewBuilder
    private func actionLogHistorySection(for id: AgentID) -> some View {
        let recent = allActionLogs.filter { $0.agentId == id.rawValue }.prefix(5)
        if !recent.isEmpty {
            Divider().padding(.vertical, 2)
            Text("RECENT ACTIONS (\(recent.count))")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
            ForEach(Array(recent)) { action in
                HStack(spacing: 4) {
                    Image(systemName: action.success ? "checkmark.circle" : "xmark.circle")
                        .font(.system(size: 9))
                        .foregroundStyle(action.success ? .green : .red)
                    Text(action.actionType)
                        .font(.system(size: 10, weight: .medium))
                    Spacer()
                    if action.executedByUserApproval {
                        Image(systemName: "person.fill.checkmark")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                            .help("Exécuté avec approval user")
                    }
                    Text(action.executedAt, format: .dateTime.day().month(.abbreviated).hour().minute())
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 4)
                .background(RoundedRectangle(cornerRadius: 4).fill(.thinMaterial))
            }
        }
    }

    // v1.156 — Sentinel last poll timestamps (visible debug santé)
    @State private var sentinelTimestamps: SentinelTimestamps = .empty
    private struct SentinelTimestamps {
        let stub: Date?
        let github: Date?
        let fs: Date?
        let mcp: Date?
        static let empty = SentinelTimestamps(stub: nil, github: nil, fs: nil, mcp: nil)
    }

    @ViewBuilder
    private var sentinelLastPollBadges: some View {
        let items: [(label: String, date: Date?)] = [
            ("stub", sentinelTimestamps.stub),
            ("github", sentinelTimestamps.github),
            ("fs", sentinelTimestamps.fs),
            ("mcp", sentinelTimestamps.mcp)
        ]
        let nonEmpty = items.filter { $0.date != nil }
        if !nonEmpty.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Divider().padding(.vertical, 2)
                Text("LAST POLL")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    ForEach(nonEmpty, id: \.label) { item in
                        if let date = item.date {
                            let relative = RelativeDateTimeFormatter().localizedString(for: date, relativeTo: .now)
                            Text("\(item.label) \(relative)")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(IRISTokens.aquaTint.opacity(0.10))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            .task {
                // Charge les timestamps actor-isolated
                let stub = await Sentinel.shared.lastStubEmittedAt
                let github = await Sentinel.shared.lastGithubPollAt
                let fs = await Sentinel.shared.lastFSPollAt
                let mcp = await Sentinel.shared.lastMCPPollAt
                sentinelTimestamps = SentinelTimestamps(stub: stub, github: github, fs: fs, mcp: mcp)
            }
        }
    }

    // v1.91 — Affiche les sources Sentinel actuellement snoozées avec remaining time
    @ViewBuilder
    private var sentinelSnoozeBadges: some View {
        let now = Date()
        let snoozed = Sentinel.knownSources.compactMap { source -> (String, Date)? in
            guard let until = Sentinel.snoozeUntil(source: source), until > now else { return nil }
            return (source, until)
        }
        if !snoozed.isEmpty {
            HStack(spacing: 4) {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(IRISTokens.goldAccent)
                ForEach(snoozed, id: \.0) { item in
                    Text("\(item.0) \(Self.remainingShort(item.1))")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(IRISTokens.goldAccent)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(IRISTokens.goldAccent.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
            .padding(.top, 4)
        }
    }

    private static func remainingShort(_ until: Date) -> String {
        let s = max(0, until.timeIntervalSinceNow)
        if s < 60 { return "\(Int(s))s" }
        if s < 3600 { return "\(Int(s/60))m" }
        return "\(Int(s/3600))h"
    }

    // MARK: — Pending actions

    private var pendingActionsSection: some View {
        VStack(alignment: .leading, spacing: IRISTokens.spacing8) {
            HStack {
                sectionHeader("Actions en attente", count: appState.pendingActions.count, accent: .red)
                // v1.141 — Batch approve/reject toutes les pending réversibles
                if appState.pendingActions.contains(where: { $0.isReversible }) {
                    Button {
                        let reversibles = appState.pendingActions.filter { $0.isReversible }
                        Task {
                            for action in reversibles {
                                await EventBus.shared.publish(
                                    .actionApproved(actionId: action.actionId, approvedAt: .now)
                                )
                            }
                        }
                    } label: {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)
                    .help("Approve toutes les actions réversibles (\(appState.pendingActions.filter { $0.isReversible }.count))")
                }
            }

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
                        await EventBus.shared.publish(.actionApproved(actionId: action.actionId, approvedAt: .now))
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(IRISTokens.irisAccent)

                Button("Reject") {
                    Task {
                        await EventBus.shared.publish(.actionRejected(actionId: action.actionId, reason: nil))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.red)

                Spacer()
            }
        }
        .padding(IRISTokens.spacing16)
        .background(RoundedRectangle(cornerRadius: IRISTokens.cornerRadiusMedium).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: IRISTokens.cornerRadiusMedium).strokeBorder(IRISTokens.goldAccent.opacity(0.3), lineWidth: 0.5))
    }

    // MARK: — Drafts + Signals

    private var draftsSection: some View {
        // v1.78 — filter status
        let availableStatuses = Array(Set(allDrafts.map(\.status))).sorted()
        let filteredAll = draftStatusFilter.isEmpty
            ? Array(allDrafts)
            : allDrafts.filter { $0.status == draftStatusFilter }
        let drafts = Array(filteredAll.prefix(5))
        return VStack(alignment: .leading, spacing: IRISTokens.spacing8) {
            HStack {
                sectionHeader("Drafts récents", count: drafts.count, accent: .secondary)
                // v1.85 — Compose new manual
                Button {
                    showComposeDraft = true
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(IRISTokens.aquaTint)
                }
                .buttonStyle(.plain)
                .help("Composer un draft manuel (bypass Quill)")
                if !availableStatuses.isEmpty {
                    Picker("", selection: $draftStatusFilter) {
                        Text("all").tag("")
                        ForEach(availableStatuses, id: \.self) { s in
                            Text(s).tag(s)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.mini)
                    .frame(maxWidth: 90)
                }
            }
            if drafts.isEmpty {
                Text(draftStatusFilter.isEmpty
                    ? "Quill se déclenche sur signaux ≥ high."
                    : "Aucun draft avec status=\(draftStatusFilter).")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(drafts) { draft in draftRow(draft) }
            }
        }
    }

    private func draftRow(_ draft: Draft) -> some View {
        let isEditing = editingDraftId == draft.id
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: channelIcon(draft.channel))
                    .font(.system(size: 11)).foregroundStyle(IRISTokens.irisAccent)
                Text(draft.subject ?? String(draft.content.prefix(50)))
                    .font(.system(size: 12, weight: .medium)).lineLimit(1)
                Spacer()
                // v1.63 — Edit inline
                Button {
                    if isEditing {
                        // Save
                        draft.content = draftEditBuffer
                        try? modelContext.save()
                        editingDraftId = nil
                    } else {
                        draftEditBuffer = draft.content
                        editingDraftId = draft.id
                    }
                } label: {
                    Image(systemName: isEditing ? "checkmark.circle" : "pencil")
                        .font(.system(size: 10))
                        .foregroundStyle(isEditing ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .help(isEditing ? "Sauvegarder modifs" : "Éditer le contenu")
                // v1.34 — Copy to clipboard
                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    let toCopy: String
                    if let subject = draft.subject {
                        toCopy = "Subject: \(subject)\n\n\(draft.content)"
                    } else {
                        toCopy = draft.content
                    }
                    pasteboard.setString(toCopy, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Copier draft dans le clipboard")
                // v1.51 — Open in Mail.app via mailto:
                if draft.channel == "email" {
                    Button {
                        openInMailApp(draft: draft)
                    } label: {
                        Image(systemName: "paperplane")
                            .font(.system(size: 10))
                            .foregroundStyle(IRISTokens.irisAccent)
                    }
                    .buttonStyle(.plain)
                    .help("Ouvrir dans Mail.app (mailto:)")
                }
                // v1.63 — Delete
                Button {
                    if editingDraftId == draft.id { editingDraftId = nil }
                    modelContext.delete(draft)
                    try? modelContext.save()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Supprimer ce draft")
                statusBadge(draft.status)
            }

            // v1.63 — Inline editor
            if isEditing {
                TextEditor(text: $draftEditBuffer)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(minHeight: 80, maxHeight: 200)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.05)))
                    .padding(.top, 2)
            }

            HStack(spacing: IRISTokens.spacing8) {
                Text(draft.tone).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                // v1.228 — Model tag (color-coded by family)
                if !draft.modelUsed.isEmpty {
                    Text(modelShortName(draft.modelUsed))
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(modelColor(draft.modelUsed))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(modelColor(draft.modelUsed).opacity(0.12)))
                }
                Text(draft.createdAt, format: .dateTime.hour().minute().second())
                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                Spacer()
                Text("$\(String(format: "%.5f", draft.costUSD))")
                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4).padding(.horizontal, IRISTokens.spacing8)
        .background(RoundedRectangle(cornerRadius: IRISTokens.cornerRadiusSmall).fill(.thinMaterial))
    }

    // v1.228 — Short label for model family tag
    private func modelShortName(_ model: String) -> String {
        let lower = model.lowercased()
        if lower.contains("opus") { return "Opus" }
        if lower.contains("sonnet") { return "Sonnet" }
        if lower.contains("haiku") { return "Haiku" }
        return String(model.prefix(10))
    }

    // v1.228 — Color-coded model family tint
    private func modelColor(_ model: String) -> Color {
        let lower = model.lowercased()
        if lower.contains("opus") { return IRISTokens.irisAccent }
        if lower.contains("sonnet") { return IRISTokens.aquaTint }
        if lower.contains("haiku") { return IRISTokens.goldAccent }
        return .secondary
    }

    private var signalsSection: some View {
        let signals = Array(allSignals.prefix(8))
        let unackedCount = signals.filter { !$0.acknowledged }.count
        return VStack(alignment: .leading, spacing: IRISTokens.spacing8) {
            HStack {
                sectionHeader("Signals récents", count: signals.count, accent: .secondary)
                // v1.99 — Mark all visible acknowledged (batch action)
                if unackedCount > 0 {
                    Button {
                        for signal in signals where !signal.acknowledged {
                            signal.acknowledged = true
                        }
                        try? modelContext.save()
                    } label: {
                        Image(systemName: "checkmark.seal")
                            .font(.system(size: 11))
                            .foregroundStyle(.green.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .help("Marquer tous les \(unackedCount) signaux visibles comme acknowledged")
                }
            }
            if signals.isEmpty {
                Text("Sentinel démarre dans quelques secondes…")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                ForEach(signals) { signal in signalRow(signal) }
            }
        }
    }

    private func signalRow(_ signal: Signal) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: IRISTokens.spacing8) {
            importanceDot(signal.importance)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(signal.source.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
                    if let project = signal.projectScope {
                        Text("· \(project)")
                            .font(.system(size: 9, design: .monospaced)).foregroundStyle(IRISTokens.irisAccent)
                    }
                    Spacer()
                    // v1.82 — Send to Quill (force draft generation pour ce signal)
                    Button {
                        sendSignalToQuill(signal)
                    } label: {
                        Image(systemName: "paperplane")
                            .font(.system(size: 9))
                            .foregroundStyle(IRISTokens.aquaTint.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .help("Send to Quill (force draft generation high importance)")
                    // v1.149 — Send to Conductor as context (prepend dans currentInput + navigate)
                    Button {
                        let contextLine = "[Contexte signal \(signal.source)/\(signal.importance): \(signal.summary)]\n"
                        appState.currentInput = contextLine + appState.currentInput
                        appState.selection = .agent(.conductor)
                    } label: {
                        Image(systemName: "arrow.right.square")
                            .font(.system(size: 9))
                            .foregroundStyle(IRISTokens.irisAccent.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .help("Inject ce signal comme contexte dans le prochain message Conductor")
                    if signal.acknowledged {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                    Text(signal.emittedAt, format: .dateTime.hour().minute().second())
                        .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                }
                Text(signal.summary)
                    .font(.system(size: 11)).foregroundStyle(.primary).lineLimit(2)
            }
        }
        .padding(.vertical, 4)
        .opacity(signal.acknowledged ? 0.5 : 1.0)
        .contentShape(Rectangle())
        .onTapGesture {
            // v1.33 — toggle acknowledged state
            signal.acknowledged.toggle()
            try? modelContext.save()
        }
        .help(signal.acknowledged ? "Click pour un-acknowledge" : "Click pour acknowledge")
    }

    // v1.86 — Open project in IDE (Cursor first, then Xcode .xcodeproj, fallback Finder)
    private func openProjectInIDE(path: String) {
        let fm = FileManager.default
        let projectURL = URL(fileURLWithPath: path)

        // 1. Si .xcodeproj présent dans le dossier → Xcode
        if let contents = try? fm.contentsOfDirectory(atPath: path),
           let xcodeproj = contents.first(where: { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }) {
            let fullPath = (path as NSString).appendingPathComponent(xcodeproj)
            NSWorkspace.shared.open(URL(fileURLWithPath: fullPath))
            return
        }

        // 2. Tente Cursor (bundle id com.todesktop.230313mzl4w4u92)
        let cursorURL = URL(fileURLWithPath: "/Applications/Cursor.app")
        if fm.fileExists(atPath: cursorURL.path) {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([projectURL], withApplicationAt: cursorURL, configuration: config) { _, _ in }
            return
        }

        // 3. Fallback Finder
        NSWorkspace.shared.activateFileViewerSelecting([projectURL])
    }

    // v1.82 — Force Quill draft pour un signal donné (republie comme high importance)
    private func sendSignalToQuill(_ signal: Signal) {
        // Republie le signal comme importance .high pour déclencher Quill (qui filtre >= .high)
        let summary = signal.summary
        let source = signal.source
        Task {
            await EventBus.shared.publish(
                .signalEmitted(from: .sentinel, importance: .high, summary: summary, source: source)
            )
        }
    }

    // v1.185 — Export tous les drafts créés aujourd'hui en un seul Markdown sur le home dir
    private func exportTodaysDrafts() {
        let todays = allDrafts.filter { Calendar.current.isDateInToday($0.createdAt) }
        guard !todays.isEmpty else { return }

        let dateHeader = Date().formatted(date: .complete, time: .omitted)
        var md = "# IRIS Drafts — \(dateHeader)\n\n"
        md += "_\(todays.count) drafts_\n\n"
        md += "---\n\n"
        for draft in todays {
            let title = draft.subject ?? draft.tone
            md += "## \(title.isEmpty ? "(no subject)" : title)\n\n"
            md += "**Created:** \(draft.createdAt.formatted(.dateTime.hour().minute()))\n\n"
            if !draft.tone.isEmpty {
                md += "**Tone:** \(draft.tone)\n\n"
            }
            md += "```\n\(draft.content)\n```\n\n---\n\n"
        }

        let iso = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("iris-drafts-today-\(iso).md")

        do {
            try md.write(to: url, atomically: true, encoding: .utf8)
            exportDraftsStatus = "✅ → \(url.lastPathComponent)"
        } catch {
            exportDraftsStatus = "⚠️ \(error.localizedDescription)"
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            exportDraftsStatus = nil
        }
    }

    // v1.260 — Export TOUS les audits en un seul Markdown sur le home dir
    private func exportAllAuditsMD() {
        guard !allAudits.isEmpty else { return }

        let header = "# IRIS Audits Export — \(Date().formatted(date: .complete, time: .shortened))\n\n"
        var md = header
        md += "_\(allAudits.count) audits_\n\n"
        md += "---\n\n"

        for audit in allAudits {
            md += "## \(audit.projectCodename) · \(audit.verdict)\n\n"
            md += "**Created:** \(audit.createdAt.formatted(.dateTime.day().month().year().hour().minute()))\n\n"
            md += "**Model:** \(audit.modelUsed) · **Cost:** $\(String(format: "%.3f", audit.costUSD))\n\n"

            let findings = Self.parseStringArray(audit.findingsJSON)
            if !findings.isEmpty {
                md += "**Findings:**\n"
                for f in findings { md += "- \(f)\n" }
                md += "\n"
            }

            let topActions = Self.parseActionObjects(audit.topActionsJSON)
            if !topActions.isEmpty {
                md += "**Top actions:**\n"
                for a in topActions {
                    md += "- \(a.action) _(effort: \(a.effort) · impact: \(a.impact))_\n"
                }
                md += "\n"
            }

            md += "---\n\n"
        }

        let iso = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("iris-audits-\(iso).md")

        do {
            try md.write(to: url, atomically: true, encoding: .utf8)
            exportAuditsStatus = "✅ → \(url.lastPathComponent)"
        } catch {
            exportAuditsStatus = "⚠️ \(error.localizedDescription)"
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            exportAuditsStatus = nil
        }
    }

    // MARK: — Helpers visuels

    private func sectionHeader(_ title: String, count: Int, accent: Color) -> some View {
        sectionHeader(title, count: count, accent: accent, pinnable: nil)
    }

    // v1.158 — Copy agent stats summary to clipboard (utile pour share debug ou Notion)
    private func copyAgentSummary(for id: AgentID, count: Int) {
        let date = DateFormatter()
        date.dateFormat = "yyyy-MM-dd HH:mm"
        let descriptor = id.descriptor
        var md = "## \(descriptor.displayName) (`\(id.rawValue)`)\n\n"
        md += "_\(descriptor.tagline)_\n\n"
        md += "- **Count** : \(count)\n"
        md += "- **Status** : \(appState.agentStatus(id).rawValue)\n"
        md += "- **Date snapshot** : \(date.string(from: Date()))\n"
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(md, forType: .string)
    }

    // v1.48 — Header avec bouton pin pour agent sections
    @ViewBuilder
    private func sectionHeader(_ title: String, count: Int, accent: Color, pinnable agentId: AgentID?) -> some View {
        HStack(spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold)).tracking(1.4).foregroundStyle(.secondary)
            if count > 0 {
                Text("\(count)").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(accent)
            }
            Spacer()
            if let agentId {
                // v1.158 — Copy stats summary to clipboard (Markdown)
                Button {
                    copyAgentSummary(for: agentId, count: count)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Copy \(agentId.descriptor.displayName) summary Markdown")
                Button {
                    pinned.toggle(agentId)
                } label: {
                    Image(systemName: pinned.isPinned(agentId) ? "pin.fill" : "pin")
                        .font(.system(size: 10))
                        .foregroundStyle(pinned.isPinned(agentId) ? IRISTokens.irisAccent : .secondary)
                }
                .buttonStyle(.plain)
                .help(pinned.isPinned(agentId) ? "Désépingler section" : "Épingler section (toujours visible)")
            }
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
            case "sent", "active": return .green
            case "approved": return IRISTokens.aquaTint
            case "rejected", "failed": return .red
            case "tiede": return IRISTokens.goldAccent
            case "dormant", "archived": return .secondary
            default: return .secondary
            }
        }()
        return Text(status)
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(color.opacity(0.12)).clipShape(Capsule())
    }

    private func verdictBadge(_ verdict: String) -> some View {
        let color: Color = {
            switch verdict {
            case "GREEN": return .green
            case "YELLOW": return IRISTokens.goldAccent
            case "RED": return .red
            default: return .secondary
            }
        }()
        return Text(verdict)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(color.opacity(0.15)).clipShape(Capsule())
    }

    // MARK: — v1.51 Mail.app handoff

    private func openInMailApp(draft: Draft) {
        let subject = draft.subject ?? "Draft IRIS"
        let body = draft.content

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = ""
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]

        if let url = components.url {
            NSWorkspace.shared.open(url)
        }
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
        return Circle().fill(color).frame(width: 6, height: 6).padding(.top, 4)
    }
}

#Preview {
    InspectorView()
        .environment(IRISAppState())
        .frame(width: 340, height: 700)
}

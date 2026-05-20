import SwiftUI
import SwiftData
import AppKit

// IRIS v1.0.A — Inspector dédié par agent sélectionné. Sections globales (pending actions / drafts / signals) toujours visibles.
// + Sections agent-spécifiques quand sélectionné : Cartographer / Auditor / Builder / Advisor.

struct InspectorView: View {
    @Environment(IRISAppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @State private var pinned = InspectorPinnedSections.shared  // v1.48

    @Query(sort: \Draft.createdAt, order: .reverse) private var allDrafts: [Draft]
    @Query(sort: \Signal.emittedAt, order: .reverse) private var allSignals: [Signal]
    @Query(sort: \ProjectRecord.lastPushAt, order: .reverse) private var allProjects: [ProjectRecord]
    @Query(sort: \AuditReport.createdAt, order: .reverse) private var allAudits: [AuditReport]
    // v1.32 — derniers briefings Advisor depuis EventLog (kind=agentResponse, fromAgent=advisor)
    @Query(
        filter: #Predicate<EventLog> { $0.kind == "agentResponse" && $0.fromAgent == "advisor" },
        sort: \EventLog.timestamp,
        order: .reverse
    ) private var advisorBriefings: [EventLog]

    @State private var scaffoldProjectName: String = ""
    @State private var scaffoldSelectedSkill: String = "doc-first-project-scaffolding"
    @State private var auditPickedProject: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: IRISTokens.spacing24) {
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
        default:
            simpleAgentSection(id)
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
                Spacer()
            }
        }
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
        return VStack(alignment: .leading, spacing: IRISTokens.spacing8) {
            sectionHeader("Witness", count: screenSignals.count, accent: IRISTokens.irisAccent, pinnable: .witness)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "eyes")
                        .foregroundStyle(IRISTokens.irisAccent)
                    Text("Témoin")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
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
                Text("DERNIERS CONTEXTES")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                ForEach(Array(screenSignals)) { signal in
                    witnessRow(signal)
                }
            }
        }
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
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(.thinMaterial))
    }

    // MARK: — Cartographer

    private var cartographerSection: some View {
        VStack(alignment: .leading, spacing: IRISTokens.spacing8) {
            sectionHeader("Cartographer", count: allProjects.count, accent: IRISTokens.irisAccent, pinnable: .cartographer)

            Button {
                Task { await Cartographer.shared.refresh() }
            } label: {
                Label("Refresh now", systemImage: "arrow.clockwise")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            ForEach(Array(allProjects.prefix(8))) { project in
                projectRow(project)
            }

            if allProjects.count > 8 {
                Text("… +\(allProjects.count - 8) autres")
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
            if project.isPrivate {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(.thinMaterial))
    }

    // MARK: — Auditor

    private var auditorSection: some View {
        VStack(alignment: .leading, spacing: IRISTokens.spacing8) {
            sectionHeader("Auditor", count: allAudits.count, accent: IRISTokens.irisAccent, pinnable: .auditor)

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

            ForEach(Array(allAudits.prefix(5))) { audit in
                auditRow(audit)
            }
        }
    }

    private func auditRow(_ audit: AuditReport) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                verdictBadge(audit.verdict)
                Text(audit.projectCodename)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text(audit.createdAt, format: .dateTime.day().month(.abbreviated).hour().minute())
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Text(audit.headline)
                .font(.system(size: 11))
                .foregroundStyle(.primary.opacity(0.8))
                .lineLimit(2)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(.thinMaterial))
    }

    // MARK: — Builder

    private var builderSection: some View {
        VStack(alignment: .leading, spacing: IRISTokens.spacing8) {
            sectionHeader("Builder", count: Builder.availableSkills.count, accent: IRISTokens.irisAccent, pinnable: .builder)

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
            }

            Divider().padding(.vertical, 2)

            Text("Skill sélectionné")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)

            if let selected = Builder.availableSkills.first(where: { $0.name == scaffoldSelectedSkill }) {
                Text(selected.summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: — Advisor

    private var advisorSection: some View {
        let recent = Array(advisorBriefings.prefix(3))
        let opusCost = appState.costByModel["claude-opus-4-7"] ?? 0
        return VStack(alignment: .leading, spacing: IRISTokens.spacing8) {
            sectionHeader("Advisor", count: recent.count, accent: IRISTokens.irisAccent, pinnable: .advisor)

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
            }
        }
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
        let drafts = Array(allDrafts.prefix(5))
        return VStack(alignment: .leading, spacing: IRISTokens.spacing8) {
            sectionHeader("Drafts récents", count: drafts.count, accent: .secondary)
            if drafts.isEmpty {
                Text("Quill se déclenche sur signaux ≥ high.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(drafts) { draft in draftRow(draft) }
            }
        }
    }

    private func draftRow(_ draft: Draft) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: channelIcon(draft.channel))
                    .font(.system(size: 11)).foregroundStyle(IRISTokens.irisAccent)
                Text(draft.subject ?? String(draft.content.prefix(50)))
                    .font(.system(size: 12, weight: .medium)).lineLimit(1)
                Spacer()
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
                statusBadge(draft.status)
            }
            HStack(spacing: IRISTokens.spacing8) {
                Text(draft.tone).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
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

    private var signalsSection: some View {
        let signals = Array(allSignals.prefix(8))
        return VStack(alignment: .leading, spacing: IRISTokens.spacing8) {
            sectionHeader("Signals récents", count: signals.count, accent: .secondary)
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

    // MARK: — Helpers visuels

    private func sectionHeader(_ title: String, count: Int, accent: Color) -> some View {
        sectionHeader(title, count: count, accent: accent, pinnable: nil)
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

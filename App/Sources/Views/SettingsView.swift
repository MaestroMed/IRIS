import SwiftUI
import SwiftData
import AppKit

/// v0.1 + v1.9 — Settings panel : API key Anthropic + skill marketplace + backup/restore + MIND import.
struct SettingsView: View {
    @Environment(IRISAppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var apiKeyDraft: String = ""
    @State private var testStatus: TestStatus = .idle
    @State private var savedMessage: String?
    @State private var backupStatus: String?

    enum TestStatus: Equatable {
        case idle
        case testing
        case success(String)
        case failure(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: IRISTokens.spacing24) {
            header

            Divider()

            anthropicKeySection

            Divider()

            skillMarketplaceSection

            Divider()

            modelsRoutingSection

            Divider()

            backupSection

            Divider()

            sentinelIntervalsSection

            Divider()

            conductorPromptSection

            Divider()

            agentVisibilitySection

            Divider()

            notificationsSection

            Divider()

            dangerZoneSection

            Spacer()

            footer
        }
        .padding(IRISTokens.spacing32)
        .frame(minWidth: 560, idealWidth: 640, minHeight: 480)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            apiKeyDraft = IRISKeychain.shared.getAnthropicAPIKey() ?? ""
        }
    }

    // MARK: — Sections

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Settings")
                .font(.system(size: 32, weight: .light, design: .serif))
                .foregroundStyle(IRISTokens.irisAccent)
            Text("v0.1")
                .font(IRISTokens.monoFont)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Fermer", action: { dismiss() })
                .keyboardShortcut(.cancelAction)
        }
    }

    private var anthropicKeySection: some View {
        VStack(alignment: .leading, spacing: IRISTokens.spacing16) {
            sectionTitle("Anthropic API key", subtitle: "Requis pour Conductor + Quill + Auditor + Advisor + Builder (Claude Opus / Sonnet).")

            SecureField("sk-ant-…", text: $apiKeyDraft)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, design: .monospaced))

            HStack {
                Button(action: saveKey) {
                    Label("Enregistrer", systemImage: "lock.shield")
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(apiKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty)

                Button(action: testKey) {
                    if case .testing = testStatus {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Tester (Haiku ping)", systemImage: "network")
                    }
                }
                .disabled(apiKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty)

                if appState.hasAnthropicKey {
                    Button(role: .destructive, action: deleteKey) {
                        Label("Supprimer", systemImage: "trash")
                    }
                }

                Spacer()
            }

            statusBanner
        }
    }

    private var skillMarketplaceSection: some View {
        let registry = SkillRegistry.shared
        return VStack(alignment: .leading, spacing: IRISTokens.spacing8) {
            HStack(alignment: .top) {
                sectionTitle(
                    "Skill marketplace (\(registry.enabledNames.count)/\(registry.allSkills.count) actifs)",
                    subtitle: "Toggle pour activer/désactiver. Builder utilise uniquement les skills actifs."
                )
                Spacer()
                HStack(spacing: 4) {
                    Button(action: exportSkillsConfig) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .controlSize(.mini)
                    .help("Export config skills en JSON (partage entre Macs)")
                    Button(action: importSkillsConfig) {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .controlSize(.mini)
                    .help("Import config skills JSON (overwrite current)")
                }
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(SkillSource.allCasesOrdered, id: \.self) { source in
                        let skillsForSource = registry.allSkills.filter { $0.source == source }
                        if !skillsForSource.isEmpty {
                            Text(source.displayName.uppercased())
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .padding(.top, IRISTokens.spacing8)
                                .padding(.horizontal, IRISTokens.spacing4)
                            ForEach(skillsForSource) { skill in
                                skillRow(skill, registry: registry)
                            }
                        }
                    }
                }
                .padding(.horizontal, IRISTokens.spacing4)
            }
            .frame(maxHeight: 240)
        }
    }

    private func skillRow(_ skill: SkillEntry, registry: SkillRegistry) -> some View {
        HStack(alignment: .top, spacing: IRISTokens.spacing8) {
            Toggle("", isOn: Binding(
                get: { registry.isEnabled(skill.name) },
                set: { _ in registry.toggle(skill.name) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(skill.name)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                    Text(skill.priority.rawValue)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(priorityColor(skill.priority))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(priorityColor(skill.priority).opacity(0.12))
                        .clipShape(Capsule())
                }
                Text(skill.summary)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(.vertical, 3)
    }

    private func priorityColor(_ priority: SkillPriority) -> Color {
        switch priority {
        case .high: return IRISTokens.irisAccent
        case .medium: return IRISTokens.aquaTint
        case .low: return .secondary
        }
    }

    @State private var conductorModelSelection: String = ""
    @State private var auditorModelSelection: String = ""
    @State private var quillModelSelection: String = ""
    @State private var advisorModelSelection: String = ""

    private var modelsRoutingSection: some View {
        VStack(alignment: .leading, spacing: IRISTokens.spacing8) {
            sectionTitle("Routing modèles", subtitle: "v1.47 : Conductor model picker. Autres agents en pickers v1.48+.")

            // v1.47 — Picker dédié Conductor model
            HStack {
                Text("Conductor model")
                    .font(.system(size: 11))
                Spacer()
                Picker("", selection: $conductorModelSelection) {
                    Text("Opus 4.7 ($15/M in · $75/M out)").tag(ClaudeModel.opus47.rawValue)
                    Text("Sonnet 4.6 ($3/M in · $15/M out)").tag(ClaudeModel.sonnet46.rawValue)
                    Text("Haiku 4.5 ($1/M in · $5/M out)").tag(ClaudeModel.haiku45.rawValue)
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(maxWidth: 280)
                .onChange(of: conductorModelSelection) { _, newValue in
                    if let model = ClaudeModel(rawValue: newValue) {
                        Conductor.setModel(model)
                    }
                }
            }
            .padding(.leading, IRISTokens.spacing16)

            // v1.49 — Auditor model picker
            HStack {
                Text("Auditor model")
                    .font(.system(size: 11))
                Spacer()
                Picker("", selection: $auditorModelSelection) {
                    Text("Sonnet 4.6 (recommandé)").tag(ClaudeModel.sonnet46.rawValue)
                    Text("Opus 4.7 (qualité +)").tag(ClaudeModel.opus47.rawValue)
                    Text("Haiku 4.5 (cheap)").tag(ClaudeModel.haiku45.rawValue)
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(maxWidth: 280)
                .onChange(of: auditorModelSelection) { _, newValue in
                    if let model = ClaudeModel(rawValue: newValue) {
                        Auditor.setModel(model)
                    }
                }
            }
            .padding(.leading, IRISTokens.spacing16)

            // v1.50 — Quill model picker
            HStack {
                Text("Quill model")
                    .font(.system(size: 11))
                Spacer()
                Picker("", selection: $quillModelSelection) {
                    Text("Sonnet 4.6 (recommandé)").tag(ClaudeModel.sonnet46.rawValue)
                    Text("Opus 4.7 (qualité +)").tag(ClaudeModel.opus47.rawValue)
                    Text("Haiku 4.5 (cheap)").tag(ClaudeModel.haiku45.rawValue)
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(maxWidth: 280)
                .onChange(of: quillModelSelection) { _, newValue in
                    if let model = ClaudeModel(rawValue: newValue) {
                        Quill.setModel(model)
                    }
                }
            }
            .padding(.leading, IRISTokens.spacing16)

            // v1.50 — Advisor model picker
            HStack {
                Text("Advisor model")
                    .font(.system(size: 11))
                Spacer()
                Picker("", selection: $advisorModelSelection) {
                    Text("Opus 4.7 (recommandé)").tag(ClaudeModel.opus47.rawValue)
                    Text("Sonnet 4.6 (cheaper)").tag(ClaudeModel.sonnet46.rawValue)
                    Text("Haiku 4.5 (fast)").tag(ClaudeModel.haiku45.rawValue)
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(maxWidth: 280)
                .onChange(of: advisorModelSelection) { _, newValue in
                    if let model = ClaudeModel(rawValue: newValue) {
                        Advisor.setModel(model)
                    }
                }
            }
            .padding(.leading, IRISTokens.spacing16)

            Divider().padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 4) {
                routingRow(label: "Builder · Advisor", model: "claude-opus-4-7", cost: "$15/M in · $75/M out")
                routingRow(label: "Quill · Auditor", model: "claude-sonnet-4-6", cost: "$3/M in · $15/M out")
                routingRow(label: "Sentinel · Scribe · Cartographer · Envoy", model: "claude-haiku-4-5", cost: "$1/M in · $5/M out")
                routingRow(label: "Witness (v1.5+)", model: "gemini-2.5-flash-lite", cost: "cheap vision input")
            }
            .padding(.leading, IRISTokens.spacing16)
        }
        .onAppear {
            conductorModelSelection = Conductor.currentModel.rawValue
            auditorModelSelection = Auditor.currentModel.rawValue
            quillModelSelection = Quill.currentModel.rawValue
            advisorModelSelection = Advisor.currentModel.rawValue
        }
    }

    // MARK: — v1.40 Danger zone (reset all)

    private var dangerZoneSection: some View {
        VStack(alignment: .leading, spacing: IRISTokens.spacing8) {
            sectionTitle(
                "⚠️ Danger zone",
                subtitle: "Reset complet — supprime UserDefaults iris.* + Keychain Anthropic. Action irréversible."
            )

            Button(role: .destructive) {
                let alert = NSAlert()
                alert.messageText = "Reset complet IRIS ?"
                alert.informativeText = "Cela supprime : API key Anthropic, config skills, sentinel intervals, sidebar visibility, system prompt, model pickers. Les données SwiftData (memories, signals, drafts, audits) restent. Continuer ?"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Reset")
                alert.addButton(withTitle: "Annuler")
                if alert.runModal() == .alertFirstButtonReturn {
                    resetAllSettings()
                }
            } label: {
                Label("Reset all settings", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.red)
        }
    }

    private func resetAllSettings() {
        // Clear UserDefaults iris.*
        let dict = UserDefaults.standard.dictionaryRepresentation()
        for key in dict.keys where key.hasPrefix("iris.") {
            UserDefaults.standard.removeObject(forKey: key)
        }
        // Clear Keychain Anthropic
        _ = IRISKeychain.shared.deleteAnthropicAPIKey()
        // Refresh UI state
        apiKeyDraft = ""
        appState.refreshKeyPresence()
        backupStatus = "✅ Reset complet effectué — restart IRIS pour effet plein."
    }

    // MARK: — v1.44 Notifications natives macOS

    @State private var notifsEnabled: Bool = false
    @State private var notifsStatus: String = "(non vérifié)"

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: IRISTokens.spacing8) {
            sectionTitle(
                "Notifications natives macOS",
                subtitle: "Push sur signaux importance critical (CI failures, leads chauds, alertes Sentinel). Demande permission une fois."
            )

            HStack(spacing: IRISTokens.spacing8) {
                Toggle("Activer notifications critical", isOn: $notifsEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: notifsEnabled) { _, newValue in
                        IRISNotifications.isEnabled = newValue
                        if newValue {
                            Task {
                                let granted = await IRISNotifications.requestAuthorization()
                                notifsStatus = granted ? "✅ Autorisées" : "⚠️ Refusées (System Settings → Notifications → IRIS)"
                            }
                        }
                    }

                Spacer()

                Text(notifsStatus)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(notifsStatus.hasPrefix("✅") ? .green : .secondary)
            }
        }
        .onAppear {
            notifsEnabled = IRISNotifications.isEnabled
            Task {
                let status = await IRISNotifications.authorizationStatus()
                notifsStatus = {
                    switch status {
                    case .authorized, .provisional: return "✅ Autorisées"
                    case .denied: return "⚠️ Refusées (System Settings)"
                    case .notDetermined: return "(pas encore demandé)"
                    default: return "(\(status.rawValue))"
                    }
                }()
            }
        }
    }

    // MARK: — v1.43 Agent visibility sidebar

    private var agentVisibilitySection: some View {
        let visibility = AgentVisibility.shared
        return VStack(alignment: .leading, spacing: IRISTokens.spacing8) {
            sectionTitle(
                "Sidebar agents (\(visibility.visibleAgents.count)/\(AgentID.businessAgents.count) visibles)",
                subtitle: "Toggle pour masquer/afficher dans le sidebar. Persist UserDefaults."
            )

            VStack(alignment: .leading, spacing: 3) {
                ForEach(AgentID.businessAgents, id: \.rawValue) { agent in
                    HStack(spacing: 6) {
                        Toggle("", isOn: Binding(
                            get: { !visibility.isHidden(agent) },
                            set: { _ in visibility.toggle(agent) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)

                        Image(systemName: agent.descriptor.symbol)
                            .font(.system(size: 11))
                            .foregroundStyle(IRISTokens.irisAccent)
                            .frame(width: 16)

                        Text(agent.descriptor.displayName)
                            .font(.system(size: 11, design: .monospaced))

                        Text(agent.descriptor.alias)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)

                        Spacer()
                    }
                }
            }
        }
    }

    // MARK: — v1.42 Conductor system prompt customizable

    @State private var conductorPromptDraft: String = ""
    @State private var conductorPromptUsingDefault: Bool = true
    @State private var conductorPromptStatus: String?

    private var conductorPromptSection: some View {
        VStack(alignment: .leading, spacing: IRISTokens.spacing8) {
            sectionTitle(
                "Conductor system prompt",
                subtitle: "Override le prompt par défaut. Reset = revert au default. Persist UserDefaults."
            )

            ScrollView {
                TextEditor(text: $conductorPromptDraft)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(minHeight: 120, maxHeight: 200)
                    .background(RoundedRectangle(cornerRadius: IRISTokens.cornerRadiusSmall).fill(.thinMaterial))
            }
            .frame(maxHeight: 220)

            HStack(spacing: IRISTokens.spacing8) {
                Button(action: saveConductorPrompt) {
                    Label("Save override", systemImage: "checkmark.circle")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(IRISTokens.irisAccent)
                .disabled(conductorPromptDraft.trimmingCharacters(in: .whitespaces).isEmpty)

                Button(action: resetConductorPrompt) {
                    Label("Reset au default", systemImage: "arrow.uturn.backward")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(conductorPromptUsingDefault)

                Spacer()

                Text(conductorPromptUsingDefault ? "Default actif" : "Override actif")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(conductorPromptUsingDefault ? .secondary : IRISTokens.goldAccent)
            }

            if let status = conductorPromptStatus {
                Text(status)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(status.hasPrefix("✅") ? .green : .red)
            }
        }
        .onAppear {
            loadConductorPrompt()
        }
    }

    private func loadConductorPrompt() {
        conductorPromptDraft = Conductor.currentSystemPrompt()
        let override = UserDefaults.standard.string(forKey: "iris.conductor.systemPromptOverride") ?? ""
        conductorPromptUsingDefault = override.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func saveConductorPrompt() {
        Conductor.setSystemPromptOverride(conductorPromptDraft)
        conductorPromptUsingDefault = false
        conductorPromptStatus = "✅ Override saved. Active dès le prochain call."
    }

    private func resetConductorPrompt() {
        Conductor.setSystemPromptOverride(nil)
        conductorPromptDraft = Conductor.currentSystemPrompt()
        conductorPromptUsingDefault = true
        conductorPromptStatus = "✅ Reset OK — default prompt restauré."
    }

    // MARK: — v1.30 Sentinel intervals

    @State private var stubIntervalSeconds: Double = 60
    @State private var githubIntervalSeconds: Double = 300
    @State private var fsIntervalSeconds: Double = 60

    private var sentinelIntervalsSection: some View {
        VStack(alignment: .leading, spacing: IRISTokens.spacing8) {
            sectionTitle("Sentinel intervals (poll cadence)", subtitle: "Tune si Sentinel est trop bavard ou pas assez réactif. Persist UserDefaults.")

            intervalSlider(
                label: "Stub signals (templates fictifs)",
                value: $stubIntervalSeconds,
                range: 10...600,
                step: 10,
                onCommit: { sec in
                    Task { await Sentinel.shared.setStubInterval(UInt64(sec)) }
                }
            )

            intervalSlider(
                label: "GitHub pushedAt poll",
                value: $githubIntervalSeconds,
                range: 60...1800,
                step: 30,
                onCommit: { sec in
                    Task { await Sentinel.shared.setGithubInterval(UInt64(sec)) }
                }
            )

            intervalSlider(
                label: "FS mtime poll (projets actifs)",
                value: $fsIntervalSeconds,
                range: 10...600,
                step: 10,
                onCommit: { sec in
                    Task { await Sentinel.shared.setFSInterval(UInt64(sec)) }
                }
            )

            Text("Restart IRIS pour appliquer aux timers en cours.")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .onAppear {
            Task {
                stubIntervalSeconds = Double(await Sentinel.shared.currentStubInterval)
                githubIntervalSeconds = Double(await Sentinel.shared.currentGithubInterval)
                fsIntervalSeconds = Double(await Sentinel.shared.currentFSInterval)
            }
        }
    }

    private func intervalSlider(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        onCommit: @escaping (Double) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.system(size: 11))
                Spacer()
                Text("\(Int(value.wrappedValue))s")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(IRISTokens.irisAccent)
            }
            Slider(value: value, in: range, step: step) {
                Text(label)
            } onEditingChanged: { editing in
                if !editing { onCommit(value.wrappedValue) }
            }
            .controlSize(.small)
        }
        .padding(.bottom, 4)
    }

    // MARK: — v1.9 Backup / Restore + v1.4.A MIND import

    private var backupSection: some View {
        VStack(alignment: .leading, spacing: IRISTokens.spacing8) {
            sectionTitle("Backup / Import", subtitle: "Export complet SwiftData JSON · Import backup IRIS · Import audits depuis MIND.")

            HStack(spacing: IRISTokens.spacing8) {
                Button(action: exportBackup) {
                    Label("Export tout", systemImage: "square.and.arrow.up")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(IRISTokens.irisAccent)

                Button(action: importBackup) {
                    Label("Import backup", systemImage: "square.and.arrow.down")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(action: importMIND) {
                    Label("Import MIND", systemImage: "iphone.gen3")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(action: exportMarkdown) {
                    Label("Export MD", systemImage: "doc.text")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Export human-readable Markdown (memories + audits + projects + signaux 24h)")

                Spacer()
            }

            if let msg = backupStatus {
                Text(msg)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(msg.hasPrefix("✅") ? .green : (msg.hasPrefix("⚠️") ? .red : .secondary))
                    .padding(.top, 4)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("MIND import attend ~/iris-mind-export.json (array {codename, verdict, headline, createdAt?, findings?[]}).")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func exportBackup() {
        do {
            let container = modelContext.container
            let url = try BackupService.exportAll(container: container)
            backupStatus = "✅ Exporté vers \(url.path) (\(humanByteSize(at: url)))"
        } catch {
            backupStatus = "⚠️ Export échoué : \(error.localizedDescription)"
        }
    }

    private func importBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
        panel.title = "Sélectionne un backup IRIS"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let container = modelContext.container
            let stats = try BackupService.importBackup(container: container, from: url)
            backupStatus = "✅ Backup importé : \(stats.summary)"
        } catch {
            backupStatus = "⚠️ Import échoué : \(error.localizedDescription)"
        }
    }

    private func exportMarkdown() {
        do {
            let container = modelContext.container
            let url = try BackupService.exportAsMarkdown(container: container)
            backupStatus = "✅ Markdown exporté vers \(url.path) (\(humanByteSize(at: url)))"
        } catch {
            backupStatus = "⚠️ Export MD échoué : \(error.localizedDescription)"
        }
    }

    // MARK: — v1.14 Skills config export/import

    private func exportSkillsConfig() {
        guard let data = SkillRegistry.shared.exportConfig() else {
            backupStatus = "⚠️ Export skills échoué"
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "iris-skills-config.json"
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url)
            backupStatus = "✅ Config skills exportée vers \(url.lastPathComponent)"
        } catch {
            backupStatus = "⚠️ Save skills config échoué : \(error.localizedDescription)"
        }
    }

    private func importSkillsConfig() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
        panel.title = "Sélectionne config skills JSON"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try Data(contentsOf: url)
            if SkillRegistry.shared.importConfig(from: data) {
                backupStatus = "✅ Config skills importée (\(SkillRegistry.shared.enabledNames.count) actifs)"
            } else {
                backupStatus = "⚠️ Format JSON invalide"
            }
        } catch {
            backupStatus = "⚠️ Read échoué : \(error.localizedDescription)"
        }
    }

    private func importMIND() {
        let defaultURL = URL(fileURLWithPath: "\(NSHomeDirectory())/iris-mind-export.json")
        let url: URL
        if FileManager.default.fileExists(atPath: defaultURL.path) {
            url = defaultURL
        } else {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.json]
            panel.allowsMultipleSelection = false
            panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
            panel.title = "Sélectionne le fichier MIND export JSON"
            guard panel.runModal() == .OK, let pickedURL = panel.url else { return }
            url = pickedURL
        }

        do {
            let container = modelContext.container
            let count = try BackupService.importMINDExport(container: container, from: url)
            backupStatus = "✅ MIND : \(count) audits importés depuis \(url.lastPathComponent)"
        } catch {
            backupStatus = "⚠️ MIND import échoué : \(error.localizedDescription)"
        }
    }

    private func humanByteSize(at url: URL) -> String {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return "?" }
        if size < 1024 { return "\(size) B" }
        if size < 1024 * 1024 { return "\(size / 1024) kB" }
        return "\(size / 1024 / 1024) MB"
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: IRISTokens.spacing4) {
            Text("API key stockée dans le Keychain macOS (service `app.iris.macos.secrets`, account `anthropic-api-key`).")
                .font(IRISTokens.monoFont)
                .foregroundStyle(.secondary)
            Text("Coût session courante : $\(String(format: "%.4f", appState.sessionCostUSD))")
                .font(IRISTokens.monoFont)
                .foregroundStyle(appState.sessionCostUSD > 1 ? IRISTokens.goldAccent : .secondary)
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        switch testStatus {
        case .idle:
            if let saved = savedMessage {
                Label(saved, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 12))
            } else {
                EmptyView()
            }
        case .testing:
            EmptyView()
        case .success(let msg):
            Label(msg, systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .font(.system(size: 12))
        case .failure(let msg):
            Label(msg, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.system(size: 12))
        }
    }

    // MARK: — Helpers

    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private func routingRow(label: String, model: String, cost: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.system(size: 12))
            Spacer()
            Text(model)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(IRISTokens.irisAccent)
            Text(cost)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: — Actions

    private func saveKey() {
        let trimmed = apiKeyDraft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let ok = IRISKeychain.shared.setAnthropicAPIKey(trimmed)
        savedMessage = ok ? "Clé enregistrée dans le Keychain." : "Échec sauvegarde Keychain."
        appState.refreshKeyPresence()
    }

    private func deleteKey() {
        _ = IRISKeychain.shared.deleteAnthropicAPIKey()
        apiKeyDraft = ""
        savedMessage = "Clé supprimée."
        appState.refreshKeyPresence()
        testStatus = .idle
    }

    private func testKey() {
        let trimmed = apiKeyDraft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        // Sauve d'abord, sinon le client ne pourra pas l'utiliser
        _ = IRISKeychain.shared.setAnthropicAPIKey(trimmed)
        appState.refreshKeyPresence()
        savedMessage = nil
        testStatus = .testing

        Task {
            do {
                let response = try await AnthropicClient.shared.sendMessage(
                    model: .haiku45,
                    system: nil,
                    messages: [Message(role: .user, content: "Respond with exactly: pong")],
                    maxTokens: 16,
                    cacheSystem: false
                )
                let text = response.firstTextContent ?? "<empty>"
                let cost = response.usage.estimatedCostUSD(model: .haiku45)
                await MainActor.run {
                    testStatus = .success("Pong reçu (\(text.prefix(20))). Coût test : $\(String(format: "%.6f", cost))")
                }
            } catch {
                await MainActor.run {
                    testStatus = .failure(error.localizedDescription)
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .environment(IRISAppState())
}

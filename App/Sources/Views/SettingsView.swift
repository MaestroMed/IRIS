import SwiftUI
import SwiftData
import AppKit

/// v0.1 + v1.9 — Settings panel : API key Anthropic + skill marketplace + backup/restore + MIND import.
/// v1.171 — Storage summary section (per-entity counts).
/// v1.174 — Open Application Support folder in Finder.
/// v1.187 — Witness Pause/Resume quick toggle (shares @AppStorage key with Witness.swift).
/// v1.190 — Re-seed memories from disk button (calls MemorySeeder).
/// v1.196 — Open ~/Developer folder button (Cartographer scan target).
/// v1.205 — About IRIS section (version, boot, uptime, commit, github link).
/// v1.212 — Witness blocklist viewer + per-row unblock button.
/// v1.220 — Witness vision capture toggle (@AppStorage witnessVisionEnabled).
/// v1.226 — Keyboard shortcuts cheatsheet augmented (Cmd+L, Cmd+F logs, Cmd+1..5 palette).
/// v1.232 — Reset Sentinel intervals to defaults button.
/// v1.238 — Burst alert threshold slider (@AppStorage shared with LogsView).
/// v1.245 — Memory browser shortcuts added to cheatsheet.
/// v1.252 — Max events displayed slider for LogsView (@AppStorage).
/// v1.259 — Reset Witness vision counters button (daily quota + 30d cost history).
/// v1.262 — Quick-select chips (5/10/20/50) for Conductor history max pairs.
/// v1.268 — Witness vision daily quota slider (@AppStorage shared with Witness.swift).
/// v1.274 — Import config from JSON button (NSOpenPanel + UserDefaults restore).
/// v1.289 — Auto-backup frequency Picker (off/hourly/daily/weekly).
/// v1.295 — Notification threshold Picker (importance-driven, UI only).
/// v1.304 — Clear UserDefaults caches button (preserves API keys + data).
/// v1.338 — Gemini API key section + GeminiClient test ping (mirror Anthropic flow).
/// v1.310 — Verbose logs toggle (@AppStorage shared with LogsView).
/// v1.316 — Reset agent visibility button (restore all defaults).
/// v1.321 — Cmd+? shortcut documented in cheatsheet (binding TODO).
/// v1.328 — EventLog auto-purge cadence Picker (UI only).
/// v1.344 — Envoy webhook URL config + real send (Mail.app + webhook POST).
/// v1.347 — Cartographer auto-scan on launch toggle (@AppStorage cartographerAutoScanOnLaunch).
/// v1.346 — Toggle Conductor inject Witness vision dans system prompt (@AppStorage conductorUseWitnessContext).
struct SettingsView: View {
    @Environment(IRISAppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var apiKeyDraft: String = ""
    @State private var testStatus: TestStatus = .idle
    @State private var savedMessage: String?
    @State private var backupStatus: String?
    // v1.338 — Gemini API key
    @State private var geminiKeyDraft: String = ""
    @State private var geminiTestStatus: TestStatus = .idle
    @State private var geminiSavedMessage: String?
    @AppStorage("witnessPaused") private var witnessPaused: Bool = false  // v1.187
    @AppStorage("witnessVisionEnabled") private var witnessVisionEnabled: Bool = true  // v1.220
    @AppStorage("burstAlertThreshold") private var burstAlertThreshold: Int = 50  // v1.238
    @AppStorage("logsMaxDisplay") private var logsMaxDisplay: Int = 500  // v1.252
    @AppStorage("logsVerbosePayload") private var logsVerbosePayload: Bool = false  // v1.310
    @AppStorage("iris.witness.visionMaxCallsPerDay") private var witnessVisionDailyCap: Int = 100  // v1.268
    @AppStorage("backupAutoFrequency") private var backupAutoFrequency: String = "daily"  // v1.289
    @AppStorage("notificationMinImportance") private var notificationMinImportance: Int = 5  // v1.295
    @AppStorage("eventLogPurgeCadence") private var purgeCadence: String = "off"  // v1.328
    @AppStorage("envoyWebhookURL") private var envoyWebhookURL: String = ""  // v1.344
    @AppStorage("cartographerAutoScanOnLaunch") private var cartographerAutoScanOnLaunch: Bool = true  // v1.347
    @AppStorage("conductorUseWitnessContext") private var conductorUseWitnessContext: Bool = true  // v1.346
    @State private var blocklistRefreshTick: Int = 0  // v1.212 — force re-render after unblock
    @State private var resetVisionStatus: String?  // v1.259
    @State private var importConfigStatus: String?  // v1.274
    @State private var clearCacheStatus: String?  // v1.304
    @State private var agentResetStatus: String?  // v1.316

    // v1.212 — Read live from UserDefaults, tied to blocklistRefreshTick for reactivity.
    private var blockedIds: [String] {
        let _ = blocklistRefreshTick
        return UserDefaults.standard.stringArray(forKey: "iris.witness.blockedBundleIds") ?? []
    }

    // v1.171 — Storage summary @Query directives
    @Query private var allEventLogs: [EventLog]
    @Query private var allMemories: [Memory]
    @Query private var allAuditReports: [AuditReport]
    @Query private var allDrafts: [Draft]
    @Query private var allSignals: [Signal]
    @Query private var allProjectRecords: [ProjectRecord]
    @Query private var allActionLogs: [ActionLog]

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

            geminiKeySection  // v1.338

            Divider()

            envoyConfigSection  // v1.344

            Divider()

            skillMarketplaceSection

            Divider()

            modelsRoutingSection

            Divider()

            backupSection

            Divider()

            sentinelIntervalsSection

            Divider()

            cartographerSection  // v1.347

            Divider()

            conductorPromptSection

            Divider()

            agentVisibilitySection

            Divider()

            notificationsSection

            Divider()

            mcpServersSection  // v1.113

            Divider()

            witnessBlocklistSection

            Divider()

            dataFoldersSection

            Divider()

            shortcutsCheatsheetSection  // v1.142

            Divider()

            storageSection  // v1.171

            Divider()

            dangerZoneSection

            Divider()

            aboutSection  // v1.205

            Spacer()

            footer
        }
        .padding(IRISTokens.spacing32)
        .frame(minWidth: 560, idealWidth: 640, minHeight: 480)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            apiKeyDraft = IRISKeychain.shared.getAnthropicAPIKey() ?? ""
            geminiKeyDraft = IRISKeychain.shared.getGeminiAPIKey() ?? ""  // v1.338
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

    // v1.338 — Gemini API key section (mirror Anthropic).
    private var geminiKeySection: some View {
        VStack(alignment: .leading, spacing: IRISTokens.spacing16) {
            sectionTitle("Gemini API key", subtitle: "Optionnel. Backend alternatif (Gemini 2.5 Flash / Pro). Stocké Keychain account `gemini-api-key`.")

            SecureField("AIza…", text: $geminiKeyDraft)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, design: .monospaced))

            HStack {
                Button(action: saveGeminiKey) {
                    Label("Enregistrer", systemImage: "lock.shield")
                }
                .disabled(geminiKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty)

                Button(action: testGeminiKey) {
                    if case .testing = geminiTestStatus {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Tester (Flash ping)", systemImage: "network")
                    }
                }
                .disabled(geminiKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty)

                if IRISKeychain.shared.hasGeminiAPIKey() {
                    Button(role: .destructive, action: deleteGeminiKey) {
                        Label("Supprimer", systemImage: "trash")
                    }
                }

                Spacer()
            }

            geminiStatusBanner
        }
    }

    @ViewBuilder
    private var geminiStatusBanner: some View {
        switch geminiTestStatus {
        case .idle:
            if let saved = geminiSavedMessage {
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

    // v1.344 — Envoy webhook URL config (real send POST endpoint).
    private var envoyConfigSection: some View {
        VStack(alignment: .leading, spacing: IRISTokens.spacing16) {
            sectionTitle("Envoy webhook", subtitle: "URL POST optionnelle pour drafts channel='webhook' (Slack/Discord/n8n incoming). Stocké UserDefaults.")
            TextField("https://hooks.slack.com/services/…", text: $envoyWebhookURL)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, design: .monospaced))
            Text("Vide = Envoy reste en mode 'pas de webhook'. Channel='email' utilise toujours Mail.app handoff via mailto:.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
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
                    // v1.55 — Hot-reload skills depuis disk
                    Button(action: reloadSkillsFromDisk) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .controlSize(.mini)
                    .help("Re-scan ~/.claude/skills/ pour détecter nouveaux skills installés")
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
    @State private var witnessVisionModel: String = ""  // v1.110
    @State private var witnessVisionMaxPerDay: Double = 100  // v1.111
    @State private var conductorMaxTokens: Double = 2048  // v1.61
    @State private var costLimitUSD: Double = 1.0          // v1.72
    @State private var auditorMonthlyAuto: Bool = false    // v1.93
    @State private var advisorHour: Int = 8                // v1.103
    @State private var conductorHistoryPairs: Double = 10  // v1.106
    @State private var auditorPerFile: Double = 4   // v1.122 — KB
    @State private var auditorTotal: Double = 15    // v1.122 — KB

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

            // v1.111 — Witness vision daily quota
            HStack {
                Text("Witness vision quota /jour")
                    .font(.system(size: 11))
                Slider(value: $witnessVisionMaxPerDay, in: 10...500, step: 10)
                    .frame(maxWidth: 200)
                Text("\(Int(witnessVisionMaxPerDay))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 50, alignment: .trailing)
                    .onChange(of: witnessVisionMaxPerDay) { _, newValue in
                        Witness.setMaxVisionCallsPerDay(Int(newValue))
                    }
                Text("(used \(Witness.visionCallsToday))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, IRISTokens.spacing16)

            // v1.110 — Witness vision model picker (Phase A)
            HStack {
                Text("Witness vision model")
                    .font(.system(size: 11))
                Spacer()
                Picker("", selection: $witnessVisionModel) {
                    Text("Haiku 4.5 (cheap · ~$0.002/call)").tag(ClaudeModel.haiku45.rawValue)
                    Text("Sonnet 4.6 (better · ~$0.006/call)").tag(ClaudeModel.sonnet46.rawValue)
                    Text("Opus 4.7 (overkill)").tag(ClaudeModel.opus47.rawValue)
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(maxWidth: 280)
                .onChange(of: witnessVisionModel) { _, newValue in
                    if let model = ClaudeModel(rawValue: newValue) {
                        Witness.setVisionModel(model)
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

            // v1.103 — Advisor briefing hour
            HStack {
                Text("Advisor briefing hour")
                    .font(.system(size: 11))
                Stepper(value: $advisorHour, in: 0...23) {
                    Text("\(advisorHour)h00")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .controlSize(.small)
                .onChange(of: advisorHour) { _, newValue in
                    Advisor.setScheduledHour(newValue)
                }
                Spacer()
                Text("Restart IRIS pour appliquer")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, IRISTokens.spacing16)

            // v1.122 — Auditor file budget sliders (per-file cap + total budget)
            HStack {
                Text("Auditor per-file cap")
                    .font(.system(size: 11))
                Slider(value: $auditorPerFile, in: 1...20, step: 1)
                    .frame(maxWidth: 160)
                Text("\(Int(auditorPerFile)) KB")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 50, alignment: .trailing)
                    .onChange(of: auditorPerFile) { _, v in
                        Auditor.setPerFileCapBytes(Int(v * 1000))
                    }
                Spacer()
            }
            .padding(.leading, IRISTokens.spacing16)

            HStack {
                Text("Auditor total budget")
                    .font(.system(size: 11))
                Slider(value: $auditorTotal, in: 5...100, step: 5)
                    .frame(maxWidth: 160)
                Text("\(Int(auditorTotal)) KB")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 50, alignment: .trailing)
                    .onChange(of: auditorTotal) { _, v in
                        Auditor.setTotalBudgetBytes(Int(v * 1000))
                    }
                Spacer()
            }
            .padding(.leading, IRISTokens.spacing16)

            // v1.93 — Auditor monthly auto-audit toggle
            HStack {
                Toggle(isOn: $auditorMonthlyAuto) {
                    Text("Auditor monthly auto-audit (active projects)")
                        .font(.system(size: 11))
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .onChange(of: auditorMonthlyAuto) { _, newValue in
                    Auditor.setMonthlyAutoEnabled(newValue)
                }
                Spacer()
                if let last = Auditor.monthlyLastAt {
                    Text("dernier : \(RelativeDateTimeFormatter().localizedString(for: last, relativeTo: .now))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                } else {
                    Text("jamais")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.leading, IRISTokens.spacing16)

            // v1.61 — Conductor maxTokens slider
            HStack {
                Text("Conductor max output tokens")
                    .font(.system(size: 11))
                Slider(value: $conductorMaxTokens, in: 512...8192, step: 256)
                    .frame(maxWidth: 200)
                Text("\(Int(conductorMaxTokens))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .trailing)
                    .onChange(of: conductorMaxTokens) { _, newValue in
                        Conductor.setMaxTokens(Int(newValue))
                    }
            }
            .padding(.leading, IRISTokens.spacing16)

            // v1.106 — Conductor history depth slider
            HStack {
                Text("Conductor history depth (paires)")
                    .font(.system(size: 11))
                Slider(value: $conductorHistoryPairs, in: 2...30, step: 1)
                    .frame(maxWidth: 200)
                Text("\(Int(conductorHistoryPairs))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .trailing)
                    .onChange(of: conductorHistoryPairs) { _, newValue in
                        Conductor.setMaxHistoryPairs(Int(newValue))
                    }
            }
            .padding(.leading, IRISTokens.spacing16)

            // v1.262 — Quick-select chips for Conductor history max pairs
            HStack(spacing: 4) {
                Text("Quick:")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                ForEach([5, 10, 20, 50], id: \.self) { value in
                    Button {
                        conductorHistoryPairs = Double(value)
                        Conductor.setMaxHistoryPairs(value)
                    } label: {
                        Text("\(value)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Int(conductorHistoryPairs) == value ? .white : .primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Int(conductorHistoryPairs) == value ? IRISTokens.aquaTint : Color.secondary.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                    .help("Set max history pairs to \(value)")
                }
                Spacer()
            }
            .padding(.leading, IRISTokens.spacing16)

            // v1.72 — Cost limit slider (notif macOS si dépassé)
            HStack {
                Text("Session cost limit (alerte)")
                    .font(.system(size: 11))
                Slider(value: $costLimitUSD, in: 0.1...10, step: 0.1)
                    .frame(maxWidth: 200)
                Text("$\(String(format: "%.2f", costLimitUSD))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .trailing)
                    .onChange(of: costLimitUSD) { _, newValue in
                        IRISAppState.setCostLimit(newValue)
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
            witnessVisionModel = Witness.currentVisionModel.rawValue  // v1.110
            witnessVisionMaxPerDay = Double(Witness.maxVisionCallsPerDay)  // v1.111
            conductorMaxTokens = Double(Conductor.currentMaxTokens)  // v1.61
            conductorHistoryPairs = Double(Conductor.currentMaxHistoryPairs)  // v1.106
            auditorPerFile = Double(Auditor.perFileCapBytes) / 1000  // v1.122
            auditorTotal = Double(Auditor.totalBudgetBytes) / 1000   // v1.122
            costLimitUSD = IRISAppState.costLimitUSD                     // v1.72
            auditorMonthlyAuto = Auditor.monthlyAutoEnabled              // v1.93
            advisorHour = Advisor.scheduledHour                          // v1.103
        }
    }

    // MARK: — v1.40 Danger zone (reset all)

    // MARK: — v1.58 Witness blocklist

    @State private var witnessBlocklistTick: Int = 0  // force re-render
    @State private var witnessBlocklistDraft: String = ""

    private var witnessBlocklistSection: some View {
        let blocked = Witness.blockedBundleIds
        return VStack(alignment: .leading, spacing: IRISTokens.spacing8) {
            sectionTitle(
                "Witness blocklist (\(blocked.count))",
                subtitle: "Bundle IDs ignorés lors de la capture frontmost (apps sensibles : Mail, Slack, 1Password)."
            )
            .id(witnessBlocklistTick)

            // Liste courante
            if blocked.isEmpty {
                Text("Aucune app blocklistée — Witness capture tout.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 4)], alignment: .leading, spacing: 4) {
                    ForEach(Array(blocked).sorted(), id: \.self) { bundleId in
                        blockedChip(bundleId)
                    }
                }
            }

            // Suggérés
            Text("SUGGESTIONS")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.top, IRISTokens.spacing4)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 4)], alignment: .leading, spacing: 4) {
                ForEach(Witness.suggestedBlocklist, id: \.bundleId) { item in
                    let isBlocked = blocked.contains(item.bundleId)
                    Button {
                        if isBlocked {
                            Witness.removeBlocked(item.bundleId)
                        } else {
                            Witness.addBlocked(item.bundleId)
                        }
                        witnessBlocklistTick += 1
                    } label: {
                        Text(item.name)
                            .font(.system(size: 10))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background((isBlocked ? Color.red : IRISTokens.aquaTint).opacity(0.15))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            // Custom add
            HStack(spacing: IRISTokens.spacing8) {
                TextField("bundle ID custom (ex: com.example.app)", text: $witnessBlocklistDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .controlSize(.small)
                Button("Ajouter") {
                    let id = witnessBlocklistDraft.trimmingCharacters(in: .whitespaces)
                    guard !id.isEmpty else { return }
                    Witness.addBlocked(id)
                    witnessBlocklistDraft = ""
                    witnessBlocklistTick += 1
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(witnessBlocklistDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func blockedChip(_ bundleId: String) -> some View {
        HStack(spacing: 4) {
            Text(bundleId)
                .font(.system(size: 10, design: .monospaced))
            Button {
                Witness.removeBlocked(bundleId)
                witnessBlocklistTick += 1
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(Color.red.opacity(0.12))
        .clipShape(Capsule())
    }

    // MARK: — v1.142 Keyboard shortcuts cheatsheet

    private var shortcutsCheatsheetSection: some View {
        VStack(alignment: .leading, spacing: IRISTokens.spacing8) {
            sectionTitle("Raccourcis clavier", subtitle: "Cheatsheet de tous les raccourcis IRIS (référence rapide).")

            let shortcuts: [(category: String, items: [(combo: String, label: String)])] = [
                ("Conductor",
                 [("Cmd+Enter", "Envoyer message"),
                  ("Cmd+K", "Command palette"),
                  ("Cmd+.", "Stop génération en cours"),
                  ("Cmd+⌫", "Clear input")]
                ),
                ("Agents",
                 [("Cmd+1..0", "Sélectionner agent 1..10 (Conductor → Advisor)")]
                ),
                ("Actions",
                 [("Cmd+Shift+R", "Refresh Cartographer"),
                  ("Cmd+R", "Refresh Cartographer (raccourci court)"),    // v1.8
                  ("Cmd+Shift+B", "Brief Advisor maintenant"),
                  ("Cmd+B", "Brief Advisor (raccourci court)"),           // v1.8
                  ("Cmd+Shift+A", "Audit projet sélectionné")]
                ),
                ("Command palette",                                       // v1.178
                 [("Cmd+1..5", "Exécuter quick action 1-5 (top 5 résultats)")]
                ),
                ("Logs",                                                  // v1.197 / v1.219
                 [("Cmd+L", "Clear filters (in Logs view)"),
                  ("Cmd+F", "Focus search field (in Logs view)")]
                ),
                ("Memory browser",                                        // v1.245
                 [("⌘/", "Focus search field (in Memory browser)")]
                ),
                ("Système",
                 [("Cmd+,", "Settings"),
                  ("Cmd+Shift+O", "Ouvrir fenêtre principale depuis MenuBar"),
                  // TODO: bind Cmd+? to open Settings → Shortcuts tab (or palette help)
                  ("⌘?", "Show this cheatsheet"),                          // v1.321
                  ("Cmd+Q", "Quitter IRIS")]
                )
            ]

            ForEach(Array(shortcuts.enumerated()), id: \.offset) { _, group in
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.category.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    ForEach(Array(group.items.enumerated()), id: \.offset) { _, item in
                        HStack {
                            Text(item.combo)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(IRISTokens.aquaTint)
                                .frame(width: 130, alignment: .leading)
                            Text(item.label)
                                .font(.system(size: 11))
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .padding(.vertical, 1)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: — v1.52 Data folders shortcuts + v1.59 EventLog purge

    @State private var purgeDays: Double = 30
    @State private var reseedStatus: String?  // v1.190

    private var dataFoldersSection: some View {
        VStack(alignment: .leading, spacing: IRISTokens.spacing8) {
            sectionTitle(
                "Données & memory",
                subtitle: "Accès rapide aux dossiers IRIS + purge logs anciens (réduit taille SwiftData)."
            )

            HStack(spacing: IRISTokens.spacing8) {
                Button {
                    revealInFinder(path: ("~/.claude/projects/-Users-mehdinafaa-Iris/memory" as NSString).expandingTildeInPath)
                } label: {
                    Label("Memory folder…", systemImage: "folder")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Ouvre ~/.claude/projects/-Users-mehdinafaa-Iris/memory dans Finder")

                Button {
                    revealInFinder(path: ("~/.claude/skills" as NSString).expandingTildeInPath)
                } label: {
                    Label("Skills folder…", systemImage: "wrench.and.screwdriver")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Ouvre ~/.claude/skills dans Finder")

                // v1.196 — Open ~/Developer folder (Cartographer scan target)
                Button {
                    openDeveloperFolder()
                } label: {
                    Label("~/Developer folder", systemImage: "folder")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Reveal ~/Developer dans Finder (target Cartographer)")

                // v1.190 — Re-seed memories from disk
                Button {
                    reseedMemories()
                } label: {
                    Label("Re-seed depuis disk", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Force re-seed des memories depuis ~/.claude/projects/.../memory/*.md")

                if let reseedStatus {
                    Text(reseedStatus)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Divider().padding(.vertical, IRISTokens.spacing4)

            // v1.59 — EventLog purge
            HStack(spacing: IRISTokens.spacing8) {
                Text("Purger logs >")
                    .font(.system(size: 11))
                Slider(value: $purgeDays, in: 7...90, step: 1)
                    .frame(maxWidth: 160)
                Text("\(Int(purgeDays)) jours")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .leading)
                Button {
                    purgeOldEventLogs(days: Int(purgeDays))
                } label: {
                    Label("Purger", systemImage: "trash")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(IRISTokens.goldAccent)
                Spacer()
            }

            // v1.328 — EventLog auto-purge cadence Picker (UI only).
            // TODO: wire purgeCadence to a periodic Timer task that calls existing EventLog cleanup (v1.59).
            HStack(spacing: IRISTokens.spacing8) {
                Image(systemName: "trash.circle")
                    .foregroundStyle(.orange.opacity(0.8))
                    .font(.system(size: 12))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Auto-purge EventLog")
                        .font(.system(size: 11, weight: .medium))
                    Text("Périodicité de nettoyage automatique des events anciens")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("", selection: $purgeCadence) {
                    Text("Off").tag("off")
                    Text("Daily").tag("daily")
                    Text("Weekly").tag("weekly")
                    Text("Monthly").tag("monthly")
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(maxWidth: 100)
                .pickerStyle(.menu)
            }
        }
    }

    private func purgeOldEventLogs(days: Int) {
        let container = modelContext.container
        do {
            let count = try BackupService.purgeEventLogsOlderThan(days: days, container: container)
            backupStatus = "🗑️ Purgé \(count) EventLog > \(days)j."
        } catch {
            backupStatus = "⚠️ Purge échouée : \(error.localizedDescription)"
        }
    }

    // v1.190 — Re-seed memories from disk via MemorySeeder
    private func reseedMemories() {
        reseedStatus = "⏳ Re-seed en cours…"
        Task { @MainActor in
            await MemorySeeder.seedIfNeeded(in: modelContext)
            reseedStatus = "✅ Re-seed lancé"
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                reseedStatus = nil
            }
        }
    }

    // v1.196 — Open ~/Developer folder (Cartographer scan target)
    private func openDeveloperFolder() {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Developer", isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path) else {
            let alert = NSAlert()
            alert.messageText = "Dossier ~/Developer absent"
            alert.informativeText = "Crée ~/Developer pour que Cartographer le scanne."
            alert.alertStyle = .informational
            alert.runModal()
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func revealInFinder(path: String) {
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            // Si le dossier n'existe pas encore, ouvre le parent
            let parent = url.deletingLastPathComponent()
            NSWorkspace.shared.open(parent)
        }
    }

    // v1.171 — Storage summary (per-entity counts)
    private var storageSection: some View {
        VStack(alignment: .leading, spacing: IRISTokens.spacing8) {
            sectionTitle(
                "Stockage",
                subtitle: "Compteurs SwiftData par type d'entité — vue diagnostique."
            )

            VStack(spacing: IRISTokens.spacing4) {
                storageRow(icon: "list.bullet.rectangle", name: "EventLog", count: allEventLogs.count)
                storageRow(icon: "books.vertical", name: "Memory", count: allMemories.count)
                storageRow(icon: "checkmark.shield", name: "AuditReport", count: allAuditReports.count)
                storageRow(icon: "pencil.and.scribble", name: "Draft", count: allDrafts.count)
                storageRow(icon: "eye.circle", name: "Signal", count: allSignals.count)
                storageRow(icon: "folder.fill", name: "ProjectRecord", count: allProjectRecords.count)
                storageRow(icon: "hand.raised", name: "ActionLog", count: allActionLogs.count)
            }

            // v1.174 — Reveal Application Support folder in Finder
            HStack {
                Button { revealDataFolder() } label: {
                    Label("Open data folder", systemImage: "folder.fill")
                        .font(.system(size: 11))
                }
                .controlSize(.small)
                .help("Reveal le dossier Application Support IRIS dans Finder")
            }

            // v1.187 — Witness Pause/Resume quick toggle
            HStack(spacing: IRISTokens.spacing8) {
                Image(systemName: witnessPaused ? "eye.slash.fill" : "eye.fill")
                    .foregroundStyle(witnessPaused ? .red.opacity(0.8) : .green.opacity(0.8))
                    .font(.system(size: 14))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Witness").font(.system(size: 11, weight: .medium))
                    Text(witnessPaused ? "Pause — pas de capture" : "Active — capture frontmost")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    witnessPaused.toggle()
                    Task { await Witness.shared.setPaused(witnessPaused) }
                } label: {
                    Text(witnessPaused ? "Resume" : "Pause").font(.system(size: 11))
                }
                .controlSize(.small)
                .tint(witnessPaused ? .green : .red.opacity(0.8))
            }

            // v1.220 — Witness vision capture toggle
            HStack(spacing: 8) {
                Image(systemName: witnessVisionEnabled ? "eye.fill" : "eye.slash")
                    .foregroundStyle(witnessVisionEnabled ? IRISTokens.aquaTint : .secondary.opacity(0.6))
                    .font(.system(size: 12))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Vision capture").font(.system(size: 11, weight: .medium))
                    Text(witnessVisionEnabled ? "Active — analyse screenshots avec Haiku" : "Disabled — capture metadata seulement")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $witnessVisionEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }

            // v1.259 — Reset Witness vision counters (daily quota + 30d cost)
            HStack(spacing: 8) {
                Button {
                    resetVisionCounters()
                } label: {
                    Label("Reset vision counters", systemImage: "arrow.counterclockwise.circle")
                        .font(.system(size: 11))
                }
                .controlSize(.small)
                .tint(.secondary)
                .help("Réinitialise les compteurs Witness vision (calls today + cost 30d rolling)")
                if let status = resetVisionStatus {
                    Text(status)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            // v1.268 — Witness vision daily quota slider
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Vision daily quota")
                        .font(.system(size: 12))
                    Spacer()
                    Text("\(witnessVisionDailyCap) calls/day")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(IRISTokens.aquaTint)
                }
                Slider(
                    value: Binding(
                        get: { Double(witnessVisionDailyCap) },
                        set: { witnessVisionDailyCap = Int($0) }
                    ),
                    in: 10...500,
                    step: 10
                )
                .controlSize(.small)
                Text("Limite max appels Witness vision (Haiku) par jour. Reset à minuit.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            // v1.238 — Burst alert threshold (LogsView burst banner trigger)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Burst alert threshold")
                        .font(.system(size: 12))
                    Spacer()
                    Text("\(burstAlertThreshold) events/min")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(IRISTokens.aquaTint)
                }
                Slider(
                    value: Binding(
                        get: { Double(burstAlertThreshold) },
                        set: { burstAlertThreshold = Int($0) }
                    ),
                    in: 10...200,
                    step: 5
                )
                .controlSize(.small)
                Text("Logs banner alerte si events/60s dépasse ce seuil.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            // v1.252 — Max events displayed in LogsView
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Max events displayed")
                        .font(.system(size: 12))
                    Spacer()
                    Text("\(logsMaxDisplay)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(IRISTokens.aquaTint)
                }
                Slider(
                    value: Binding(
                        get: { Double(logsMaxDisplay) },
                        set: { logsMaxDisplay = Int($0) }
                    ),
                    in: 100...2000,
                    step: 100
                )
                .controlSize(.small)
                Text("Combien d'events afficher en même temps dans LogsView (performance vs visibility).")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            // v1.310 — Verbose logs toggle (extends payload truncation 200 → 1000 chars)
            HStack {
                Image(systemName: "text.justify")
                    .foregroundStyle(IRISTokens.aquaTint)
                    .font(.system(size: 12))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Verbose logs")
                        .font(.system(size: 11, weight: .medium))
                    Text("Affiche payloads complets dans LogsView (jusqu'à 1000 chars au lieu de 200)")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $logsVerbosePayload)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }

            // v1.212 — Witness blocklist viewer (per-row unblock)
            witnessBlocklistViewerSection
        }
    }

    // MARK: — v1.212 Witness blocklist viewer

    private var witnessBlocklistViewerSection: some View {
        let ids = blockedIds
        return VStack(alignment: .leading, spacing: IRISTokens.spacing8) {
            HStack {
                Image(systemName: "nosign")
                    .foregroundStyle(.red.opacity(0.8))
                Text("Witness blocklist")
                    .font(.system(size: 14, weight: .light, design: .serif))
                Spacer()
                Text("\(ids.count) bloqués")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if ids.isEmpty {
                Text("Aucune app bloquée.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            } else {
                ForEach(ids, id: \.self) { bundleId in
                    HStack(spacing: 8) {
                        Image(systemName: "app.dashed")
                            .foregroundStyle(.secondary.opacity(0.7))
                            .font(.system(size: 12))
                        Text(bundleId)
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1)
                        Spacer()
                        Button { unblockApp(bundleId) } label: {
                            Text("Unblock").font(.system(size: 10))
                        }
                        .controlSize(.small)
                        .tint(.green)
                    }
                }
            }
        }
        .padding(IRISTokens.spacing8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func unblockApp(_ bundleId: String) {
        Witness.removeBlocked(bundleId)
        blocklistRefreshTick += 1
    }

    // v1.174 — Reveal the SwiftData store location in Finder
    private func revealDataFolder() {
        guard var url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }
        url.appendPathComponent(Bundle.main.bundleIdentifier ?? "iris.app")
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func storageRow(icon: String, name: String, count: Int) -> some View {
        HStack(spacing: IRISTokens.spacing8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .center)
            Text(name)
                .font(.system(size: 12))
            Spacer()
            Text("\(count)")
                .font(.system(size: 16, weight: .medium, design: .monospaced))
                .foregroundStyle(IRISTokens.irisAccent)
        }
        .padding(.vertical, 2)
    }

    private var dangerZoneSection: some View {
        VStack(alignment: .leading, spacing: IRISTokens.spacing8) {
            sectionTitle(
                "⚠️ Danger zone",
                subtitle: "Reset complet — supprime UserDefaults iris.* + Keychain Anthropic. Action irréversible."
            )

            HStack(spacing: IRISTokens.spacing8) {
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

                // v1.159 — Export all settings as Markdown
                Button {
                    exportSettingsMarkdown()
                } label: {
                    Label("Export config MD", systemImage: "doc.text.below.ecg")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(IRISTokens.aquaTint)

                // v1.274 — Import config from JSON (restore UserDefaults)
                Button {
                    importConfig()
                } label: {
                    Label("Import config JSON", systemImage: "square.and.arrow.down")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(IRISTokens.aquaTint)
                .help("Importer un fichier config JSON (settings IRIS)")

                // v1.304 — Clear UserDefaults cache (preserves API keys + fundamentals)
                Button {
                    clearAllCaches()
                } label: {
                    Label("Clear UserDefaults cache", systemImage: "eraser.fill")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.orange)
                .help("Réinitialise les caches UserDefaults IRIS (préserve API keys + system fundamentals)")
            }

            if let status = importConfigStatus {
                Text(status)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(status.hasPrefix("✅") ? .green : (status.hasPrefix("⚠️") ? .red : .secondary))
                    .padding(.top, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let status = clearCacheStatus {
                Text(status)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(status.hasPrefix("✅") ? .green : (status.hasPrefix("⚠️") ? .red : .secondary))
                    .padding(.top, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // v1.304 — Clear UserDefaults caches (preserves API keys + sensitive keys).
    private func clearAllCaches() {
        let alert = NSAlert()
        alert.messageText = "Clear UserDefaults caches IRIS ?"
        alert.informativeText = "Cela réinitialise les préférences UI (filtres, sliders, toggles). N'efface PAS les données SwiftData ni les clés API. Continuer ?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Annuler")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        // Known IRIS pref keys (non "iris." prefixed) — conservative list.
        let knownIRISPrefs: Set<String> = [
            "burstAlertThreshold",
            "logsMaxDisplay",
            "memoryHideTagCloud",
            "witnessPaused",
            "witnessVisionEnabled",
            "backupAutoFrequency",
            "notificationMinImportance",
            "conductorUseWitnessContext"  // v1.346
        ]

        let dict = UserDefaults.standard.dictionaryRepresentation()
        var cleared = 0
        for key in dict.keys {
            let lowerKey = key.lowercased()
            // Exclude any sensitive key
            if lowerKey.contains("apikey") || lowerKey.contains("anthropickey") || lowerKey.contains("secret") || lowerKey.contains("token") {
                continue
            }
            if key.hasPrefix("iris.") || knownIRISPrefs.contains(key) {
                UserDefaults.standard.removeObject(forKey: key)
                cleared += 1
            }
        }
        clearCacheStatus = "✅ \(cleared) caches reset"
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { clearCacheStatus = nil }
    }

    // v1.274 — Import config from JSON, restoring UserDefaults keys.
    private func importConfig() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        panel.message = "Sélectionner un fichier config JSON IRIS exporté"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let data = try Data(contentsOf: url)
                if let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    var applied = 0
                    for (key, value) in dict {
                        UserDefaults.standard.set(value, forKey: key)
                        applied += 1
                    }
                    importConfigStatus = "✅ Importé \(applied) clés"
                } else {
                    importConfigStatus = "⚠️ JSON format invalide"
                }
            } catch {
                importConfigStatus = "⚠️ \(error.localizedDescription)"
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { importConfigStatus = nil }
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

    // v1.159 — Export all iris.* UserDefaults keys as a Markdown dump, grouped by category.
    private func exportSettingsMarkdown() {
        let dict = UserDefaults.standard.dictionaryRepresentation()
        let irisKeys = dict.keys.filter { $0.hasPrefix("iris.") }.sorted()

        // Group by the prefix between "iris." and the next "."
        // e.g. "iris.foo.bar" → category "foo"; "iris.foo" → category "_root"
        var groups: [String: [String]] = [:]
        for key in irisKeys {
            let afterPrefix = key.dropFirst("iris.".count)
            let category: String
            if let dotIdx = afterPrefix.firstIndex(of: ".") {
                category = String(afterPrefix[..<dotIdx])
            } else {
                category = "_root"
            }
            groups[category, default: []].append(key)
        }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        let now = Date()
        let isoStamp = isoFormatter.string(from: now)
        // Sanitize ISO for filename (replace ":" since macOS Finder displays them as "/")
        let safeStamp = isoStamp.replacingOccurrences(of: ":", with: "-")

        var md = "# IRIS Settings Dump — \(isoStamp)\n\n"
        for category in groups.keys.sorted() {
            md += "## iris.\(category)\n"
            for key in groups[category, default: []] {
                let value = dict[key] ?? "<nil>"
                md += "- **\(key)** : \(value)\n"
            }
            md += "\n"
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let fileURL = home.appendingPathComponent("iris-settings-\(safeStamp).md")

        do {
            try md.write(to: fileURL, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            backupStatus = "✅ Settings dumped → \(fileURL.lastPathComponent)"
        } catch {
            backupStatus = "⚠️ Export échoué : \(error.localizedDescription)"
        }
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

            // v1.295 — Notification threshold Picker (UI only)
            // TODO: wire notification threshold to NotificationCenter triggers (Sentinel signalEmitted handler).
            HStack(spacing: 8) {
                Image(systemName: "bell.badge")
                    .foregroundStyle(IRISTokens.aquaTint)
                    .font(.system(size: 12))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Notification threshold").font(.system(size: 11, weight: .medium))
                    Text("Notify pour signals importance >= seuil")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("", selection: $notificationMinImportance) {
                    Text("Off").tag(99)
                    Text("Critical (5)").tag(5)
                    Text("High (4)").tag(4)
                    Text("Normal (3)").tag(3)
                    Text("All (>=1)").tag(1)
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(maxWidth: 120)
                .pickerStyle(.menu)
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

            HStack(spacing: 6) {
                Button {
                    resetAgentVisibility()
                } label: {
                    Label("Reset agent visibility", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 11))
                }
                .controlSize(.small)
                .tint(.secondary)
                .help("Restaure tous les agents sidebar à leur état visible par défaut")

                if let status = agentResetStatus {
                    Text(status)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // v1.316 — Reset all sidebar agents to visible (clear hiddenAgents set).
    private func resetAgentVisibility() {
        AgentVisibility.shared.hiddenAgents = []
        agentResetStatus = "✅ Reset"
        Task {
            try? await Task.sleep(for: .seconds(3))
            await MainActor.run { agentResetStatus = nil }
        }
    }

    // MARK: — v1.42 Conductor system prompt customizable

    @State private var conductorPromptDraft: String = ""
    @State private var conductorPromptUsingDefault: Bool = true
    @State private var conductorPromptStatus: String?

    // v1.66 — Presets quick-switch
    private struct ConductorPreset {
        let name: String
        let body: String
    }

    private static let conductorPresets: [ConductorPreset] = [
        ConductorPreset(name: "Default (IRIS exocortex)", body: Conductor.defaultSystemPrompt),
        ConductorPreset(name: "Coding mode (Swift + arch)", body: """
        Tu es Conductor en mode Coding — assistant senior Swift/macOS pour Mehdi.

        Tu connais : SwiftUI, Swift 6.3 strict concurrency, SwiftData, Tuist, Combine,
        AsyncStream, actors, MainActor isolation, AppKit interop.

        Style :
        - Réponses denses, code-first
        - Cite file:line quand pertinent
        - Pas de "Great question!" — direct au fix
        - Si tu vois un anti-pattern (sur-architecture, retry sans diag, mock prod-grade),
          flag-le explicitement
        - Préfère diff/patch précis vs réécrire tout
        """),
        ConductorPreset(name: "Writing mode (FR formel client)", body: """
        Tu es Conductor en mode Writing — rédacteur FR pour les drafts client de Numelite.

        Style :
        - FR formel professionnel (vouvoiement strict pour clients)
        - "Bonjour [prénom]," / "Bien à vous,"
        - Pas d'argot, pas d'abréviation
        - Termes techniques OK si pertinents pour le client
        - Phrases courtes, structure logique
        - Pas de buzzwords vides ("innovant", "disruptif")

        Pour les drafts marketing public FR :
        - Ton engageant, value-first
        - Hook → bénéfice → CTA clair
        - Données chiffrées si dispo
        """),
        ConductorPreset(name: "Strategy mode (advisor sparring)", body: """
        Tu es Conductor en mode Strategy — sparring partner stratégique pour Mehdi
        (opérateur solo Numelite, agency FR + lead-gen tech).

        Mission :
        - Aider à prioriser actions (top 3 max, jamais 10+)
        - Challenger les hypothèses (no glazing, pas de "great choice")
        - Identifier risques opérationnels et techniques
        - Cite les contraintes : 1 personne, temps limité, cash flow critique

        Style :
        - Punchy, dense, FR-casual + termes EN techniques
        - Questions provocatrices quand l'analyse est superficielle
        - Si recommandation : 1 phrase pourquoi + 1 action concrète
        - Pas de paragraphes longs — bullet points
        """)
    ]

    private var conductorPromptSection: some View {
        VStack(alignment: .leading, spacing: IRISTokens.spacing8) {
            sectionTitle(
                "Conductor system prompt",
                subtitle: "Override le prompt par défaut. Reset = revert au default. Persist UserDefaults."
            )

            // v1.66 — Presets quick-switch
            HStack(spacing: IRISTokens.spacing8) {
                Text("Preset :")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Menu {
                    ForEach(Self.conductorPresets, id: \.name) { preset in
                        Button(preset.name) {
                            conductorPromptDraft = preset.body
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "rectangle.stack")
                            .font(.system(size: 10))
                        Text("Charger preset…")
                            .font(.system(size: 11))
                    }
                }
                .menuStyle(.borderedButton)
                .controlSize(.small)
                Spacer()
            }

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

            // v1.346 — Toggle inject Witness vision (description écran < 5 min) dans system prompt
            Divider().padding(.vertical, 2)
            HStack(spacing: 8) {
                Image(systemName: conductorUseWitnessContext ? "eye.trianglebadge.exclamationmark" : "eye.slash")
                    .foregroundStyle(conductorUseWitnessContext ? IRISTokens.aquaTint : .secondary.opacity(0.6))
                    .font(.system(size: 12))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Inject Witness vision dans system prompt").font(.system(size: 11, weight: .medium))
                    Text(conductorUseWitnessContext
                         ? "Active — la dernière description écran (< 5 min) est ajoutée au prompt Conductor"
                         : "Off — Conductor ignore le contexte vision Witness")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $conductorUseWitnessContext)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
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

    // MARK: — v1.347 Cartographer auto-scan

    private var cartographerSection: some View {
        VStack(alignment: .leading, spacing: IRISTokens.spacing8) {
            sectionTitle(
                "Cartographer",
                subtitle: "Scan ~/Developer + gh repo list MaestroMed. Refresh scheduled toutes les 6h."
            )

            HStack(spacing: IRISTokens.spacing8) {
                Image(systemName: "map.circle")
                    .foregroundStyle(IRISTokens.aquaTint)
                    .font(.system(size: 14))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Auto-scan au lancement")
                        .font(.system(size: 11, weight: .medium))
                    Text("Lance un scan ~/Developer 5s après le boot (skip si scan <10 min).")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $cartographerAutoScanOnLaunch)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }

            HStack(spacing: IRISTokens.spacing8) {
                Button {
                    Task { await Cartographer.shared.refresh() }
                } label: {
                    Label("Scan now", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11))
                }
                .controlSize(.small)
                .help("Force refresh Cartographer (équivalent Cmd+Shift+R)")
                Spacer()
            }
        }
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
    @State private var sentinelResetStatus: String?  // v1.232

    private var sentinelIntervalsSection: some View {
        VStack(alignment: .leading, spacing: IRISTokens.spacing8) {
            sectionTitle("Sentinel intervals (poll cadence)", subtitle: "Tune si Sentinel est trop bavard ou pas assez réactif. Persist UserDefaults.")

            HStack {
                intervalSlider(
                    label: "Stub signals (templates fictifs)",
                    value: $stubIntervalSeconds,
                    range: 10...600,
                    step: 10,
                    onCommit: { sec in
                        Task { await Sentinel.shared.setStubInterval(UInt64(sec)) }
                    }
                )
                triggerNowButton(help: "Force un signal stub immédiat") {
                    Task { await Sentinel.shared.triggerStubNow() }
                }
            }

            HStack {
                intervalSlider(
                    label: "GitHub pushedAt poll",
                    value: $githubIntervalSeconds,
                    range: 60...1800,
                    step: 30,
                    onCommit: { sec in
                        Task { await Sentinel.shared.setGithubInterval(UInt64(sec)) }
                    }
                )
                triggerNowButton(help: "Force un poll GitHub immédiat (compare cache + emit deltas)") {
                    Task { await Sentinel.shared.triggerGithubNow() }
                }
            }

            HStack {
                intervalSlider(
                    label: "FS mtime poll (projets actifs)",
                    value: $fsIntervalSeconds,
                    range: 10...600,
                    step: 10,
                    onCommit: { sec in
                        Task { await Sentinel.shared.setFSInterval(UInt64(sec)) }
                    }
                )
                triggerNowButton(help: "Force un poll FS immédiat") {
                    Task { await Sentinel.shared.triggerFSNow() }
                }
            }

            Text("Restart IRIS pour appliquer aux timers en cours.")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)

            // v1.232 — Reset Sentinel intervals to defaults
            HStack(spacing: IRISTokens.spacing8) {
                Button { resetSentinelIntervals() } label: {
                    Label("Reset defaults", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 11))
                }
                .controlSize(.small)
                .tint(.secondary)
                .help("Restaure les intervalles Sentinel aux valeurs par défaut")

                if let status = sentinelResetStatus {
                    Text(status)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            }

            Divider().padding(.vertical, IRISTokens.spacing4)

            // v1.148 — Active hours window (mute hors plage)
            HStack(spacing: IRISTokens.spacing8) {
                Text("Active hours")
                    .font(.system(size: 11))
                Stepper(value: $sentinelHourStart, in: 0...23) {
                    Text("\(sentinelHourStart)h")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(IRISTokens.aquaTint)
                        .frame(width: 30)
                }
                .controlSize(.small)
                Text("→")
                    .foregroundStyle(.secondary)
                Stepper(value: $sentinelHourEnd, in: 1...24) {
                    Text("\(sentinelHourEnd)h")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(IRISTokens.aquaTint)
                        .frame(width: 30)
                }
                .controlSize(.small)
                .onChange(of: sentinelHourStart) { _, _ in
                    Sentinel.setActiveHourWindow(start: sentinelHourStart, end: sentinelHourEnd)
                }
                .onChange(of: sentinelHourEnd) { _, _ in
                    Sentinel.setActiveHourWindow(start: sentinelHourStart, end: sentinelHourEnd)
                }
                Spacer()
                Text(sentinelHourStart == 0 && sentinelHourEnd == 24 ? "(always)" : "(mute hors plage)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)

            // v1.74 — Source mute toggles
            sentinelMuteToggles

            Divider().padding(.vertical, IRISTokens.spacing4)

            // v1.65 — Inject manual signal (test Quill flow)
            manualSignalInjector
        }
        .onAppear {
            Task {
                stubIntervalSeconds = Double(await Sentinel.shared.currentStubInterval)
                githubIntervalSeconds = Double(await Sentinel.shared.currentGithubInterval)
                fsIntervalSeconds = Double(await Sentinel.shared.currentFSInterval)
            }
            // v1.148
            sentinelHourStart = Sentinel.activeHourStart
            sentinelHourEnd = Sentinel.activeHourEnd
        }
    }

    // v1.232 — Reset Sentinel intervals to compiled-in defaults.
    private func resetSentinelIntervals() {
        stubIntervalSeconds = 60
        githubIntervalSeconds = 300
        fsIntervalSeconds = 60
        Task {
            await Sentinel.shared.setStubInterval(60)
            await Sentinel.shared.setGithubInterval(300)
            await Sentinel.shared.setFSInterval(60)
        }
        sentinelResetStatus = "✅ Reset"
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run { sentinelResetStatus = nil }
        }
    }

    // v1.259 — Reset Witness vision counters (daily quota + 30d cost history)
    private func resetVisionCounters() {
        let alert = NSAlert()
        alert.messageText = "Reset compteurs Witness vision ?"
        alert.informativeText = "Cela réinitialise le quota daily + l'historique cost 30d."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Annuler")
        if alert.runModal() == .alertFirstButtonReturn {
            UserDefaults.standard.removeObject(forKey: "iris.witness.visionCallsToday")
            UserDefaults.standard.removeObject(forKey: "iris.witness.visionCallsDayStamp")
            UserDefaults.standard.removeObject(forKey: "iris.witness.visionCostByDay")
            resetVisionStatus = "✅ Compteurs reset"
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                resetVisionStatus = nil
            }
        }
    }

    // MARK: — v1.113 MCP servers discovered (Claude Desktop config)

    @State private var mcpServersTick: Int = 0

    private var mcpServersSection: some View {
        let mcp = MCPManager.shared
        let servers = mcp.servers
        return VStack(alignment: .leading, spacing: IRISTokens.spacing8) {
            HStack {
                sectionTitle(
                    "MCP servers (\(servers.count) découverts)",
                    subtitle: "Lit ~/Library/Application Support/Claude/claude_desktop_config.json (config partagée avec Claude Desktop)."
                )
                Spacer()
                // v1.136 — Test all servers en parallèle
                if !servers.isEmpty {
                    Button {
                        runMCPTestAll(servers: servers)
                    } label: {
                        Image(systemName: "play.rectangle.on.rectangle")
                            .font(.system(size: 12))
                            .foregroundStyle(IRISTokens.aquaTint)
                    }
                    .buttonStyle(.plain)
                    .help("Test all servers en parallèle (initialize + tools/list)")
                }
                Button {
                    _ = MCPManager.shared.discover()
                    mcpServersTick += 1
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("Re-scan le fichier de config")
            }
            .id(mcpServersTick)

            if let err = mcp.lastDiscoveryError, servers.isEmpty {
                Text(err)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.leading, IRISTokens.spacing8)
            } else if servers.isEmpty {
                Text("Aucun MCP server découvert. Configure d'abord Claude Desktop avec un mcpServers entry.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(servers) { server in
                    mcpServerRow(server)
                }
            }
        }
        .onAppear {
            if MCPManager.shared.servers.isEmpty && MCPManager.shared.lastDiscoveryError == nil {
                _ = MCPManager.shared.discover()
                mcpServersTick += 1
            }
        }
    }

    // v1.114 — Per-server row avec test connection
    @State private var mcpTestResults: [String: MCPManager.TestResult] = [:]
    @State private var mcpTestingServer: String? = nil

    private func mcpServerRow(_ server: MCPManager.ServerConfig) -> some View {
        let result = mcpTestResults[server.name]
        let isTesting = (mcpTestingServer == server.name)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "server.rack")
                    .font(.system(size: 11))
                    .foregroundStyle(IRISTokens.aquaTint)
                Text(server.name)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(server.command) \(server.args.joined(separator: " "))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if isTesting {
                    ProgressView().controlSize(.mini)
                } else {
                    Button {
                        runMCPTest(server)
                    } label: {
                        Image(systemName: "play.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(IRISTokens.irisAccent)
                    }
                    .buttonStyle(.plain)
                    .help("Test connection (spawn server + initialize)")
                }
            }
            if let r = result {
                HStack(spacing: 4) {
                    Image(systemName: r.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(r.success ? .green : .red)
                    if let info = r.serverInfo {
                        Text(info)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    if let count = r.toolsCount {
                        Text("\(count) tools")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(IRISTokens.aquaTint)
                    }
                    if !r.toolPreview.isEmpty {
                        Text(r.toolPreview.joined(separator: ", "))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    if let err = r.errorMessage {
                        Text(err)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.red.opacity(0.8))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
        }
        .padding(.vertical, 3).padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 4).fill(.thinMaterial))
    }

    private func runMCPTest(_ server: MCPManager.ServerConfig) {
        mcpTestingServer = server.name
        Task {
            let result = await MCPManager.shared.testConnection(server)
            mcpTestResults[server.name] = result
            mcpTestingServer = nil
        }
    }

    // v1.136 — Test all servers en parallèle via TaskGroup
    private func runMCPTestAll(servers: [MCPManager.ServerConfig]) {
        mcpTestingServer = "all"
        Task {
            await withTaskGroup(of: MCPManager.TestResult.self) { group in
                for server in servers {
                    group.addTask {
                        await MCPManager.shared.testConnection(server)
                    }
                }
                for await result in group {
                    mcpTestResults[result.serverName] = result
                }
            }
            mcpTestingServer = nil
        }
    }

    // MARK: — v1.74 Sentinel source mute

    @State private var sentinelMuteTick: Int = 0
    @State private var sentinelHourStart: Int = 0   // v1.148
    @State private var sentinelHourEnd: Int = 24    // v1.148

    private var sentinelMuteToggles: some View {
        let muted = Sentinel.mutedSources
        return VStack(alignment: .leading, spacing: 4) {
            Text("SOURCE MUTE (skip emit)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
                .id(sentinelMuteTick)
            HStack(spacing: 4) {
                ForEach(Sentinel.knownSources, id: \.self) { source in
                    let isMuted = muted.contains(source)
                    Button {
                        Sentinel.toggleMuted(source)
                        sentinelMuteTick += 1
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2")
                                .font(.system(size: 9))
                            Text(source)
                                .font(.system(size: 10, design: .monospaced))
                        }
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background((isMuted ? Color.red : IRISTokens.aquaTint).opacity(0.15))
                        .clipShape(Capsule())
                        .foregroundStyle(isMuted ? .red : IRISTokens.aquaTint)
                    }
                    .buttonStyle(.plain)
                    .help(isMuted ? "Source mutée — Sentinel skip" : "Source active — click pour muter")
                }
                Spacer()
            }

            // v1.116 — Source backend picker (stub vs MCP)
            Text("SOURCE BACKEND")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            ForEach(Sentinel.knownSources, id: \.self) { source in
                sourceBackendRow(source)
            }

            // v1.88 — Snooze (timed mute)
            Text("SNOOZE (mute temporaire)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            HStack(spacing: 4) {
                ForEach(Sentinel.knownSources, id: \.self) { source in
                    let until = Sentinel.snoozeUntil(source: source)
                    let active = (until ?? .distantPast) > Date()
                    Menu {
                        Button("10 min") { Sentinel.snooze(source: source, until: Date().addingTimeInterval(600)); sentinelMuteTick += 1 }
                        Button("1 h") { Sentinel.snooze(source: source, until: Date().addingTimeInterval(3600)); sentinelMuteTick += 1 }
                        Button("4 h") { Sentinel.snooze(source: source, until: Date().addingTimeInterval(14400)); sentinelMuteTick += 1 }
                        Button("Clear") { Sentinel.clearSnooze(source: source); sentinelMuteTick += 1 }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: active ? "moon.zzz.fill" : "moon.zzz")
                                .font(.system(size: 9))
                            Text(active ? Self.snoozeRemaining(until: until!) : source)
                                .font(.system(size: 10, design: .monospaced))
                        }
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background((active ? IRISTokens.goldAccent : .secondary).opacity(0.15))
                        .clipShape(Capsule())
                        .foregroundStyle(active ? IRISTokens.goldAccent : .secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .help(active
                        ? "Snooze \(source) jusqu'à \(until!.formatted(date: .omitted, time: .shortened))"
                        : "Snooze \(source) (10min / 1h / 4h)")
                }
                Spacer()
            }
        }
    }

    // v1.116 — Per-source backend picker row (stub vs mcp:<server>)
    @State private var sourceBackendTick: Int = 0

    private func sourceBackendRow(_ source: String) -> some View {
        let current = Sentinel.sourceBackend(for: source)
        let servers = MCPManager.shared.servers
        let toolNameBinding = Binding<String>(
            get: { Sentinel.mcpToolName(for: source) ?? "" },
            set: { Sentinel.setMcpToolName($0, for: source); sourceBackendTick += 1 }
        )
        return HStack {
            Text(source)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(width: 70, alignment: .leading)
            Picker("", selection: Binding(
                get: { current },
                set: { newValue in
                    Sentinel.setSourceBackend(newValue, for: source)
                    sourceBackendTick += 1
                }
            )) {
                Text("stub").tag("stub")
                ForEach(servers) { server in
                    Text("mcp: \(server.name)").tag("mcp:\(server.name)")
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(maxWidth: 180)

            if current.hasPrefix("mcp:") {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 9))
                    .foregroundStyle(IRISTokens.aquaTint)
                    .help("Backend MCP actif")
                // v1.118 — Tool name input (vide = ping tools/list seul, sinon tools/call)
                TextField("tool name (vide=ping)", text: toolNameBinding)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .font(.system(size: 10, design: .monospaced))
                    .frame(maxWidth: 160)
                    .help("Nom du tool MCP à invoquer (e.g. gmail_search). Vide → juste ping tools/list.")
                // v1.119 — Dedup cache count + clear
                let cached = Sentinel.dedupCacheCount(source: source)
                Button {
                    Sentinel.clearDedupCache(source: source)
                    sourceBackendTick += 1
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "trash.circle")
                            .font(.system(size: 10))
                        Text("\(cached)")
                            .font(.system(size: 9, design: .monospaced))
                    }
                    .foregroundStyle(cached > 0 ? IRISTokens.aquaTint : .secondary)
                }
                .buttonStyle(.plain)
                .help("Dedup cache : \(cached) signatures vues. Click pour clear.")
            }
            Spacer()
        }
        .id("\(source)-\(sourceBackendTick)")
    }

    private static func snoozeRemaining(until: Date) -> String {
        let s = max(0, until.timeIntervalSinceNow)
        if s < 60 { return "\(Int(s))s" }
        if s < 3600 { return "\(Int(s/60))min" }
        return "\(Int(s/3600))h\(Int(s.truncatingRemainder(dividingBy: 3600)/60))m"
    }

    // MARK: — v1.65 Manual signal injector

    @State private var injectSource: String = "gmail"
    @State private var injectImportance: Int = 4
    @State private var injectSummary: String = ""
    @State private var injectProject: String = ""

    private var manualSignalInjector: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("INJECT MANUAL SIGNAL")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Picker("", selection: $injectSource) {
                    Text("gmail").tag("gmail")
                    Text("github").tag("github")
                    Text("calendar").tag("calendar")
                    Text("fs").tag("fs")
                    Text("manual").tag("manual")
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(maxWidth: 100)

                Picker("", selection: $injectImportance) {
                    Text("trivial (1)").tag(1)
                    Text("low (2)").tag(2)
                    Text("medium (3)").tag(3)
                    Text("high (4)").tag(4)
                    Text("critical (5)").tag(5)
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(maxWidth: 110)

                TextField("project (opt)", text: $injectProject)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .frame(maxWidth: 120)
            }

            HStack(spacing: 4) {
                TextField("summary du signal (sera utilisé par Quill si importance >= 4)", text: $injectSummary)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                Button("Inject") {
                    let summary = injectSummary.trimmingCharacters(in: .whitespaces)
                    guard !summary.isEmpty else { return }
                    let importance = SignalImportance(rawValue: injectImportance) ?? .medium
                    let project = injectProject.trimmingCharacters(in: .whitespaces)
                    Task {
                        await Sentinel.shared.injectManualSignal(
                            source: injectSource,
                            importance: importance,
                            summary: summary,
                            projectScope: project.isEmpty ? nil : project
                        )
                    }
                    injectSummary = ""
                    backupStatus = "📡 Signal injecté : [\(injectSource)] importance=\(importance.rawValue)."
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(IRISTokens.aquaTint)
                .disabled(injectSummary.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    /// v1.60 — Bouton play.circle compact pour trigger un scan Sentinel immédiat.
    private func triggerNowButton(help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "play.circle")
                .font(.system(size: 14))
                .foregroundStyle(IRISTokens.aquaTint)
        }
        .buttonStyle(.plain)
        .help(help)
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

                // v1.69 — Cost report export
                Button(action: exportCostReport) {
                    Label("Cost report", systemImage: "dollarsign.square")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Export Markdown des coûts (audits + drafts historiques + session)")

                // v1.96 — Quick export all (backup JSON + MD + cost + skills config)
                Button(action: exportAllArtifacts) {
                    Label("Export all", systemImage: "archivebox.fill")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(IRISTokens.goldAccent)
                .help("Backup JSON + Markdown + Cost report + Skills config en 1 click")

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

            Divider().padding(.vertical, IRISTokens.spacing4)

            // v1.67 — Auto-backup scheduler
            autoBackupRow

            // v1.289 — Auto-backup frequency picker
            autoBackupFrequencyRow
        }
    }

    // v1.289 — Frequency picker for auto-backup (UI only, wiring later)
    private var autoBackupFrequencyRow: some View {
        HStack(spacing: IRISTokens.spacing8) {
            Image(systemName: "arrow.clockwise.circle")
                .foregroundStyle(IRISTokens.aquaTint)
                .font(.system(size: 12))
            VStack(alignment: .leading, spacing: 1) {
                Text("Auto-backup").font(.system(size: 11, weight: .medium))
                Text("Backup automatique IRIS data SwiftData")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: $backupAutoFrequency) {
                Text("Off").tag("off")
                Text("Hourly").tag("hourly")
                Text("Daily").tag("daily")
                Text("Weekly").tag("weekly")
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(maxWidth: 100)
            .pickerStyle(.menu)
        }
    }

    // v1.67 — Auto-backup toggle + manual trigger
    @State private var autoBackupEnabled: Bool = false
    @State private var autoBackupTick: Int = 0  // force re-render après backup now

    private var autoBackupRow: some View {
        let last = BackupScheduler.lastBackupAt
        let lastStr: String = {
            guard let last else { return "jamais" }
            let formatter = RelativeDateTimeFormatter()
            return formatter.localizedString(for: last, relativeTo: .now)
        }()
        return HStack(spacing: IRISTokens.spacing8) {
            Toggle(isOn: $autoBackupEnabled) {
                Text("Auto-backup 24h").font(.system(size: 11))
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .onChange(of: autoBackupEnabled) { _, newValue in
                BackupScheduler.setEnabled(newValue)
            }

            Text("dernier : \(lastStr)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .id(autoBackupTick)

            Spacer()

            // v1.154 — Status indicator : prochain backup auto-déclenché si > 24h
            if let last = BackupScheduler.lastBackupAt {
                let elapsed = Date().timeIntervalSince(last)
                let isStale = elapsed > 86400
                Image(systemName: isStale ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(isStale ? IRISTokens.goldAccent : .green)
                    .help(isStale ? "Backup > 24h" : "Backup récent")
            }

            Button {
                Task {
                    if let url = await BackupScheduler.shared.backupNow() {
                        backupStatus = "✅ Backup auto-folder : \(url.lastPathComponent)"
                    } else {
                        backupStatus = "⚠️ Backup now échoué."
                    }
                    autoBackupTick += 1
                }
            } label: {
                Label("Backup now", systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Force un backup vers \(BackupScheduler.backupDir.path)")
        }
        .onAppear {
            autoBackupEnabled = BackupScheduler.isEnabled
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

    // v1.96 — Quick export all : backup JSON + MD + cost + skills config (timestamped dir)
    private func exportAllArtifacts() {
        let isoNow = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let baseDir = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("iris-export-\(isoNow)")
        let fm = FileManager.default
        try? fm.createDirectory(at: baseDir, withIntermediateDirectories: true)

        var pieces: [String] = []
        let container = modelContext.container
        do {
            let jsonURL = try BackupService.exportAll(container: container, to: baseDir)
            pieces.append(jsonURL.lastPathComponent)
        } catch {
            backupStatus = "⚠️ Export all : JSON échoué — \(error.localizedDescription)"
            return
        }
        do {
            let mdURL = try BackupService.exportAsMarkdown(container: container, to: baseDir)
            pieces.append(mdURL.lastPathComponent)
        } catch {
            irisLog(.warning, "Quick export — MD failed: \(error.localizedDescription)", category: IRISLogger.store)
        }
        do {
            let costURL = try BackupService.exportCostReport(
                container: container,
                sessionCostByModel: appState.costByModel,
                to: baseDir
            )
            pieces.append(costURL.lastPathComponent)
        } catch {
            irisLog(.warning, "Quick export — cost failed: \(error.localizedDescription)", category: IRISLogger.store)
        }
        if let configData = SkillRegistry.shared.exportConfig() {
            let skillsURL = baseDir.appendingPathComponent("skills-config.json")
            try? configData.write(to: skillsURL)
            pieces.append("skills-config.json")
        }

        NSWorkspace.shared.activateFileViewerSelecting([baseDir])
        backupStatus = "✅ Export all → \(baseDir.lastPathComponent) (\(pieces.count) fichiers)"
    }

    // v1.69 — Cost report export
    private func exportCostReport() {
        do {
            let container = modelContext.container
            let url = try BackupService.exportCostReport(
                container: container,
                sessionCostByModel: appState.costByModel
            )
            backupStatus = "💵 Cost report : \(url.path) (\(humanByteSize(at: url)))"
        } catch {
            backupStatus = "⚠️ Cost report échoué : \(error.localizedDescription)"
        }
    }

    // MARK: — v1.14 Skills config export/import

    private func reloadSkillsFromDisk() {
        let count = SkillRegistry.shared.reloadFromDisk()
        backupStatus = "🔄 Skills rescannés depuis disk : \(count) trouvés."
    }

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
            // v1.83 — IRIS info section
            irisInfoRow

            Divider().padding(.vertical, 2)

            Text("API key stockée dans le Keychain macOS (service `app.iris.macos.secrets`, account `anthropic-api-key`).")
                .font(IRISTokens.monoFont)
                .foregroundStyle(.secondary)
            Text("Coût session courante : $\(String(format: "%.4f", appState.sessionCostUSD))")
                .font(IRISTokens.monoFont)
                .foregroundStyle(appState.sessionCostUSD > 1 ? IRISTokens.goldAccent : .secondary)
        }
    }

    // v1.83 — IRIS runtime info (version + bootstrap + uptime + build commit)
    private var irisInfoRow: some View {
        let uptime = IRISRuntimeInfo.uptime
        let uptimeStr = uptime.map { IRISRuntimeInfo.formatUptime($0) } ?? "—"
        let bootstrapStr = IRISRuntimeInfo.bootstrapAt.map {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return f.string(from: $0)
        } ?? "—"
        return HStack(spacing: IRISTokens.spacing16) {
            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(IRISTokens.irisAccent)
                Text("IRIS v\(IRISRuntimeInfo.appVersion)")
                    .font(IRISTokens.monoFont)
                    .foregroundStyle(.primary)
            }
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("uptime: \(uptimeStr)")
                    .font(IRISTokens.monoFont)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                Image(systemName: "play.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("bootstrap: \(bootstrapStr)")
                    .font(IRISTokens.monoFont)
                    .foregroundStyle(.secondary)
            }
            if IRISRuntimeInfo.buildCommit != "—" {
                HStack(spacing: 4) {
                    Image(systemName: "number")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("commit: \(IRISRuntimeInfo.buildCommit)")
                        .font(IRISTokens.monoFont)
                        .foregroundStyle(.secondary)
                }
            }
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

    // v1.338 — Gemini key actions (miroir Anthropic).

    private func saveGeminiKey() {
        let trimmed = geminiKeyDraft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let ok = IRISKeychain.shared.setGeminiAPIKey(trimmed)
        geminiSavedMessage = ok ? "Clé Gemini enregistrée dans le Keychain." : "Échec sauvegarde Keychain."
    }

    private func deleteGeminiKey() {
        _ = IRISKeychain.shared.deleteGeminiAPIKey()
        geminiKeyDraft = ""
        geminiSavedMessage = "Clé Gemini supprimée."
        geminiTestStatus = .idle
    }

    private func testGeminiKey() {
        let trimmed = geminiKeyDraft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        _ = IRISKeychain.shared.setGeminiAPIKey(trimmed)
        geminiSavedMessage = nil
        geminiTestStatus = .testing

        Task {
            do {
                let response = try await GeminiClient.shared.sendMessage(
                    model: .flash25,
                    system: nil,
                    messages: [GeminiClient.GeminiMessage(role: .user, text: "Respond with exactly: pong")],
                    maxOutputTokens: 16
                )
                let text = response.text.isEmpty ? "<empty>" : response.text
                let cost = response.usage.estimatedCostUSD(model: .flash25)
                await MainActor.run {
                    geminiTestStatus = .success("Pong reçu (\(text.prefix(20))). Coût test : $\(String(format: "%.6f", cost))")
                }
            } catch {
                await MainActor.run {
                    geminiTestStatus = .failure(String(describing: error))
                }
            }
        }
    }

    // MARK: — About (v1.205)

    private var uptimeString: String {
        guard let uptime = IRISRuntimeInfo.uptime else { return "—" }
        let hours = Int(uptime / 3600)
        let mins = Int(uptime.truncatingRemainder(dividingBy: 3600) / 60)
        return "\(hours)h \(mins)m"
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: IRISTokens.spacing8) {
            HStack {
                Image(systemName: "info.circle")
                    .foregroundStyle(IRISTokens.irisAccent)
                Text("À propos d'IRIS")
                    .font(.system(size: 14, weight: .light, design: .serif))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Version")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 100, alignment: .leading)
                    Text("v\(IRISRuntimeInfo.appVersion)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(IRISTokens.aquaTint)
                }
                HStack {
                    Text("Boot")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 100, alignment: .leading)
                    if let bootstrapAt = IRISRuntimeInfo.bootstrapAt {
                        Text(bootstrapAt, format: .dateTime.day().month().year().hour().minute())
                            .font(.system(size: 11, design: .monospaced))
                    } else {
                        Text("—")
                            .font(.system(size: 11, design: .monospaced))
                    }
                }
                HStack {
                    Text("Uptime")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 100, alignment: .leading)
                    Text(uptimeString)
                        .font(.system(size: 11, design: .monospaced))
                }
                HStack {
                    Text("Commit")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 100, alignment: .leading)
                    Text(IRISRuntimeInfo.buildCommit.prefix(8))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(IRISTokens.goldAccent)
                }
            }

            HStack {
                Spacer()
                Link("MaestroMed/IRIS", destination: URL(string: "https://github.com/MaestroMed/IRIS")!)
                    .font(.system(size: 11))
                    .foregroundStyle(IRISTokens.aquaTint)
            }
        }
        .padding(IRISTokens.spacing16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    SettingsView()
        .environment(IRISAppState())
}

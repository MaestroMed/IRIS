import SwiftUI
import AppKit
import ScreenCaptureKit

/// v1.345 — Onboarding 3 étapes guidées au premier launch.
/// Apparaît si Anthropic key absente OU ~/Developer manquant OU screen-recording permission non accordée.
/// Skippable mais utile pour user freshly installed.
struct OnboardingSheet: View {
    @Environment(IRISAppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var step: Int = 1
    @State private var apiKeyDraft: String = ""
    @State private var saveStatus: String?

    var body: some View {
        VStack(spacing: IRISTokens.spacing24) {
            // Header
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(IRISTokens.aquaTint)
                    .font(.system(size: 28))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bienvenue dans IRIS")
                        .font(.system(size: 24, weight: .light, design: .serif))
                    Text("Ton exocortex perso. Configure 3 trucs et c'est parti.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Skip") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.small)
            }

            Divider()

            // Step indicators
            HStack(spacing: IRISTokens.spacing8) {
                ForEach(1...3, id: \.self) { i in
                    HStack(spacing: 4) {
                        ZStack {
                            Circle().fill(i <= step ? IRISTokens.aquaTint : Color.secondary.opacity(0.2)).frame(width: 22, height: 22)
                            Text("\(i)").font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(i <= step ? .white : .secondary)
                        }
                        Text(stepLabel(i)).font(.system(size: 11)).foregroundStyle(i == step ? .primary : .secondary)
                    }
                    if i < 3 {
                        Rectangle().fill(Color.secondary.opacity(0.2)).frame(height: 1).frame(maxWidth: 30)
                    }
                }
                Spacer()
            }

            Divider()

            // Step content
            Group {
                switch step {
                case 1: step1ApiKey
                case 2: step2Permissions
                case 3: step3DeveloperFolder
                default: EmptyView()
                }
            }
            .frame(minHeight: 220)

            Spacer()

            // Footer nav
            HStack {
                if step > 1 {
                    Button("Précédent") { step -= 1 }
                        .controlSize(.small)
                }
                Spacer()
                if step < 3 {
                    Button("Suivant") { step += 1 }
                        .keyboardShortcut(.defaultAction)
                        .controlSize(.regular)
                } else {
                    Button("Terminer") {
                        UserDefaults.standard.set(true, forKey: "iris.onboarding.completed")
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.regular)
                }
            }
        }
        .padding(IRISTokens.spacing32)
        .frame(minWidth: 560, idealWidth: 640, minHeight: 480, idealHeight: 520)
        .onAppear {
            apiKeyDraft = IRISKeychain.shared.getAnthropicAPIKey() ?? ""
        }
    }

    private func stepLabel(_ i: Int) -> String {
        switch i {
        case 1: return "API key"
        case 2: return "Permissions"
        case 3: return "Projets"
        default: return ""
        }
    }

    // MARK: — Step 1 — Anthropic API key

    private var step1ApiKey: some View {
        VStack(alignment: .leading, spacing: IRISTokens.spacing16) {
            Label("Anthropic API key", systemImage: "key.fill")
                .font(.system(size: 14, weight: .medium))
            Text("Requise pour Conductor + Auditor + Quill + Advisor (Claude Opus/Sonnet/Haiku). Stockée Keychain macOS, jamais en clair.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            if IRISKeychain.shared.hasAnthropicAPIKey() {
                Label("Clé déjà configurée — tu peux passer.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 12))
            } else {
                SecureField("sk-ant-…", text: $apiKeyDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, design: .monospaced))
                HStack {
                    Button("Enregistrer dans Keychain") {
                        let trimmed = apiKeyDraft.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        let ok = IRISKeychain.shared.setAnthropicAPIKey(trimmed)
                        saveStatus = ok ? "✅ Clé enregistrée" : "⚠️ Échec Keychain"
                        appState.refreshKeyPresence()
                    }
                    .disabled(apiKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    .controlSize(.small)
                    if let s = saveStatus {
                        Text(s).font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(s.hasPrefix("✅") ? .green : .red)
                    }
                    Spacer()
                    Link("Obtenir une clé →", destination: URL(string: "https://console.anthropic.com/account/keys")!)
                        .font(.system(size: 11))
                }
            }
        }
    }

    // MARK: — Step 2 — Permissions

    private var step2Permissions: some View {
        VStack(alignment: .leading, spacing: IRISTokens.spacing16) {
            Label("Permissions macOS", systemImage: "lock.shield.fill")
                .font(.system(size: 14, weight: .medium))
            Text("IRIS utilise ScreenCaptureKit pour Witness (capture frontmost + vision optionnelle), et NotificationCenter pour signaux critiques.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            // Screen recording check button
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.dashed.and.paperclip").foregroundStyle(IRISTokens.aquaTint)
                    Text("Enregistrement d'écran (Witness vision)").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Button("Ouvrir réglages") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                            NSWorkspace.shared.open(url)
                        }
                    }.controlSize(.small)
                }
                HStack(spacing: 6) {
                    Image(systemName: "bell.badge.fill").foregroundStyle(IRISTokens.goldAccent)
                    Text("Notifications (signaux critiques)").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Button("Ouvrir réglages") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                            NSWorkspace.shared.open(url)
                        }
                    }.controlSize(.small)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 6).fill(.thinMaterial))

            Text("Ces permissions sont demandées la première fois qu'une fonctionnalité s'en sert. Tu peux les régler maintenant ou plus tard.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: — Step 3 — Developer folder

    private var step3DeveloperFolder: some View {
        let developerURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Developer", isDirectory: true)
        let exists = FileManager.default.fileExists(atPath: developerURL.path)
        return VStack(alignment: .leading, spacing: IRISTokens.spacing16) {
            Label("Dossier ~/Developer", systemImage: "folder.fill")
                .font(.system(size: 14, weight: .medium))
            Text("Cartographer scanne ~/Developer pour détecter tes projets locaux (git status, dernière activité). C'est la convention IRIS.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Image(systemName: exists ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(exists ? .green : .red)
                Text(exists ? "Dossier détecté : \(developerURL.path)" : "Dossier absent — Cartographer ne scannera rien")
                    .font(.system(size: 11, design: .monospaced))
                Spacer()
                if !exists {
                    Button("Créer") {
                        try? FileManager.default.createDirectory(at: developerURL, withIntermediateDirectories: true)
                    }.controlSize(.small)
                }
                Button("Ouvrir Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([developerURL])
                }.controlSize(.small).disabled(!exists)
            }
            .padding(IRISTokens.spacing8)
            .background(RoundedRectangle(cornerRadius: 6).fill(.thinMaterial))

            Text("Tu peux aussi cloner tes repos GitHub avec `gh repo clone` directement dans ~/Developer/<codename>.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}

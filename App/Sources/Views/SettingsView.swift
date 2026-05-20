import SwiftUI

/// v0.1 — Settings panel. Pour l'instant : juste l'API key Anthropic.
/// v0.x+ : credentials MCP (Gmail OAuth, GitHub, etc.), choix modèles par agent, théme, raccourcis.
struct SettingsView: View {
    @Environment(IRISAppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var apiKeyDraft: String = ""
    @State private var testStatus: TestStatus = .idle
    @State private var savedMessage: String?

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

            modelsRoutingSection

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

    private var modelsRoutingSection: some View {
        VStack(alignment: .leading, spacing: IRISTokens.spacing8) {
            sectionTitle("Routing modèles (informatif v0.1)", subtitle: "Par défaut (override par agent en v1.0+).")

            VStack(alignment: .leading, spacing: 4) {
                routingRow(label: "Conductor · Builder · Advisor", model: "claude-opus-4-7", cost: "$15/M in · $75/M out")
                routingRow(label: "Quill · Auditor", model: "claude-sonnet-4-6", cost: "$3/M in · $15/M out")
                routingRow(label: "Sentinel · Scribe · Cartographer · Envoy", model: "claude-haiku-4-5", cost: "$1/M in · $5/M out")
                routingRow(label: "Witness (v1.5+)", model: "gemini-2.5-flash-lite", cost: "cheap vision input")
            }
            .padding(.leading, IRISTokens.spacing16)
        }
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

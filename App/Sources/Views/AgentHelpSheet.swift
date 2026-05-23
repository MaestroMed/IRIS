import SwiftUI

/// v1.341 — Agent help sheet: liste des agents IRIS avec exemples de queries cliquables.
/// Ouvert depuis Dashboard "Show help" button.
struct AgentHelpSheet: View {
    @Environment(IRISAppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: IRISTokens.spacing16) {
            // Header
            HStack {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundStyle(IRISTokens.aquaTint)
                    .font(.system(size: 22))
                Text("Comment utiliser IRIS")
                    .font(.system(size: 22, weight: .light, design: .serif))
                Spacer()
                Button("Fermer") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            Text("Chaque agent fait une chose. Clique sur un exemple → ça injecte la query dans le chat Conductor, prêt à envoyer.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: IRISTokens.spacing16) {
                    ForEach(AgentInfo.all, id: \.agent.rawValue) { info in
                        agentCard(info)
                    }
                }
            }
        }
        .padding(IRISTokens.spacing24)
        .frame(minWidth: 600, idealWidth: 720, minHeight: 500, idealHeight: 640)
    }

    private func agentCard(_ info: AgentInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: info.agent.descriptor.symbol)
                    .foregroundStyle(info.color)
                    .font(.system(size: 16))
                    .frame(width: 22)
                Text(info.agent.descriptor.displayName)
                    .font(.system(size: 15, weight: .medium))
                Text("·")
                    .foregroundStyle(.secondary)
                Text(info.agent.descriptor.tagline)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Text(info.what)
                .font(.system(size: 11))
                .foregroundStyle(.primary.opacity(0.85))
                .padding(.leading, 30)
                .padding(.bottom, 4)
            // Example queries
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(info.examples.enumerated()), id: \.offset) { _, example in
                    Button {
                        appState.currentInput = example
                        appState.selection = .agent(.conductor)
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.right.circle")
                                .font(.system(size: 9))
                                .foregroundStyle(info.color.opacity(0.7))
                            Text(example)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 4).fill(info.color.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 30)
        }
        .padding(IRISTokens.spacing8)
        .background(RoundedRectangle(cornerRadius: 6).fill(.thinMaterial))
    }
}

private struct AgentInfo {
    let agent: AgentID
    let color: Color
    let what: String
    let examples: [String]

    static let all: [AgentInfo] = [
        AgentInfo(
            agent: .conductor,
            color: IRISTokens.irisAccent,
            what: "Le chat principal. Tu lui parles, il dispatche vers les autres agents selon ta query.",
            examples: [
                "Que s'est-il passé sur mes projets depuis hier ?",
                "Résume mes 5 dernières conversations importantes.",
                "Quels projets ont besoin d'attention ?",
            ]
        ),
        AgentInfo(
            agent: .auditor,
            color: IRISTokens.aquaTint,
            what: "Audit un projet (code quality, gaps, next actions). Coût: ~$0.02 par audit Sonnet.",
            examples: [
                "audit atelier_frisson",
                "audit az_construction",
                "audit tous mes projets actifs",
            ]
        ),
        AgentInfo(
            agent: .quill,
            color: IRISTokens.goldAccent,
            what: "Écrit des drafts (email, message, texte) à partir d'un signal ou d'une demande.",
            examples: [
                "drafte un mail de relance pour le client AZ Construction",
                "écris un message Slack pour annoncer la mise en prod v2",
                "rédige une note pour l'équipe sur les changements du sprint",
            ]
        ),
        AgentInfo(
            agent: .advisor,
            color: IRISTokens.goldAccent,
            what: "Brief matinal Opus (synthèse de ce qui compte aujourd'hui). Auto chaque jour à 8h.",
            examples: [
                "Brief now",
                "Que dois-je faire en priorité aujourd'hui ?",
                "Synthèse de cette semaine",
            ]
        ),
        AgentInfo(
            agent: .cartographer,
            color: IRISTokens.aquaTint,
            what: "Scan ~/Developer + gh repo list. Maintient la map de tes projets à jour.",
            examples: [
                "Refresh cartographer",
                "Liste mes projets actifs",
                "Quels repos ont bougé cette semaine ?",
            ]
        ),
        AgentInfo(
            agent: .sentinel,
            color: IRISTokens.irisAccent,
            what: "Surveille en arrière-plan : push GitHub, modifs FS ~/Developer, signaux MCP. Émet des Signals.",
            examples: [
                "Trigger sentinel github now",
                "Quels signaux non-acknowledged ?",
                "Mute la source FS pendant 2h",
            ]
        ),
        AgentInfo(
            agent: .witness,
            color: IRISTokens.aquaTint,
            what: "Capture passive : frontmost app + screenshots Haiku Vision (cost-capped). Te sert de mémoire externe.",
            examples: [
                "Sur quoi j'ai bossé ce matin ?",
                "Capture vision de la fenêtre actuelle",
                "Top apps utilisées cette semaine",
            ]
        ),
        AgentInfo(
            agent: .builder,
            color: IRISTokens.goldAccent,
            what: "Scaffolde un nouveau projet depuis un SKILL.md (~/.claude/skills/<skill>/). Git init + commit auto.",
            examples: [
                "scaffold mon-nouveau-site avec le skill lead-gen-local-services-fr",
                "scaffold api-projet-x avec nextjs-stack-baseline-2026",
                "Liste les skills disponibles",
            ]
        ),
        AgentInfo(
            agent: .scribe,
            color: IRISTokens.aquaTint,
            what: "Retrieval sémantique sur tes mémoires (NLEmbedding top-K). Conductor l'appelle automatiquement.",
            examples: [
                "cherche AZ Construction décisions",
                "cherche skills factory pattern",
                "cherche tout ce que je sais sur Supabase",
            ]
        ),
        AgentInfo(
            agent: .envoy,
            color: IRISTokens.irisAccent,
            what: "Envoie les drafts approuvés (Mail.app, webhook). Demande toujours ton approbation avant.",
            examples: [
                "Approve last draft",
                "Quelles actions sont en attente ?",
                "Annule l'action en cours",
            ]
        ),
    ]
}

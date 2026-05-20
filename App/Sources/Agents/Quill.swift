import Foundation
import SwiftData

/// Quill v0.4 — rédige drafts en réponse aux signaux importants. JAMAIS n'envoie.
/// Subscribe `signalEmitted` importance ≥ 4 → invoke Claude Sonnet 4.6 → publish `draftReady`.
///
/// v0.4 : draft générique (email FR formel client). v1.x : routing tonalité par audience
/// + intégration Scribe pour contexte personnalisé par projet/client.
///
/// Cf docs/IRIS-AGENTS-CATALOG.md §4 Quill.
public actor Quill {
    public static let shared = Quill()

    private var subscriptionTask: Task<Void, Never>?
    private var onCost: CostSink?
    private weak var modelContainer: ModelContainer?

    private init() {}

    public func start(
        modelContainer: ModelContainer,
        onCost: @escaping CostSink
    ) async {
        self.modelContainer = modelContainer
        self.onCost = onCost
        guard subscriptionTask == nil else { return }

        let stream = await EventBus.shared.subscribe()
        subscriptionTask = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                if case .signalEmitted(let from, let importance, let summary, let source) = event,
                   from == .sentinel,
                   importance >= .high {
                    await self.handleSignal(importance: importance, summary: summary, source: source)
                }
            }
        }

        irisLog(.info, "Quill started — listening signals ≥ high", category: IRISLogger.agents)
    }

    public func stop() {
        subscriptionTask?.cancel()
        subscriptionTask = nil
    }

    // MARK: — v1.50 Model picker

    private static let modelKey = "iris.quill.model"

    public static var currentModel: ClaudeModel {
        if let raw = UserDefaults.standard.string(forKey: modelKey),
           let model = ClaudeModel(rawValue: raw) {
            return model
        }
        return .sonnet46
    }

    public static func setModel(_ model: ClaudeModel) {
        UserDefaults.standard.set(model.rawValue, forKey: modelKey)
    }

    // MARK: — Drafting

    private static let systemPrompt = """
    Tu es Quill — l'agent rédacteur d'IRIS pour Mehdi (opérateur solo Numelite, agency FR).

    Ta mission : drafter une réponse courte et utile à un signal entrant.
    Tu NE renvoies JAMAIS l'email ; tu produis juste le brouillon. Envoy s'en charge.

    Règles :
    - Style cohérent : direct, no glazing, FR-casual + termes EN techniques quand pertinent
    - Pour les clients (atelier_frisson / az_construction / ief_and_co / sconnect / sconnect / nacks): ton formel-FR poli
    - Pour les internes (github, ci_failure): ton bref technique
    - Adapté à la criticité (importance 4 = posé, importance 5 = urgent + concret)
    - Pas de "great question", pas de "I'd be happy to" — directement utile
    - Format : sujet (1 ligne) + corps (3-8 lignes)

    Output STRICT JSON :
    {"subject": "...", "body": "...", "tone": "formel-fr-client|tech-en-pr|casual-fr-team", "channel": "email|slack|github_comment"}
    """

    private func handleSignal(
        importance: SignalImportance,
        summary: String,
        source: String?
    ) async {
        // v1.20 — Détection audience via context signal
        let audience = Self.detectAudience(source: source, summary: summary)
        let toneGuidance = Self.toneGuidanceFor(audience: audience)

        let userPrompt = """
        Signal entrant à drafter :
        - Source : \(source ?? "inconnu")
        - Importance : \(importance.rawValue)/5
        - Résumé : \(summary)
        - Audience détectée : \(audience.rawValue)

        \(toneGuidance)

        Drafte la réponse en JSON strict.
        """

        let quillModel = Self.currentModel  // v1.50
        do {
            let response = try await AnthropicClient.shared.sendMessage(
                model: quillModel,
                system: Self.systemPrompt,
                messages: [Message(role: .user, content: userPrompt)],
                maxTokens: 1024,
                cacheSystem: true
            )

            let content = response.firstTextContent ?? "{}"
            let cost = response.usage.estimatedCostUSD(model: quillModel)
            onCost?(cost, quillModel.rawValue)

            // Parse JSON (best-effort — si malformé, on fallback en texte brut comme body)
            let parsed = Self.parseDraftJSON(content) ?? .init(
                subject: nil,
                body: content,
                tone: "formel-fr-client",
                channel: "email"
            )

            // Persist Draft
            let draftId = UUID()
            if let container = await modelContainer {
                await MainActor.run {
                    let context = container.mainContext
                    let draft = Draft(
                        id: draftId,
                        signalId: nil,  // v0.4 : pas de FK propre ; v0.5+ tracker via correlationId bus
                        audience: "client",
                        channel: parsed.channel,
                        tone: parsed.tone,
                        subject: parsed.subject,
                        content: parsed.body,
                        modelUsed: ClaudeModel.sonnet46.rawValue,
                        costUSD: cost,
                        status: "pending"
                    )
                    context.insert(draft)
                    try? context.save()
                }
            }

            // Publish on bus
            await EventBus.shared.publish(
                .draftReady(
                    draftId: draftId,
                    signalId: nil,
                    channel: parsed.channel,
                    summary: parsed.subject ?? String(parsed.body.prefix(80))
                )
            )

            irisLog(.info,
                "Quill draft ready \(draftId.uuidString.prefix(8)) — channel=\(parsed.channel) cost=$\(String(format: "%.5f", cost))",
                category: IRISLogger.agents
            )
        } catch {
            irisLog(.error, "Quill draft failed: \(error.localizedDescription)", category: IRISLogger.agents)
            await EventBus.shared.publish(.agentFailure(agent: .quill, error: error.localizedDescription))
        }
    }

    // MARK: — v1.20 Audience detection

    public enum Audience: String, Sendable {
        case clientFormalFR = "formel-fr-client"
        case techPullRequestEN = "tech-en-pr"
        case casualTeamFR = "casual-fr-team"
        case marketingPublicFR = "marketing-fr-public"
    }

    /// Détecte l'audience à partir du source + summary du signal Sentinel.
    /// Mapping basique v1.20, à raffiner v1.20.B avec project context.
    private static func detectAudience(source: String?, summary: String) -> Audience {
        let lowSummary = summary.lowercased()
        // Mention client codenames → tone formel client
        let clientCodenames = ["atelier_frisson", "atelier frisson", "odelie",
                               "az construction", "azconstruction",
                               "ief", "iefandco",
                               "sconnect", "s'connect", "s connect",
                               "monjoel", "mon joel",
                               "01ta", "01 ta", "transfert aeroport",
                               "az epoxy", "azepoxy",
                               "formaroute",
                               "atelierfrissons"]
        for codename in clientCodenames {
            if lowSummary.contains(codename) {
                return .clientFormalFR
            }
        }

        // Source github + signal type → tech EN PR tone
        if source == "github" {
            if lowSummary.contains("ci ") || lowSummary.contains("ci failure") ||
               lowSummary.contains("pr") || lowSummary.contains("pull request") ||
               lowSummary.contains("commit") {
                return .techPullRequestEN
            }
        }

        // Calendar / interne → casual FR team
        if source == "calendar" {
            return .casualTeamFR
        }

        // Mention "newsletter" / "marketing" / "campagne" → marketing public FR
        if lowSummary.contains("newsletter") || lowSummary.contains("marketing") ||
           lowSummary.contains("campagne") || lowSummary.contains("public") {
            return .marketingPublicFR
        }

        return .casualTeamFR
    }

    private static func toneGuidanceFor(audience: Audience) -> String {
        switch audience {
        case .clientFormalFR:
            return """
            **Tone à appliquer** : formel-fr-client (poli, sobre, valeur claire).
            - Vouvoiement strict
            - "Bonjour [prénom]," / "Bien à vous,"
            - Pas d'argot, pas d'abréviation
            - Termes techniques OK si pertinents pour le client (cite leur stack si visible)
            - Si client = cliente (Odelie, Atelier Frisson...) : ton sobre + valoriser leur projet
            """
        case .techPullRequestEN:
            return """
            **Tone à appliquer** : tech-en-pr (concise, code-aware, GitHub style).
            - English (PR conventions internationales)
            - Imperative mood ("Fix Y", "Add X")
            - Reference files/lines précisément (file.swift:42)
            - Suggest specific actions (revert, hotfix, rebase, etc.)
            - Skip pleasantries
            """
        case .casualTeamFR:
            return """
            **Tone à appliquer** : casual-fr-team (FR informel, direct, technique).
            - Tutoiement OK
            - FR-casual + termes EN techniques sans complexe (no glazing)
            - Bullet points si > 2 idées
            - Pas de "Bonjour" formel
            """
        case .marketingPublicFR:
            return """
            **Tone à appliquer** : marketing-fr-public (engageant, value-first, sans bullshit).
            - FR fluide, attractif
            - Hook puis bénéfice puis CTA
            - Données chiffrées si dispo
            - Pas de buzzwords vides ("innovant", "disruptif")
            """
        }
    }

    // MARK: — Helpers

    private struct ParsedDraft: Sendable {
        let subject: String?
        let body: String
        let tone: String
        let channel: String
    }

    private static func parseDraftJSON(_ raw: String) -> ParsedDraft? {
        // Trim markdown fences si Claude les ajoute parfois
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            // Strip fences
            cleaned = cleaned
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        return ParsedDraft(
            subject: json["subject"] as? String,
            body: (json["body"] as? String) ?? "",
            tone: (json["tone"] as? String) ?? "formel-fr-client",
            channel: (json["channel"] as? String) ?? "email"
        )
    }
}

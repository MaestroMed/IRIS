# IRIS — Roadmap

**Date** : 2026-05-20 · **Statut** : design v0
**Sister doc** : [IRIS-VISION.md](IRIS-VISION.md), [IRIS-ARCHITECTURE.md](IRIS-ARCHITECTURE.md), [IRIS-AGENTS-CATALOG.md](IRIS-AGENTS-CATALOG.md)

---

## Philosophie

Mehdi a demandé « 100 prochaines versions ». Cette roadmap en propose ~45 granulaires sur 6 phases majeures. Chaque version = **un livrable utile concret**, pas un chunk de framework abstrait. Anti-over-architecting respecté.

**Rythme cible** : v0.0.x toutes les 1-3 jours, v0.x toutes les 1-2 semaines, v1.x toutes les 2-4 semaines.

**Critère go/no-go pour chaque version** : si la scope d'une version ne tient pas en une session de travail (2-6 h), elle doit être scindée.

---

## Phase 0 — Hello IRIS (v0.0.1 → v0.0.5)

Objectif : bootstrap le repo, app shell qui lance, UI vide qui ouvre, communication agent ↔ UI fonctionnelle.

| Version | Scope | Critère acceptation | Dépendances |
|---|---|---|---|
| **v0.0.1** | Bootstrap SwiftUI Mac app via **Tuist 4** (cohérence MIND). Bundle ID `app.iris.macos`, target macOS 26. SwiftUI minimal : `IRISApp.swift` @main + `ContentView.swift` "Hello Mehdi". Repo `MaestroMed/IRIS` (overwrite placeholder 2023). | `tuist generate && xcodebuild -scheme IRIS build` OK. App lance, montre "Hello Mehdi". | Xcode 26.5 + Tuist 4.x déjà OK ✅ |
| **v0.0.2** | Layout 3 panels (sidebar agents / main canvas / right inspector) via `NavigationSplitView` macOS-natif. Liquid Glass tokens (couleurs iris/aqua/sky soft, blur materials natifs macOS). | Visuel cohérent avec MIND. Panels redimensionnables. Aucune logique encore. | v0.0.1 |
| **v0.0.3** | Event Bus interne via `AsyncStream<IRISEvent>` Swift. Logger structuré via `os_log` + viewer dans panel "System". | Click bouton UI → event publié sur le bus → log visible + roundtrip vers autre view. | v0.0.2 |
| **v0.0.4** | Schema **SwiftData** : `Agent`, `Event`, `ActionLog`, `Memory`, `Signal`, `Project`. CloudKit container configuré (pas encore sync). | Tables `@Model` créées, seed minimal, queries `@Query` OK. | v0.0.3 |
| **v0.0.5** | Conductor mock : reçoit event "user.input" via TextField → echo dans le bus → UI affiche. Pas de LLM encore. | Type "hello", reçois "echo: hello" dans le panel principal. | v0.0.4 |

**Livré fin Phase 0** : app IRIS qui ouvre, qui a une UI cohérente MIND, qui peut router un événement bout en bout. Aucun agent fonctionnel encore — base technique uniquement.

---

## Phase 1 — Premiers agents fonctionnels (v0.1 → v0.5)

Objectif : 5 agents minimaux qui forment une boucle utile cross-source.

| Version | Scope | Critère acceptation | Dépendances |
|---|---|---|---|
| **v0.1** | **Conductor réel** (Claude Opus via `swift-anthropic` SDK ou wrapper REST, prompt caching activé). Décide qui dispatcher quand. Pour l'instant : un seul worker fictif "echo". | Conductor reçoit input user, dispatch à echo worker, retourne réponse. Cost trace visible. | v0.0.5 |
| **v0.2** | **Scribe v1** : embeddings via **Apple NaturalLanguage** + `NLEmbedding` natif macOS OU CoreML modèle bge-small. Stockage SwiftData append-only. Retrieval par similarité. | "Souviens-toi que X" → Scribe stocke. "Qu'est-ce que tu sais de Y" → Scribe retrieve top-3. | v0.1 |
| **v0.3** | **Sentinel Gmail** via wrapper du MCP Gmail server existant (spawn Node process via `Process` API Swift, JSON-RPC stdio). Classification importance via Haiku. Signaux affichés dans panel "Signals". | Nouveau mail dans la boîte → apparait dans Signals avec importance + summary < 30s. | v0.2, MCP Gmail branché |
| **v0.4** | **Quill drafts Gmail**. Sur signal Sentinel importance ≥ 4, propose draft dans panel "Drafts" (sans envoyer). | Email client arrive → draft Quill prêt < 60s. Mehdi peut review/copier-coller manuellement (pas d'Envoy encore). | v0.3 |
| **v0.5** | **Envoy email supervised**. Bouton "Send" sur draft → confirmation modal (NSAlert native) → Envoy envoie via Gmail MCP. Log dans action_log SwiftData. Undo grayed out (email = non-réversible). | Flow complet Gmail : detect → draft → review → send sans toucher l'app Gmail. | v0.4 |

**Livré fin Phase 1** : boucle email semi-automatique fonctionnelle. Sentinel observe, Quill drafte, Mehdi valide, Envoy envoie. Mémoire (Scribe) capitalisée pour calibrer Quill.

---

## Phase 2 — Catalogue complet d'agents (v0.6 → v0.9)

Objectif : compléter les 5 agents restants pour atteindre le catalogue de 10.

| Version | Scope | Critère acceptation | Dépendances |
|---|---|---|---|
| **v0.6** | **Cartographer v1**. Scan `~/Developer/*` + `gh repo list MaestroMed` quotidien. Maintient `store.projects` + sync `~/Iris/artefacts/PROJECTS-MAP.md` automatiquement. | Nouveau repo créé sur GitHub MaestroMed → apparait dans Cartographer panel < 24h. | v0.2 |
| **v0.7** | **Auditor v1**. Invoke skill `damage-control` (déjà installé) sur un projet à la demande. Stocke audit report dans store + écrit fichier `docs/damage-control/PLAN-{date}.md` dans le projet. | "Audit Atelier Frisson" → rapport damage-control complet généré en 5-10 min. | v0.6 |
| **v0.8** | **Builder v1** invoke skills factory. Premier skill cible : `doc-first-project-scaffolding` sur un nouveau projet. Propose diff avant write. | "Setup le scaffolding pour [nouveau projet]" → 10+ fichiers .md proposés en diff, write après approuvé. | v0.6 |
| **v0.9** | **Advisor v1** briefing matinal. Tick scheduled 8h00. Lit Scribe + Sentinel + Cartographer + actions_log. Synthèse top 3 priorités + 2 risques + 1 challenge. Notification macOS. | À 8h00 chaque matin, Mehdi reçoit notif IRIS avec briefing. Cliquable → ouvre panel détail. | v0.6, v0.7 |

**Livré fin Phase 2** : 9/10 agents fonctionnels (Witness vient phase 4). Boucle quotidienne complète : Advisor briefe matin → Mehdi pilote actions → Auditor audit hebdo → Cartographer maintient map.

---

## Phase 3 — Production-ready + skill marketplace local (v1.0 → v1.4)

Objectif : v1.0 = utilisable au quotidien par Mehdi en remplacement de Claude Desktop pour les tâches couvertes.

| Version | Scope | Critère acceptation | Dépendances |
|---|---|---|---|
| **v1.0** | Stable : tous agents (sauf Witness), tests Vitest+cargo couverture core, updater Tauri signed, .dmg notarisé. Premier README utilisateur. | Mehdi utilise IRIS au quotidien pendant 2 semaines sans crash bloquant. | v0.9 |
| **v1.1** | **Skill marketplace local**. Panel "Skills" liste les 11 skills factory + 4 existants. Mehdi peut install/désactiver/configurer. Builder utilise la liste active. | Toggle skill on/off depuis UI → Builder respecte le choix au prochain dispatch. | v1.0 |
| **v1.2** | **Sentinel multi-source v2**. Ajout : GitHub events (PRs / issues / commits / CI), Calendar events, file system watcher sur projets actifs. | Tous les types de signaux apparaissent unifiés dans le panel Signals avec filtres. | v1.0 |
| **v1.3** | **Builder + Envoy git workflow**. "Crée une PR pour [feature]" → Builder scaffold + commit + branch, Envoy push + crée PR via gh. | Flow complet feature → PR en < 5 commandes UI, sans CLI git manuel. | v1.0 |
| **v1.4** | **MIND ↔ IRIS data sync v1** (sens MIND → IRIS d'abord). Lit les audits clients depuis CloudKit zone partagée. Affiche dans Cartographer. | Mehdi voit dans IRIS les audits MIND faits depuis l'iPhone. | v1.0, MIND iOS coopère côté write CloudKit |

---

## Phase 4 — Eyes / Vision / Attention (v1.5 → v1.9)

Objectif : implémenter l'angle distinctif "yeux" de la vision.

| Version | Scope | Critère acceptation | Dépendances |
|---|---|---|---|
| **v1.5** | **Witness v1 — screen capture** (frontmost window only, IRIS pas frontmost). Capture toutes les 5 s. Identification app + window title + project guess via Cartographer. | Panel "Witness" affiche en temps réel "Mehdi sur Cursor / repo AZConstruction_v0". | v1.0 |
| **v1.6** | **Witness vision contextuelle**. Screenshots envoyés à Gemini 2.5 Flash-Lite (cheap vision input). Comprend : "Mehdi écrit un email à Odelie" / "Mehdi review une PR sur AZ Construction". | Advisor utilise context Witness pour suggestions contextuelles ("tu travailles sur Atelier Frisson, voici le draft Quill en attente pour Odelie"). | v1.5 |
| **v1.7** | **Witness webcam opt-in**. Permission Tauri webcam. Détection présence/absence + pose estimation grossière. Pas d'enregistrement. | Mehdi absent 5 min → IRIS met en pause Builder actions. Présent → reprend. | v1.5 |
| **v1.8** | **UI dense Bloomberg-style**. Refonte UI v2 avec panels modulaires drag-resize, widgets agents customisables, dashboard global. | Mehdi peut configurer son layout (3-5 panels visibles selon besoin). Layout persisté. | v1.5 |
| **v1.9** | **Attention-aware prioritization**. Witness signale quel panel Mehdi regarde → Conductor prioritise les updates de ce panel + ralentit les autres. | Mehdi regarde panel Signals → events arrivent rapidement. Mehdi switch à Drafts → Signals ralentit, Drafts prioritise. | v1.7 |

---

## Phase 5 — Cloud sync, multi-devices, federation (v2.0 → v2.9)

Objectif : préparer IRIS pour 3-5 early adopters (autres opérateurs solo) tout en gardant local-first par défaut.

| Version | Scope | Critère acceptation | Dépendances |
|---|---|---|---|
| **v2.0** | **Cloud sync optionnel E2EE**. Tunnel sécurisé via Tauri http + chiffrement age. Sync `store.memories` + `store.projects` cross-devices. | Mehdi installe IRIS sur 2 Macs, mémoires sync. Backup cloud chiffré activable. | v1.0 |
| **v2.1** | **MIND ↔ IRIS sync bi-directionnel v2**. IRIS push audits + signaux client vers MIND. MIND push leads vers IRIS pour drafts. | Round-trip : lead arrive dans MIND → IRIS Quill drafte → Mehdi approve → Envoy send → MIND log. | v1.4, MIND iOS phase 2 |
| **v2.2** | **Multi-user setup (single-tenant)**. Possibilité d'installer IRIS pour un autre opérateur solo en local. Configuration par fichier `.iris/config.yaml`. | Un early adopter installe IRIS, configure ses MCPs, ses skills. Fonctionnel < 30 min. | v1.0 |
| **v2.3** | **Skill marketplace partagé**. Skills exportables/importables via fichier .zip. Catalog en ligne (GitHub repo communautaire). | Un opérateur partage un skill via PR sur le catalog repo. Les autres l'install en 1 clic. | v1.1 |
| **v2.4** | **Telemetry opt-in privacy-first**. Agrégats anonymisés (lesquels skills sont utilisés, lesquels patterns d'usage). Pour optimiser le produit. | Telemetry désactivée par défaut. Si opt-in, les events anonymes remontent sur infrastructure Numelite. | v2.0 |
| **v2.5** | **Federated learning agents (research)**. Calibrage Quill ton par contexte cross-utilisateurs sans fuite (federated avg de paramètres prompts). | POC technique sur 3 early adopters. Quality boost mesuré sur tonalité. | v2.4 |
| **v2.6** | **Windows + Linux builds first-class**. CI cross-platform, installers .msi (Win) + .AppImage (Linux), tests UI sur Win et Linux. | Un early adopter Linux installe IRIS, fonctionnel complet. | v1.0 |
| **v2.7** | **IRIS mobile compagnon (Web PWA)**. Frontend React déployé en PWA accessible depuis iPhone (URL personnelle de Mehdi). Read-only au début. | Mehdi consulte ses Signals + Drafts depuis l'iPhone. Pas d'action. | v2.0 |
| **v2.8** | **IRIS mobile action limited (PWA)**. Approve drafts depuis l'iPhone. Notification push si action requise. | Mehdi peut Approve un Quill draft depuis l'iPhone et l'envoyer. | v2.7 |
| **v2.9** | **Hardening sécurité prod**. Audit pen-test (peut être auto-fait via damage-control élargi). Signature codes, sandboxing renforcé, threat model documenté. | Threat model documenté. Aucune vulnérabilité critique sur audit. | v2.0 |

---

## Phase 6 — Offre commerciale Numelite (v3.0+)

Objectif : IRIS devient un produit vendable par Numelite.

| Version | Scope | Critère acceptation |
|---|---|---|
| **v3.0** | **Landing page + onboarding flow**. Tarification 200-500€/mois. Trial 14 jours. Onboarding 30 min guidé. | 3 premiers paying customers signés. |
| **v3.1** | **License management + admin SaaS Numelite**. Backend Numelite pour gérer licences, billing (Stripe), support. | 10 paying customers actifs. |
| **v3.2** | **Templates par segment d'opérateur**. IRIS pré-configuré pour freelance dev, freelance design, agency 2-5 personnes, consultant indépendant. | Onboarding < 15 min selon template choisi. |
| **v3.3** | **Intégrations clés** : Linear, Notion, Slack, Discord, Stripe (lecture revenus), Plausible (audience). | Top 5 intégrations demandées par early adopters disponibles. |
| **v3.4** | **Equipe (multi-user multi-tenant)**. Permettre à des binômes de partager IRIS. | 3 customers tests en mode binôme. |
| **v3.x** | Continu : nouveaux agents spécialisés, nouveaux skills, nouvelles intégrations, marketplace skill payant. | Croissance MRR + NPS > 50. |

---

## Roadmap récap visuel

```
2026 Q2-Q3
v0.0.x  Hello IRIS              ▓░░░░░░░░░░░░░░░░░  Bootstrap
v0.1    Conductor + LLM         ▓▓░░░░░░░░░░░░░░░░  Premier agent
v0.2-3  Scribe + Sentinel       ▓▓▓░░░░░░░░░░░░░░░  Mémoire + observation
v0.4-5  Quill + Envoy          ▓▓▓▓░░░░░░░░░░░░░░  Boucle email auto
v0.6-9  5 agents restants       ▓▓▓▓▓▓░░░░░░░░░░░░  Catalogue 10

2026 Q4
v1.0    Production-ready        ▓▓▓▓▓▓▓░░░░░░░░░░░  Daily use Mehdi
v1.1-4  Skill marketplace, multi-source, MIND sync ▓▓▓▓▓▓▓▓▓░░░░░░░

2027 Q1-Q2
v1.5-9  Eyes / Vision / UI dense ▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░  Angle distinctif

2027 Q3-Q4
v2.0-9  Cloud sync, multi-devices, early adopters ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░

2028+
v3.0+   Offre commerciale Numelite ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓ MRR + croissance
```

---

## Dépendances externes à anticiper

| Phase | Dépendance | Action |
|---|---|---|
| 0 | Tauri 2 stable | OK, déjà stable |
| 0 | Repo `MaestroMed/IRIS` overwrite placeholder | Décision Mehdi requise (cf question 6 ARCHITECTURE) |
| 1 | Claude Opus 4.7 API + prompt caching | Clé API Anthropic en place (déjà via Claude Code) |
| 1 | ONNX Runtime + modèle bge-small téléchargeable | Bundled dans l'app v0.2 |
| 1 | MCP Gmail server installé | Déjà en place dans Claude Code |
| 2 | MCP GitHub via gh CLI | gh déjà auth (MaestroMed) |
| 4 | Permissions macOS Screen Recording + Camera | Demande system permissions Tauri |
| 5 | Infrastructure cloud Numelite (tunnel sync) | À provisionner avant v2.0 |
| 6 | Stripe + landing + legal Numelite | Setup SaaS classique avant v3.0 |

---

## Anti-roadmap (ce qu'on NE fait PAS)

- **Pas de framework agentique custom maison**. Tauri + JS workers + SQLite suffisent. Si CrewAI / LangGraph deviennent indispensables → on les intègre, pas on les remplace.
- **Pas de fine-tuning de modèles propriétaires**. On reste sur API Anthropic + Gemini + embeddings open (bge/nomic) en local.
- **Pas d'app mobile native (Swift / Kotlin) avant v2.7**. Web PWA suffit pour read-only mobile.
- **Pas de blockchain, pas de Web3, pas de crypto.** Jamais.
- **Pas d'IA générative pour le design / branding de l'app elle-même** — utiliser Mehdi + skill `gpt-image-2-prompter` + Liquid Glass tokens MIND, pas auto-generated UI.
- **Pas de Slack / Discord clones internes**. On lit/écrit dans les outils existants via MCP, on ne fait pas un n-ième messenger.

---

## Décisions Mehdi requises avant v0.0.1

1. **Option C (Tauri) confirmée ?** ou Option A (Mac native) / B (Web pur)
2. **Repo cible** : overwrite `MaestroMed/IRIS` (placeholder 2023) ou nouveau `MaestroMed/iris-app` ?
3. **DA Liquid Glass** : tokens CSS exportables depuis MIND iOS ? Si oui, lien fichier. Sinon, on les recrée à partir des couleurs du README MIND (iris/aqua/sky).
4. **Permissions OS dès v0.0.1** : on demande Screen Recording + Camera tout de suite (pour préparer Witness phase 4) ou seulement quand requis ?
5. **Cadence releases** : 1 version / 1-3 jours en phase 0, on tient ? ou plus lent pour respecter ton temps disponible ?
6. **Visibilité publique de la roadmap** : on push dès maintenant le repo public, ou on garde privé jusqu'à v1.0 ?

---

<!-- Roadmap rédigée 2026-05-20 par la skill-factory IRIS phase 1. Granularité ~45 versions sur 6 phases. À itérer après retours Mehdi. -->

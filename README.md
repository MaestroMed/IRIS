# IRIS

> **Premier exocortex local desktop multi-agents avec UX visuelle dense.**
> Pendant desktop de [MIND](https://github.com/MaestroMed/matter_hub) (cockpit Numelite iOS).

![Mac](https://img.shields.io/badge/macOS-26+-black?style=flat&logo=apple)
![Swift](https://img.shields.io/badge/Swift-6.3-orange?style=flat&logo=swift)
![Version](https://img.shields.io/badge/version-1.0.0-iris?style=flat)
![Agents](https://img.shields.io/badge/agents-9/10_live-iris?style=flat)
![Status](https://img.shields.io/badge/status-self--use_active-green?style=flat)

IRIS est un compagnon Mac qui observe ton flux de travail, te suggère des actions, et exécute (sous validation) ce que tu approuves. Pas un chatbot, pas un IDE — un **cockpit personnel d'opérateur** avec 10 agents spécialisés qui se coordonnent en local.

---

## Features actuelles (v1.0)

**10 agents spécialisés** (9 live, Witness vient en v1.5) :

| Agent | Rôle | Modèle | État |
|---|---|---|---|
| 🪄 **Conductor** | Orchestrateur central, route les inputs | Claude Opus 4.7 | ✅ live |
| 👁️ **Sentinel** | Observe sources externes (signal stub v0.3) | Claude Haiku 4.5 | ✅ stub |
| 📚 **Scribe** | Mémoire long terme + retrieval sémantique | NLEmbedding macOS | ✅ live |
| 🖋️ **Quill** | Rédige drafts (jamais n'envoie) | Claude Sonnet 4.6 | ✅ live |
| ✅ **Auditor** | Audit projets via skill `damage-control` | Mock v0.7 | ✅ mock |
| 🗺️ **Cartographer** | Maintient la carte vivante des projets | Haiku + filesystem + `gh` | ✅ live |
| 🔨 **Builder** | Scaffold via 11 skills factory | Mock v0.8 | ✅ mock |
| ✈️ **Envoy** | Actions externes irréversibles supervisées | Mock send v0.5 | ✅ mock |
| 👀 **Witness** | Vision computer screen + webcam | Gemini Flash-Lite | ⏳ v1.5 |
| 💡 **Advisor** | Briefing matinal 8h + brief now manuel | Claude Opus 4.7 | ✅ live |

**Flow automatique fonctionnel bout en bout** :
1. Sentinel émet signal (gmail/github/calendar/fs) — toutes les 60s en stub
2. Si importance ≥ high → Quill drafte via Sonnet (~$0.001)
3. Envoy propose action dans Inspector "Actions en attente"
4. Tu clique **Approve** → mock send + ActionLog append-only
5. Transcript affiche "✅ Action exécutée"

**Cockpit visuel dense** (Liquid Glass, cohérent MIND iOS) :
- Sidebar 10 agents (status dot live)
- Main canvas : transcript Conductor + cost session tracker
- Inspector dédié par agent sélectionné (Refresh / Audit / Scaffold / Brief now)

**Local-first** : SwiftData + Keychain. Aucune donnée n'est envoyée à un serveur externe — sauf les prompts qui partent à l'API Anthropic (et toi qui as choisi de mettre ta clé).

---

## Quick start

### Prérequis

- macOS 26+ (Apple Silicon)
- Xcode 26+ installé via App Store
- (auto via setup.sh) Homebrew + Tuist

### Install

```bash
git clone https://github.com/MaestroMed/IRIS.git ~/Iris
cd ~/Iris
./scripts/setup.sh
```

Le script install les dépendances, génère le projet Xcode et fait un build verify.

### Lancer

```bash
make run        # build + open -a IRIS
# ou via Xcode :
make open
```

### First run (ajouter ta clé Anthropic)

1. Ouvre l'app → tu vois "IRIS / Conductor / Mode mock — pas d'API key" (gold badge)
2. **Cmd+,** → Settings panel
3. Colle ta clé `sk-ant-...` → **Enregistrer**
4. **Tester (Haiku ping)** → vérifie que la clé répond ($0.000005)
5. Ferme Settings
6. Dans Main Canvas, tape ton premier message → réponse Claude Opus 4.7 avec contexte FR-casual

Dans les 5 secondes, Sentinel commence à émettre des signaux dans Inspector "Signals récents". Sur les importants, Quill drafte (visible dans "Drafts récents"). Envoy te propose alors une action dans "Actions en attente" — clic **Approve** et la boucle est complète.

### Optional — Sentry pour error tracking

Si tu veux centraliser les erreurs côté Sentry (cohérence MIND iOS) :

```bash
export SENTRY_DSN="https://...@oXXXX.ingest.sentry.io/YYY"
make run
```

Sans DSN, Sentry est skip silencieusement. Aucune fuite.

---

## Architecture

Stack figée :

```
Framework         Swift 6.3 strict concurrency + SwiftUI + SwiftData
Build             Tuist 4 (cohérence MIND iOS)
DB                SwiftData local (CloudKit activé en v1.4 pour sync MIND)
LLM               Anthropic Messages API direct (Claude Opus 4.7 / Sonnet 4.6 / Haiku 4.5)
Embeddings        Apple NaturalLanguage (NLEmbedding FR + EN fallback)
Observability     Sentry SDK swift-cocoa (DSN optionnel)
UI                Liquid Glass tokens cohérents MIND iOS (iris/aqua/sky soft)
Keychain          API keys + Sentry DSN dans Keychain macOS chiffré
```

**Pourquoi Mac native SwiftUI** (vs Tauri / Electron / Web) ? Cohérence avec MIND iOS (Swift packages partageables), perf Apple Silicon native, intégration Apple ecosystem (Spotlight + Continuity + Live Activities), design Liquid Glass natif.

Détails complets :
- [docs/IRIS-VISION.md](docs/IRIS-VISION.md) — philosophie + manifeste 10 principes + positionnement vs concurrents
- [docs/IRIS-ARCHITECTURE.md](docs/IRIS-ARCHITECTURE.md) — 3 options techniques évaluées + architecture multi-agents + sécurité
- [docs/IRIS-AGENTS-CATALOG.md](docs/IRIS-AGENTS-CATALOG.md) — 10 agents + 5 flows-types end-to-end
- [docs/IRIS-ROADMAP.md](docs/IRIS-ROADMAP.md) — 45 versions sur 6 phases (v0.0.1 → v3.0)

---

## Dev workflow

```bash
make help        # liste des commandes
make generate    # tuist install + generate (régénère .xcodeproj)
make build       # build Debug macOS
make run         # build + open -a IRIS
make test        # build + run tests
make open        # ouvre Xcode sur IRIS.xcworkspace
make clean       # clean DerivedData + .xcodeproj
make reset       # clean + install + generate (from scratch)
```

CI GitHub Actions ([.github/workflows/ci.yml](.github/workflows/ci.yml)) tourne sur `macos-15` à chaque push/PR (strict mode v1.0 : tests doivent passer).

---

## Roadmap

- **v0.0.x — v0.5** ✅ Bootstrap + Conductor LLM + boucle Sentinel→Quill→Envoy (mock)
- **v0.6 — v1.0** ✅ Cartographer + Auditor + Builder + Advisor + UI dédiée + Sentry
- **v1.1 — v1.4** ⏳ Sentinel Gmail réel (MCP Process spawn) + GitHub events + Cal.com sync + MIND CloudKit sync
- **v1.5 — v1.9** ⏳ Witness (screen + webcam attention) + UI Bloomberg-dense + attention-aware prioritization
- **v2.0 — v2.9** ⏳ Cloud sync E2EE + multi-devices + early adopters
- **v3.0+** ⏳ Offre commerciale Numelite

---

## Pour qui ?

**v1.0** : Mehdi (opérateur solo Numelite, 25+ projets parallèles).
**v2.0** : 3-5 early adopters opérateurs solo / freelances tech francophones.
**v3.0+** : offre commerciale à 200-500€/mois (cockpit personnel d'opérateur agency).

Pas pour : grandes équipes (un IRIS = un utilisateur), use-cases purement codeurs (Cursor est meilleur), use-cases purement chat (Claude Desktop suffit).

---

## License

Propriétaire — IRIS (Numelite). Adapt freely si tu fork.

---

## Genèse

Concept original 2023 (repo placeholder MaestroMed/IRIS — "Interactive & Responsive Intelligent System"). Reprise mai 2026 avec l'arrivée du MacBook Pro M5 et l'extension naturelle de MIND iOS vers le desktop.

Construit en mode mega swarm 24h avec [Claude Code](https://github.com/anthropics/claude-code) — Anthropic Claude Opus 4.7 (1M context). 15 versions shippées en moins de 24h cumulées.

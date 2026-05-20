# IRIS — workspace local

État au 2026-05-20 : **phase 1 skill-factory terminée (11 skills livrés)** + **phase 2 vision/architecture/roadmap livrée en docs**. Code v0.0.1 en attente d'arbitrages Mehdi.

## Documents vision (lire dans l'ordre)

1. [docs/IRIS-VISION.md](docs/IRIS-VISION.md) — philosophie, manifeste 10 principes, positionnement vs MIND + concurrents (Claude Desktop / Cursor / CrewAI / Devin / Rewind / Open Interpreter)
2. [docs/IRIS-ARCHITECTURE.md](docs/IRIS-ARCHITECTURE.md) — 3 options techniques (Mac native SwiftUI / Web Next.js / **Hybride Tauri 2 ← recommandation**) + architecture multi-agents + intégrations MCP + sécurité
3. [docs/IRIS-AGENTS-CATALOG.md](docs/IRIS-AGENTS-CATALOG.md) — 10 agents (Conductor, Sentinel, Scribe, Quill, Auditor, Cartographer, Builder, Envoy, Witness, Advisor) + 5 flows-types end-to-end
4. [docs/IRIS-ROADMAP.md](docs/IRIS-ROADMAP.md) — 45 versions sur 6 phases (v0.0.1 → v3.0+)

## Phase 1 — Skill factory ✅ TERMINÉE

11 skills générés dans `~/.claude/skills/` :
- HAUTE : `lead-gen-local-services-fr`, `doc-first-project-scaffolding`, `spec-driven-build-with-claude-md`, `programmatic-seo-local-combos`, `backoffice-custom-cms-crm-rbac`
- MOY : `nextjs-stack-baseline-2026`, `monorepo-turbo-with-claude-agents`, `booking-marketplace-calcom-or-custom`, `ai-pipeline-orchestrator`
- BASSE : `viral-content-pipeline-long-to-short`, `configurateur-3d-r3f-product`

Index complet : `~/.claude/skills/SKILLS-INDEX.md`. Skill `damage-control` aussi installé. Skills existants conservés : `gpt-image-2-prompter`, `state-of-the-art`, `animation-hero`.

Artefacts produits :
- `artefacts/PROJECTS-MAP.md` — cartographie 26 repos GitHub MaestroMed + 19 projets unitaires (avec sous-projets MIND iOS + FORGESTRUC Python)
- `artefacts/PATTERNS-REPORT.md` — 11 patterns validés (≥ 3 projets distincts) + 9 demote/rejetés/non-vérifiables-v1

## Phase 2 — Vision / Architecture / Roadmap ✅ DOCS LIVRÉS

Cf section "Documents vision" ci-dessus.

## Phase 3 — Code (en cours)

**v0.0.1 ✅ shipped** : bootstrap Tuist + SwiftUI app shell + DesignTokens Liquid Glass + entitlements minimaux. Build SUCCEEDED. Lancé sur Mac M5.

Versions suivantes en cours via swarm parallèle : v0.0.2 (NavigationSplitView 3 panels + Asset Catalog) · v0.0.3 (Event Bus AsyncStream) · v0.0.4 (SwiftData schema 6 models) · v0.0.5 (Conductor mock assemblage) · v0.1 (Conductor LLM réel Claude Opus).

## Setup local (machine neuve)

```bash
./scripts/setup.sh
```

Installe Xcode CLT, Homebrew, Tuist, génère le projet, build verify. Suppose Xcode app déjà installé via App Store.

## Dev quotidien

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

## CI

GitHub Actions [`.github/workflows/ci.yml`](.github/workflows/ci.yml) tourne sur macos-15 à chaque push/PR sur main. Build + tests en non-strict pour v0.0.x (strict à partir v0.1).

## Structure

- `artefacts/` — outputs intermédiaires (PROJECTS-MAP, PATTERNS-REPORT, etc.)
- `docs/` — décisions, specs, références
- `prompts/` — copies locales des prompts PASS1 / PASS2 et autres pipelines de la factory (à venir)

## Repo upstream

`git@github.com:MaestroMed/IRIS.git` — repo placeholder 2023 vide, à pousser après validation phase 1.

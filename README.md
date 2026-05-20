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

## Phase 3 — v0.0.1 code (en attente arbitrages Mehdi)

6 décisions requises (cf [docs/IRIS-ROADMAP.md](docs/IRIS-ROADMAP.md) section "Décisions Mehdi requises avant v0.0.1").

## Structure

- `artefacts/` — outputs intermédiaires (PROJECTS-MAP, PATTERNS-REPORT, etc.)
- `docs/` — décisions, specs, références
- `prompts/` — copies locales des prompts PASS1 / PASS2 et autres pipelines de la factory (à venir)

## Repo upstream

`git@github.com:MaestroMed/IRIS.git` — repo placeholder 2023 vide, à pousser après validation phase 1.

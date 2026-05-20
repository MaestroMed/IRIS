# PROJECTS-MAP.md

Cartographie multi-source des projets de Mehdi pour alimenter PASS1 (extract patterns).

**Date** : 2026-05-20
**Source 1** : GitHub `MaestroMed` (26 repos, métadonnées + README + structure scannés)
**Source 2** : GitHub `Numelite` (org annoncée — **inexistante** sur GitHub au 2026-05-20, tous les projets clients vivent en réalité sous `MaestroMed`)
**Source 3** : Locaux station fixe — à compléter par Mehdi
**Source 4** : Cocons (idées) — à compléter par Mehdi

---

## Section 1 — Repos GitHub MaestroMed (26)

### Actifs (push < 1 mois) — 16 repos

| Repo | Codename | Domaine | Stack principal | Artefacts notables | Pattern visible |
|---|---|---|---|---|---|
| `Numelite_v1` | **Numelite** | SaaS / outil interne (privé) | TypeScript | — | — (privé, à scanner après clone) |
| `IEFandCo_v0` | **IEF & Co** | Vitrine + backoffice B2B métallerie IDF | Next.js 15, Drizzle, Supabase, TipTap, Three.js, Mux, Iron Session | README, .env.example | Admin magic-link, RichText, SEO B2B mono-géo |
| `Sconnect` | **S'Connect** | Lead-gen électricité/serrurerie IDF | Next.js 15, Supabase, Resend/SendGrid, TipTap, DnD-Kit, Tanstack Table, Sentry | README complet, backoffice content | Cookie consent RGPD, GTM/Analytics, formulaire devis multi-step |
| `CableAvenue_v0` | — | E-commerce câbles informatiques (privé) | TypeScript | — | Modernisation probable de `cadepanne` (legacy) |
| `AZConstruction_v0` | **AZ Construction** | E-commerce métallerie sur mesure + configurateur 3D | Next.js, Prisma, R3F/Three.js, React PDF, Upstash, Recharts, XLSX, Resend, Sentry | README détaillé, dashboard KPI | Configurateur 3D, devis multi-étapes avec PDF, admin multi-tenant |
| `AZEpoxy_v0` | **AZ Epoxy** | Site produits/services epoxy + booking | Next.js, Sanity, Drizzle/Neon, Upstash, Cal.com, React PDF, Resend, Sentry, Lighthouse CI | README, GUIDE_GOOGLE_SERVICES.md | Sanity CMS + booking Cal.com, rate-limiting |
| `AZ_Interne_v0` | — | Outil interne agency (privé, monorepo) | Turbo monorepo, TypeScript | AGENTS.md, multi-package | Claude API agents internes, automation agency |
| `kckills` ⭐ | **KCKills** (+ KAMETO pivot) | Projet community/gaming sérieux avec analyzer pipeline + event map + pivot Kameto (streamer Twitch FR). Spec-driven. | TypeScript | **CLAUDE.md 46k**, ANALYZER_PIPELINE_SPEC.md, EVENT_MAP_SPEC.md, KAMETO_PIVOT_SPEC.md | spec-driven dev, analyzer pipeline, event mapping |
| `Alignd.co` | — | Plateforme/SaaS « Alignd » (hypothèse) | HTML | — | — |
| `atelierfrissons_v0` | **Atelier Frisson** ⭐ | E-commerce wellness premium (cliente Odelie, contrat 4k+3k×12) | Next.js, Supabase, TipTap, Mux HLS, Sentry, @react-email, Base UI, Drizzle | **CLAUDE.md 1397 lignes**, SEO_STRATEGY, FORGE_WORKFLOW, SUPABASE_SETUP, SESSION_HISTORY, .claude/rules/ | YMYL compliance (age-gate VerifyMy/AnonymAGE), paiement adulte CCBill, 2FA TOTP, Mux HLS, Klaviyo + Resend |
| `AZAssist_v0` ⭐ | **FORGESTRUC** (sous-dossier `forgestruc/`) | Conteneur : `forgestruc/` (Python web app Docker + Alembic + Lighthouse CI) + `Plan (1)/` 715M (scans plans communaux IDF : Bois-Colombes, Bourget, Chaville, Ecouen, Lafayette, Livry-Gargan, Montrouge, Noisy-le-Sec — assets pour AZ Construction probable) | **Python** (forgestruc) | forgestruc/README, COVERAGE_REPORT.md, DEMO_DAY.md, lighthouserc.json, alembic/ | App Python avec SQL migrations, perf monitoring, Docker-based, demo day artifacts |
| `01_transfertaeroport` | **01 TA** | Plateforme transferts aéroport | Next.js 15, Prisma, Sentry, Dnd-Kit, Radix, Heroicons, Axe-core, Lighthouse CI | README_REVAMP.md, ENV_PRODUCTION_TEMPLATE.md, GUIDE_MISE_EN_LIGNE.md | Marketplace booking, monitoring prod, a11y CI |
| `JustExist` | — | Obscur (portfolio / lifestyle ?) | TypeScript | — | — |
| `3D_Configurator_v0` | — | Composant configurateur 3D réutilisable | TypeScript, Sanity, Drizzle, Playwright | Lighthouse config, IMAGE_PROMPTS.md, e2e | Sanity + Drizzle, AI image prompts pour assets |
| `Formaroute` | — | Formation/e-learning (hypothèse) | Next.js, Radix UI, react-hook-form | — | Design system Radix, app form-heavy |
| `matter_hub` ⭐ | **MIND** + connectors + registry + hub | **Mono-repo conteneur** : `mind/` (app iOS Swift) + `hub/` + `connectors/` + `registry/`. MIND = cockpit Numelite (pivot 2026, plus second-brain). Audit pipeline 14 probes parallèles, GPT Image 2 boards, Claude Code SOTA brief generator. | Swift (mind) + Python (hub) | mind/README 20k, **mind/ULTRAPLAN.md 130k**, MIND_CRON_LOG.md | iOS SwiftUI + SwiftData + CloudKit, Tuist 4, audit-pipeline orchestré par Claude, generate-image GPT, export multi-format (PDF/MD/JSON/Notion), Spotlight indexing |

### Tièdes (push 1–6 mois) — 6 repos

| Repo | Codename | Domaine | Stack | Artefacts | Pattern |
|---|---|---|---|---|---|
| `ForgeLab` | **FORJA / Forge Lab** | SaaS AI viral clip creator (long-form → 9:16) | **Python** (backend pipeline) | README features | AI virality scoring, hook detection, karaoke subtitles, preset system |
| `ViralArchitectEngine_v1` | — | Framework agentic 3D viral (Blender + Claude agents) | Turbo monorepo, Blender pipeline | **AGENTS.md, CLAUDE.md**, Action_guide.md, Analyzer_pipeline_spec.md, Audit_20_points.md | Architecture agentic complexe (analyzer pipeline, audit 20-points), Blender automation |
| `01TA` | **01 TA** (alias court) | Frontend simplified du `01_transfertaeroport` | Next.js 15, Motion | README, guide Vercel | Landing + booking simplified fork |
| `AZConcept_v0` | **AZ Concept** | Prototype landing/concept brand AZ | Next.js 15, Framer Motion, Lucide | ARCHITECTURE.md, CONTENT_CHECKLIST.md, FEATURES.md, IMAGE_PROMPTS.md, QUESTIONNAIRE.md, **SEO_STRATEGY.md**, DESIGN_SYSTEM.md | Prototyping ultra-doc (questionnaire, checklist, SEO plan, IMAGE_PROMPTS) |
| `Matterhub_projects` | — | Hub multi-projets (interne ?) | — | — | — |
| `FastFabric_v0` | — | Plateforme « Fast Fabric » (textile/abstraction ?) | React Router 7, Radix | — | React Router v7 cutting-edge |

### Dormants (push > 6 mois) — 4 repos (candidats archive)

| Repo | État | Note |
|---|---|---|
| `Dolores_v1` | 2025-06-06 | Refactor de Dolores_01 (IA assistant probable). Possible patterns d'orchestration agent. |
| `IRIS` | 2023-10-30 | Placeholder vide (README 18 octets). Le concept renaît maintenant (cf [[project-iris]]). |
| `Dolores_01` | 2023-05-10 | Première version Dolores. Legacy. |
| `cadepanne` | 2023-03-26 | E-commerce câbles vanilla HTML. Probable précurseur de CableAvenue_v0. |

---

## Section 2 — Codenames PASS1 et mapping

| Codename PASS1 | Repo MaestroMed | Statut | Note |
|---|---|---|---|
| **Numelite** | `Numelite_v1` | ✅ Mappé | Privé, à scanner après clone |
| **AZ Construction** | `AZConstruction_v0` | ✅ Mappé | |
| **AZ Epoxy** | `AZEpoxy_v0` | ✅ Mappé | |
| **01 TA / 01 Transfert Aéroport** | `01_transfertaeroport` + `01TA` | ✅ Mappé (× 2) | Deux repos pour le même client (full vs simplified) |
| **IRIS** | `IRIS` | ✅ Mappé (legacy) | Vide, on construit la v2 ici (workspace `/Users/mehdinafaa/Iris/`) |
| **KCKills** | `kckills` | ✅ Probable | À scanner pour confirmer |
| **Atelier Frisson** (non cité PASS1) | `atelierfrissons_v0` | ⭐ Ajouté | Client Numelite premium (YMYL, contrat lourd, doc CLAUDE.md exhaustive) |
| **IEF & Co** (non cité PASS1) | `IEFandCo_v0` | ⭐ Ajouté | Vitrine B2B métallerie IDF |
| **S'Connect** (non cité PASS1) | `Sconnect` | ⭐ Ajouté | Lead-gen électricité IDF |
| **MonJoel** | — | ❌ Absent MaestroMed | Sur station fixe ou cocon |
| **VESPER** | — | ❌ Absent MaestroMed | Sur station fixe ou cocon |
| **GREYDAWN** | — | ❌ Absent MaestroMed | Sur station fixe ou cocon |
| **Skibidi Lanta** | — | ❌ Absent MaestroMed | Sur station fixe ou cocon |
| **Nacks** (Nacks Galerie) | — | ❌ Absent MaestroMed | Sur station fixe ou cocon |
| **Verdenomia** | — | ❌ Absent MaestroMed | Sur station fixe ou cocon |
| **FORGESTRUC** | `AZAssist_v0/forgestruc/` | ✅ Mappé (sous-dossier) | Python web app Docker, Alembic, Lighthouse CI |
| **MIND** | `matter_hub/mind/` | ✅ Mappé (sous-dossier) | App iOS Swift, cockpit Numelite (pivot 2026), audit pipeline 14 probes, Claude SOTA brief generator |
| **KAMETO** | `kckills/KAMETO_PIVOT_SPEC.md` | ✅ Mappé (sub-spec) | Pivot Twitch FR de kckills |
| **THEIA / STARLIGHT / fn Night Filter / Watchers / Epstein** | — | ❌ Absent | Projets investigatifs GREYDAWN, probablement même origine |
| **KAIROS / FORJA / Numelite Flow / Trouveur** | `ForgeLab` = FORJA possible | ⚠️ Partiel | À confirmer avec Mehdi |

---

## Section 3 — Locaux station fixe

*À compléter par Mehdi. Format suggéré : codename, type (web/contenu/research), domaine, lien possible vers repo MaestroMed équivalent ou rewrite prévu.*

```
- MonJoel : ?
- VESPER : ?
- GREYDAWN : ?
- Skibidi Lanta : ?
- Nacks Galerie : ?
- Verdenomia : ?
- (autres)
```

---

## Section 4 — Cocons (idées non encore codées)

*À compléter par Mehdi. Format : codename, 1-2 lignes de pitch, état (idée pure / brief existant / spec en cours).*

```
- (à lister)
```

---

## Section 5 — Patterns transversaux pré-identifiés

Sortis du recon, **à valider/affiner en PASS1** :

1. **Lead-gen local services FR** (vitrine + formulaire devis + RGPD + monitoring) — `Sconnect`, `IEFandCo_v0`, `01_transfertaeroport` (+ probablement `MonJoel`, `AZConstruction_v0` partiel)
2. **E-commerce premium avec compliance lourde** (Stripe-like + age-gate/legal + monitoring + a11y) — `atelierfrissons_v0`, `AZConstruction_v0`, `AZEpoxy_v0`
3. **Configurateur 3D / visualisation produit** — `AZConstruction_v0`, `3D_Configurator_v0`
4. **Monorepo + agentic system internalisé** (Claude API agents, AGENTS.md + CLAUDE.md riche) — `AZ_Interne_v0`, `ViralArchitectEngine_v1`, `atelierfrissons_v0` (très doc)
5. **Doc-first prototyping** (ARCHITECTURE.md, CONTENT_CHECKLIST.md, IMAGE_PROMPTS.md, SEO_STRATEGY.md, QUESTIONNAIRE.md systématiquement) — `AZConcept_v0`, `atelierfrissons_v0`, `3D_Configurator_v0`
6. **AI/Content viral pipeline** — `ForgeLab`, `ViralArchitectEngine_v1`
7. **CMS headless Sanity intégré** — `AZEpoxy_v0`, `3D_Configurator_v0`
8. **Booking Cal.com / marketplace pattern** — `AZEpoxy_v0`, `01_transfertaeroport`
9. **Backoffice admin custom + RBAC + 2FA** — `AZConstruction_v0`, `atelierfrissons_v0`, `IEFandCo_v0`
10. **SEO mono-géo (IDF dominante)** — `Sconnect`, `IEFandCo_v0`, `AZConstruction_v0` (cluster IDF)

Patterns **suspectés par PASS1 mais à confirmer après ajout des locaux** :
- `competitor-audit-to-differentiator` (suspecté pour MonJoel, AZ Construction, Verdenomia, Nacks)
- `google-ads-multi-vertical-architecture` (MonJoel 60 campagnes, AZ, 01 TA)
- `outreach-database-scoring` (Nacks 147 galeries, AZ China 500 prospects)
- `creative-bible-to-production-pipeline` (VESPER, Skibidi Lanta, KC tribute)
- `investigative-research-classification` (GREYDAWN/THEIA)
- `landing-page-3-variants-strategic` (MonJoel C, AZ Construction, Verdenomia, Nacks)
- `spec-driven-feature-build` (AZ Époxy, Trouveur, kckills) → partiel sur MaestroMed (AZ Epoxy + kckills présents)

---

## Section 6 — Préparation PASS1

**Dataset accessible immédiatement** : 22 repos actifs/tièdes (sur 26), dont 16 actifs.

**Recommandation** : lancer PASS1 sur les 16 actifs + ajouter `ViralArchitectEngine_v1` et `AZConcept_v0` (tièdes mais ultra documentés). Soit ~18 projets. PASS1 dit ≥ 3 projets par pattern — largement couvert.

**Clones à faire** (shallow `--depth 1` dans `/Users/mehdinafaa/Developer/`) :
- `Numelite_v1`, `AZConstruction_v0`, `AZEpoxy_v0`, `AZ_Interne_v0`, `atelierfrissons_v0`, `Sconnect`, `IEFandCo_v0`, `CableAvenue_v0`, `kckills`, `01_transfertaeroport`, `01TA`, `JustExist`, `3D_Configurator_v0`, `Formaroute`, `ForgeLab`, `ViralArchitectEngine_v1`, `AZConcept_v0`, `AZAssist_v0`

Skip clones (sauf demande explicite) :
- `IRIS` (vide), `Dolores_v1` / `Dolores_01` / `cadepanne` (dormants), `FastFabric_v0` (tiède sans doc), `Alignd.co` (HTML, à clarifier), `matter_hub` (vide), `Matterhub_projects` (vide)

**À arbitrer avec Mehdi avant clone** :
- Exclure `atelierfrissons_v0` (cliente, doc confidentielle) ?
- Exclure `Numelite_v1`, `AZ_Interne_v0`, `AZAssist_v0`, `CableAvenue_v0` (privés) ?
- Attendre les locaux station fixe avant de lancer ou faire un PASS1 v1 sur MaestroMed seul ?

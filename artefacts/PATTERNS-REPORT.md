# Rapport d'extraction de patterns — PASS1 v1

**Date** : 2026-05-20
**Scope** : 19 projets unitaires de Mehdi (GitHub `MaestroMed`, scannés en local dans `~/Developer/`)
**Méthode** : PASS1 (Mehdi) — règle dure : un pattern n'est validé que s'il apparaît dans **≥ 3 projets distincts**
**Note importante** : Plusieurs codenames cités dans PASS1 (MonJoel, VESPER, GREYDAWN, Skibidi Lanta, Verdenomia, THEIA/STARLIGHT/Watchers, Numelite Flow, Trouveur) sont **absents du dataset** — ils vivent sur la station fixe ou à l'état de cocon. Les patterns qui dépendent uniquement d'eux sont marqués "non vérifiable v1" et seront ré-évalués en v2 après transfert.

---

## Inventaire (26 repos scannés, 19 retenus pour analyse, 7 éliminés)

| Repo / Sub-projet | Codename | Retenu | Raison si éliminé |
|---|---|---|---|
| `atelierfrissons_v0` | Atelier Frisson [VIP] | ✅ | CLAUDE.md 58k = source de vérité ultime |
| `AZConstruction_v0` | AZ Construction [PRIV] | ✅ | E-comm + R3F + Prisma |
| `AZEpoxy_v0` | AZ Epoxy [PUB] | ✅ | Sanity + Cal.com + Drizzle |
| `AZConcept_v0` | AZ Concept [PUB] | ✅ | Doc-first prototyping pur |
| `AZ_Interne_v0` | AZ Interne [PRIV] | ❌ | Repo vide (size 0) |
| `Sconnect` | S'Connect [PUB] | ✅ | Lead-gen électricité IDF |
| `IEFandCo_v0` | IEF & Co [PUB] | ✅ | B2B métallerie + 173 routes + ULTRAPLAN |
| `CableAvenue_v0` | CableAvenue [PRIV] | ✅ | E-comm câbles + agents.md |
| `Numelite_v1` | Numelite [PRIV] | ✅ | SaaS interne agency |
| `01_transfertaeroport` | 01 TA [PUB] | ✅ | Marketplace booking + dispatch |
| `01TA` | 01 TA alias [PRIV] | ✅ | Landing simplified du même client |
| `ForgeLab` | FORJA / Forge Lab [PUB] | ✅ | Electron + FastAPI + AI clip viral |
| `ViralArchitectEngine_v1` | — [PUB] | ✅ | Agentic Blender + Audit_20_points |
| `JustExist` | **Nacks Galerie** [PUB] | ✅ | Monorepo Nacks/Naguy + GSAP + R3F + Auth.js + Stripe Payment Intents |
| `3D_Configurator_v0` | — [PUB] | ✅ | R3F + Sanity + Drizzle + MEGA_BRIEF 26k + SOUL.md |
| `Formaroute` | — [PUB] | ✅ | Auto-école Domont + Cal.com + 60+ pages SEO local |
| `kckills` | **LoLTok / KCKills** [PUB] | ✅ | TikTok kills LoL + KC + pivot Kameto + Python worker + Cloudflare R2 |
| `AZAssist_v0` / `forgestruc/` | **FORGESTRUC** [PRIV] | ✅ | Python web + Docker + alembic + Lighthouse |
| `matter_hub` / `mind/` | **MIND** [PUB] | ✅ | App iOS Swift cockpit Numelite + 14 probes audit |
| `matter_hub` / `hub`+`connectors`+`registry` | matter_hub core | ⚠️ | Pas creusé en profondeur — hub central interne |
| `Matterhub_projects` | — | ❌ | Vide |
| `FastFabric_v0` | — | ❌ | Tiède + très mince |
| `Alignd.co` | — | ❌ | HTML pur, peu de signal |
| `IRIS` (legacy 2023) | IRIS legacy | ❌ | Placeholder vide |
| `Dolores_v1`, `Dolores_01` | — | ❌ | Dormants > 6 mois |
| `cadepanne` | — | ❌ | Legacy 2023 HTML statique |

**Total retenus** : 19 projets.

---

## Mapping codenames PASS1 → projets (mise à jour finale)

| Codename PASS1 | Projet réel | Note |
|---|---|---|
| Numelite | Numelite_v1 | ✅ |
| AZ Construction | AZConstruction_v0 | ✅ |
| AZ Epoxy | AZEpoxy_v0 | ✅ |
| AZ Concept | AZConcept_v0 | ✅ |
| 01 TA | 01_transfertaeroport + 01TA | ✅ |
| Atelier Frisson | atelierfrissons_v0 | ✅ VIP — CLAUDE.md 58k |
| IEF & Co | IEFandCo_v0 | ✅ |
| S'Connect | Sconnect | ✅ |
| **Nacks Galerie** | **JustExist** | ✅ **NOUVEAU MAPPING** — README confirme Naguy "Nacks" Claude, Mehdi signe "Kairos — architecte & dev lead" |
| **KCKills / LoLTok / KAMETO** | kckills | ✅ Tous trois = le même projet (CLAUDE.md "LOLTOK", `KAMETO_PIVOT_SPEC.md`) |
| **FORGESTRUC** | AZAssist_v0/forgestruc/ | ✅ Sous-dossier |
| **MIND** | matter_hub/mind/ | ✅ Sous-dossier, ATTENTION : MIND a pivoté en 2026 — n'est plus un second-brain, c'est le cockpit studio Numelite |
| FORJA / Forge Lab | ForgeLab | ✅ |
| **KAIROS** | À ignorer | Nom que Claude a utilisé pour Mehdi dans une conversation passée (signature README Nacks). Pas un projet, pas le handle réel de Mehdi. |
| MonJoel | — | ❌ Absent dataset (station fixe ou cocon) |
| VESPER | — | ❌ Absent |
| GREYDAWN | — | ❌ Absent |
| Skibidi Lanta | — | ❌ Absent |
| Verdenomia | — | ❌ Absent |
| THEIA, STARLIGHT, fn Night Filter, Watchers, Epstein | — | ❌ Absents (probable cluster GREYDAWN) |
| Numelite Flow, Trouveur | — | ❌ Absents |

---

## Patterns détectés (classés par fréquence + impact)

### Pattern 1 : `lead-gen-local-services-fr`

- **Fréquence** : 5 projets — Sconnect [PUB], IEFandCo_v0 [PUB], 01_transfertaeroport [PUB], Formaroute [PUB], AZEpoxy_v0 [PUB] (partiel — services + booking)
- **Description** : site vitrine FR services pros locaux/régionaux (serrurerie/électricité/métallerie/auto-école/transferts). Formulaire devis multi-step + intervention urgente + contact + RGPD complet + SEO local pro.
- **Séquence consolidée** :
  1. Détection brand + secteur + zone géo (IDF dominante)
  2. Setup Next.js 15 App Router + TS + Tailwind + Vercel + Supabase ou Drizzle
  3. Build : Homepage avec hero + services + témoignages + FAQ + CTA, pages /services/[slug], page /contact, page /devis multi-step, page /intervention urgente (si secteur urgence)
  4. Pages légales : mentions, confidentialité, cookies, CGV/CGU
  5. Setup RGPD : cookie consent granulaire (CMP) + GA4 + GTM (Consent Mode v2)
  6. Setup email : Resend domain auth (DKIM/SPF/DMARC) + templates React Email
  7. Setup admin panel : auth magic link ou JWT, CMS des contenus, gestion leads
  8. Setup SEO local : Schema.org (LocalBusiness, Service, FAQPage, BreadcrumbList), sitemap dynamique, robots.txt
  9. Monitoring : Sentry + UptimeRobot externe + Speed Insights Vercel
  10. Déploiement Vercel + DNS + post-déploiement (sitemap → Search Console + Bing)
- **Variations observées** :
  - Sconnect : SEO sans pages géo dédiées, focus services
  - IEFandCo_v0 : exhaustif (173 routes, 40 combos `depannage × zone`, 44 glossaire) — niveau pro
  - 01_transfertaeroport : ajoute dispatch live + génération PDF facture + tarifs config
  - Formaroute : 60+ pages SEO local (1 ville pilier + 15+ villes périphériques)
  - AZEpoxy_v0 : ajoute booking Cal.com (overlap Pattern 8)
- **Étapes compressibles** :
  - **Template** : structure de dossiers `src/app/{services,zones,blog,realisations,api}/`, schema Drizzle `services + zones + leads + faq + testimonials + media + users + redirects`, components `Hero / Services / Testimonials / FAQ / CTA / Footer / StickyMobileCTA`
  - **Décision répétée** : Resend > Brevo (SendGrid en backup), Supabase ou Drizzle/Neon (jamais Firebase), Vercel (jamais Netlify), Tailwind v4 (Bootstrap = no)
  - **Output canonique** : `env.example.txt` avec sections [Site / DB / Email / Phone / Google Services / Sécurité / Maintenance / Sentry] dans cet ordre
  - **Sources externes systématiquement consultées** : DR/DA des concurrents, structure des SERP locaux pour [service + ville], Schema.org generators, Google Search Console
- **Triggers naturels** : « monte-moi un site vitrine pour [client] », « lead-gen local pour serrurier/électricien/métallier », « il me faut un site avec formulaire devis multi-step + RGPD », « SEO local IDF pour services pros »
- **Skill candidate** : **OUI**, priorité HAUTE
- **Risk anonymisation PASS2** : faible — le pattern est sectoriel et géo-générique. Skill doit dire "services pros local FR", pas "Sconnect / IEFandCo / Formaroute".

---

### Pattern 2 : `programmatic-seo-local-combos`

- **Fréquence** : 4 projets — IEFandCo_v0 [PUB] (40 combos `depannage/[service]/[zone]`), Formaroute [PUB] (20+ `auto-ecole-[ville]` + `permis-b-[ville]`), atelierfrissons_v0 [VIP] (500 pages `livraison/[ville]`), Sconnect [PUB] (services × zones partiel)
- **Description** : génération programmatique de pages SEO long-tail par combinaison [service / catégorie] × [zone / ville]. Chaque page unique sur contenu et metadata, mais sortie d'un template.
- **Séquence consolidée** :
  1. Lister les axes (ex: services × zones, ou catégories × villes)
  2. Définir le template MDX/TSX avec slots : intro géo, service détaillé, FAQ locale, témoignages locaux, CTA, breadcrumb, schema LocalBusiness scopé
  3. Source des données : JSON ou table DB (`zones`, `services`, `villes`)
  4. Génération : routes dynamiques `[service]/[zone]` ou `[ville]/[categorie]`
  5. Unicité contenu : sections rotatives ou variables géo injectées
  6. Sitemap dynamique avec priority cohérente
  7. Internal linking : du pilier vers les combos, des combos entre eux par proximité géo
- **Variations observées** :
  - IEFandCo : 5 services × 8 zones = 40 combos, niveau industriel
  - Formaroute : pilier `auto-ecole-domont` + variantes villes
  - atelierfrissons : 500 pages via FORJA (factory pSEO custom)
- **Étapes compressibles** :
  - **Template** : `app/[service]/[zone]/page.tsx` avec generateStaticParams, metadata generator, schema injector
  - **Décision répétée** : ne pas dupliquer le contenu mot-à-mot — varier 30 % minimum, intercaler données chiffrées locales (population, distance, intervention type)
  - **Sources externes** : INSEE pour pop/codes postaux, Google Trends pour volumes par requête, SERP analysis pour requêtes long-tail réelles
- **Triggers naturels** : « génère-moi 40 pages services × zones », « pSEO local », « pillar + clusters par ville »
- **Skill candidate** : **OUI**, priorité HAUTE
- **Risk anonymisation PASS2** : faible

---

### Pattern 3 : `doc-first-project-scaffolding`

- **Fréquence** : 6 projets — AZConcept_v0 [PUB], atelierfrissons_v0 [VIP], 3D_Configurator_v0 [PUB], Formaroute [PUB], IEFandCo_v0 [PUB], JustExist/Nacks [PUB]
- **Description** : avant ligne de code, génération d'une suite canonique de fichiers `.md` qui constituent la source de vérité du projet. Le code suit la doc, pas l'inverse.
- **Séquence consolidée** :
  1. `README.md` (vision + quick start)
  2. `ARCHITECTURE.md` (technique + structure dossiers)
  3. `FEATURES.md` (spécifications fonctionnelles)
  4. `DESIGN_SYSTEM.md` (couleurs, typo, composants)
  5. `CONTENT_CHECKLIST.md` (contenu à fournir par le client)
  6. `QUESTIONNAIRE.md` (questions au client avant build)
  7. `SEO_STRATEGY.md` (stratégie SEO + exemples pages)
  8. `IMAGE_PROMPTS.md` (prompts AI pour les visuels build) — overlap avec `gpt-image-2-prompter`
  9. `DEPLOYMENT.md` (procédure déploiement)
  10. Optionnel : `ULTRAPLAN.md` (roadmap phases), `COMPETITIVE_ANALYSIS.md`, `SECURITY.md`, `PERFORMANCE.md`, `COMPLIANCE.md`, `SESSION_HISTORY.md` (journal Claude Code)
- **Variations observées** :
  - AZConcept_v0 : suite complète, projet de prototypage pur
  - atelierfrissons : doc complète + `.claude/rules/` (content, seo, a11y, security, performance) + `.claude/agents/` + `.claude/skills/`
  - 3D_Configurator_v0 : `HEARTBEAT.md` (état vivant), `MEGA_BRIEF.md` 26k, `SOUL.md`
  - IEFandCo_v0 : `ULTRAPLAN.md` (vision monopole + roadmap 18 mois Phases A→E) + `BACKOFFICE-PLAN.md`
- **Étapes compressibles** :
  - **Template figé** : la liste ordonnée des fichiers `.md` avec sections pré-remplies vides
  - **Décision répétée** : Mehdi répond toujours OUI à "tu veux que je génère QUESTIONNAIRE.md avant de coder ?" → fige cette décision
  - **Output canonique** : la structure exacte de QUESTIONNAIRE.md (sections : Brand, Cibles, Concurrence, Contenu, SEO, Délais, Budget) et de CONTENT_CHECKLIST.md (Logos, Photos, Textes, Vidéos, Témoignages, Mentions légales)
- **Triggers naturels** : « on démarre un projet, génère-moi le scaffolding doc », « QUESTIONNAIRE.md pour [client] », « il me faut ARCHITECTURE+FEATURES+SEO_STRATEGY avant que j'écrive du code »
- **Skill candidate** : **OUI**, priorité HAUTE — c'est probablement le skill le plus utilisé en pratique
- **Risk anonymisation PASS2** : très faible — purement méthodologique

---

### Pattern 4 : `spec-driven-build-with-claude-md`

- **Fréquence** : 6 projets — atelierfrissons_v0 [VIP] (CLAUDE.md 58k), kckills/LoLTok [PUB] (CLAUDE.md 46k "~2000 lignes, chaque ligne compte"), 3D_Configurator_v0 [PUB] (MEGA_BRIEF.md 26k), matter_hub/mind [PUB] (ULTRAPLAN.md 130k), CableAvenue_v0 [PRIV] (agents.md), IEFandCo_v0 [PUB] (ULTRAPLAN.md)
- **Description** : CLAUDE.md (ou équivalent ULTRAPLAN/MEGA_BRIEF) sert de source de vérité absolue. Document de 30-130 k volumineux par nécessité, structuré en sections numérotées, contient toutes les contraintes éditoriales / techniques / business / juridiques + règles "à lire avant tout" pour Claude Code.
- **Séquence consolidée** :
  1. Section "RÈGLES POUR CLAUDE CODE — À LIRE AVANT TOUT" (numérotée 10 points : lire en entier, conventions, sécurité, validation)
  2. Vision & contexte (projet, positionnement, références visuelles, objectifs business chiffrés)
  3. Stack technique **figée** (tableau avec justifications des choix sensibles)
  4. Architecture du projet (arborescence complète avec commentaires)
  5. Règles éditoriales (vocabulaire, tonalité, anti-patterns rédactionnels)
  6. Plan d'exécution par sprints / phases validées
  7. Référence vers `.claude/rules/`, `.claude/agents/`, `.claude/skills/`, `docs/SEO_STRATEGY.md`, etc.
- **Variations observées** :
  - atelierfrissons : contraintes Arcom + RGPD + YMYL + ban vocabulaire explicite (très contraint)
  - LoLTok : architecture technique super précise (worker Python + Supabase + R2 + Gemini + Claude Haiku)
  - mind/ULTRAPLAN : 130k → probablement la plus exhaustive
- **Étapes compressibles** :
  - **Template** : squelette CLAUDE.md avec sections obligatoires (Règles / Vision / Stack figée / Architecture / Règles éditoriales / Plan / Références)
  - **Décision répétée** : pas de `any` TS, validation Zod systématique, jamais de secret en dur, shadcn via CLI jamais copie manuelle, Server Components par défaut, commit checklist (typecheck + lint + test)
  - **Sources externes** : SERP analysis pour positionnement, références concurrentes par secteur
- **Triggers naturels** : « écris-moi le CLAUDE.md pour ce projet », « source de vérité pour [client] », « brief exhaustif pour Claude Code »
- **Skill candidate** : **OUI**, priorité HAUTE — couplé avec Pattern 3 mais distinct (3 = scaffolding multi-fichiers, 4 = LE document maître)
- **Risk anonymisation PASS2** : faible — la structure est générique, le contenu projet-spécifique

---

### Pattern 5 : `nextjs-stack-baseline-2026`

- **Fréquence** : 12+ projets (tous les web) — Sconnect, IEFandCo_v0, AZConstruction_v0, AZEpoxy_v0, AZConcept_v0, atelierfrissons, 01_transfertaeroport, 01TA, JustExist/Nacks, Formaroute, CableAvenue_v0, Numelite_v1, 3D_Configurator_v0
- **Description** : stack baseline opinionated commune à tous les projets web. Pas une question, c'est l'ADN.
- **Stack** :
  ```
  Framework         Next.js 15 (App Router, RSC, Server Actions)
  Language          TypeScript strict
  Styling           Tailwind CSS 4 + shadcn/ui (via CLI)
  Animations        Framer Motion / Motion v12
  Forms             React Hook Form + Zod
  Email             Resend + React Email
  DB                Supabase (Postgres) OU Drizzle/Neon OU Prisma/Vercel Postgres
  Auth              Magic link (Supabase Auth ou custom JWT + bcrypt)
  Monitoring        Sentry + Vercel Speed Insights
  Tests             Vitest (unit) + Playwright (E2E)
  Hosting           Vercel
  CDN/Security      Cloudflare en amont (pour projets sensibles)
  Rate limiting     Upstash Redis
  CMS               Sanity OU TipTap intégré OU rien (fichiers source)
  ```
- **Variations** : choix DB selon projet (Supabase si auth + storage, Drizzle/Neon si serverless edge, Prisma si héritage). Sanity surtout pour blog/contenu riche.
- **Étapes compressibles** :
  - **Template figé** : `package.json` minimal, `tsconfig.json` strict, `next.config.js`, `tailwind.config.ts`, `.eslintrc`, `.prettierrc`, `playwright.config.ts`, `vitest.config.ts`, `.github/workflows/ci.yml`
  - **Décision répétée** : `pnpm` (jamais yarn ni npm, sauf clients qui imposent npm), Tailwind v4 (pas v3), Next 15 (App Router only)
  - **Sources externes systématiquement consultées** : versions stables Next.js / Tailwind / Sentry (web_search "Next.js latest stable 2026"), changelogs avant upgrade
- **Triggers naturels** : « setup le starter Next.js », « initialiser le repo », « la base technique habituelle »
- **Skill candidate** : **OUI**, priorité HAUTE — overlap potentiel avec `state-of-the-art` (skill existant) → **À FUSIONNER ou À COORDONNER** : `state-of-the-art` impose la vérification SOTA, ce skill-ci impose la stack opinionated baseline. Complémentaires.
- **Risk anonymisation PASS2** : nul

---

### Pattern 6 : `backoffice-custom-cms-crm-rbac`

- **Fréquence** : 5 projets — IEFandCo_v0 [PUB] (37 routes admin, CMS + CRM + GMAO, CommandPalette, MediaPicker, AIReplyButton), AZConstruction_v0 [PRIV] (dashboard KPI + médiathèque Cloudinary + gestion produits/familles/options/commandes/devis/clients B2C-B2B + CMS pages + Stripe config), Sconnect [PUB] (admin panel + auth JWT bootstrap), atelierfrissons [VIP] (BACKOFFICE_SPEC 18 modules + 2FA TOTP), 01_transfertaeroport [PUB] (dashboard temps réel + dispatch chauffeurs + tarifs config)
- **Description** : admin/* custom intégré, multi-modules : CMS pages, CRM leads, médiathèque, RBAC, auth admin (magic link + 2FA optionnel/obligatoire selon sensibilité), CommandPalette type Linear, MediaPicker.
- **Séquence consolidée** :
  1. Auth admin : magic link via email OU JWT + bcrypt, table `admin_users` avec bootstrap par env vars (premier admin)
  2. Layout admin : Sidebar + Topbar + CommandPalette (Cmd+K) + ThemeToggle
  3. Modules : Dashboard (KPI + graphs Recharts), Pages (CMS via TipTap), Leads (table filtrable + export), Médias (upload + Cloudinary fallback local), Settings (logo + SEO + emails)
  4. RBAC simple : roles `admin` / `editor` / `viewer`, middleware route guard
  5. 2FA TOTP optionnel (obligatoire pour projets sensibles type Atelier Frisson)
  6. Audit log : table `audit_events` qui log create/update/delete
- **Variations** :
  - IEF & Co : 37 routes incluant GMAO (gestion maintenance) — niveau industriel
  - atelierfrissons : 2FA TOTP obligatoire admin + spec 18 modules
  - 01_transfertaeroport : URL admin "secrète" (`/admin-ops-2024`) + dispatch map
- **Étapes compressibles** :
  - **Template** : structure `src/app/admin/(authed)/{dashboard,leads,pages,media,settings,users}/page.tsx` + middleware + components admin (Sidebar, Topbar, CommandPalette, MediaPicker, DataTable)
  - **Décision répétée** : auth magic link par défaut, 2FA TOTP si données sensibles, audit log toujours
- **Triggers naturels** : « il me faut un backoffice », « admin custom pour [client] », « gestion leads + CMS pages », « dashboard admin avec command palette »
- **Skill candidate** : **OUI**, priorité HAUTE
- **Risk anonymisation PASS2** : moyen — RBAC custom et structure routes à abstraire en générique

---

### Pattern 7 : `monorepo-turbo-with-claude-agents`

- **Fréquence** : 4 projets — ViralArchitectEngine_v1 [PUB] (Turbo + AGENTS.md + CLAUDE.md + apps/packages), JustExist/Nacks [PUB] (Turborepo pnpm workspaces, apps/web + apps/admin + packages/db|auth|ui|emails|config), AZ_Interne_v0 [PRIV] (Turbo monorepo + AGENTS.md), ForgeLab [PUB] (Electron + Python FastAPI monorepo apps/desktop + apps/forge-engine + packages/shared)
- **Description** : monorepo Turborepo + pnpm workspaces, structure `apps/{web,admin,worker} + packages/{db,auth,ui,emails,config}` + AGENTS.md + CLAUDE.md + souvent `.claude/agents/` et `.claude/skills/`.
- **Séquence consolidée** :
  1. `pnpm-workspace.yaml` + `turbo.json` + `tsconfig.base.json`
  2. `apps/web` (Next.js) + `apps/admin` (Next.js séparé) optionnel + `apps/worker` (Python ou Node) si pipeline
  3. `packages/db` (Drizzle schema partagé) + `packages/auth` (Auth.js v5 ou custom) + `packages/ui` (design system partagé) + `packages/emails` (React Email templates) + `packages/config` (tsconfig, eslint, tailwind, prettier partagés)
  4. AGENTS.md à la racine (handoff humain/agent) + CLAUDE.md (source de vérité)
  5. `.claude/agents/` (sub-agents projet-spécifiques) + `.claude/skills/` (skills locaux au projet) + `.claude/rules/` (règles éditoriales si applicable)
  6. Scripts Turbo : `dev`, `build`, `lint`, `typecheck`, `format`, `clean`
- **Variations** :
  - JustExist/Nacks : monorepo très propre (Auth.js v5 magic link + GSAP/Lenis/Motion + Three.js + Stripe Payment Intents embed + Auth.js + Plausible)
  - ForgeLab : mixe Electron + Python FastAPI dans `apps/forge-engine` (uvicorn) + apps/desktop (Electron)
  - ViralArchitectEngine_v1 : ajoute `blender/` (3D source) + `docs/` (Action_guide, Analyzer_pipeline_spec, Audit_20_points)
- **Étapes compressibles** :
  - **Template figé** : la liste `apps/` + `packages/` standard + `turbo.json` + `pnpm-workspace.yaml` + tsconfig.base + AGENTS.md squelette
  - **Décision répétée** : Turbo > Nx (toujours), pnpm > yarn berry, `apps/web` séparé de `apps/admin` quand admin > 20 routes
- **Triggers naturels** : « setup monorepo », « apps + packages », « turborepo pour [client] », « il me faut un agent system intégré »
- **Skill candidate** : **OUI**, priorité MOYENNE
- **Risk anonymisation PASS2** : faible

---

### Pattern 8 : `booking-marketplace-calcom-or-custom`

- **Fréquence** : 3 projets — AZEpoxy_v0 [PUB] (Cal.com API booking), Formaroute [PUB] (Cal.com embed pour évaluation), 01_transfertaeroport [PUB] (booking custom + dispatch + Google Places + WhatsApp notifications)
- **Description** : prise de RDV / réservation. Soit Cal.com embed (quick & dirty mais ça marche), soit custom (avec form multi-step + Google Places + assignation dispatch + notifications).
- **Séquence consolidée** :
  - **Cal.com path** : créer event-type sur Cal.com, embed via `next-cal-com` ou iframe, webhook pour sync DB locale, email confirmation via Resend
  - **Custom path** : form multi-step (date/heure + adresses Google Places + service + récap), pricing engine configurable (surcharges nuit/weekend/bagages, surge), persist `bookings` table Prisma/Drizzle, dashboard dispatch (carte + assignation chauffeur), email confirmation + WhatsApp optionnel
- **Variations** :
  - AZEpoxy : Cal.com pour devis booking (simple)
  - Formaroute : Cal.com embed pour "évaluation" (lead qualification gratuite)
  - 01_transfertaeroport : custom complet + dispatch live
- **Étapes compressibles** :
  - **Template** : composant `BookingForm.tsx` (multi-step + RHF + Zod + Google Places), table `bookings` schema, API route `/api/bookings` avec validation + email
  - **Décision répétée** : Cal.com si simple devis 30 min ; custom si pricing variable ou besoin dispatch
- **Triggers naturels** : « il me faut un booking », « réservation en ligne pour [client] », « Cal.com vs custom »
- **Skill candidate** : **OUI**, priorité MOYENNE
- **Risk anonymisation PASS2** : faible

---

### Pattern 9 : `ai-pipeline-orchestrator-claude-llm`

- **Fréquence** : 4 projets — matter_hub/mind [PUB] (14 probes parallèles orchestrées par Claude → AuditReport structuré + scoring + quick wins + strategic bets + hidden risks + pitch email), kckills/LoLTok [PUB] (worker Python : SENTINEL → HARVESTER → VOD_HUNTER → CLIPPER → ANALYZER Gemini → MODERATOR Claude Haiku → OG_GENERATOR → WATCHDOG, orchestrateur asyncio supervisé), ViralArchitectEngine_v1 [PUB] (Analyzer_pipeline_spec.md + Audit_20_points.md), ForgeLab [PUB] (AI segmentation + virality scoring + hook detection orchestré FastAPI)
- **Description** : pipeline d'orchestration multi-étapes où chaque étape est soit déterministe (ffmpeg, parsing) soit LLM (Claude/Gemini/Whisper). Chaque étape produit un artefact structuré (schéma Zod ou Pydantic), agrégés en synthèse finale.
- **Séquence consolidée** :
  1. Définir le DAG (étapes + dépendances)
  2. Chaque étape = fonction async typée (input → output schématisé)
  3. Routage modèles : Claude Opus pour synthèse complexe, Sonnet pour intermédiaire, Haiku pour modération bulk, Gemini Flash-Lite pour vidéo cheap
  4. Schéma de l'AuditReport / Synthesis : verdict + findings + ranked actions + scoring (impact × ease × urgency) — overlap avec damage-control
  5. Persistance résultats (DB ou fichiers JSON) pour replay / re-run avec nouveau prompt
  6. Monitoring : Discord webhooks pour alertes, WATCHDOG pattern
- **Variations** :
  - mind : audit web client (PageSpeed, headers, TLS, DNS, WHOIS, App Store, social, sitemap…) synthétisé en pitch
  - LoLTok : pipeline temporel (matchs LEC en live) avec rate-limiter global
  - ForgeLab : pipeline vidéo (segmentation + scoring)
- **Étapes compressibles** :
  - **Template** : module orchestrator avec asyncio.gather + retry exponentiel + rate-limiter centralisé + state machine par job
  - **Décision répétée** : Claude pour synthèse, Gemini Flash-Lite pour vidéo bulk (cost), Haiku pour modération
  - **Overlap MAJEUR avec `damage-control` (skill installé)** : damage-control est un cas particulier de ce pattern (audit projet en 8 axes). À fusionner ? À garder distinct ?
- **Triggers naturels** : « pipeline AI multi-étapes », « orchestrateur d'agents », « audit automatisé », « scanner X probes en parallèle »
- **Skill candidate** : **À ARBITRER** — soit fusion avec damage-control (étendre damage-control à des domaines non-audit), soit skill séparé `ai-pipeline-orchestrator` plus générique. Priorité MOYENNE.
- **Risk anonymisation PASS2** : moyen — structure générique mais exemples projet-spécifiques

---

### Pattern 10 : `viral-content-pipeline-long-to-short`

- **Fréquence** : 3 projets — ForgeLab [PUB] (long-form → 9:16 clips avec virality scoring + karaoke subtitles + presets Viral Pro/MrBeast/Clean/Minimal + cold open intro), kckills/LoLTok [PUB] (kills LoL → dual H 16:9 + V 9:16 clips automatisés + scoring Gemini + multikill badges), ViralArchitectEngine_v1 [PUB] (framework agentic 3D viral)
- **Description** : pipeline qui prend du contenu long (video/match/scène) et le compresse en clips courts viraux optimisés réseaux sociaux verticaux (TikTok/Reels/Shorts).
- **Séquence consolidée** :
  1. Ingestion source (YouTube URL, video local, match LEC)
  2. Transcription / détection événement (Whisper, frame diff, kill detection)
  3. Segmentation + scoring viralité (LLM rate chaque segment 0-100)
  4. Hook detection (cold open)
  5. Encodage dual : H 16:9 (préservé) + V 9:16 (crop intelligent)
  6. Sous-titres karaoké word-by-word (preset)
  7. Cold open intro + branding
  8. Export batch
- **Étapes compressibles** :
  - **Template** : worker Python + ffmpeg dual encode + Whisper/Gemini scorer + presets YAML
  - **Décision répétée** : ffmpeg + NVENC (GPU) pour speed, NVIDIA CUDA recommandé
- **Triggers naturels** : « pipeline clip viral », « long-form vers TikTok/Reels », « kill detection auto », « subtitles karaoke »
- **Skill candidate** : **OUI**, priorité MOYENNE
- **Risk anonymisation PASS2** : faible

---

### Pattern 11 : `configurateur-3d-react-three-fiber`

- **Fréquence** : 3 projets — AZConstruction_v0 [PRIV] (configurateur 3D 7 familles produits), 3D_Configurator_v0 [PUB] (composant configurateur 3D réutilisable, Sanity + Drizzle), JustExist/Nacks [PUB] (Three.js + R3F + drei dans stack worldbuilding)
- **Description** : configurateur produit interactif 3D avec Three.js / React Three Fiber. Visualisation produit + options (couleur, dimensions, finition) + ajout au panier ou devis.
- **Séquence consolidée** :
  1. Modélisation 3D (glb/gltf) ou paramétrique
  2. Setup R3F scène : Canvas + Suspense + Stage + drei controls
  3. State des options (Zustand)
  4. Bindings options → matériaux / géométries
  5. Génération preview (snapshot) pour récap + email
  6. Ajout panier / submit devis
- **Étapes compressibles** :
  - **Template** : `components/configurator/` avec Scene.tsx, Controls.tsx, OptionsPanel.tsx, useConfiguratorStore.ts (Zustand)
  - **Décision répétée** : R3F + drei (jamais Three vanilla), glb avec Draco compression, Suspense pour lazy load assets
  - **Sources externes** : Sketchfab pour modèles libres, ThreeJS Editor pour QA, Spline si non-coder
- **Triggers naturels** : « configurateur 3D », « visualisation produit interactif », « R3F pour [produit] »
- **Skill candidate** : **OUI**, priorité BASSE-MOYENNE
- **Risk anonymisation PASS2** : faible

---

## Patterns détectés mais en-dessous du seuil (rejetés ou demote)

| Pattern suspecté | Projets | Décision | Note |
|---|---|---|---|
| `cms-sanity-headless` | AZEpoxy + 3D_Configurator + Formaroute | **3/3 ✅ mais marginal** | Sanity est un sous-élément, pas un workflow complet. À mentionner dans Pattern 5 (stack baseline) plutôt que skill dédié. |
| `payment-ecommerce-stripe-or-alternative` | AZConstruction + atelierfrissons (CCBill) + JustExist (Stripe Payment Intents) + Sconnect (partiel) | **3-4 ✅** | À couvrir dans un skill `ecommerce-checkout-flow` si Mehdi multiplie les e-comm. Pour l'instant **demote** : usage trop ponctuel + chaque cas a son provider. |
| `competitor-audit-to-differentiator` (PASS1) | Suspecté MonJoel/AZ/Verdenomia/Nacks | **Non vérifiable v1** | JustExist/Nacks a un README + DECISIONS.md mais pas explicitement un competitor audit. À ré-évaluer en v2 quand MonJoel + Verdenomia transférés. |
| `google-ads-multi-vertical-architecture` (PASS1) | MonJoel 60 campagnes + AZ + 01TA | **Non vérifiable v1** | MonJoel absent. AZ et 01TA n'ont pas de structure Google Ads dans le repo (logique : c'est dans Google Ads UI, pas dans le code). À demander à Mehdi si workflow externe au repo. |
| `outreach-database-scoring` (PASS1) | Nacks 147 galeries + AZ China 500 + backlinks 13 cibles | **Non vérifiable v1** | Activité métier hors code. À demander à Mehdi s'il a des sheets/notes structurées à scanner. |
| `creative-bible-to-production-pipeline` (PASS1) | VESPER + Skibidi + KC tribute | **Partiellement présent** | kckills/LoLTok a un CLAUDE.md exhaustif et un pipeline complet, mais c'est plus du "spec-driven build" que "creative bible". VESPER + Skibidi absents. À ré-évaluer v2. |
| `investigative-research-classification` (PASS1) | GREYDAWN + THEIA + STARLIGHT + etc. | **Non vérifiable v1** | Tous absents. Cluster à scanner d'un coup quand Mehdi transfère. |
| `landing-page-3-variants-strategic` (PASS1) | MonJoel C + AZ Construction + Verdenomia + Nacks | **Non vérifiable v1** | MonJoel + Verdenomia absents. AZ et Nacks ont des landings mais pas explicitement "3 variantes strategic". À demander à Mehdi. |
| `seo-technical-audit-fr` (PASS1) | — | **Couvert par mind/audit pipeline + damage-control** | Pas un skill séparé, c'est une instance du Pattern 9 + damage-control. |

---

## Recommandation de skill set final

**11 skills proposés** (objectif PASS1 : 8-15, OK).

### Priorité HAUTE (à générer en premier, livrer 3, validation Mehdi, puis suite)

| # | Skill | Pattern source | Projets source | Note PASS2 |
|---|---|---|---|---|
| 1 | `lead-gen-local-services-fr` | Pattern 1 | Sconnect, IEFandCo, 01_transfertaeroport, Formaroute, AZEpoxy partiel | Anonymisation faible. Template `env.example`, structure `src/app/` standard, schema Drizzle, components Hero/Services/FAQ/CTA. |
| 2 | `doc-first-project-scaffolding` | Pattern 3 | AZConcept, atelierfrissons, 3D_Configurator, Formaroute, IEFandCo, Nacks | Anonymisation nulle. Templates figés : ARCHITECTURE.md, FEATURES.md, SEO_STRATEGY.md, QUESTIONNAIRE.md, CONTENT_CHECKLIST.md, IMAGE_PROMPTS.md, DESIGN_SYSTEM.md, DEPLOYMENT.md. |
| 3 | `spec-driven-build-with-claude-md` | Pattern 4 | atelierfrissons, kckills/LoLTok, 3D_Configurator (MEGA_BRIEF), mind/ULTRAPLAN, IEFandCo/ULTRAPLAN | Template CLAUDE.md squelette avec sections obligatoires + règles non-négo. |
| 4 | `programmatic-seo-local-combos` | Pattern 2 | IEFandCo (40 combos), Formaroute (20 villes), atelierfrissons (500 livraison/ville), Sconnect partiel | Template `[service]/[zone]/page.tsx` + generateStaticParams + schema injector. |
| 5 | `backoffice-custom-cms-crm-rbac` | Pattern 6 | IEFandCo (37 routes), AZConstruction, Sconnect, atelierfrissons (18 modules), 01_transfertaeroport | Anonymiser RBAC custom. Template structure `admin/(authed)/...` + CommandPalette + MediaPicker + DataTable + 2FA optionnel. |

### Priorité MOYENNE

| # | Skill | Pattern source | Note |
|---|---|---|---|
| 6 | `nextjs-stack-baseline-2026` | Pattern 5 | Coordonner avec `state-of-the-art` (existant). Ce skill = stack opinionated figée, `state-of-the-art` = force la vérif des versions SOTA. Complémentaires. |
| 7 | `monorepo-turbo-with-claude-agents` | Pattern 7 | Template Turbo + apps/packages + AGENTS.md + .claude/agents+skills+rules. |
| 8 | `booking-marketplace-calcom-or-custom` | Pattern 8 | Décision Cal.com vs custom selon complexité pricing. |
| 9 | `ai-pipeline-orchestrator` | Pattern 9 | **À ARBITRER** : fusionner avec damage-control ou skill séparé ? Voir Question 3 ci-dessous. |

### Priorité BASSE

| # | Skill | Pattern source | Note |
|---|---|---|---|
| 10 | `viral-content-pipeline-long-to-short` | Pattern 10 | Niche mais riche (ForgeLab + LoLTok + ViralArchitectEngine). |
| 11 | `configurateur-3d-r3f-product` | Pattern 11 | Niche (AZConstruction + 3D_Configurator). |

### À FUSIONNER avec skills existants (pas créer)

- **Pattern 13 (image generation pipeline)** : `gpt-image-2-prompter` existe déjà. Étendre avec un module "IMAGE_PROMPTS.md generator for project builds" — ajouter aux assets de ce skill.
- **Pattern 5 (stack baseline)** : coordonner avec `state-of-the-art` existant.
- **Pattern 9 (ai-pipeline-orchestrator)** : potentiellement étendre `damage-control` au lieu de créer un skill séparé.

---

## Questions de clarification pour Mehdi

1. **Projets absents** : confirme la localisation de MonJoel, VESPER, GREYDAWN, Skibidi Lanta, Verdenomia, THEIA/STARLIGHT/Watchers, Numelite Flow, Trouveur — station fixe ? cocon ? Quand peux-tu transférer ? Sans eux, les patterns `competitor-audit-to-differentiator`, `creative-bible-to-production-pipeline`, `investigative-research-classification`, `landing-page-3-variants-strategic`, `google-ads-multi-vertical-architecture`, `outreach-database-scoring` restent non vérifiables.

2. **Nacks = JustExist** : confirme. Et confirme que tu signes "Kairos" comme handle perso (≠ projet KAIROS).

3. **Pattern 9 (ai-pipeline-orchestrator) vs damage-control** : trois options :
   - (a) Étendre `damage-control` pour devenir un meta-skill d'audit/pipeline générique (kckills kill detection, mind client audit, etc. deviennent des "domaines" de damage-control)
   - (b) Skill séparé `ai-pipeline-orchestrator` pour les cas non-audit, damage-control reste l'audit projet 8 axes
   - (c) Skip ce pattern (overlap trop fort)

4. **Pattern 5 (nextjs-stack-baseline-2026)** : tu veux un skill explicite qui impose la stack par défaut, OU tu préfères que `state-of-the-art` (existant) couvre ça en demandant vérification SOTA à chaque init ? Mon conseil : skill séparé qui fige la stack, `state-of-the-art` reste générique.

5. **Sélection des 3 premiers skills pour PASS2** : ma suggestion = **1 (`lead-gen-local-services-fr`) + 2 (`doc-first-project-scaffolding`) + 3 (`spec-driven-build-with-claude-md`)** — ce sont ceux que tu vas réutiliser dès le prochain projet (Mai-Juin 2026 si nouveau client lead-gen, ou nouveau spec exhaustif pour un projet ambitieux). Tu valides ou tu en veux d'autres dans le batch 1 ?

6. **Pattern `outreach-database-scoring` (Nacks 147 galeries)** : as-tu une Notion / sheet / Airtable structurée de prospects que je peux scanner pour valider ce pattern ? Sinon je le rejette définitivement (workflow métier hors code).

7. **MIND a pivoté** : MIND n'est plus second-brain mais cockpit Numelite. Comment positionnes-tu IRIS par rapport à ça ? (a) reprend l'idée originale d'exocortex que MIND a abandonnée, (b) compagnon dev/skills/code du cockpit MIND, (c) autre. Pas urgent pour PASS2 mais important pour la phase suivante.

---

## Self-audit final

Pour chaque pattern validé : ≥ 3 projets distincts ? Vérif :

| Pattern | Projets count | Liste 3 minimum | OK ? |
|---|---|---|---|
| 1 — lead-gen-local-services-fr | 5 | Sconnect, IEFandCo, 01_transfertaeroport | ✅ |
| 2 — programmatic-seo-local-combos | 4 | IEFandCo (40 combos), Formaroute (20 villes), atelierfrissons (500 pages) | ✅ |
| 3 — doc-first-project-scaffolding | 6 | AZConcept, atelierfrissons, 3D_Configurator | ✅ |
| 4 — spec-driven-build-with-claude-md | 6 | atelierfrissons (CLAUDE.md 58k), kckills (CLAUDE.md 46k), mind (ULTRAPLAN 130k) | ✅ |
| 5 — nextjs-stack-baseline-2026 | 12+ | Tous les web | ✅ |
| 6 — backoffice-custom-cms-crm-rbac | 5 | IEFandCo (37 routes admin), AZConstruction, atelierfrissons (18 modules) | ✅ |
| 7 — monorepo-turbo-with-claude-agents | 4 | ViralArchitectEngine, JustExist/Nacks, AZ_Interne_v0, ForgeLab | ✅ |
| 8 — booking-marketplace-calcom-or-custom | 3 | AZEpoxy, Formaroute, 01_transfertaeroport | ✅ pile-poil |
| 9 — ai-pipeline-orchestrator-claude-llm | 4 | mind (14 probes), kckills/LoLTok (worker), ForgeLab (FastAPI), ViralArchitectEngine | ✅ |
| 10 — viral-content-pipeline-long-to-short | 3 | ForgeLab, kckills/LoLTok, ViralArchitectEngine | ✅ pile-poil |
| 11 — configurateur-3d-r3f-product | 3 | AZConstruction, 3D_Configurator, JustExist/Nacks (stack) | ✅ pile-poil |

**Tous les 11 patterns tiennent le seuil ≥ 3 projets distincts.** Aucun à demote.

**Aucun pattern inventé sans données.** Toutes les sources viennent des READMEs / CLAUDE.md / AGENTS.md / structure de repos clonés en local.

**Recommandation finale** : générer en PASS2 les 5 skills HAUTE en priorité absolue (livrer 3 d'abord pour validation), puis les 4 MOYENNES, puis arbitrer BASSES et FUSIONS.

---

<!-- Sources brutes : PROJECTS-MAP.md + scan ~/Developer/ + READMEs / CLAUDE.md / AGENTS.md des 19 projets retenus -->

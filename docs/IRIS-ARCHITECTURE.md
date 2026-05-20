# IRIS — Architecture technique

**Date** : 2026-05-20 · **Statut** : option A retenue (override Mehdi vs ma reco Tauri)
**Sister doc** : [IRIS-VISION.md](IRIS-VISION.md), [IRIS-AGENTS-CATALOG.md](IRIS-AGENTS-CATALOG.md), [IRIS-ROADMAP.md](IRIS-ROADMAP.md)

> **DÉCISION 2026-05-20** : Mehdi retient **Option A — Mac native SwiftUI** (override de la reco Tauri). Justifications : cohérence MIND iOS (Swift packages partageables), perf Apple Silicon native, intégration Apple ecosystem maximale (Spotlight + Continuity + Live Activities), design Liquid Glass natif. Trade-offs assumés : pas multi-platform Win/Linux avant phase 2-3 (web compagnon en v2.7).

---

## 1. Cadrage — contraintes Mehdi

| Contrainte | Valeur |
|---|---|
| Skill set principal | Web (Next.js 15, TypeScript) — 12+ projets actifs. Python (FORGESTRUC, ForgeLab, mind audit pipeline). |
| Skill set secondaire | Swift / SwiftUI — surface limitée (MIND iOS), pas de Mac dev expérience documentée |
| Machine | MacBook Pro M5 (mai 2026) — Apple Silicon, perf neural engine |
| OS cible primaire | macOS 26+ (cohérence MIND iOS 26+) |
| OS cible secondaire | Web (compagnon mobile depuis MIND iOS si IRIS Mac-only) |
| Distribution attendue v1 | Self-use Mehdi. Pas d'App Store, pas de cloud public. |
| Distribution attendue v2-v3 | 3-5 early adopters opérateurs solo francophones, puis offre commerciale Numelite |
| Latence acceptable | < 100ms pour interactions UI, < 2s pour réponse agent simple, async OK pour pipelines |
| Stockage | Local-first ; cloud optionnel pour sync MIND |
| MCPs déjà branchés (Claude Code) | Gmail, Calendar, Chrome (in-Chrome), computer-use, scheduled-tasks, Adobe Creative Cloud, Cloudinary, mcp-registry, et 10+ autres |

---

## 2. Trois options techniques

### Option A — Mac native SwiftUI

**Stack** : Swift 6 + SwiftUI + SwiftData + CloudKit + Tuist 4 + Swift packages.

**Architecture** :
```
IRIS.app (Mac, SwiftUI)
├── Cores (Swift packages partagés avec MIND iOS)
│   ├── IRISCore (agents, scheduler, message bus)
│   ├── IRISStore (SwiftData models, CloudKit sync)
│   └── IRISIntegrations (MCP client wrappers)
├── Agents (Swift actors, isolated state)
├── MCPProcessSpawner (Process pour spawn Node/Python MCP servers)
└── UI (SwiftUI views, Liquid Glass design system)
```

**Pros** :
- Performance native Apple Silicon (Neural Engine pour ML local, Metal pour rendu)
- Intégration OS profonde : Spotlight, Notifications, Live Activities, Dynamic Island sur iPhone si extension, AppleScript / Accessibility API, Continuity avec MIND iOS
- Sandboxing macOS robuste, security baked-in
- **Cohérence MIND** : Swift packages partagés (audit pipeline réutilisé, design system commun)
- CloudKit gratuit, sync MIND ↔ IRIS via zone privée
- DMG distribution + App Store si voulu phase 3

**Cons** :
- Skill set Mehdi : Swift surface limitée. Courbe d'apprentissage Mac dev (différent d'iOS)
- MCP servers existants en Node/Python → process spawn (acceptable mais bricolé)
- Non-portable : Mac only, pas Windows/Linux pour clients early adopters phase 2
- Distribution App Store : process review, restrictions sandbox plus serrées
- Itération plus lente que Web (build Xcode, signing, hot reload moins fluide qu'en React)

### Option B — Web Next.js 15 PWA

**Stack** : Next.js 15 (App Router, RSC) + TypeScript + Tailwind v4 + shadcn + IndexedDB (Dexie) + Service Worker + Postgres local (via Tauri-like pont OU container Docker user-installed).

**Architecture** :
```
Browser tab IRIS (https://localhost:3000 OU PWA installée)
├── Next.js App Router (RSC + Client Components)
├── Agent Runtime (TypeScript, Web Workers pour isolation)
├── IndexedDB / Dexie (mémoire locale)
├── Service Worker (offline + cache)
└── MCP Bridge (Node.js sidecar process pour MCP servers)
```

**Pros** :
- Skill set Mehdi : maîtrise totale (12+ projets Next.js déjà livrés)
- Itération ultra-rapide (HMR Next.js, déploiement Vercel pour preview à n'importe qui en 30s)
- Multi-platform automatic : Mac, Windows, Linux, iPad, Android — partout où il y a un browser moderne
- Distribution : URL share, PWA install, zéro friction
- Coordination naturelle avec les 11 skills factory (tous web)
- Compagnon mobile gratuit (PWA sur iPhone, sync via cloud léger)

**Cons** :
- Sandbox browser limite l'accès OS : pas d'AppleScript, pas d'Accessibility API, pas de Spotlight, pas de Live Activities
- Local-first plus dur : IndexedDB OK mais Postgres local = container Docker (friction install pour Mehdi)
- MCP servers en sidecar = process spawn par un Node externe (Mehdi doit lancer un service en parallèle)
- Pas natif macOS — perd la cohérence look-and-feel avec MIND iOS
- Permissions browser pour webcam (eyes phase 4) plus contraignantes que macOS native

### Option C — Hybride Tauri 2 (Rust core + Web frontend)

**Stack** : Tauri 2 (Rust backend + WebView2/WKWebView frontend) + React + TypeScript + Tailwind v4 + shadcn + SQLite local (rusqlite) OU embedded Postgres + MCP servers spawned par Rust process manager.

**Architecture** :
```
IRIS.app (Tauri bundle — Mac/Windows/Linux)
├── Rust Backend (Tauri commands, agents runtime, MCP spawner)
│   ├── AgentRuntime (Tokio async, message passing)
│   ├── MCPManager (spawn + supervise MCP server processes)
│   ├── Store (SQLite + sqlx OR libSQL)
│   └── OSBridge (Tauri plugins : notifications, fs, shell, http, store, deep-linking)
├── Frontend (React + Tailwind + shadcn dans WebView)
│   ├── Panels denses (style Bloomberg)
│   ├── Agent state subscriber (event bus Tauri)
│   └── Liquid Glass design system (CSS variables, cohérent MIND)
└── Bundle (.dmg Mac, .msi Windows, .deb/.appimage Linux)
```

**Pros** :
- **Best of both worlds** : UI Web (skill set Mehdi) + accès OS via Rust (Tauri plugins)
- Multi-platform : Mac + Windows + Linux d'un coup (réseau d'early adopters phase 2 élargi)
- Bundle léger (~10-30 MB vs Electron 100-200 MB)
- Sécurité Rust : MCP process manager robuste, sandboxing capabilities-based via Tauri allowlist
- DA Liquid Glass implémentable en CSS (cohérence MIND visuelle, pas code)
- Itération rapide (Vite HMR pour le frontend, Rust hot-reload via cargo-watch)
- Distribution : DMG / MSI / AppImage signed, ou App Store si voulu phase 3
- Updater intégré (Tauri auto-update)

**Cons** :
- Mehdi connaît peu Rust — courbe d'apprentissage. Mitigation : 90% du code Rust est "Tauri commands" pattern (boilerplate prévisible)
- Pas d'AppleScript / Accessibility native — partiel via Tauri shell plugin + scripts AppleScript externes
- Pas de partage code direct avec MIND iOS (mais sync via API REST/GraphQL OU CloudKit côté MIND → SQLite côté IRIS via worker)
- WebView2 (Windows) parfois flaky sur très anciennes versions Win

### Option D (variante) — Apple Silicon Swift + WebView pour panels denses

Mix Mac native SwiftUI (chrome de l'app, intégration OS) + WebView (panels denses en React pour itération rapide). Plus complexe à monter, partage maximum avec MIND, mais coût initial élevé.

→ Phase 2 si IRIS prend et qu'on veut maximiser l'intégration Apple ecosystem.

---

## 3. Recommandation argumentée

**→ Option C (Hybride Tauri 2)** pour v0.0.1 → v1.0.

**Justifications** :

1. **Skill set Mehdi respecté** : 90% du code (UI panels, agents JS/TS, intégrations MCP côté frontend) en TypeScript + React. Le Rust se limite à : spawn MCP servers, lecture/écriture SQLite, Tauri commands fs/shell/notifications. Pattern boilerplate prévisible.
2. **Multi-platform dès v1** : Mac + Windows + Linux d'un coup. Phase 2 early adopters non bloquée par OS.
3. **Anti-over-architecting** : Tauri 2 ship un installer .dmg en 1 commande, pas besoin de monter un backend serveur ni un framework custom. C'est le path le moins risqué pour livrer v0.1 en 2-3 semaines.
4. **MCP compat naturel** : Tauri Rust spawn n'importe quel binaire externe (Node, Python, Go) → tous les MCP servers existants marchent sans wrapper custom.
5. **Cohérence MIND visuelle** : Liquid Glass implémentable en CSS variables, design tokens partagés via fichier JSON exporté depuis MIND iOS.
6. **Bundle léger** : 20-30 MB vs Electron 150 MB, et perf native pour l'agent runtime (Rust + Tokio).
7. **Migration future** : si Mehdi veut basculer Apple-natif en phase 2 (cohérence MIND maximale), on migre la couche backend Rust → Swift en gardant le frontend React. Migration progressive.

**Anti-arguments pesés** :
- Courbe Rust : réelle mais limitée. ~500 lignes Rust max pour v0.1. Claude Code peut écrire 80% (Tauri commands sont pattern-matching évident).
- Pas natif macOS pur : trade-off accepté pour le multi-platform.
- WebView vs natif : panels denses en HTML/CSS/JS sont plus rapides à itérer qu'en SwiftUI, et Mehdi peut réutiliser shadcn / Motion / R3F qu'il connaît.

---

## 4. Architecture multi-agents (commune aux 3 options)

```
                    ┌──────────────────────────┐
                    │       UI (Panels)        │
                    │   Glanceable dense view  │
                    └────────────┬─────────────┘
                                 │ Subscribe events
                    ┌────────────▼─────────────┐
                    │      Event Bus           │
                    │  (pub/sub typed events)  │
                    └────────────┬─────────────┘
                                 │
        ┌────────────────────────┼─────────────────────────┐
        │                        │                         │
   ┌────▼─────┐           ┌──────▼──────┐          ┌──────▼──────┐
   │ Conductor│           │   Memory    │          │ MCP Manager │
   │ (router) │◄─────────►│  (Scribe)   │          │ (Tauri Rust)│
   └────┬─────┘           └─────────────┘          └──────┬──────┘
        │ dispatch                                         │ spawn
        ▼                                                  ▼
   ┌─────────────────────────────────┐          ┌─────────────────┐
   │   Workers (Agents spécialisés)   │          │  MCP Servers    │
   │  Sentinel · Scribe · Quill ·     │◄────────►│  (Node/Python   │
   │  Auditor · Cartographer ·        │          │   external      │
   │  Builder · Envoy · Witness ·     │          │   processes)    │
   │  Advisor                         │          └─────────────────┘
   └─────────────────────────────────┘
                  │
                  ▼
   ┌─────────────────────────────────┐
   │      Local Store (SQLite)        │
   │  · Memories                      │
   │  · Action logs (append-only)     │
   │  · Agent state snapshots         │
   │  · Skill registry                │
   │  · Project map cache             │
   └─────────────────────────────────┘
```

### Concepts core

- **Event Bus typé** : Tous les agents publient/écoutent via un bus pub/sub. Schéma événements en TypeScript + Zod (validation runtime).
- **Conductor** : seul agent avec accès écriture au routing. Reçoit événements UI (user input), dispatch aux workers selon spec.
- **Workers isolés** : chaque agent = state local + capabilities déclarées + tools accessibles (skills, MCP, store read/write). Isolation par capabilities, pas par process (mais possible en v2).
- **Memory append-only** : Scribe écrit tout dans un log immuable (DuckDB ou SQLite WAL). Retrieval via embeddings (sqlite-vec) + index sémantique.
- **MCP Manager** : Rust supervise les processus MCP servers (Gmail, Calendar, etc.). Restart auto si crash. Resource limits par process.
- **UI Subscriber** : la UI ne pull jamais, elle s'abonne. Latence interaction < 100ms.

---

## 5. Intégrations MCP (réutiliser l'existant)

IRIS ne réinvente pas l'intégration aux sources. Il utilise les MCP servers déjà branchés dans Claude Code :

| Source | MCP server existant | Capability IRIS |
|---|---|---|
| Gmail | `mcp__c1d04fe4-3a8d-4902-a18c-888ecaff3fa1__*` | Sentinel observe nouveaux threads, Quill drafte, Envoy envoie |
| Calendar | `mcp__b7b24690-8b31-49f5-9767-918b21ee3adb__*` | Sentinel observe events, Advisor propose réorga |
| Chrome | `mcp__Claude_in_Chrome__*` | Witness comprend page active, Builder fill forms |
| computer-use | `mcp__computer-use__*` | Builder agit sur n'importe quelle app desktop (review HIG) |
| scheduled-tasks | `mcp__scheduled-tasks__*` | Conductor schedule recurring tasks |
| Adobe Creative | `mcp__d6449b8c-...__*` | Builder génère visuels via Adobe MCP |
| GitHub (gh CLI via shell) | Bash | Sentinel observe commits/PRs, Cartographer met à jour map |

**Principe** : IRIS appelle les MCP servers via Rust Process spawn (Tauri) ou directement via JSON-RPC stdio si le MCP server est compatible. Permissions explicites par agent (Envoy a droit `send_email`, Quill a droit `create_draft` mais pas `send`).

---

## 6. Sécurité, sandbox, permissions

### 6.1 Sandboxing par agent (capabilities-based)

Chaque agent déclare ses capabilities dans son spec :

```yaml
agent: quill
capabilities:
  read:
    - gmail.drafts
    - store.memories
    - store.projects
  write:
    - store.drafts
    - gmail.drafts.create
  forbidden:
    - gmail.send       # Réservé à Envoy
    - shell.execute    # Réservé à Builder
    - fs.write_anywhere
```

Le Conductor vérifie les caps avant de dispatcher. Tentative d'action hors caps = rejet + log + notification user.

### 6.2 User approval pour actions sensitive

- **Auto-approve** : lecture sources (Gmail, Calendar), suggestions UI, drafts (Quill), updates store internes
- **Confirmation requise** : envoi email (Envoy), création PR GitHub (Builder), modification fichier outside `/Users/mehdinafaa/Iris/`, dépense API > 0.10€
- **Hard-blocked sans accord explicite** : modification de fichiers système, transferts d'argent, posts sur réseaux sociaux publics, suppression de données

### 6.3 Reversibilité

Tout action exécutée est loggée append-only dans `store.action_logs` :
```
{ id, timestamp, agent, action, params, result, reversible: true|false, undo_payload }
```

Mehdi peut faire "undo last action" depuis n'importe où dans l'UI. Les actions non-réversibles (email envoyé) sont marquées et nécessitent une confirmation supplémentaire au moment.

### 6.4 Local-first + chiffrement

- Stockage SQLite local chiffré (SQLCipher ou rusqlite-cipher)
- Clé dans macOS Keychain (Tauri keychain plugin)
- Cloud sync optionnel chiffré bout en bout (E2EE via age ou WireGuard tunnel) — phase 2

---

## 7. Stack technique récap (Option C Tauri retenue)

```
Backend                  Rust 1.85+ stable
  Framework              Tauri 2.x
  Async                  Tokio
  DB                     SQLite via sqlx (WAL mode, sqlite-vec pour embeddings)
  Embeddings             ONNX Runtime local (modèle bge-small ou nomic-embed)
  HTTP                   reqwest
  Process supervisor     Tauri builtin + custom logic
  Keychain               keyring crate (cross-platform)

Frontend                 React 19 + TypeScript 5
  Build                  Vite 6
  Styling                Tailwind CSS 4
  Components             shadcn/ui via CLI
  State                  Zustand (state global) + TanStack Query (cache server-side)
  Animations             Motion v12 (Liquid Glass transitions)
  Charts                 Recharts (dashboards agents)
  Forms                  React Hook Form + Zod
  Schemas validation     Zod (compartis frontend ↔ backend via specta-rs)

Agents                   TypeScript (frontend Workers) + Rust pour bridges OS
  Runtime                Web Workers (isolation par agent)
  LLM SDK                @anthropic-ai/sdk (Claude Opus/Sonnet/Haiku 4.x), @google/genai (Gemini Flash-Lite)
  Schema validation      Zod sur tous les events
  Prompts                Templates versionnés dans repo + Anthropic prompt caching

MCP Integration          MCP SDK Rust (mcp-rust client) + spawn Node/Python MCP servers via Tauri shell

Tooling
  Tests                  Vitest (TS) + cargo test (Rust) + Playwright (E2E)
  Lint/format            Biome + rustfmt + clippy
  CI                     GitHub Actions (build Mac/Win/Linux + sign + release)
  Updater                Tauri updater (signed releases sur GitHub Releases)
  Bundle                 .dmg (Mac signed + notarized), .msi (Win), .AppImage (Linux)
```

---

## 8. Migration paths

**Tauri → Mac native Swift (option D)** — phase 2 si cohérence MIND iOS devient critique :
1. Garder frontend React intact (compatible WebView macOS)
2. Réécrire le backend Rust en Swift packages (réutilisables avec MIND iOS)
3. Swap Tauri shell → WKWebView natif
4. Distribution App Store + iCloud sync natif

**Tauri → Web pur (option B)** — peu probable, mais si pivot vers SaaS pur :
1. Sortir le backend Rust en Node.js/Edge serverless
2. Frontend React intact → déployer Vercel
3. Sync MCP via API routes au lieu de spawn local
4. Permettre IRIS dans le browser (compromise local-first → cloud-first hybride)

---

## 9. Décisions ouvertes (à arbitrer avec Mehdi avant code v0.0.1)

1. **Option C confirmée** ? Ou Mehdi préfère Option A (Mac native) ou Option B (Web pur) ?
2. **Embeddings local** : ONNX Runtime + bge-small (CPU OK) ou stretch GPU (Metal) avec nomic-embed plus précis mais lourd ?
3. **DB locale** : SQLite (simple, robuste) ou DuckDB (analytics-friendly, lourde pour append fréquent) ?
4. **LLM router** : Anthropic only (cohérence Claude Code) ou multi-provider dès v0.1 (Gemini Flash-Lite pour bulk) ?
5. **Cloud sync MIND** : implémenter en v1.x ou v2.0 ?
6. **Repo** : code IRIS pushé dans `MaestroMed/IRIS` (overwrite placeholder 2023) ou nouveau repo dédié `MaestroMed/iris-app` ?

---

<!-- Architecture rédigée 2026-05-20 par la skill-factory IRIS phase 1. Pas encore challengée par Mehdi. À itérer après son retour. -->

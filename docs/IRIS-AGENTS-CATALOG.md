# IRIS — Catalogue des agents

**Date** : 2026-05-20 · **Statut** : design v0
**Sister doc** : [IRIS-VISION.md](IRIS-VISION.md), [IRIS-ARCHITECTURE.md](IRIS-ARCHITECTURE.md), [IRIS-ROADMAP.md](IRIS-ROADMAP.md)

10 agents spécialisés qui se coordonnent via le Conductor + Event Bus. Pas un agent qui fait tout, plusieurs agents qui font UNE chose bien.

---

## Convention commune à tous les agents

Chaque agent est un module isolé avec :

```yaml
agent: <kebab-case-name>
alias: <nom FR clin d'œil>
mission: <1 phrase>
trigger: <quand il s'active>
capabilities:
  read:    [sources/stores accessibles en lecture]
  write:   [sources/stores accessibles en écriture]
  forbidden: [explicitement interdit]
tools:
  skills:  [skills factory utilisables]
  mcps:    [MCP servers utilisables]
memory:    [ce que l'agent stocke pour lui-même]
events_in: [événements écoutés sur le bus]
events_out:[événements émis sur le bus]
llm_model: <Opus 4.7 | Sonnet 4.6 | Haiku 4.5 | Gemini 2.5 Flash-Lite>
```

Routing modèles par défaut : **Opus** pour Conductor + Advisor (synthèse complexe), **Sonnet** pour Quill + Auditor (rédaction qualité), **Haiku** pour Sentinel + Scribe retrieval + Cartographer (bulk cheap), **Gemini Flash-Lite** pour Witness vision (vidéo/image input cheap).

---

## 1. Conductor (Maître d'œuvre)

**Mission** : orchestrateur central. Reçoit les inputs (utilisateur, événements bus, schedule), décide qui fait quoi, dispatch aux workers.

```yaml
agent: conductor
trigger: input user OU event prioritaire du bus
capabilities:
  read: [TOUT — visibilité globale]
  write: [bus.dispatch_only — pas d'action directe]
  forbidden: [aucune écriture directe aux sources externes]
tools:
  skills: [tous via dispatch aux workers]
  mcps: [aucun directement]
memory: [intentions utilisateur, dispatch history, échecs de routing]
events_in: [user.input, sentinel.signal, scheduled.tick, agent.failure]
events_out: [worker.dispatch:<agent>, ui.update, error.raised]
llm_model: claude-opus-4-7
```

Le Conductor est le seul agent avec une vue 360°. Il ne fait jamais d'action terrain — il route. Ça permet l'observabilité totale (chaque action passe par lui, donc loggable).

---

## 2. Sentinel (Vigie)

**Mission** : observer en continu les sources externes (Gmail, GitHub, Calendar, file system, screen). Signaler ce qui mérite attention.

```yaml
agent: sentinel
trigger: poll periodic (toutes les 30s à 5 min selon source) + webhooks si dispo
capabilities:
  read: [gmail.threads, github.events, calendar.events, fs.watched_dirs, screen.frontmost_window]
  write: [store.signals, store.observations]
  forbidden: [send_anything, write_to_external]
tools:
  skills: []
  mcps: [Gmail, Calendar, Chrome (in-Chrome ou screen capture), gh CLI via shell]
memory: [dernière sync par source, baseline d'activité par source, signaux déjà émis (dédup)]
events_in: [conductor.scope_change (focus a changé de projet)]
events_out: [sentinel.signal {source, importance:1-5, summary, raw_link}]
llm_model: claude-haiku-4-5  # bulk classification, cheap
```

**Règles de signalement** :
- Email d'un client identifié (cf Cartographer) → importance 4
- Email standard → 2
- GitHub PR ouverte sur un repo actif → 4
- GitHub CI failure → 5
- Calendar event dans < 15 min → 4
- File modifié dans un projet actif → 1 (juste log)

Sentinel ne juge pas — il quantifie. Le Conductor décide quoi en faire.

---

## 3. Scribe (Greffier)

**Mission** : mémoire long terme. Tout ce que Mehdi a fait, dit, décidé est indexé et retrouvable. Sert aussi de mémoire partagée entre agents.

```yaml
agent: scribe
trigger: event.requires_memory_op (sur demande)
capabilities:
  read: [store.memories, store.action_logs]
  write: [store.memories]
  forbidden: [write outside store]
tools:
  skills: []
  mcps: []  # purement local
memory: [embedding index sqlite-vec + facets temporelles/projet/agent]
events_in: [memory.store, memory.retrieve, memory.update]
events_out: [memory.found {chunks}, memory.stored {id}]
llm_model: claude-haiku-4-5  # embeddings + light synthesis
```

**Format mémoire** : compatible avec les mémoires Claude existantes (`~/.claude/projects/<repo>/memory/<name>.md` avec frontmatter). Scribe lit/écrit aussi dans ce dossier en plus de son SQLite local.

**Retrieval** : embeddings + filtres facettes (par projet, par agent émetteur, par fenêtre temporelle, par type : user / feedback / project / reference).

---

## 4. Quill (Plumitif)

**Mission** : rédiger. Emails, messages Slack, posts, docs, commit messages, descriptions de PR, drafts de réponses. JAMAIS envoyer.

```yaml
agent: quill
trigger: conductor.dispatch (drafting requested) OU sentinel.signal {type: needs_response}
capabilities:
  read: [scribe.memories, store.projects, gmail.thread_context]
  write: [store.drafts, gmail.drafts.create (Gmail API draft, pas send)]
  forbidden: [gmail.send, slack.send, github.comment_publish]
tools:
  skills: [doc-first-project-scaffolding (pour drafter doc projet), spec-driven-build-with-claude-md (pour drafter CLAUDE.md)]
  mcps: [Gmail (draft only)]
memory: [tonalité Mehdi par contexte (client formel / dev casual / interne agency), drafts précédents validés]
events_in: [draft.request {context, audience, tone}]
events_out: [draft.ready {id, content, audience}, draft.iteration_requested]
llm_model: claude-sonnet-4-6  # rédaction qualité, cost-aware
```

Quill apprend le style de Mehdi par contexte. Première rédaction = template. Après 5-10 validations → drafts plus alignés.

---

## 5. Auditor (Inspecteur)

**Mission** : audit projets, code reviews, health checks. Instancie les skills `damage-control` + `ai-pipeline-orchestrator`.

```yaml
agent: auditor
trigger: conductor.dispatch (audit requested) OU scheduled (audit mensuel par projet actif)
capabilities:
  read: [fs.project_dir, github.repo_data, store.projects]
  write: [store.audit_reports, fs.docs/damage-control/*.md (output damage-control)]
  forbidden: [modifications code, modifications config production]
tools:
  skills: [damage-control, ai-pipeline-orchestrator]
  mcps: [gh CLI via shell, Chrome (PageSpeed checks)]
memory: [history audits par projet, deltas entre audits (régressions détectées)]
events_in: [audit.request {project, scope}, scheduled.monthly_audit]
events_out: [audit.complete {project, verdict, top_actions, regressions}]
llm_model: claude-sonnet-4-6  # synthèse audit qualité
```

Auditor délègue le scan technique aux skills (damage-control) et au pipeline orchestrator pour les checks parallèles. Il agrège et synthétise.

---

## 6. Cartographer (Cartographe)

**Mission** : maintenir la carte vivante des projets de Mehdi. Sait qui est qui, qui en est où, quel est le pattern dominant par projet.

```yaml
agent: cartographer
trigger: scheduled (daily refresh) OU event {new_project_detected, project_archived}
capabilities:
  read: [fs.~/Developer/*, github.user_repos, store.projects]
  write: [store.projects, fs.Iris/artefacts/PROJECTS-MAP.md (sync vivant)]
  forbidden: [actions sur les projets eux-mêmes]
tools:
  skills: []
  mcps: [gh CLI via shell]
memory: [delta projets time-series, mapping codenames → repos, état par projet]
events_in: [project.discovered, project.dormant_detected, fs.changes]
events_out: [project.updated {id, changes}, map.refreshed]
llm_model: claude-haiku-4-5  # classification + résumé, bulk
```

Cartographer est l'agent qui maintient `PROJECTS-MAP.md` vivant. Il détecte automatiquement les nouveaux projets, marque les dormants, met à jour les stacks, mappe les codenames.

---

## 7. Builder (Artisan)

**Mission** : exécuter du code, scaffolder, instancier des skills factory. Interface avec Cursor/Claude Code en CLI.

```yaml
agent: builder
trigger: conductor.dispatch (build/scaffold/execute requested)
capabilities:
  read: [fs.~/Developer/*, fs.~/Iris/*]
  write: [fs.~/Developer/<project>/* (avec confirmation user), fs.~/Iris/scratch/*]
  forbidden: [fs.system, package install global, git push (déférer à Envoy)]
tools:
  skills: [doc-first-project-scaffolding, spec-driven-build-with-claude-md, lead-gen-local-services-fr, programmatic-seo-local-combos, backoffice-custom-cms-crm-rbac, nextjs-stack-baseline-2026, monorepo-turbo-with-claude-agents, booking-marketplace-calcom-or-custom, viral-content-pipeline-long-to-short, configurateur-3d-r3f-product]
  mcps: [shell (bash), computer-use (si UI app autom)]
memory: [skills déjà invoqués par projet, succès/échecs, patterns détectés en cours de build]
events_in: [build.request, scaffold.request]
events_out: [build.complete {files_changed, diff}, build.failed {reason}]
llm_model: claude-opus-4-7  # code generation qualité
```

Builder est le "muscle" qui transforme les skills en code. Il propose toujours un diff avant d'écrire (révisable). Confirmation user obligatoire pour les modifications hors `~/Iris/scratch/`.

---

## 8. Envoy (Ambassadeur)

**Mission** : actions externes irréversibles. Envoi d'emails, posts Slack, ouverture de PRs, commentaires GitHub, paiements API. Toujours sous confirmation user.

```yaml
agent: envoy
trigger: conductor.dispatch (send/post/push approved by user)
capabilities:
  read: [store.drafts, store.pending_actions]
  write: [gmail.send, slack.post, github.pr.create, github.issue.create, github.comment.publish, shell.git.push]
  forbidden: [aucune limite particulière mais TOUT requiert confirmation user explicite]
tools:
  skills: []
  mcps: [Gmail (send), Slack (si MCP installé), gh CLI via shell]
memory: [actions exécutées + résultat, undo payloads quand possible]
events_in: [action.execute {type, params, approved_by_user_at}]
events_out: [action.completed {id, result, undo_token?}, action.failed]
llm_model: claude-haiku-4-5  # juste exécution, pas génération
```

Envoy ne décide jamais — il exécute des actions déjà préparées (par Quill ou Builder) ET déjà validées par Mehdi. Chaque exécution = entrée append-only dans `store.action_logs`.

---

## 9. Witness (Témoin)

**Mission** : observer Mehdi (UI active, screen frontmost, optionnellement webcam). Comprendre le contexte applicatif. Phase 1 : screen seulement. Phase 4+ : webcam opt-in.

```yaml
agent: witness
trigger: tick (toutes les 2-5 s) OU user.focus_change
capabilities:
  read: [screen.frontmost_window_capture, mouse.position, keyboard.idle_seconds, webcam.presence (opt-in)]
  write: [store.attention_logs]
  forbidden: [capture quand IRIS n'est pas frontmost, upload screenshots]
tools:
  skills: []
  mcps: [computer-use (screen capture limité), webcam Tauri plugin (opt-in)]
memory: [pattern d'attention Mehdi (heures actives, contexts récurrents), focus state historique]
events_in: [witness.tick]
events_out: [context.changed {app, window_title, project_guess?}, attention.absent, attention.focused {panel}]
llm_model: gemini-2.5-flash-lite  # vision input cheap pour comprendre screen
```

Witness est le sens « yeux » d'IRIS. Permissions explicites obligatoires (Tauri permission dialog). Les screenshots ne sortent jamais de la machine.

---

## 10. Advisor (Conseiller)

**Mission** : sparring partner. Propose, challenge, suggère. Pas d'action — juste conseil. Le seul agent qui parle proactivement à Mehdi sans qu'il ait demandé.

```yaml
agent: advisor
trigger: scheduled (matin briefing 8h, midi point, soir wrap-up) OU event.significant_signal
capabilities:
  read: [TOUT en lecture, mais via scribe.retrieve, sentinel.signals, cartographer.projects, witness.attention]
  write: [store.suggestions]
  forbidden: [toute action directe — purement conseil]
tools:
  skills: [state-of-the-art (vérif SOTA), product-management:brainstorm (sparring)]
  mcps: []
memory: [historique suggestions + acceptées / rejetées par Mehdi, motifs de rejet]
events_in: [scheduled.briefing, conductor.advice_requested]
events_out: [advice.suggest {topic, options, reasoning}, advice.challenge {claim, counter}]
llm_model: claude-opus-4-7  # qualité raisonnement maximale
```

Advisor est le seul agent qui peut dire « tu te trompes ». Pas de glazing. Il challenge les choix de Mehdi (recoupement direct avec le ton no-glazing documenté en mémoire).

---

## Tableau croisé capabilities × sources

| Source/Ressource | Sentinel | Scribe | Quill | Auditor | Cartographer | Builder | Envoy | Witness | Advisor | Conductor |
|---|---|---|---|---|---|---|---|---|---|---|
| Gmail read | R | – | R | – | – | – | – | – | – | R |
| Gmail draft create | – | – | W | – | – | – | – | – | – | – |
| Gmail send | – | – | – | – | – | – | **W** | – | – | – |
| GitHub read | R | – | R | R | R | R | – | – | R | R |
| GitHub PR create | – | – | – | – | – | – | **W** | – | – | – |
| GitHub commit push | – | – | – | – | – | – | **W** | – | – | – |
| Calendar | R | – | – | – | – | – | – | – | R | R |
| File system (projets) | R | R | R | R | R | R/W | – | – | R | R |
| Screen capture | – | – | – | – | – | – | – | R | – | – |
| Webcam (opt-in) | – | – | – | – | – | – | – | R | – | – |
| Shell execute | – | – | – | – | – | R/W | R/W | – | – | – |
| Store memories | – | R/W | R | R | R | R | R | R | R | R |
| Store drafts | – | R | R/W | – | – | – | R | – | R | R |
| Store action_logs (append-only) | W | W | W | W | W | W | W | W | W | W |

Bold W = action sensible nécessitant confirmation user.

---

## 5 flows-types end-to-end

### Flow 1 — Nouveau email client → réponse semi-automatique

```
[09:14] Sentinel : poll Gmail toutes les 30 s → nouveau thread "Devis structures escalier" de Odelie (Atelier Frisson cliente)
→ Sentinel émet sentinel.signal {source:gmail, importance:4, summary, raw_link}
→ Conductor reçoit signal, vérifie Cartographer (Atelier Frisson = client actif VIP)
→ Conductor dispatch Scribe.retrieve(context: atelier_frisson)
→ Scribe retourne mémoires : ton client formel-FR, derniers échanges, décisions sur le projet
→ Conductor dispatch Quill.draft(thread_id, context, tone:formel-fr-client)
→ Quill lit thread, génère draft v1, stock dans store.drafts + crée Gmail draft
→ Quill émet draft.ready
→ UI panel "Drafts" highlight le nouveau, Mehdi voit en glance
[09:16] Mehdi clique, review, ajuste 2 mots, hit Approve
→ Conductor dispatch Envoy.send(draft_id)
→ Envoy envoie via Gmail MCP, log dans action_logs
→ Envoy émet action.completed {undo:false_email_sent}
→ Scribe stocke l'échange en mémoire pour calibrer Quill futur
```

### Flow 2 — CI failure sur repo actif → diagnostic préemptif

```
[14:32] Sentinel : webhook GitHub → CI failed sur AZ Construction main
→ Sentinel émet sentinel.signal {source:github, importance:5, summary}
→ Conductor dispatch Auditor.investigate(repo: AZConstruction_v0, type: ci_failure)
→ Auditor invoke skill ai-pipeline-orchestrator → lit logs CI, analyse stack trace via Claude
→ Auditor identifie cause probable + propose fix
→ Auditor émet audit.complete {project, root_cause, suggested_fix}
→ UI panel "Audits" notification rouge
[14:34] Mehdi voit le briefing, clique pour détails
→ Mehdi : "fix this"
→ Conductor dispatch Builder.apply_fix(suggestion)
→ Builder propose diff, Mehdi review et approuve
→ Conductor dispatch Envoy.push(branch: hotfix/ci-fix)
→ Envoy push, log
→ Sentinel observe CI re-run, ping quand vert
```

### Flow 3 — Briefing matinal proactif

```
[08:00] Scheduled tick → Conductor invoke Advisor.morning_briefing
→ Advisor lit :
  - Scribe : décisions/actions de hier
  - Sentinel : signals depuis hier soir (5 emails, 2 PRs review demandés, 1 calendar event 10h)
  - Cartographer : 12 projets actifs, status delta vs hier
  - Witness : pattern attention Mehdi (matins productifs sur code, après-midi mails)
→ Advisor synthétise top 3 priorités du jour + 2 risques + 1 challenge ("hier tu as passé 4h sur LoLTok, tu l'avais cadré 1h — pourquoi ?")
→ Advisor émet advice.suggest {topic:daily, ...}
→ UI panel "Briefing" affiche, notification macOS
[08:02] Mehdi ouvre IRIS, voit briefing en glance
→ Si Mehdi clique sur une suggestion → Conductor dispatch action correspondante
```

### Flow 4 — Nouveau projet client → scaffolding semi-auto

```
Mehdi via IRIS chat-box : "nouveau client Auto-école Cergy, on monte un site lead-gen + booking"
→ Conductor parse intent
→ Conductor dispatch Cartographer.register_project(codename: AECergy, type: lead-gen-local-fr+booking)
→ Cartographer ajoute entrée dans PROJECTS-MAP.md + store.projects
→ Conductor dispatch Builder.scaffold(skills: [doc-first-project-scaffolding, lead-gen-local-services-fr, booking-marketplace-calcom-or-custom])
→ Builder invoke skills séquentiellement :
  1. doc-first scaffold ARCHITECTURE/FEATURES/SEO_STRATEGY/QUESTIONNAIRE/etc.
  2. lead-gen template src/app structure + .env.example
  3. booking ajoute Cal.com embed component
→ Builder propose diff complet (40 fichiers créés)
→ Mehdi review diff dans panel "Builder"
[Mehdi approuve]
→ Builder écrit fichiers dans ~/Developer/AECergy/
→ Conductor dispatch Envoy.git_init_and_push(repo: AECergy_v0, org: MaestroMed)
→ Envoy crée repo GitHub + push initial commit
→ Cartographer met à jour map avec repo URL
```

### Flow 5 — Mehdi absent → IRIS met en veille

```
[16:45] Witness : Mehdi absent du screen + clavier idle > 5 min + webcam confirme absence
→ Witness émet attention.absent
→ Conductor reçoit, vérifie actions en cours (Builder en plein scaffold)
→ Conductor met en pause les actions interruptibles (Builder), continue les non-interruptibles (Sentinel poll)
→ Conductor dispatch Scribe.snapshot_session
→ Scribe stocke un résumé état session pour reprise
[17:30] Witness : Mehdi revient (présence + clavier actif)
→ Witness émet attention.present
→ Conductor reprend les actions paused
→ Advisor briefe : "tu étais absent 45 min, voici ce qui a bougé : 2 emails Sentinel marqués importance 4, CI rouge sur LoLTok réparée auto, draft Quill prêt pour Odelie"
```

---

## Composition agents ↔ skills factory

Chaque agent peut invoquer des skills factory. Les skills sont des **outils** que les agents instancient ; les agents sont des **acteurs persistants** qui survivent à un appel skill.

| Skill factory | Agents qui l'invoquent |
|---|---|
| `lead-gen-local-services-fr` | Builder |
| `doc-first-project-scaffolding` | Builder, Quill |
| `spec-driven-build-with-claude-md` | Builder, Quill |
| `programmatic-seo-local-combos` | Builder |
| `backoffice-custom-cms-crm-rbac` | Builder |
| `nextjs-stack-baseline-2026` | Builder |
| `monorepo-turbo-with-claude-agents` | Builder |
| `booking-marketplace-calcom-or-custom` | Builder |
| `ai-pipeline-orchestrator` | Auditor, Builder |
| `viral-content-pipeline-long-to-short` | Builder |
| `configurateur-3d-r3f-product` | Builder |
| `damage-control` | Auditor |
| `gpt-image-2-prompter` | Quill (génération visuels pour drafts/posts) |
| `state-of-the-art` | Advisor (vérif SOTA), Builder (avant init projet) |
| `animation-hero` | Builder (sur projet web visuel) |

---

<!-- Catalogue rédigé 2026-05-20 par la skill-factory IRIS phase 1. Inspirations : Claude Code subagents (Explore/Plan), CrewAI roles, MIND iOS audit pipeline, mattpocock/skills + obra/superpowers patterns. -->

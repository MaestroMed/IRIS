# IRIS — Vision

**Tagline** : Premier exocortex local desktop multi-agents avec UX visuelle dense. Pendant desktop de MIND iOS.

**Date** : 2026-05-20 · **Statut** : design v0 (vision pré-code)

---

## 1. Pourquoi IRIS existe

Mehdi pilote 25+ projets en parallèle (clients agency Numelite + outils internes + projets créatifs). Sa ressource la plus rare = son temps et son attention. Trois problèmes structurels que les outils actuels ne résolvent pas :

1. **Le contexte se perd** entre projets. Switcher de AZ Construction à Atelier Frisson à LoLTok = redémarrer le mental load à zéro à chaque fois. Aucun outil ne maintient un état "où j'en suis sur chaque projet, qui attend quoi de moi, qu'est-ce qui a bougé depuis ma dernière session".
2. **Les séquences se répètent** sans factoriser. Anti-pattern Mehdi documenté. La skill-factory phase 1 a commencé à corriger ça (11 skills livrés), mais sans orchestrateur qui *utilise* les skills automatiquement, ils restent dormants.
3. **L'attention est fragmentée**. Email arrive, GitHub PR ouverte, Calendar reminder, Slack message — sans hiérarchisation intelligente cross-sources. Switching tax énorme.

Les LLMs actuels (ChatGPT Desktop, Claude Desktop, Cursor) sont des **chats**, pas des **exocortex**. Tu leur poses une question, ils répondent. Ils n'observent pas ton flux, ne prennent pas d'initiative, ne se coordonnent pas entre eux, ne se souviennent pas durablement de toi.

**IRIS comble ce vide.**

---

## 2. Positionnement vs MIND

| | MIND (iOS — cockpit Numelite) | IRIS (Mac/Web — exocortex Mehdi) |
|---|---|---|
| Cible primaire | Tes CLIENTS (audit, leads, invoices) | TOI (sparring, mémoire, action) |
| Plateforme | iPhone + iPad | Mac desktop principal, Web compagnon optionnel |
| Stack | Swift + SwiftUI + SwiftData + CloudKit + Tuist 4 | À designer (cf IRIS-ARCHITECTURE.md) |
| Mode d'usage | Cockpit consulté ponctuellement | Compagnon continu pendant le travail |
| Modèle interaction | Tu consultes l'audit/lead/invoice produit | Les agents observent + agissent + te briefent |
| DA | Liquid Glass (iris/aqua/sky soft) | Même DA pour cohérence visuelle Numelite |
| Sync | CloudKit zone privée | Sync avec MIND via CloudKit OU local Postgres |

**Non-recoupement** : MIND ne pilote pas le code/skills/repos/email de Mehdi. IRIS ne pilote pas les clients à la place de Mehdi.

**Complémentarité** : un audit IRIS sur un repo client peut être pushé dans MIND comme nouvelle entrée du cockpit. Une nouvelle ligne lead arrivée dans MIND peut déclencher un workflow IRIS (drafter la réponse email).

---

## 3. Différenciation marché (mai 2026)

| Concurrent | Force | Manque vs IRIS |
|---|---|---|
| **Claude Desktop** (Anthropic) | Best LLM, MCP natif, gratuit | Single-agent, chat-first, pas d'observation continue, pas d'UX dense |
| **Cursor** | Excellent code editor + agent | Code-only, pas d'autres domaines |
| **ChatGPT Desktop** | Mass adoption | Single-agent, chat-first |
| **Notion AI** | Intégré dans Notion | Notion-only, pas d'agents externes, pas d'observation OS |
| **CrewAI / LangGraph / AutoGen** | Frameworks agentiques puissants | Code-only, pas d'UX, pour développeurs, pas tout-en-un |
| **Devin** (Cognition) | Agent autonome dev | Cloud-only, code-only, $500/mois |
| **Adept** | Action sur browser via vision | Browser-only, jeune, américain |
| **Rewind** | Mémoire continue Mac | Memory only, pas d'agents, pas d'action |
| **Open Interpreter** | Shell agent local | Shell-only, single-agent |
| **Replit Agent** | Cloud agent code | Cloud, code-only |
| **Pi** (Inflection / Microsoft) | Personal AI conversational | Single-agent, chat, faible action |

**Le gap qu'IRIS occupe** : **multi-agents + UX visuelle dense + local-first + cross-domain (code + email + calendar + projects + browser) + intégration OS profonde**.

Aucun produit en mai 2026 ne combine ces 5 attributs.

---

## 4. L'angle "yeux"

Mehdi à l'init (2026-05-20) : « Une petite expérimentation pour voir à quel point les yeux peuvent aider à faire avancer le traitement de l'UX/UI comme d'une interface humain / ordinateur. »

Trois interprétations cumulatives :

### 4.1 — UX visuelle dense (livré dès v0.1)

Par opposition à l'interface chat dominante (textbox + scroll). IRIS utilise des **panels multiples à la Bloomberg Terminal mais agentic** :
- Chaque agent a sa zone visible
- Activité temps réel (qui pense, qui agit, qui attend)
- État glanceable : Mehdi voit tout d'un coup, pas besoin de scroller un historique
- DA Liquid Glass cohérente avec MIND iOS

### 4.2 — Vision computer pour comprendre l'écran (v0.5+)

- Capture screenshot périodique de l'écran actif (Mac) — fenêtre fronted only
- IRIS comprend le contexte applicatif (Cursor sur quel repo ? Browser sur quel domaine ? Email actif ?)
- Suggestions contextuelles : "tu travailles sur AZ Construction, voici le dernier commit + 2 issues ouvertes"
- **Permission opt-in stricte**, traitement local uniquement, jamais upload

### 4.3 — Attention tracking via webcam (v1.x+, option)

- Webcam pour détecter présence/absence/focus
- Si Mehdi absent > 30s → IRIS pause les actions non-critiques
- Si Mehdi regarde un panel précis → IRIS prioritise les updates de ce panel
- Si signes de fatigue (clignements + posture) → suggestion pause
- **Permission opt-in stricte**, jamais upload, jamais enregistrement

---

## 5. Manifeste — 10 principes non-négociables

1. **Multi-agents par défaut.** Pas un agent qui fait tout, plusieurs agents spécialisés qui se coordonnent. Conductor orchestre, Sentinel observe, Scribe se souvient, Quill rédige, etc. (cf IRIS-AGENTS-CATALOG.md)
2. **UX visuelle dense.** Pas de chat-first. Panels multiples, état temps réel, glanceable. La chat-box est UN composant parmi 10, pas le centre.
3. **Local-first.** Données chez Mehdi (CloudKit ou SwiftData ou IndexedDB ou Postgres local selon variante choisie). Pas de cloud par défaut. Cloud optionnel pour sync MIND iOS.
4. **Intégration OS profonde** (selon variante choisie). Spotlight, Notifications natives, Live Activities, File system, AppleScript / Accessibility API si Mac native. Pas un browser tab anonyme.
5. **Modulaire et composable.** Agents = composables. Skills = ressources que les agents instancient. Les 11 skills factory + futurs skills sont des outils que les agents IRIS utilisent.
6. **Anti-over-architecting.** Chaque release = livrable utile. Pas de framework abstrait avant le premier agent qui marche en production. Roadmap incrémentale v0.0.1 → v3.0 (cf IRIS-ROADMAP.md).
7. **Vitesse > perfection.** v0.1 ship en 2-3 semaines, pas 6 mois. Itération continue avec feedback Mehdi en boucle courte.
8. **Transparence absolue.** Chaque action agent visible. Chaque action non-triviale demande confirmation (sauf opt-out par Mehdi). Tout reversible (logs structurés append-only).
9. **Apprend Mehdi.** Mémoire long terme (Scribe). Préférences, anti-patterns, vocabulaire, habitudes, projets. Persistant cross-sessions. Format compatible avec les mémoires Claude existantes (`~/.claude/projects/<repo>/memory/`).
10. **Cohérence avec MIND.** Même DA Liquid Glass. Sync données (audits IRIS push vers MIND, leads MIND déclenchent workflows IRIS). Workflow continu mobile ↔ desktop.

---

## 6. Vision long terme (2026 → 2030)

**2026 H2** — IRIS v1.0 installé chez Mehdi seul. 10 agents en boucle complète. Skill marketplace local. Sync MIND. Anti-pattern over-architecting respecté.

**2027** — IRIS v2.0 testé par 3-5 early adopters (autres opérateurs solo / freelances tech francophones). Cloud sync optionnel. Multi-devices Mac + iOS (avec MIND). Marketplace skills partagé entre opérateurs.

**2028+** — IRIS v3.0 offre commerciale Numelite. Vendu comme « Cockpit personnel d'opérateur agency » à 200-500€/mois. Sister product de `damage-control` vendu en SaaS à 200-400€/mois (mentionné dans README damage-control).

**2030 angle long shot** — IRIS devient le réseau social de l'attention augmentée. Les agents apprennent collectivement sans fuiter le contexte privé (federated learning). Standard de fait pour les opérateurs solo / petites équipes haute densité.

---

## 7. Ce qu'IRIS n'est PAS

- **Pas un chatbot.** Si tu veux poser une question one-shot, utilise Claude Desktop.
- **Pas un IDE.** Cursor reste l'IDE.
- **Pas un PM tool.** Linear / Notion / Asana restent les PM tools (mais IRIS lit depuis et écrit dedans via MCP).
- **Pas un CRM.** MIND est le cockpit clients.
- **Pas un cloud SaaS.** Local-first. Cloud strictement optionnel.
- **Pas un framework agentique de plus pour développeurs.** CrewAI / LangGraph existent. IRIS est un produit fini pour un opérateur solo, pas un kit de construction.

---

<!-- Vision rédigée 2026-05-20 par la skill-factory IRIS phase 1. Sources : conversation init Mehdi 2026-05-20 + project_iris.md mémoire + PROJECTS-MAP.md + PATTERNS-REPORT.md + scan ~/Developer/matter_hub/mind/ (README + ULTRAPLAN.md MIND iOS). -->

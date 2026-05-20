# IRIS — Cloud sync design (v2.x)

**Date** : 2026-05-20 · **Statut** : design v0 pour phase 5 roadmap
**Sister docs** : [IRIS-VISION.md](IRIS-VISION.md), [IRIS-ARCHITECTURE.md](IRIS-ARCHITECTURE.md), [IRIS-ROADMAP.md](IRIS-ROADMAP.md)

---

## 1. Pourquoi cloud sync ?

v1.x local-first volontairement (cf manifeste IRIS-VISION §5 principe 3). Mais 3 cas d'usage nécessitent du cloud sync **optionnel** :

1. **Multi-devices Mehdi** : un IRIS sur Mac M5 principal + un IRIS éventuel sur Mac mini bureau ou MacBook Air voyage. Continuité des memories, signals, drafts, audits cross-machines.
2. **MIND ↔ IRIS sync** : leads inbound captés par MIND iOS doivent déclencher Quill draft côté IRIS Mac. Audits IRIS doivent apparaître dans MIND cockpit clients.
3. **Phase 2 early adopters (v2.x → v3.x)** : 3-5 utilisateurs autres opérateurs solo. Chacun a SON IRIS local + SON cloud sync personnel (pas de cross-user partage en v2). Marketplace skills partagé vient v2.3.

**Non-goal v2.0** :
- Pas de cross-user sharing (un user = un cloud namespace)
- Pas de cloud-first (tout reste local-first, le cloud est mirror)
- Pas de cloud sync forcé (opt-in strict)

---

## 2. Threat model

**Acteurs hostiles considérés** :
- Provider cloud (Apple iCloud, AWS, etc.) — assume curieux/compromis
- Compromission compte iCloud — assume possible
- Vol device — assume Mac volé sans Keychain unlock OK
- Network MITM — assume actif

**Données sensibles à protéger** :
- Mémoires Mehdi (préférences, anti-patterns, contexte business clients)
- Conversations Conductor (Q/R historiques)
- Drafts emails (contenu pré-envoi)
- API keys (Anthropic, Gmail OAuth, GitHub PAT) — restent locales Keychain, jamais cloud

**Garanties cibles** :
- E2EE : provider cloud ne peut lire aucune donnée user en clair
- Forward secrecy : compromission clés future ne révèle pas le passé
- Per-user isolation : un user compromis ne révèle pas un autre user
- Plausible deniability sur metadata : provider ne sait pas quels types de mémoires (juste blobs chiffrés)

**Non-garanties v2.0** :
- Pas de plausible deniability sur les volumes (provider voit "X MB uploadés")
- Pas de résistance state-level (NSA, etc.) — assume out-of-scope

---

## 3. Trois options évaluées

### Option A — age + CloudKit shared zone

**Stack** :
- [age](https://github.com/FiloSottile/age) (X25519 + ChaCha20-Poly1305) pour chiffrement local AVANT upload
- CloudKit private database (zone par device, sync cross-devices Apple)
- MIND iOS partage le même CloudKit container avec IRIS Mac

**Flow** :
1. Genère keypair age au premier launch IRIS (privé stocké Keychain, public partagé entre devices)
2. Pour sync : chiffre SwiftData snapshot avec age public key → upload blob CloudKit
3. Read : pull blob CloudKit → déchiffre avec age private key
4. Cross-device Mac : Keychain sync iCloud propage la clé privée
5. MIND iOS : utilise même CloudKit container, mêmes clés age

**Pros** :
- E2EE strict (CloudKit voit blobs)
- Pas d'infra à provisionner (CloudKit gratuit ≤ 10GB)
- Sync Apple automatique
- Cohérence MIND iOS (déjà CloudKit)

**Cons** :
- Lock-in Apple (mais on est Mac/iOS-only de toute façon)
- Latence sync ~30s (CloudKit pas optimisé real-time)
- Conflict resolution à gérer côté app (CloudKit n'aide pas)
- age dépend sur Swift package (`swift-age` ou bridge à un binaire)

### Option B — WireGuard tunnel + serveur Numelite custom

**Stack** :
- WireGuard tunnel vers un serveur Numelite (OVH/Scaleway, EU)
- Serveur stocke blobs chiffrés
- Authentification via clé Wireguard (pas de mot de passe à gérer)

**Pros** :
- Indépendant Apple
- Latence faible (push/pull WebSocket dédié)
- Multi-platform si IRIS Windows/Linux phase 3 (v2.6)

**Cons** :
- Infra à provisionner et maintenir (coût + uptime + backups)
- Pas de sync MIND iOS natif (faut bridge)
- Plus complexe à debug (tunnel, certificats)

### Option C — CloudKit shared zone DIRECT (sans E2EE custom)

**Stack** :
- CloudKit private database + SwiftData CloudKit sync built-in
- iCloud chiffre at-rest mais Apple peut techniquement lire

**Pros** :
- Zéro code custom (SwiftData fait tout)
- Sync MIND iOS trivial
- Latence Apple CloudKit
- Pas de gestion clés

**Cons** :
- Pas E2EE — provider Apple peut lire les memories Mehdi
- Compromis privacy vs simplicité
- Pas conforme au principe "local-first + E2EE" du manifeste

---

## 4. Recommandation

**Phase v2.0 → v2.3 : Option A (age + CloudKit shared zone)**

Justifications :
- Respecte le principe E2EE du manifeste (principe 3)
- Cohérence MIND iOS (même CloudKit container, même clé age partagée)
- Pas d'infra Numelite à payer/maintenir
- age est éprouvé cryptographiquement (X25519 + ChaCha20-Poly1305, audited)

**Trade-off accepté** : on dépend Apple ecosystem (mais on est déjà Mac/iOS-only en v1).

**Phase v2.6+ (Windows/Linux early adopters)** : ajouter Option B en parallèle pour les non-Apple users. CloudKit pour Apple, WireGuard tunnel pour autres OS.

**Phase v3.x (commercial Numelite)** : Option B devient l'option par défaut, CloudKit reste pour utilisateurs Apple natifs.

---

## 5. Architecture détaillée (Option A retenue)

### 5.1 Keypair management

```
┌────────────────────────────────────────────────┐
│              First launch IRIS Mac              │
│                                                 │
│  1. Genère age keypair (X25519)                │
│  2. Stocke private key dans Keychain :         │
│     - service "app.iris.macos.secrets"         │
│     - account "iris-cloud-sync-private-key"    │
│     - accessibility WhenUnlockedThisDeviceOnly │
│  3. Public key écrit dans                      │
│     "iris-cloud-sync-public-key" Keychain      │
│  4. iCloud Keychain sync propage automatiquement│
│     vers autres Macs Mehdi + MIND iOS          │
└────────────────────────────────────────────────┘
```

### 5.2 Sync upload (push local → cloud)

```
SwiftData change → debounce 30s → batch upload
                       │
                       ▼
              ┌──────────────────────┐
              │ BackupService.       │
              │  exportPayload()      │  → JSON snapshot complet (v1.9 réutilisé)
              └────────┬─────────────┘
                       │
                       ▼
              ┌──────────────────────┐
              │ age.encrypt(payload,  │  → blob chiffré
              │   recipient: publicKey)│
              └────────┬─────────────┘
                       │
                       ▼
              ┌──────────────────────┐
              │ CloudKit.save(blob,   │  → record "iris-snapshot-<timestamp>"
              │   record: snapshot)   │     dans private DB
              └──────────────────────┘
```

### 5.3 Sync download (pull cloud → local)

```
App launch OR push notif CloudKit → pull latest snapshot
                       │
                       ▼
              ┌──────────────────────┐
              │ CloudKit.query(      │  → blob chiffré (latest record)
              │   sort: createdAt    │
              │   limit: 1)          │
              └────────┬─────────────┘
                       │
                       ▼
              ┌──────────────────────┐
              │ age.decrypt(blob,    │  → JSON snapshot
              │   identity: privateKey│
              └────────┬─────────────┘
                       │
                       ▼
              ┌──────────────────────┐
              │ BackupService.        │  → merge dans SwiftData
              │  importBackup()       │     (idempotent par UUID, v1.9 réutilisé)
              └──────────────────────┘
```

### 5.4 Conflict resolution

**v2.0 simple — Last-Write-Wins (LWW) par modelObjectId** :
- Chaque @Model a un `updatedAt: Date` (à ajouter en v2.0.A)
- Si local.updatedAt > cloud.updatedAt → upload écrase cloud
- Si cloud.updatedAt > local.updatedAt → cloud écrase local
- Cas d'edge : conflit simultané → favorise le device avec le dernier interaction user récente (heuristique)

**v2.5+ — CRDT migration si besoin** :
- Si Mehdi rapporte des pertes de données récurrentes → migration vers CRDT (e.g., Y.js bindings Swift) pour merge fin
- Réservé v2.5+ une fois retour terrain v2.0-v2.4

### 5.5 Structure CloudKit

```
Container : iCloud.app.iris.macos.shared
  Private DB :
    Zone "iris-sync-zone"
      Records :
        "iris-snapshot-<UUID>"
          - blob (Data) — age-encrypted JSON
          - createdAt (Date)
          - deviceId (String) — pour debug
          - schemaVersion (Int) — pour migrations
```

### 5.6 Migration v1.x → v2.0

1. v2.0 release ship avec cloud sync DÉSACTIVÉ par défaut
2. Settings panel "Cloud Sync" :
   - Toggle "Activer cloud sync"
   - Bouton "Générer ma keypair"
   - Bouton "Push now" (manuel pour test)
   - Bouton "Pull now"
3. Mehdi active manuellement la 1ère fois
4. Au prochain launch, auto-sync (debounce 30s) si activé

---

## 6. POC code outline

### 6.1 Swift package age bridge

Pas de SPM age natif officiel. Options :

1. **Wrap binaire age via Process spawn** (rapide à monter, dépend gestion install age sur Mac user)
2. **CryptoKit + X25519 + ChaCha20-Poly1305 maison** (Apple natif, plus light, mais on réinvente partiellement age)

**Choix v2.0** : Option 2 CryptoKit. age c'est juste X25519+ChaCha, CryptoKit a tout ce qu'il faut.

### 6.2 Squelette IRISCloudSync.swift

```swift
import Foundation
import CryptoKit
import CloudKit

public actor IRISCloudSync {
    public static let shared = IRISCloudSync()

    private let containerIdentifier = "iCloud.app.iris.macos.shared"
    private let zoneName = "iris-sync-zone"

    // Genère keypair X25519, stocke dans Keychain.
    public func generateKeypair() throws -> (publicKey: Data, privateKey: Data)
    public func loadKeypair() throws -> (publicKey: Data, privateKey: Data)?

    // Push : encrypt payload → upload CloudKit
    public func push(payload: Data) async throws

    // Pull : query CloudKit → decrypt → return payload
    public func pull() async throws -> Data?

    // Encrypt / decrypt avec ChaCha20-Poly1305 + X25519 ECDH
    private func encrypt(_ data: Data, publicKey: Data) throws -> Data
    private func decrypt(_ blob: Data, privateKey: Data) throws -> Data
}
```

### 6.3 Wire dans IRISApp

```swift
// IRISApp.bootstrap step 11.b — v2.0
if UserDefaults.standard.bool(forKey: "iris.cloudSync.enabled") {
    await CloudSyncOrchestrator.shared.start(
        sync: IRISCloudSync.shared,
        modelContainer: modelContainer,
        debounceSeconds: 30
    )
}
```

CloudSyncOrchestrator écoute IRISEvent et déclenche push après debounce. Pull au launch + push notif CloudKit subscription.

---

## 7. Roadmap v2.0 → v2.9 (cf IRIS-ROADMAP.md phase 5)

| Version | Scope cloud sync |
|---|---|
| **v2.0** | Cloud sync E2EE basique. Toggle Settings. Push/Pull manuel + auto debounce 30s. age via CryptoKit. CloudKit zone privée. Idempotent UUID upsert. |
| **v2.0.A** | `updatedAt: Date` ajouté sur tous @Model pour LWW conflict resolution. Migration SwiftData mineure. |
| **v2.1** | MIND ↔ IRIS sync bidirectionnel : MIND iOS upload audits clients dans même CloudKit container. IRIS pull dans Cartographer + Inspector. Réverse : IRIS push leads inbound vers MIND. |
| **v2.2** | Multi-user setup pour 3-5 early adopters. Chacun génère sa keypair. Pas de cross-user sharing (un container par user). |
| **v2.3** | Skill marketplace partagé (catalog Numelite repo public). Skills sont commités via PR, pas via sync E2EE. |
| **v2.4** | Telemetry opt-in privacy-first. Agrégats anonymisés (lesquels skills, frequencies). |
| **v2.5** | Migration vers CRDT (Y.js Swift bindings) si conflits LWW deviennent problématiques. |
| **v2.6** | Windows + Linux first-class. Cloud sync via WireGuard tunnel Numelite serveur (cf option B). CloudKit reste pour Apple. |
| **v2.7-v2.8** | IRIS mobile PWA (read + approve actions). Sync via tunnel WireGuard si Apple deny PWA CloudKit. |
| **v2.9** | Hardening sécurité prod : pen-test, threat model documenté, code signing renforcé, sandboxing macOS re-activé avec NSOpenPanel one-shot pour ~/Developer. |

---

## 8. Décisions à arbitrer avant v2.0 code

1. **CryptoKit X25519+ChaCha20 maison ou bridge age binaire ?** Reco : CryptoKit maison (pas de dépendance shell out).
2. **`updatedAt` ajouté à tous @Model maintenant en v1.x ou v2.0 ?** Reco : v2.0 (avec migration SwiftData propre).
3. **CloudKit container identifier final ?** Reco : `iCloud.app.iris.macos.shared` (cohérence MIND).
4. **Push debounce 30s OK ?** Reco : 30s pour v2.0, configurable Settings v2.1+.
5. **Conflict UX** : si conflit détecté en pull, montrer modal "Override local ou cloud ?" — ou silencieux LWW ? Reco : silencieux LWW v2.0, modal v2.5+ si CRDT pas suffisant.

---

## 9. Non-décisions pour ce design

- **Pas de OAuth Provider intermédiaire** : Keychain iCloud sync suffit pour Mehdi multi-devices personnels.
- **Pas de Web app sync** : v1.x web compagnon (v2.7+) lira un dump JSON ou tunnel séparé, pas CloudKit (impossible en Web).
- **Pas de sharing cross-users avant v3.x** : marketplace skills partagé via repo GitHub public, pas via sync E2EE personnel.

---

<!-- Design rédigé 2026-05-20 par la skill-factory IRIS phase 2 (mode 24h autonomous).
Sources : IRIS-VISION manifeste + IRIS-ARCHITECTURE phase Future + ROADMAP phase 5.
À itérer avec Mehdi avant v2.0 implémentation code. -->

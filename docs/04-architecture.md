# LuluBoard — Architecture et choix techniques (VALIDÉ le 2026-10-08, sous réserve du prototype)

> Étape 3 de la méthode, première partie. Le contrat d'API (seconde partie) sera rédigé une fois ce document validé.
> Sources : `01-cas-utilisation.md`, `02-uml-cas-utilisation.md` et `03-uml-classes.md` (validés), `integrations/lulufiles-brief.md`.

## 1. Contraintes retenues

| Contrainte | Valeur | Conséquence |
|---|---|---|
| Équipe | **1 développeur + IA** ✅ | Simplicité avant tout : un seul déploiement, un seul langage par côté (client / serveur). |
| Clients | Web, Android, iOS, Windows, macOS, Linux | Il faut partager le maximum de code, surtout le chiffrement et la synchro. |
| Chiffrement de bout en bout | obligatoire ✅ | Le serveur stocke des contenus illisibles. La logique métier « riche » vit dans le client. |
| Hors ligne dès la V1 | obligatoire ✅ | Base locale sur chaque appareil + protocole de synchronisation. |
| Échelle | lancement public, international | Viser quelques milliers d'utilisateurs la première année sans réécriture ; ne pas optimiser au-delà. |
| Fichiers | LuluFiles ou Telegram direct (variable) ✅ | En mode Telegram, les fichiers transitent par le backend (bande passante). |
| Hébergement | **PaaS** ✅ (Render, Railway, Fly.io…) | Tout est conteneurisé (Docker) pour pouvoir changer d'hébergeur sans réécrire. |
| Budget | **solutions gratuites exigées** ✅ | Privilégier l'open source et les offres gratuites ; signaler explicitement tout coût incompressible. |
| Conformité | loi 2017-20 (APDP), puis RGPD | Données minimales en clair, journalisation sans contenu, suppression effective. |

## 2. Style architectural

| Style | Pour LuluBoard |
|---|---|
| Monolithe simple | Possible, mais ~10 domaines (comptes, appareils, synchro, fichiers, liens, rappels, admin…) deviendraient vite un seul bloc emmêlé. |
| **Monolithe modulaire** ✔ | Un seul backend déployé, découpé en modules Django aux frontières nettes. Un module pourra être extrait plus tard si nécessaire (par exemple le relais de fichiers Telegram). |
| Microservices | À exclure pour un développeur seul : déploiements multiples, observabilité, cohérence des données. Le coût dépasse largement le bénéfice. |

**Recommandation : monolithe modulaire**, avec 3 processus issus du **même code** : l'API web (HTTP + WebSocket), un worker de tâches de fond et un planificateur.

## 3. Organisation interne

### Backend (Django) — modules par domaine, en couches simples

```
backend/
  config/            réglages, ASGI, routage
  apps/
    comptes/         Compte, IdentiteGoogle, CodeVerification, PreferencesCompte
    appareils/       Appareil, Session, EnveloppeCle, DemandeDeverrouillage
    elements/        Element (contenus chiffrés), Tableau, Etiquette, VersionPostIt
    synchro/         protocole de synchro + WebSocket (Channels)
    rappels/         Rappel + déclenchement des notifications push
    envois/          EnvoiAppareil
    fichiers/        Fichier, MorceauTelegram, interface StockageFichiers
                     ├─ adaptateur LuluFiles
                     └─ adaptateur Telegram direct   ← choisi par FILES_USE_DIRECT_TELEGRAM
    liens/           LienPublic + page publique de consultation
    moderation/      Signalement, Suspension
    conformite/      VersionConditions, AcceptationConditions, Annonce, DemandeSupport
  commun/            erreurs, pagination, limitation de débit, journalisation
```

Couches dans chaque module : `models` → `services` (règles métier) → `api` (vues DRF + sérialiseurs). **Pas de Clean/Hexagonal complet** : la logique métier côté serveur est mince (le serveur ne lit pas les contenus). Seule exception, le stockage des fichiers : il passe par une **interface + deux adaptateurs**, précisément parce que vous voulez pouvoir changer de fournisseur.

### Client (Flutter) — organisation par fonctionnalité

```
app/
  lib/
    noyau/
      crypto/        libsodium : clés, enveloppes, chiffrement des éléments
      stockage_local/ base SQLite locale (drift), aussi sur le web
      synchro/       file d'attente hors ligne, push/pull, résolution « dernier gagne »
      api/           client HTTP + WebSocket (généré depuis le contrat OpenAPI)
    fonctionnalites/
      compte/ appareils/ presse_papier/ post_it/ snippets/ taches/
      rappels/ fichiers/ envois/ liens/ recherche/ reglages/ onboarding/
    plateformes/
      desktop/       surveillance du presse-papier, raccourcis globaux, zone de notification,
                     fenêtres au premier plan, démarrage automatique
      mobile/        menu Partager, widget, notifications
    design_system/
```

Le mode **Visiteur** (UC-A0) n'est que l'app sans compte : même base locale, synchro désactivée.

## 4. Données

| Sujet | Décision proposée |
|---|---|
| Base serveur | **PostgreSQL** unique. Les contenus chiffrés sont stockés en `bytea`, les métadonnées dans des colonnes normales. |
| Base locale | **SQLite via drift** sur tous les clients (en WebAssembly sur le web). La recherche plein texte (UC-G2) se fait localement, avec FTS5. |
| Cache / file de messages | **Redis** : couche de messages de Channels (WebSocket), file Celery, compteurs anti-force-brute (A2, I19). |
| Tâches de fond | **Celery + Celery Beat** : envoi des rappels, purge du presse-papier et des versions selon la durée de conservation, expiration des liens, des envois et des sessions, comptes inactifs (I27), suppressions programmées (A5), transferts vers Telegram/LuluFiles. |
| Synchronisation | Le serveur garde, par compte, un **compteur de version** croissant. Chaque appareil envoie ses modifications (éléments chiffrés + `modifieLe`) et demande « tout ce qui a changé depuis la version N ». Conflit : la date de modification la plus récente l'emporte, et l'ancienne version de post-it part dans l'historique (UC-C3). Le WebSocket ne sert qu'à prévenir « il y a du nouveau » ; les données passent par HTTP. |
| Notifications push | ✅ **Firebase Cloud Messaging** (gratuit, sans quota payant) pour Android et iOS. **Web Push standard (VAPID)** pour le web : gratuit, sans Firebase. Sur desktop, l'app connectée reçoit les événements par WebSocket et programme les rappels localement. |
| E-mails | Un fournisseur transactionnel avec offre gratuite (par exemple Brevo : 300 e-mails par jour), à choisir à l'étape 8. |

## 5. Chiffrement de bout en bout (résumé technique)

Bibliothèque : **libsodium**, la même sur toutes les plateformes, dont le web.

| Clé | Rôle | Protégée par |
|---|---|---|
| Clé maître (256 bits) | chiffre les clés d'éléments et les préférences sensibles | clé de récupération **et** clé de chaque appareil (`EnveloppeCle`) |
| Clé de récupération | dernier recours (A3, I15) | l'utilisateur seul (24 mots) |
| Paire de clés d'appareil (X25519) | recevoir la clé maître d'un autre appareil (I11) | reste sur l'appareil (trousseau sécurisé du système) |
| Clé d'élément | chiffre un élément (XChaCha20-Poly1305) ; permet le lien public en direct | clé maître ; dans le lien après `#`, ou enveloppée par un mot de passe (Argon2id) |
| Mot de passe du compte | **authentification seulement**, haché côté serveur (Argon2id) | — |

## 6. Hébergement (PaaS)

- Trois services issus de la même image Docker (web, worker, beat), plus PostgreSQL et Redis managés.
- ⚠ **Mode Telegram direct sur un PaaS** : chaque fichier passe deux fois par le serveur, à l'envoi puis au téléchargement. Il faut un PaaS sans plafond de bande passante bas, et un disque temporaire pour découper les fichiers de 100 Mo. Choix précis de l'hébergeur à l'étape 8.

## 7. ADR

### ADR-001 : Monolithe modulaire Django
- **Statut** : Proposé
- **Contexte** : développeur seul, ~10 domaines, chiffrement de bout en bout (logique serveur mince), PaaS.
- **Décision** : un seul backend Django découpé en modules par domaine, déployé en 3 processus (web, worker, beat).
- **Alternatives** : microservices (coût d'exploitation trop élevé pour une personne) ; monolithe non structuré (dette rapide).
- **Conséquences** : un seul déploiement et des transactions simples ; extraction possible plus tard du relais de fichiers si la bande passante l'exige.

### ADR-002 : Flutter pour tous les clients
- **Statut** : Proposé
- **Contexte** : 6 plateformes, chiffrement et synchro qui doivent être **strictement identiques** partout.
- **Décision** : une seule app Flutter (Dart) pour le web, le mobile et le desktop.
- **Alternatives** : TypeScript (React + Tauri + React Native) → 3 applications à assembler ; mélange React/Flutter → chiffrement écrit deux fois.
- **Conséquences** : un seul code de chiffrement et de synchro. Flutter Web convient à l'application, mais pas au référencement. ❓ **Je propose une page d'accueil publique (UC-I1) séparée**, en HTML statique. La surveillance du presse-papier desktop repose sur des plugins communautaires, à valider par un prototype dès le début.

### ADR-003 : Django + DRF + Channels + Celery, PostgreSQL, Redis
- **Statut** : Proposé
- **Décision** : DRF pour l'API REST, documentée en OpenAPI ; Channels pour le WebSocket ; Celery pour les tâches.
- **Alternatives** : FastAPI (plus léger, mais l'authentification et l'administration seraient à reconstruire) ; Node (sans intérêt ici puisque les clients sont en Dart).
- **Conséquences** : écosystème mûr (Argon2, administration, migrations). ❓ **Je propose d'utiliser l'interface d'administration Django** pour les cas administrateur (I28, I29, I30) au lieu de développer une interface dédiée. Elle ne voit que des métadonnées, puisque tout le contenu est chiffré.

### ADR-004 : Chiffrement de bout en bout avec libsodium et clés par élément
- **Statut** : Proposé
- **Décision** : le schéma de clés de la section 5.
- **Conséquences** : recherche uniquement locale ; perte définitive des données sans la clé de récupération ni un autre appareil (assumé en A3). **Un audit de sécurité externe du chiffrement est recommandé avant la production.**

### ADR-005 : Synchro par versions + WebSocket de notification
- **Statut** : Proposé
- **Décision** : synchro incrémentale par compteur de version, « dernier gagne » ; le WebSocket sert seulement à signaler qu'il y a du nouveau.
- **Alternatives** : CRDT (fusion fine des modifications, inutile puisque vous avez choisi « dernier gagne ») ; synchro entièrement en WebSocket (plus fragile sur mobile).
- **Conséquences** : simple à tester. Si le WebSocket tombe, l'app continue en interrogeant le serveur à intervalles réguliers.

### ADR-006 : Interface de stockage de fichiers à deux adaptateurs
- **Statut** : Accepté ✅ (décision métier déjà prise)
- **Décision** : une interface `StockageFichiers` avec deux adaptateurs, LuluFiles et Telegram direct, choisis par `FILES_USE_DIRECT_TELEGRAM`. Chaque fichier mémorise son fournisseur.
- **Conséquences** : le mode Telegram impose de découper les fichiers en morceaux de 18 Mo et de faire passer les téléchargements par le backend.

## 8. Décisions du 2026-10-08 ✅

1. Monolithe modulaire et découpage en modules : **validés**.
2. Interface d'administration Django : **validée**. Si elle ne suffit pas, on passera à une interface d'administration personnalisée.
3. Page d'accueil publique séparée, en HTML statique : **validée**.
4. Prototype technique : **à faire maintenant**, avant de figer Flutter (voir `prototype/`).
5. Notifications push : **FCM** pour Android et iOS, **Web Push standard** pour le web, car tous deux sont gratuits.

## 9. Coûts incompressibles (aucune alternative gratuite)

| Poste | Coût | Remarque |
|---|---|---|
| Compte Apple Developer | 99 $ par an | obligatoire pour publier sur l'App Store **et** pour les notifications push iOS |
| Compte Google Play | 25 $, une seule fois | obligatoire pour publier sur le Play Store |
| Nom de domaine | ~10 € par an | indispensable pour un SaaS public (e-mails, liens) |
| Signature de code desktop | facultative | sans elle, Windows et macOS affichent un avertissement à l'installation |
| Hébergement PaaS | gratuit au départ | les offres gratuites mettent le service en veille et limitent la bande passante, ce qui est incompatible avec le mode Telegram direct en production ; à réévaluer à l'étape 8 |

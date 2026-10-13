# LuluBoard — Backend

API de LuluBoard : monolithe modulaire **Django + DRF + Channels + Celery**, PostgreSQL et Redis (voir `../docs/04-architecture.md`).
Le contrat de référence est `../docs/05-contrat-api.md`. Le schéma `../docs/openapi.yaml` est **généré** depuis le code ; il n'est jamais modifié à la main.

## Installation locale (Windows)

Prérequis : Python 3.13, [uv](https://docs.astral.sh/uv/), PostgreSQL 18, Redis (Memurai sous Windows).

```bash
cd backend
uv sync                      # installe les dépendances dans .venv
cp .env.example .env         # puis renseigner les valeurs (déjà fait en local)
```

Création de la base de développement, **une seule fois**, avec le superutilisateur `postgres`. Le script `scripts/creer_base_dev.sql` est généré localement et n'est pas versionné :

```bash
"/c/Program Files/PostgreSQL/18/bin/psql.exe" -U postgres -h localhost -f scripts/creer_base_dev.sql
```

Puis :

```bash
uv run python manage.py migrate
uv run uvicorn config.asgi:application --reload --port 8000
```

## Tests

```bash
uv run pytest
```

Chaque endpoint est livré avec ses tests et cette documentation, dans le même lot.

## Régénérer le schéma OpenAPI

```bash
uv run python manage.py spectacular --file ../docs/openapi.yaml
```

## Variables d'environnement

| Variable | Rôle |
|---|---|
| `DJANGO_SECRET_KEY` | secret Django (obligatoire, le démarrage échoue s'il manque) |
| `DJANGO_DEBUG` | `true` en local uniquement |
| `DJANGO_ALLOWED_HOSTS` | noms d'hôte acceptés, séparés par des virgules |
| `DATABASE_*` | connexion PostgreSQL |
| `REDIS_URL` | Redis : cache, WebSocket, file Celery |
| `FILES_USE_DIRECT_TELEGRAM` | `true` = API Bot Telegram en direct, `false` = LuluFiles (ADR-006) |
| `LULUFILES_BASE_URL`, `LULUFILES_API_KEY` | mode LuluFiles |
| `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHANNEL_ID` | mode Telegram direct |
| `MIN_APP_VERSION` | version minimale des apps clientes (I10) |

## Endpoints livrés

| Lot (contrat) | Route | Statut |
|---|---|---|
| 2.0 | `GET /api/v1/health` | ✅ livré, testé |
| 2.1 | `POST /api/v1/auth/inscription` | ✅ livré, testé |
| 2.1 | `POST /api/v1/auth/renvoyer-code` | ✅ livré, testé |
| 2.1 | `POST /api/v1/auth/inscription/verifier` | ✅ livré, testé |
| 2.1 | `POST /api/v1/auth/google` | ✅ livré, testé |
| 2.1 | `POST /api/v1/compte/cle-recuperation/confirmer` | ✅ livré, testé |
| 2.2 | `POST /api/v1/auth/connexion` | ✅ livré, testé |
| 2.2 | `POST /api/v1/auth/deconnexion` | ✅ livré, testé |
| 2.2 | `POST /api/v1/auth/mot-de-passe/oubli` | ✅ livré, testé |
| 2.2 | `POST /api/v1/auth/mot-de-passe/reinitialiser` | ✅ livré, testé |
| 2.3 | `GET /appareils`, `PATCH`/`DELETE /appareils/{id}`, `GET /appareils/courant/enveloppe`, `POST /appareils/courant/deverrouillage`, `GET /deverrouillages/en-attente`, `POST /deverrouillages/{id}/approuver`, `POST /deverrouillages/{id}/refuser`, `GET`/`PUT /compte/enveloppe-recuperation`, `POST /appareils/courant/deverrouiller-par-recuperation` | ✅ livré, testé |
| 2.4 | `GET`/`PATCH`/`DELETE /compte`, `POST /compte/mot-de-passe`, `POST /compte/email`, `POST /compte/email/verifier`, `POST`/`DELETE /compte/google`, `GET`/`PUT /compte/preferences`, `GET`/`PUT /appareils/courant/preferences`, `GET /conditions/actuelles`, `POST /conditions/accepter` | ✅ livré, testé |
| 2.5 | `GET /synchro/changements`, `POST /synchro/envoyer` | ✅ livré, testé |
| 2.6 | WebSocket `/api/v1/ws` | ✅ livré, testé |
| 2.7 | `POST /fichiers`, `GET /fichiers/{id}`, `GET /fichiers/{id}/acces`, `GET /fichiers/{id}/contenu`, `POST /fichiers/{id}/reessayer` | ✅ livré, testé |
| 2.8 | `POST /envois`, `GET /envois/recus`, `POST /envois/{id}/recupere` | ✅ livré, testé |
| 2.9 | `GET`/`POST /liens`, `PATCH`/`DELETE /liens/{id}` | ✅ livré, testé |
| 2.10 | `GET /public/liens/{jeton}`, `POST …/deverrouiller`, `GET …/fichier`, `POST …/signalements` | ✅ livré, testé |
| 2.11 | `GET /annonces/actives`, `POST /support`, `GET /export` | ✅ livré, testé |
| 2.12 | Administration Django `/admin/` (signalements, suspensions, annonces, conditions, support) | ✅ livré |

### `GET /api/v1/health` (public)

Indique si l'API et ses dépendances fonctionnent.

```json
{ "statut": "ok", "version": "0.1.0", "verifications": { "base": true, "redis": true, "stockage": true } }
```

- `statut` : `ok` si tout répond, `degrade` sinon.
- HTTP `200`, sauf **`503` quand la base de données est injoignable**, pour que l'hébergeur détecte la panne. Précision ajoutée au contrat.
- `stockage` teste le fournisseur actif (`getMe` sur Telegram ou `/health` de LuluFiles). Le résultat est mis en cache 60 s.
- Aucune donnée sensible : ni configuration, ni message d'erreur interne. Le jeton Telegram n'est jamais journalisé.

### Conventions communes (déjà en place)

- **Format d'erreur unique** `{ "erreur": { "code", "message", "champs"?, "requestId" } }` (`commun/erreurs.py`).
- **`X-Request-ID`** sur chaque réponse, repris dans les journaux (`commun/middleware.py`). Une valeur fournie par le client n'est reprise que si son format est sûr.
- Mots de passe hachés en **Argon2**.

## Lot 2.1 — Inscription et vérification

Les corps de requête et de réponse sont ceux du contrat (`docs/05-contrat-api.md`, section 2.1).

### Précisions apportées au contrat
- **Réinscription** : un e-mail inscrit mais jamais vérifié peut être réinscrit (le nom et le mot de passe sont remplacés, un nouveau code est envoyé).
- **Google ne fusionne jamais automatiquement** avec un compte e-mail existant : `409 email_deja_utilise`, puis liaison depuis les réglages (I16).
- **Clé de récupération (option a)** : obligatoire pour un compte e-mail (`403 cle_recuperation_non_confirmee` sur les routes 🔐), reportable pour un compte lié à Google.
- `X-App-Version` absent : la requête est acceptée (pages publiques, outils de test).

### Sessions et accès
- `Authorization: Bearer <jeton>` : jeton opaque de 256 bits, stocké **haché** (SHA-256), avec une expiration glissante de 30 jours.
- Par défaut, toute route est 🔐 (`AppareilDeverrouille`) ; les routes publiques le déclarent explicitement.

### Revue de sécurité (checklist lucio-dev)
| Catégorie | Mesure |
|---|---|
| Contrôle d'accès | permission 🔐 par défaut ; appareil révoqué → 403 ; compte suspendu → 403 ; la session est liée à un appareil |
| Injection | ORM uniquement, aucune requête SQL construite à la main |
| Côté serveur | aucune URL fournie par le client n'est appelée ; le jeton Google est vérifié par la bibliothèque officielle (signature, audience, émetteur, e-mail vérifié) |
| Côté client | API JSON uniquement ; `Cache-Control: no-store` sur les réponses qui contiennent un jeton |
| Logique métier | code valable 15 min et 5 essais, comptés même en cas d'échec (transaction séparée) ; consommation du code et activation protégées par `select_for_update` ; plafond de 3 appareils |
| Authentification | Argon2 pour les mots de passe ; codes stockés en HMAC-SHA256 ; limitation de débit sur l'inscription, la vérification, le renvoi de code et Google ; réponses identiques pour un e-mail inconnu |
| Configuration | secrets dans `.env` (non versionné) ; erreurs au format commun, sans trace interne |
| API | sérialiseurs explicites (pas d'affectation massive : `role`/`statut` ignorés, testé) ; tailles des clés contrôlées après décodage |

## Lot 2.2 — Connexion, déconnexion, mot de passe oublié

### Précisions apportées au contrat
- **Compte jamais vérifié + bon mot de passe** → `403 email_non_verifie`, et un nouveau code d'inscription est envoyé. Avec un mauvais mot de passe, la réponse reste `401 identifiants_incorrects` : rien n'est révélé.
- **Réinitialisation** → `204` sans corps. Le rappel « données lisibles seulement avec la clé de récupération ou un autre appareil » (A3) est affiché par l'app, qui le connaît d'avance.
- Après une réinitialisation, **toutes les sessions sont fermées**, mais les appareils déjà déverrouillés restent ACTIF : ils gardent leur clé locale et retrouvent l'accès en se reconnectant.
- Se connecter avec `{ appareilId }` **remplace** la session de cet appareil (l'ancien jeton cesse de fonctionner).
- Un compte Google sans mot de passe ne peut pas se connecter par mot de passe (`401`), mais peut en définir un via « mot de passe oublié ».

### Revue de sécurité
| Catégorie | Mesure |
|---|---|
| Contrôle d'accès | un `appareilId` d'un autre compte → `404` ; appareil révoqué → `403` |
| Authentification | 5 échecs en 15 min par adresse → `423` pendant 15 min (même avec le bon mot de passe) ; compteur remis à zéro après un succès ou une réinitialisation ; limite supplémentaire par IP |
| Énumération de comptes | e-mail inconnu, mauvais mot de passe ou compte Google seul : même code, même message et **même coût de calcul** (hash Argon2 factice) ; « mot de passe oublié » répond toujours `204` |
| Logique métier | un code d'inscription n'est pas accepté pour réinitialiser un mot de passe (types séparés) ; 5 essais par code |
| Session | la déconnexion supprime la session côté serveur (le jeton devient invalide immédiatement) |

## Lot 2.3 — Appareils et clés

- **Déverrouillage par un autre appareil** : le nouvel appareil crée une demande (code à 6 chiffres, 10 min) ; l'appareil actif voit la demande **sans le code**, avec la clé publique du demandeur, et doit recopier le code affiché (5 essais). Il envoie la clé maître enveloppée pour cette clé publique.
- **Déverrouillage par la clé de récupération** : `GET /compte/enveloppe-recuperation` renvoie l'enveloppe + un **défi** (32 octets, 5 min, usage unique) ; le client signe le défi avec la clé Ed25519 dérivée de la clé maître ; le serveur vérifie avec `Compte.clePubliqueVerification` (PyNaCl).
- **Révocation** : session supprimée, enveloppe invalidée **et vidée**, événement `appareil_revoque`. Refuser une demande révoque le demandeur.
- **Régénération** : mot de passe exigé (ou jeton Google pour un compte sans mot de passe), l'ancienne enveloppe est vidée, la confirmation de sauvegarde est remise à zéro.
- Événements temps réel publiés **après validation** de la transaction (`commun/evenements.py`).

Revue de sécurité : contrôle d'accès par compte sur chaque identifiant (404 sinon) ; un appareil non déverrouillé ne peut ni approuver ni révoquer ; preuve cryptographique de possession de la clé maître ; défis à usage unique ; comparaisons en temps constant.

## Lot 2.4 — Compte, préférences, conditions

- Changer d'e-mail : code envoyé à la **nouvelle** adresse, alerte à l'**ancienne** ; le changement ne prend effet qu'après le code.
- Suppression : statut `SUPPRESSION_PROGRAMMEE` pendant 30 jours ; se reconnecter l'annule (lot 2.2) ; l'effacement définitif est fait par une tâche planifiée (lot « tâches »).
- Préférences d'appareil : le jeton push est accepté en écriture seulement ; `SECURITE` reste toujours active.
- Nouvelles conditions publiées → toutes les routes 🔐 répondent `403 conditions_a_accepter`, sauf `GET`/`PATCH`/`DELETE /compte` et `/conditions/*`.

## Lot 2.5 — Synchronisation

- Un compteur de version par compte, verrouillé pendant l'application d'un lot : les envois concurrents d'un même compte sont sérialisés.
- « La dernière modification gagne » (`modifieLe`) ; une suppression est définitive et efface le contenu du serveur.
- Le serveur archive l'ancienne version d'un post-it à chaque modification, ainsi que la version perdante d'un conflit (événement `conflit`).
- Contrôles : identifiant d'un autre compte → `rejete/introuvable` (sans rien révéler) ; type immuable ; un fichier ne se crée jamais par la synchro ; presse-papier limité à 100 Ko (texte) ou 5 Mo (image), autres éléments à 10 Mo.

## Lot 2.6 — WebSocket

`ws(s)://<hôte>/api/v1/ws` : envoyer `{"type":"auth","jeton":"…"}` dans les 10 s → `{"type":"pret"}`, puis réception des événements du contrat (sans contenu). `ping` → `pong`.

## Lot 2.7 — Fichiers

- Le client envoie les octets **déjà chiffrés** ; le serveur les écrit dans un fichier temporaire, crée l'élément `FICHIER` (visible par la synchro), puis une tâche Celery les transfère.
- **Telegram direct** : morceaux de 18 Mo (`sendDocument`), SHA-256 par morceau vérifié à la relecture, reprise au premier morceau manquant en cas d'échec.
- **LuluFiles** : envoi, attente du statut `ready`, puis lien signé (si `LULUFILES_CORS_OUVERT=true`) ou flux via notre serveur.
- `GET /fichiers/{id}/contenu` prend en charge `Range` (`206`, `416`).
- Supprimer l'élément (synchro) efface les morceaux chez le fournisseur.

Lancer un worker en production : `uv run celery -A config worker -l info` (et `beat` pour les tâches planifiées).

## Lots 2.8 à 2.12

- **Envois** : vers un appareil précis ou vers tous les autres ; conservés 7 jours ; push + événement `envoi_recu`.
- **Liens publics** : contenu **en direct** (version actuelle de l'élément, avec toutes les tâches d'une liste) ; protection par mot de passe vérifiée **côté serveur** (5 essais par IP et par lien, puis 15 min de blocage) ; jeton court signé (10 min) pour télécharger le fichier d'un lien protégé ; réponse identique (`410`) pour un lien inexistant, expiré, révoqué ou désactivé.
- **Modération** (`/admin/`) : classer sans suite, désactiver le lien, suspendre le compte (sessions fermées, e-mail au propriétaire), lever une suspension.
- **Push** (`commun/push.py`) : FCM HTTP v1 ; ignoré proprement tant que `FCM_PROJECT_ID` et `FCM_FICHIER_COMPTE_SERVICE` ne sont pas renseignés.

## Tâches planifiées (Celery Beat)

| Tâche | Fréquence |
|---|---|
| Envoi des rappels dus, calcul de la prochaine occurrence | 1 min |
| Purge de rétention (presse-papier, versions de post-it) | 5 min |
| Suppression des comptes dont le délai de grâce est échu | 1 h |
| Ménage (sessions expirées, demandes et envois expirés) | 1 h |
| Inactivité (avertissement à 12 mois, suppression 30 jours plus tard) ; comptes jamais vérifiés depuis 7 jours | 24 h |

`uv run celery -A config worker -l info` et `uv run celery -A config beat -l info`.

## Déploiement (Render)

Le Blueprint `../render.yaml` crée l'API (`luluboard-api`), PostgreSQL (`luluboard-db`), Redis (`luluboard-redis`) et le site public (`luluboard-site`).
Création : dashboard Render → *New* → *Blueprint* → dépôt `LostedGhost/Board` ; les secrets marqués `sync: false` sont demandés à ce moment-là.

- Build : `deploy/render_build.sh` (`uv sync`, `collectstatic`).
- Démarrage : `deploy/render_start.sh` (migrations, premier administrateur, worker Celery + beat en arrière-plan, uvicorn).
- Base de données : `DATABASE_URL` est prioritaire sur les `DATABASE_*`. Pour passer sur Neon, remplacer sa valeur par l'URL Neon (avec `?sslmode=require`).

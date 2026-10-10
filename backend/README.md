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

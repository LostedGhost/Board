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

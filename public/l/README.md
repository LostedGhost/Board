# Page publique des liens LuluBoard (`/l/<jeton>#<clé>`)

Page statique autonome : déchiffre dans le navigateur (libsodium sumo, `sodium.js`) le contenu d'un lien public (contrat 2.10, format v1 `docs/07-format-chiffrement.md`).

## Configuration
- `config.js` : `apiUrl` (défaut `http://127.0.0.1:8000`, `""` = même origine) et `accueilUrl`.
- `index.html` : garder la directive CSP `connect-src` cohérente avec `apiUrl` (+ hôte LuluFiles si `LULUFILES_CORS_OUVERT=true`, car le téléchargement suit une redirection 302 vers un lien signé).

## Déploiement
- Réécriture obligatoire : `/l/*` → `/l/index.html` (ex. Nginx `location /l/ { try_files $uri /l/index.html; }`). Les ressources sont référencées en absolu (`/l/app.js`…).
- Repli sans réécriture : `/l/?t=<jeton>#<clé>`.
- `app/lib/noyau/config.dart` construit les URL sur `API_URL/l/<jeton>` : en prod, soit le backend (ou le proxy devant lui) sert ce dossier sous `/l/`, soit il faut faire pointer `lienPublic` vers le domaine qui l'héberge.
- CORS : si la page n'est pas servie par la même origine que l'API, ajouter son origine à `CORS_ALLOWED_ORIGINS` du backend (ex. `https://luluboard.example`).
- Servir avec `Referrer-Policy: no-referrer` et `Cache-Control: no-store` conseillés.

## Test local
```bash
cd backend && CORS_ALLOWED_ORIGINS=http://127.0.0.1:5191 EMAIL_BACKEND=django.core.mail.backends.filebased.EmailBackend EMAIL_FILE_PATH=e2e_mails uv run python manage.py runserver 8000
cd public && python -m http.server 5191
cd backend && uv run python e2e/liens_page_publique.py http://127.0.0.1:8000 e2e_mails   # imprime les URL
```

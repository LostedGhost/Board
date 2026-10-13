# Suivi de projet — Board

Chaque case cochée correspond à un artefact réellement produit et validé, pas juste "commencé".

- [x] **1. Cas d'utilisation** — liste complète, validée explicitement le 2026-10-08 → `docs/01-cas-utilisation.md` (68 cas)
- [x] **2. Diagrammes UML** — validés le 2026-10-08 → `docs/02-uml-cas-utilisation.md`, `docs/03-uml-classes.md`
- [x] **3. Choix technique et contrat d'API** — validés le 2026-10-09 → `docs/04-architecture.md`, `docs/05-contrat-api.md` (prototype Flutter encore à faire pour confirmer l'ADR-002)
- [x] **4. Backend** — 2026-10-10 : tout le contrat livré (lots 2.0 à 2.12), 165 tests, `backend/README.md`
- [x] **5. Validation complète du backend** — 2026-10-10 : scénario de bout en bout (18 étapes) + bandit + pip-audit → `docs/08-validation-backend.md`
- [x] **6. Frontend** — 2026-10-10 : application Flutter livrée (`app/`), noyau chiffré libsodium, base locale Sembast, synchro hors ligne, tous modules fonctionnels, page d'accueil publique HTML statique → `public/index.html`
- [ ] **7. Intégration** — backend et frontend réels connectés, écarts corrigés
- [ ] **8. Déploiement** — application déployée et vérifiée en conditions réelles (sans Docker, ADR D51)

## Cadrage (2026-10-08)

- Supports : web, mobile, desktop
- Modèle : produit public (SaaS), à lancer
- Services souhaités : historique presse-papier, post-it/notes, partage entre appareils, snippets/to-do/rappels, envoi de fichiers légers (stockage "Lulufiles")

## Notes / écarts assumés

- 2026-10-08 — Périmètre V1 large assumé : presque tous les services, plus le chiffrement de bout en bout et le hors ligne dès la V1. Risque accepté : V1 plus longue à livrer. Seuls le Premium et l'expansion de snippets sont reportés.
- 2026-10-10 — Déploiement sans Docker (D51) : déploiement en direct via PaaS natif Python/Node ou serveur sans conteneurisation.

## Frontend — état 2026-10-10

- Application Flutter complète (`app/`, package `luluboard`).
- Noyau : crypto (libsodium patché VS2019 D44), stockage local Sembast (D38), synchro incrémentale, API HTTP + WebSocket + session.
- Fonctionnalités : onboarding/auth, tableau de post-it, recherche globale, réglages, presse-papier, tâches, snippets, rappels, fichiers, envois, liens publics, appareils.
- Page d'accueil publique séparée (ADR-002) → `public/index.html`.
- À faire : intégration backend réel, tests de synchronisation croisés, déploiement.
## Design system et UX — état 2026-10-13

- Design system LuluFiles appliqué à l'app (jetons `Lulu` dans `app/lib/ui/theme.dart`) et à la page d'accueil ; polices Rubik/Itim embarquées (D52), contraste AA testé (D53).
- Esprit UX généralisé (D54) : filtre en direct + surlignage + Ctrl+F/Échap sur chaque écran, confirmations explicites, messages avec action suivante, accessibilité des écrans de compte (clé de récupération lisible par lecteur d'écran, codes à 6 chiffres).
- Page de consultation des liens publics `public/l/` (D55), pages `confidentialite.html` et `conditions.html` (champs éditeur/hébergeur à compléter avant lancement).
- Fonctionnalités ajoutées (D56–D64) : mentions `[[…]]` (H6), glisser-déposer entre sections (H5), étiquettes chiffrées + filtre `#` (H7), notes de tâches, « Déplacer » à la transformation, écran d'aide (I22), bandeau d'annonces (I30), signalement et renouvellement de jeton sur `public/l/` (I20).
- Reste avant lancement : mentions légales et e-mail de support à compléter, identifiants de stockage dans `.env`, service de `public/l/` sous `API_URL/l/`, test d'approbation d'un second appareil, étape 8 (déploiement).

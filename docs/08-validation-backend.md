# LuluBoard — Validation complète du backend (étape 5)

Date : 2026-10-10. Résultat : **validé**.

## 1. Tests automatisés

`uv run pytest` → **165 tests réussis** : chaque route du contrat, chaque cas d'erreur, l'isolation entre comptes, les tâches planifiées.

## 2. Scénario de bout en bout contre le serveur réel

`backend/e2e/scenario.py` lance contre un serveur `uvicorn` réellement démarré (PostgreSQL + Redis/Memurai) un parcours complet, **avec la vraie cryptographie** du format v1 (`docs/07`, implémentation de référence `backend/e2e/crypto.py`) :

| # | Étape | Résultat |
|---|---|---|
| 1 | Santé (base, Redis) | ✅ |
| 2-3 | Inscription, code lu dans l'e-mail, clé maître, enveloppes, clé de vérification | ✅ |
| 4 | Synchro refusée tant que la clé de récupération n'est pas confirmée | ✅ |
| 5 | Ouverture de l'enveloppe de l'appareil (`crypto_box_seal`) | ✅ |
| 6 | Tableau et post-it chiffrés, envoyés par la synchro | ✅ |
| 7 | Nouvel appareil, code à recopier, approbation, clé maître transmise | ✅ |
| 8 | Le second appareil tire les changements et **déchiffre** le post-it | ✅ |
| 9 | WebSocket : le premier appareil est prévenu en temps réel | ✅ |
| 10 | Historique des versions : l'ancienne version reste déchiffrable | ✅ |
| 11 | Lien public sans mot de passe, déchiffré avec la clé du fragment, **en direct** | ✅ |
| 12 | Lien protégé (Argon2id, vérificateur contrôlé par le serveur) | ✅ |
| 13 | Déverrouillage par la clé de récupération (signature Ed25519 du défi) | ✅ |
| 14 | Limite de 3 appareils | ✅ |
| 15 | Envoi chiffré d'un appareil à l'autre | ✅ |
| 16 | Révocation : la session de l'appareil révoqué cesse de fonctionner | ✅ |
| 17 | Export des données chiffrées | ✅ |
| 18 | Suppression programmée puis annulée par reconnexion | ✅ |

Non couvert par ce scénario : le transfert réel de fichiers vers Telegram ou LuluFiles, qui demande un bot Telegram (ou une clé LuluFiles) ; couvert par des tests avec un faux Telegram.

## 3. Sécurité

| Outil | Résultat |
|---|---|
| `bandit` (analyse statique, 4 206 lignes) | 1 alerte faible (exception ignorée lors d'une écriture en cache) → corrigée ; 0 alerte moyenne ou haute |
| `pip-audit` (dépendances de production) | **aucune vulnérabilité connue** |
| `manage.py check --deploy` | seule remarque restante : `SECURE_HSTS_PRELOAD` (inscription facultative à la liste de préchargement HSTS des navigateurs) |
| Checklist lucio-dev | passée lot par lot (voir `backend/README.md`) |

**Recommandation maintenue** (ADR-004) : un audit externe du chiffrement avant l'ouverture publique.

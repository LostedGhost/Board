# Suivi de projet — Board

Chaque case cochée correspond à un artefact réellement produit et validé, pas juste "commencé".

- [x] **1. Cas d'utilisation** — liste complète, validée explicitement le 2026-10-08 → `docs/01-cas-utilisation.md` (68 cas)
- [x] **2. Diagrammes UML** — validés le 2026-10-08 → `docs/02-uml-cas-utilisation.md`, `docs/03-uml-classes.md`
- [x] **3. Choix technique et contrat d'API** — validés le 2026-10-09 → `docs/04-architecture.md`, `docs/05-contrat-api.md` (prototype Flutter encore à faire pour confirmer l'ADR-002)
- [ ] **4. Backend** — tous les endpoints développés, testés et documentés, un par un
- [ ] **5. Validation complète du backend** — test de bout en bout réalisé (Postman ou équivalent)
- [ ] **6. Frontend** — design system, composants de base et pages validés sur données mock
- [ ] **7. Intégration** — backend et frontend réels connectés, écarts corrigés
- [ ] **8. Déploiement** — application déployée et vérifiée en conditions réelles

## Cadrage (2026-10-08)

- Supports : web, mobile, desktop
- Modèle : produit public (SaaS), à lancer
- Services souhaités : historique presse-papier, post-it/notes, partage entre appareils, snippets/to-do/rappels, envoi de fichiers légers (stockage "Lulufiles")

## Notes / écarts assumés

- 2026-10-08 — Périmètre V1 large assumé : presque tous les services, plus le chiffrement de bout en bout et le hors ligne dès la V1. Risque accepté : V1 plus longue à livrer. Seuls le Premium et l'expansion de snippets sont reportés.

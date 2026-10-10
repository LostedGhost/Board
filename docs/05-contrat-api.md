# LuluBoard — Contrat d'API v1 (VALIDÉ le 2026-10-09)

> Étape 3 de la méthode, seconde partie. Ce contrat est dérivé du diagramme de classes validé (`03-uml-classes.md`) et de l'architecture validée (`04-architecture.md`).
> **Règle** : aucun endpoint n'est développé à l'étape 4 s'il ne figure pas ici. Toute modification passe par une mise à jour validée de ce document.
> Le fichier OpenAPI (`openapi.yaml`) sera généré depuis le code par drf-spectacular, puis vérifié par les tests contre ce document.

---

## 1. Conventions générales

| Sujet | Règle |
|---|---|
| Base | `https://api.<domaine>/api/v1` |
| Format | JSON en UTF-8, noms de champs en `camelCase` français (comme le diagramme de classes) |
| Dates | ISO 8601 en UTC (`2026-10-09T14:03:00Z`) |
| Identifiants | UUID. **Les éléments, tableaux, étiquettes et rappels sont créés hors ligne : leur UUID est généré par le client** (UUID v7). Les autres identifiants viennent du serveur. |
| Données chiffrées | chaînes **base64url** sans remplissage. Le serveur ne les interprète jamais. |
| Authentification | `Authorization: Bearer <jeton de session>`. Jeton opaque de 256 bits, que le serveur ne stocke que sous forme hachée (`Session.jetonHash`). La session expire après 30 jours sans activité (I17), et chaque requête prolonge ce délai. |
| Appareil courant | déduit du jeton de session : chaque session appartient à un seul appareil |
| Pagination | par curseur : `?curseur=…&limite=…` → `{ "elements": [...], "curseurSuivant": "…" | null }` |
| Limitation de débit | `429` + en-tête `Retry-After`. Plafonds par adresse IP sur les routes publiques et d'authentification. |
| Langue des messages | selon l'en-tête `Accept-Language` (`fr` ou `en`) |
| Traçabilité | chaque réponse porte `X-Request-ID`. **Les journaux ne contiennent jamais de contenu, de jeton ni de clé.** |

### Format d'erreur unique

```json
{
  "erreur": {
    "code": "limite_appareils",
    "message": "Vous avez déjà 3 appareils actifs. Révoquez-en un pour continuer.",
    "champs": [{ "champ": "email", "raison": "deja_utilise" }],
    "requestId": "0b7c2f…"
  }
}
```

Le client se fie à `code` (stable dans le temps), jamais à `message`.

| HTTP | Codes d'erreur possibles |
|---|---|
| 400 | `requete_invalide` |
| 401 | `non_authentifie`, `session_expiree`, `identifiants_incorrects` |
| 403 | `interdit`, `email_non_verifie`, `cle_recuperation_non_confirmee`, `compte_suspendu`, `appareil_revoque`, `appareil_non_deverrouille`, `conditions_a_accepter`, `reserve_aux_comptes` |
| 404 | `introuvable` (y compris pour la ressource d'un autre compte, pour ne pas révéler qu'elle existe) |
| 409 | `email_deja_utilise`, `limite_appareils`, `deja_traite`, `version_client_obsolete` |
| 410 | `code_expire`, `lien_expire` |
| 413 | `fichier_trop_volumineux` (plus de 100 Mo) |
| 422 | `validation` (accompagné du tableau `champs`) |
| 423 | `connexion_bloquee` (5 échecs en 15 min, A2), `lien_bloque` (I19) |
| 426 | `mise_a_jour_requise` (I10) |
| 429 | `trop_de_requetes` |
| 502 / 503 | `stockage_indisponible`, `service_indisponible` |

Chaque client envoie `X-App-Version` à chaque requête. Si sa version est trop ancienne pour le serveur, la réponse est `426` (I10).

---

## 2. Endpoints, dans l'ordre de développement (étape 4)

Légende : 🔓 = sans authentification · 🔑 = session requise · 🔐 = session + appareil déverrouillé (ACTIF)

### 2.0 Santé
| Méthode | Route | | Description |
|---|---|---|---|
| GET | `/health` | 🔓 | `{ "statut": "ok" \| "degrade", "version": "…", "verifications": { "base": true, "redis": true, "stockage": true } }` HTTP `200`, ou `503` si la base est injoignable (précision du 2026-10-10). |

### 2.1 Inscription et vérification (A1, A1b)
| Méthode | Route | | Corps → Réponse |
|---|---|---|---|
| POST | `/auth/inscription` | 🔓 | `{ email, nomAffichage, motDePasse, conditionsAcceptees: [versionId] }` → `201 { compteId }`. Envoie le code à 6 chiffres (valable 15 min). Erreurs : `422` (format de l'e-mail, mot de passe faible), `409 email_deja_utilise`. |
| POST | `/auth/renvoyer-code` | 🔓 | `{ email, type }` → `204`. Répond toujours `204`, pour ne pas révéler si le compte existe. |
| POST | `/auth/inscription/verifier` | 🔓 | `{ email, code, appareil: AppareilNouveau, cles: ClesInitiales }` → `201 { session: SessionDTO, compte: CompteDTO, appareil: AppareilDTO }`. Le compte passe à ACTIF, le premier appareil est ACTIF. Erreurs : `410 code_expire`, `422` (code faux, avec le nombre d'essais restants). |
| POST | `/auth/google` | 🔓 | `{ idTokenGoogle, appareil: AppareilNouveau, conditionsAcceptees?, cles?: ClesInitiales }` → `200 { session, compte, appareil, nouveauCompte: bool }`. Un nouveau compte doit fournir `cles` (A1b). |
| POST | `/compte/cle-recuperation/confirmer` | 🔐 | → `204`. Renseigne `cleRecuperationConfirmeeLe` (A1, I4). **Inscription par e-mail** : obligatoire, et toutes les autres routes 🔐 répondent `403 cle_recuperation_non_confirmee` tant qu'elle n'est pas faite. **Compte Google** : peut être reportée, avec le rappel I4 ✅. |

### 2.2 Connexion et session (A2, A3, I17, I26)
| Méthode | Route | | Corps → Réponse |
|---|---|---|---|
| POST | `/auth/connexion` | 🔓 | `{ email, motDePasse, appareil: AppareilNouveau \| { appareilId } }` → `200 { session, compte, appareil }`. Un nouvel appareil reçoit le statut `EN_ATTENTE_DEVERROUILLAGE`. Si le compte était en suppression programmée, celle-ci est **annulée** (I26). Erreurs : `401 identifiants_incorrects`, `423 connexion_bloquee`, `409 limite_appareils` (avec la liste des appareils dans `details`, I11), `403 compte_suspendu` (avec le motif, I24). |
| POST | `/auth/deconnexion` | 🔑 | → `204` |
| POST | `/auth/mot-de-passe/oubli` | 🔓 | `{ email }` → `204`, toujours |
| POST | `/auth/mot-de-passe/reinitialiser` | 🔓 | `{ email, code, nouveauMotDePasse }` → `204`. Toutes les sessions sont fermées. Le serveur rappelle dans la réponse que seuls la clé de récupération ou un autre appareil permettent de relire les données (A3). |

### 2.3 Appareils et clés (A4, I11, I12, I15)
| Méthode | Route | | Corps → Réponse |
|---|---|---|---|
| GET | `/appareils` | 🔑 | → `[AppareilDTO]`, l'appareil courant étant marqué `courant: true` |
| PATCH | `/appareils/{id}` | 🔐 | `{ nom }` → `AppareilDTO` |
| DELETE | `/appareils/{id}` | 🔐 | → `204`. Révoque l'appareil (I12) : sa session est fermée et son enveloppe de clé invalidée. Les autres appareils reçoivent l'événement `appareil_revoque`. |
| GET | `/appareils/courant/enveloppe` | 🔐 | → `{ cleMaitreEnveloppee }`, l'enveloppe de l'appareil courant |
| POST | `/appareils/courant/deverrouillage` | 🔑 | → `201 DemandeDeverrouillageDTO { id, codeAffiche, expireLe }`. Créée par le **nouvel** appareil (I11). Les appareils actifs sont prévenus par WebSocket et par notification push. |
| GET | `/deverrouillages/en-attente` | 🔐 | → `[DemandeDeverrouillageDTO + appareil demandeur]` |
| POST | `/deverrouillages/{id}/approuver` | 🔐 | `{ codeAffiche, cleMaitreEnveloppee }` (clé maître chiffrée pour la clé publique du nouvel appareil) → `204`. Le nouvel appareil passe ACTIF. Erreurs : `422` si le code ne correspond pas, `410` si la demande a expiré. |
| POST | `/deverrouillages/{id}/refuser` | 🔐 | → `204` |
| GET | `/compte/enveloppe-recuperation` | 🔑 | → `{ cleMaitreEnveloppee, defi }`, pour déverrouiller avec la clé de récupération |
| POST | `/appareils/courant/deverrouiller-par-recuperation` | 🔑 | `{ cleMaitreEnveloppee, signatureDefi }` → `204`. Le nouvel appareil prouve qu'il détient la clé maître (voir l'ajout n° 1 au modèle), puis passe ACTIF. |
| PUT | `/compte/enveloppe-recuperation` | 🔐 | `{ motDePasse, cleMaitreEnveloppee }` → `204`. Régénère la clé de récupération et invalide l'ancienne (I15). |

### 2.4 Compte et préférences (A5, A6, I8, I13, I14, I16, I23)
| Méthode | Route | | Corps → Réponse |
|---|---|---|---|
| GET | `/compte` | 🔑 | → `CompteDTO` (avec `conditionsAAccepter: [VersionConditionsDTO]`) |
| PATCH | `/compte` | 🔐 | `{ nomAffichage }` → `CompteDTO` |
| POST | `/compte/mot-de-passe` | 🔐 | `{ ancienMotDePasse, nouveauMotDePasse, deconnecterAutresAppareils }` → `204` |
| POST | `/compte/email` | 🔐 | `{ nouvelEmail, motDePasse }` → `204`. Un code part vers la nouvelle adresse et une alerte vers l'ancienne. |
| POST | `/compte/email/verifier` | 🔐 | `{ code }` → `CompteDTO` |
| POST | `/compte/google` | 🔐 | `{ idTokenGoogle }` → `204` (lier) |
| DELETE | `/compte/google` | 🔐 | → `204`. `409` si le compte n'a pas de mot de passe (I16). |
| DELETE | `/compte` | 🔐 | `{ motDePasse }` → `200 { suppressionPrevueLe }` (délai de grâce de 30 jours, A5) |
| GET / PUT | `/compte/preferences` | 🔐 | `PreferencesCompteDTO` |
| GET / PUT | `/appareils/courant/preferences` | 🔐 | `PreferencesAppareilDTO` (inclut le jeton de notification push, voir l'ajout n° 2 au modèle) |
| GET | `/conditions/actuelles` | 🔓 | → `[VersionConditionsDTO]` |
| POST | `/conditions/accepter` | 🔑 | `{ versionIds: [] }` → `204` (G4, I23) |

Tant que des conditions restent à accepter, toutes les routes 🔐 répondent `403 conditions_a_accepter`, sauf `/compte`, `/conditions/*`, `/auth/deconnexion` et l'export.

### 2.5 Synchronisation (G1, I5, I6, C3) — le cœur du système

Une seule paire de routes synchronise **tout** ce que le client crée hors ligne : éléments, tableaux, étiquettes, liaisons élément-étiquette, rappels et versions de post-it.

| Méthode | Route | | Corps → Réponse |
|---|---|---|---|
| GET | `/synchro/changements?depuis={version}&limite=500` | 🔐 | → `{ versionCourante, changements: [ChangementDTO], encore: bool }` |
| POST | `/synchro/envoyer` | 🔐 | `{ changements: [ChangementDTO] }` (500 au maximum) → `{ versionCourante, resultats: [{ entite, id, statut: "accepte" \| "ecrase_par_plus_recent" \| "rejete", versionServeur?, code? }] }` |

**ChangementDTO**
```json
{
  "entite": "element | tableau | etiquette | element_etiquette | rappel | version_post_it",
  "id": "uuid",
  "version": 1842,
  "modifieLe": "2026-10-09T14:03:00Z",
  "supprimeLe": null,
  "donnees": { }
}
```

Contenu de `donnees` selon l'entité, avec exactement les mêmes champs que le diagramme de classes :

| Entité | Champs **lisibles par le serveur** | Champ chiffré |
|---|---|---|
| element | `type`, `parentId` (tableau d'un post-it, liste d'une tâche, tâche parente), `elementSourceId`, `epingleAccesRapide`, `epingle` (presse-papier), `typeContenu` (presse-papier), `archive` (post-it), `appareilAuteurId`, `cleElementEnveloppee` (vide pour une tâche) | `contenuChiffre` : regroupe tous les attributs `Chiffre~…~` de la sous-classe |
| tableau | — | `contenuChiffre` (nom, ordre) |
| etiquette | — | `contenuChiffre` (nom) |
| element_etiquette | `elementId`, `etiquetteId` | — |
| rappel | `elementId`, `prochaineEcheance`, `recurrence`, `joursSemaine`, `fuseauHoraire`, `actif` | — |
| version_post_it | `postItId`, `appareilAuteurId` | `contenuChiffre` |

**Règles du serveur**
- « Dernier gagne » : un changement dont `modifieLe` est **plus ancien** que la version stockée reçoit `ecrase_par_plus_recent`. Pour un post-it, son contenu est alors conservé dans l'historique, en `version_post_it`, et l'événement de conflit est émis (I6).
- Un changement plus récent incrémente le compteur `version` du compte, et le serveur prévient les autres appareils par WebSocket.
- `supprimeLe` renseigné = suppression définitive propagée à tous les appareils (pas de corbeille).
- Le serveur purge lui-même les entrées de presse-papier non épinglées et les versions de post-it selon les durées de conservation du compte (B4, C3). Ces purges sont publiées comme des suppressions.
- Un **fichier** ne se crée jamais par la synchro : il passe par `/fichiers` (2.7). Sa suppression, en revanche, passe par la synchro, et le serveur l'efface alors chez le fournisseur de stockage.
- Taille maximale de `contenuChiffre` : 100 Ko pour un élément de presse-papier texte, 5 Mo pour une image (B1). Tous les autres éléments sont plafonnés à **10 Mo chiffrés** ✅ (soit plusieurs millions de caractères) ; au-delà, `413` avec la suggestion de passer par un fichier.

### 2.6 WebSocket temps réel
`GET /ws` (passage en WebSocket), avec le jeton envoyé dans le premier message `{ "type": "auth", "jeton": "…" }`. Le jeton n'est jamais placé dans l'URL, car les URL apparaissent dans les journaux.

Événements envoyés par le serveur (sans aucun contenu) :
`changements { versionCourante }` · `conflit { entite, id }` · `envoi_recu { envoiId }` · `deverrouillage_demande { demandeId }` · `deverrouillage_resolu { demandeId, statut }` · `appareil_revoque { appareilId }` · `annonce { annonceId }` · `fichier_statut { fichierId, statut }`

### 2.7 Fichiers (E1, E2) — 🔐 comptes uniquement
| Méthode | Route | Corps → Réponse |
|---|---|---|
| POST | `/fichiers` | `multipart/form-data` : `metadonnees` (JSON : `id` choisi par le client, `contenuChiffre` (nom et type MIME), `cleElementEnveloppee`, `tailleOctets`) + `fichier` (octets **déjà chiffrés**) → `202 FichierDTO { statut: EN_FILE }`, ou `201` si le fichier est déjà prêt. Erreurs : `413` au-delà de 100 Mo. Le fournisseur est figé ici, selon `FILES_USE_DIRECT_TELEGRAM`. |
| GET | `/fichiers/{id}` | → `FichierDTO` (avec le statut). Les changements de statut sont aussi annoncés par WebSocket. |
| GET | `/fichiers/{id}/acces` | → mode LuluFiles : `{ mode: "lien_signe", url, expireLe }`, URL que le client lit directement (CORS ouvert pour LuluBoard). Mode Telegram : `{ mode: "flux", url: "/api/v1/fichiers/{id}/contenu" }`. |
| GET | `/fichiers/{id}/contenu` | flux des octets chiffrés, réassemblés depuis Telegram, avec prise en charge de `Range` (mode Telegram uniquement) |
| POST | `/fichiers/{id}/reessayer` | → `202`, pour un envoi en `ECHEC` |

### 2.8 Envois entre appareils (D1, H3) — 🔐
| Méthode | Route | Corps → Réponse |
|---|---|---|
| POST | `/envois` | `{ appareilCibleId \| null, elementId?, contenuChiffre? }` → `201 EnvoiDTO`. Les destinataires sont prévenus par push et WebSocket. |
| GET | `/envois/recus?statut=EN_ATTENTE` | → `[EnvoiDTO]` |
| POST | `/envois/{id}/recupere` | → `204` |

### 2.9 Liens publics — gestion (E3, H4, I21) — 🔐
| Méthode | Route | Corps → Réponse |
|---|---|---|
| POST | `/liens` | `{ elementId, duree, protegeParMotDePasse, selDerivation?, cleElementEnveloppee?, verificateurMotDePasse? }` → `201 { lien: LienDTO, jeton }`. **Le jeton n'est renvoyé qu'une seule fois.** Le client construit l'URL `https://<domaine>/l/{jeton}#{cleElement}`, avec la clé dans la partie après `#` s'il n'y a pas de mot de passe. |
| GET | `/liens` | → `[LienDTO]` (élément, création, expiration, nombre de téléchargements, statut) |
| PATCH | `/liens/{id}` | `{ duree }` → `LienDTO` (prolonger) |
| DELETE | `/liens/{id}` | → `204` (révoquer) |

### 2.10 Liens publics — consultation (I19, I20) — 🔓, limité par adresse IP
| Méthode | Route | Corps → Réponse |
|---|---|---|
| GET | `/public/liens/{jeton}` | → `{ type, protegeParMotDePasse, selDerivation? }`. Si le lien n'est **pas** protégé : `+ element` (contenu chiffré **actuel**, avec les tâches et sous-tâches d'une liste). Lien expiré, révoqué ou désactivé : `410 lien_expire`, avec le même message dans tous les cas. |
| POST | `/public/liens/{jeton}/deverrouiller` | `{ verificateurMotDePasse }` → `{ cleElementEnveloppee, element }`. 5 échecs en 15 min → `423 lien_bloque` pour cette adresse IP. |
| GET | `/public/liens/{jeton}/fichier` | → mode LuluFiles : redirection `302` vers un lien signé. Mode Telegram : flux chiffré. Pour un lien protégé, il faut d'abord le jeton court renvoyé par `deverrouiller`. Incrémente `nbTelechargements`. |
| POST | `/public/liens/{jeton}/signalements` | `{ motif, commentaire? }` → `201` |

La page web publique `/l/{jeton}` est une petite page dédiée, sans Flutter. Elle déchiffre le contenu dans le navigateur.

### 2.11 Conformité, aide, annonces
| Méthode | Route | | Corps → Réponse |
|---|---|---|---|
| GET | `/annonces/actives` | 🔓 | → `[AnnonceDTO]` |
| POST | `/support` | 🔓 | `{ emailContact, message, infosTechniques? }` → `201`. Enregistrée **et** envoyée par e-mail (I22). Limitée par adresse IP. |
| GET | `/export` | 🔐 | → toutes les données **chiffrées** du compte, que le client déchiffre et assemble localement (A6) |

### 2.12 Administration
Pas d'API : elle passe par **l'interface d'administration Django** (`/admin/`), réservée au rôle ADMINISTRATEUR (I28, I29, I30). Elle ne voit que des métadonnées.

---

## 3. Objets de transfert (DTO) principaux

```text
AppareilNouveau      { nom, type: WEB|MOBILE|DESKTOP, plateforme, versionApp, clePublique }
ClesInitiales        { enveloppeRecuperation, enveloppeAppareil, clePubliqueVerification }
SessionDTO           { jeton, expireLe }
CompteDTO            { id, email, nomAffichage, role, statut, aMotDePasse, googleLie,
                       cleRecuperationConfirmee, suppressionPrevueLe?, creeLe }
AppareilDTO          { id, nom, type, plateforme, versionApp, statut, ajouteLe, derniereActiviteLe, courant }
DemandeDeverrouillageDTO { id, appareilDemandeur: AppareilDTO, codeAffiche?, statut, expireLe }
PreferencesCompteDTO { theme, langue, fuseauHoraire, retentionPressePapier, retentionVersions }
PreferencesAppareilDTO { raccourciHistorique, raccourciCaptureRapide, demarrageAuto,
                       capturePressePapierEnPause, notificationsActives[], verrouLocal, jetonPush?, typePush? }
FichierDTO           { id, statut, tailleOctets, fournisseur, messageErreur?, creeLe }
EnvoiDTO             { id, appareilSourceId, appareilCibleId?, elementId?, contenuChiffre?, statut, envoyeLe, expireLe }
LienDTO              { id, elementId, typeElement, duree, expireLe?, protegeParMotDePasse,
                       nbTelechargements, creeLe, statut: ACTIF|EXPIRE|REVOQUE|DESACTIVE }
VersionConditionsDTO { id, type, numero, publieeLe, urlTexte }
AnnonceDTO           { id, messageFr, messageEn, debutLe, finLe? }
```

Les valeurs des énumérations sont exactement celles du diagramme de classes.

---

## 4. Points à valider

### Ajouts au diagramme de classes (validé), qu'impose le contrat
1. **`Compte.clePubliqueVerification`** : une clé publique dérivée de la clé maître. Elle permet au serveur de vérifier qu'un appareil déverrouillé par la clé de récupération possède vraiment la clé maître, sans jamais la voir. Sans elle, quelqu'un qui aurait volé le mot de passe pourrait activer un appareil (sans pouvoir lire les données, mais en occupant une des 3 places).
2. **`Appareil.jetonPush` et `Appareil.typePush` (FCM ou WEB_PUSH)** : indispensables pour envoyer les notifications push (rappels, envois, nouvel appareil).
3. **`LienPublic.verificateurMotDePasse`** (stocké haché) : sans lui, le serveur ne pourrait pas appliquer « 5 essais puis blocage » (I19). Quelqu'un qui aurait le lien pourrait tester des mots de passe hors ligne à l'infini.
4. **UUID générés par le client** pour tout ce qui se crée hors ligne.
5. **Jeton court de téléchargement** pour les fichiers des liens protégés, valable quelques minutes, sans stockage durable.

### Incohérence repérée dans les cas d'utilisation validés
6. **UC-A1 contre UC-I4** : tranché le 2026-10-09 ✅ → option **(a)**.
   - **(a)** Confirmation obligatoire à l'inscription par e-mail ; le rappel I4 ne concerne que les comptes créés avec Google, où l'étape peut être reportée.
   - **(b)** Confirmation facultative partout, avec le rappel I4 (A1 assoupli).
   - **(c)** Confirmation obligatoire partout ; I4 est supprimé.

### Questions
7. **Taille maximale d'un élément** : **10 Mo chiffrés** ✅ (validé le 2026-10-09).

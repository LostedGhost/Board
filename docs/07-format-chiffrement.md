# LuluBoard — Format de chiffrement v1

> Référence commune à l'app Flutter, à la page publique des liens (`/l/{jeton}`) et aux tests. Toute modification change la version du format.
> Bibliothèque : **libsodium** (Dart : `sodium` / `sodium_libs` ; navigateur : `libsodium-wrappers-sumo`). Toutes les valeurs binaires circulent en **base64url sans remplissage**.

## 1. Clés

| Clé | Taille | Création | Protection |
|---|---|---|---|
| `K_maitre` | 32 o | `randombytes_buf(32)` à l'inscription | enveloppes ci-dessous ; jamais envoyée en clair |
| Clé de récupération `K_recup` | 32 o | `randombytes_buf(32)` | affichée une fois à l'utilisateur, en **base32 Crockford** par groupes de 4 (`XXXX-XXXX-…`, 13 groupes) |
| Paire d'appareil (X25519) | 32 + 32 o | `crypto_box_keypair()` | clé privée dans le trousseau sécurisé de l'OS (`flutter_secure_storage`) |
| Paire de vérification (Ed25519) | 32 + 64 o | `crypto_sign_seed_keypair(seed)`, avec `seed = crypto_generichash(32, "luluboard-verification-v1", clé = K_maitre)` | dérivée, jamais stockée ; la clé publique va dans `Compte.clePubliqueVerification` |
| Clé d'élément `K_el` | 32 o | `randombytes_buf(32)` à la création de l'élément | enveloppée par `K_maitre` (`cleElementEnveloppee`) |

Une **tâche** n'a pas de clé propre : elle utilise la `K_el` de sa **liste de tâches** (racine de sa chaîne `parentId`).

## 2. Primitive AEAD commune

`aead(K, clair, ad)` = `0x01 ‖ nonce(24) ‖ crypto_aead_xchacha20poly1305_ietf_encrypt(clair, ad, nonce, K)`

- `0x01` : version du format.
- `ad` (données associées) **lie le chiffré à son objet** : on ne peut pas copier le contenu d'un élément dans un autre.

| Donnée | Clé | `ad` (UTF-8) |
|---|---|---|
| Contenu d'un élément (`contenuChiffre`) | `K_el` (ou celle de la liste pour une tâche) | `el:` + id de l'élément |
| Clé d'élément enveloppée (`cleElementEnveloppee`) | `K_maitre` | `cle:` + id de l'élément |
| Tableau, étiquette (`contenuChiffre`) | `K_maitre` | `tb:` / `et:` + id |
| Version d'un post-it | `K_el` du post-it | `el:` + id **du post-it** |
| Enveloppe de récupération | `K_recup` | `recup:v1` |
| Envoi entre appareils (`contenuChiffre`) | `K_maitre` | `envoi:` + id de l'envoi |

## 3. Enveloppes de la clé maître

- **Appareil** : `crypto_box_seal(K_maitre, clé_publique_X25519_appareil)` (80 o).
- **Récupération** : `aead(K_recup, K_maitre, "recup:v1")` (73 o).
- **Preuve de possession** (déverrouillage par récupération) : `crypto_sign_detached(défi, clé_privée_vérification)` (64 o).

## 4. Contenu clair des éléments (JSON UTF-8, avant chiffrement)

| Type | JSON |
|---|---|
| `PRESSE_PAPIER` | `{"texte": "…"}` (TEXTE/LIEN) ou `{"image": "<base64>", "mime": "image/png"}` (IMAGE) |
| `POST_IT` | `{"contenu": "<markdown>", "couleurFond": "#RRGGBB", "x": 0, "y": 0, "largeur": 220, "hauteur": 180, "ordreEmpilement": 0}` |
| `SNIPPET` | `{"titre": "…", "contenu": "…", "langage": "dart" \| null}` |
| `LISTE_TACHES` | `{"titre": "…"}` |
| `TACHE` | `{"titre": "<markdown>", "faite": false, "echeance": "<ISO 8601>" \| null, "priorite": "BASSE" \| "NORMALE" \| "HAUTE", "ordre": 0}` |
| `FICHIER` | `{"nom": "rapport.pdf", "typeMime": "application/pdf", "taille": 123456}` |
| Tableau | `{"nom": "…", "ordre": 0}` |
| Étiquette | `{"nom": "…"}` |

Champs inconnus : ignorés à la lecture (compatibilité ascendante).

## 5. Fichiers

Octets chiffrés avec **`crypto_secretstream_xchacha20poly1305`**, clé `K_el` :
`en-tête(24) ‖ bloc_1 ‖ … ‖ bloc_n`, chaque bloc = 64 Kio de clair + 17 o ; le dernier porte l'étiquette `TAG_FINAL`.
Surcoût pour 100 Mo : 24 o + 1 600 × 17 o ≈ 27 Ko (le serveur accepte 100 Mo + 64 Kio).

## 6. Liens publics

- **Sans mot de passe** : URL `https://<domaine>/l/{jeton}#{K_el en base64url}`. Le fragment n'est jamais envoyé au serveur.
- **Avec mot de passe** : `sel = randombytes_buf(16)` ; `S = crypto_pwhash(64, mot_de_passe, sel, OPSLIMIT_INTERACTIVE, MEMLIMIT_INTERACTIVE, ARGON2ID13)` ;
  `K_lien = S[0..32]` enveloppe `K_el` : `cleElementEnveloppee = aead(K_lien, K_el, "lien:" + id de l'élément)` ;
  `verificateurMotDePasse = S[32..64]`, envoyé au serveur, qui n'en stocke que le HMAC-SHA256.

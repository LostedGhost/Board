# LuluBoard — Diagramme de classes (VALIDÉ le 2026-10-08)

> Étape 2 de la méthode, seconde partie. Ce diagramme est dérivé de `docs/01-cas-utilisation.md` (validé) et de `docs/02-uml-cas-utilisation.md` (validé). C'est le **modèle de données métier** : il décrit ce qui est stocké, pas encore les tables SQL ni l'API (étape 3).

## Conventions de lecture

- `Chiffre~X~` : la donnée est **chiffrée de bout en bout**. Le serveur ne stocke qu'un contenu illisible ; seuls les appareils de l'utilisateur la voient en clair.
- Tout autre attribut est **lisible par le serveur**. C'est le strict nécessaire pour les comptes, la synchronisation, les limites (taille de fichier, 3 appareils), les rappels, l'expiration des liens et la modération.
- `Type?` : attribut facultatif (peut être vide).
- Chaque classe porte en note les cas d'utilisation qui la justifient.
- Les données d'un **Visiteur** ne quittent jamais son appareil (UC-A0). Ce modèle décrit donc le serveur et les comptes. L'app locale utilise les mêmes classes de contenu, sans `Compte`.

---

## Diagramme 1 — Compte, appareils et sécurité

```mermaid
classDiagram
  direction LR
  class Compte {
    +id : UUID
    +email : Email
    +nomAffichage : Texte
    +motDePasseHash : Texte?
    +clePubliqueVerification : Texte
    +role : RoleCompte
    +statut : StatutCompte
    +emailVerifieLe : DateHeure?
    +cleRecuperationConfirmeeLe : DateHeure?
    +dernierRappelCleLe : DateHeure?
    +derniereConnexionLe : DateHeure
    +avertiInactiviteLe : DateHeure?
    +suppressionPrevueLe : DateHeure?
    +creeLe : DateHeure
  }
  class IdentiteGoogle {
    +sujetGoogle : Texte
    +emailGoogle : Email
    +lieeLe : DateHeure
  }
  class CodeVerification {
    +type : TypeCode
    +codeHash : Texte
    +nouvelEmail : Email?
    +tentatives : Entier
    +expireLe : DateHeure
    +utiliseLe : DateHeure?
  }
  class Appareil {
    +id : UUID
    +nom : Texte
    +type : TypeAppareil
    +plateforme : Texte
    +versionApp : Texte
    +clePublique : Texte
    +jetonPush : Texte?
    +typePush : TypePush?
    +statut : StatutAppareil
    +ajouteLe : DateHeure
    +derniereActiviteLe : DateHeure
    +revoqueLe : DateHeure?
  }
  class Session {
    +jetonHash : Texte
    +derniereActiviteLe : DateHeure
    +expireLe : DateHeure
  }
  class EnveloppeCle {
    +methode : MethodeEnveloppe
    +cleMaitreEnveloppee : Octets
    +creeLe : DateHeure
    +invalideeLe : DateHeure?
  }
  class DemandeDeverrouillage {
    +codeAffiche : Texte
    +statut : StatutDemande
    +expireLe : DateHeure
  }
  class PreferencesCompte {
    +theme : Theme
    +langue : Langue
    +fuseauHoraire : Texte
    +retentionPressePapier : DureeConservation
    +retentionVersions : DureeConservation
  }
  class PreferencesAppareil {
    +raccourciHistorique : Texte
    +raccourciCaptureRapide : Texte
    +demarrageAuto : Booleen
    +capturePressePapierEnPause : Booleen
    +notificationsActives : Liste~CategorieNotification~
    +verrouLocal : VerrouLocal
  }

  Compte "1" -- "0..1" IdentiteGoogle : se connecte avec
  Compte "1" *-- "0..*" CodeVerification : reçoit
  Compte "1" *-- "0..*" Appareil : possède (3 actifs max)
  Appareil "1" *-- "0..1" Session : session courante
  Compte "1" *-- "1..*" EnveloppeCle : protège sa clé maître par
  Appareil "1" -- "0..1" EnveloppeCle : déverrouille avec
  Appareil "1" *-- "0..*" DemandeDeverrouillage : demande l'accès
  Appareil "0..1" -- "0..*" DemandeDeverrouillage : approuve
  Compte "1" *-- "1" PreferencesCompte : a
  Appareil "1" *-- "1" PreferencesAppareil : a

  note for Compte "A1 A1b A2 A3 A5 I4 I15 I17 I26 I27\nmotDePasseHash vide = compte Google seul (I16)"
  note for EnveloppeCle "Chiffrement de bout en bout : une clé maître par compte,\nenveloppée par la clé de récupération et par chaque appareil.\nLe mot de passe sert seulement à se connecter (A3)."
  note for Appareil "A4 I11 I12 · max 3 appareils au statut ACTIF"
```

### Énumérations du diagramme 1

```mermaid
classDiagram
  direction LR
  class RoleCompte {
    <<enumeration>>
    UTILISATEUR
    ADMINISTRATEUR
  }
  class StatutCompte {
    <<enumeration>>
    EN_ATTENTE_VERIFICATION
    ACTIF
    SUSPENDU
    SUPPRESSION_PROGRAMMEE
  }
  class TypeCode {
    <<enumeration>>
    INSCRIPTION
    REINITIALISATION_MOT_DE_PASSE
    CHANGEMENT_EMAIL
  }
  class TypeAppareil {
    <<enumeration>>
    WEB
    MOBILE
    DESKTOP
  }
  class StatutAppareil {
    <<enumeration>>
    EN_ATTENTE_DEVERROUILLAGE
    ACTIF
    REVOQUE
  }
  class MethodeEnveloppe {
    <<enumeration>>
    CLE_RECUPERATION
    APPAREIL
  }
  class StatutDemande {
    <<enumeration>>
    EN_ATTENTE
    APPROUVEE
    REFUSEE
    EXPIREE
  }
  class DureeConservation {
    <<enumeration>>
    INFINIE
    J90
    J30
    J7
    H24
    H1
    MIN30
  }
  class TypePush {
    <<enumeration>>
    FCM
    WEB_PUSH
  }
  class VerrouLocal {
    <<enumeration>>
    AUCUN
    CODE_PIN
    BIOMETRIE
  }
  class CategorieNotification {
    <<enumeration>>
    RAPPELS
    ENVOIS_APPAREILS
    NOUVEL_APPAREIL
    SECURITE
  }
```

---

## Diagramme 2 — Éléments du Board (contenus)

```mermaid
classDiagram
  direction TB
  class Element {
    <<abstract>>
    +id : UUID
    +type : TypeElement
    +cleElement : Chiffre~Cle~?
    +epingleAccesRapide : Booleen
    +versionSync : Entier
    +modifieLe : DateHeure
    +creeLe : DateHeure
    +supprimeLe : DateHeure?
  }
  class EntreePressePapier {
    +typeContenu : TypeContenuPP
    +contenu : Chiffre~Octets~
    +epingle : Booleen
  }
  class Tableau {
    +id : UUID
    +nom : Chiffre~Texte~
    +ordre : Chiffre~Entier~
  }
  class PostIt {
    +contenu : Chiffre~Markdown~
    +couleurFond : Chiffre~Couleur~
    +x : Chiffre~Reel~
    +y : Chiffre~Reel~
    +largeur : Chiffre~Reel~
    +hauteur : Chiffre~Reel~
    +ordreEmpilement : Chiffre~Entier~
    +archive : Booleen
  }
  class VersionPostIt {
    +contenuComplet : Chiffre~Octets~
    +creeLe : DateHeure
  }
  class Snippet {
    +titre : Chiffre~Texte~
    +contenu : Chiffre~Texte~
    +langage : Chiffre~Texte~?
  }
  class ListeTaches {
    +titre : Chiffre~Texte~
  }
  class Tache {
    +titre : Chiffre~Markdown~
    +faite : Chiffre~Booleen~
    +echeance : Chiffre~DateHeure~?
    +priorite : Chiffre~Priorite~
    +ordre : Chiffre~Entier~
  }
  class Fichier {
    voir diagramme 3
  }
  class Etiquette {
    +id : UUID
    +nom : Chiffre~Texte~
  }
  class Rappel {
    +prochaineEcheance : DateHeure
    +recurrence : Recurrence?
    +joursSemaine : Liste~JourSemaine~
    +fuseauHoraire : Texte
    +actif : Booleen
  }
  class Compte {
    voir diagramme 1
  }
  class Appareil {
    voir diagramme 1
  }

  Element <|-- EntreePressePapier
  Element <|-- PostIt
  Element <|-- Snippet
  Element <|-- ListeTaches
  Element <|-- Tache
  Element <|-- Fichier

  Compte "1" *-- "0..*" Element : possède
  Compte "1" *-- "0..*" Tableau : possède
  Compte "1" *-- "0..*" Etiquette : possède
  Tableau "1" o-- "0..*" PostIt : contient
  PostIt "1" *-- "0..*" VersionPostIt : historique
  ListeTaches "1" *-- "0..*" Tache : contient
  Tache "0..1" -- "0..*" Tache : sous-tâches
  Element "0..*" -- "0..*" Etiquette : étiqueté par
  Element "0..1" -- "0..*" Element : créé depuis
  Element "1" *-- "0..*" Rappel : a
  Appareil "0..1" -- "0..*" Element : auteur de la modification
  Appareil "0..1" -- "0..*" VersionPostIt : auteur

  note for Element "cleElement : clé propre, enveloppée par la clé maître ;
vide pour une Tache (elle utilise la clé de sa ListeTaches)
G1 synchro : la dernière modification gagne (modifieLe).\nsupprimeLe = marqueur pour propager la suppression\nà tous les appareils (pas de corbeille)."
  note for PostIt "C1 C2 C3 · la couleur du texte n'est pas stockée :\nelle est recalculée à partir de couleurFond (contraste ≥ 4,5:1)"
  note for Rappel "F3 H2 · lisible par le serveur pour envoyer le push\nau bon moment ; le texte reste dans l'élément chiffré"
```

### Énumérations du diagramme 2

```mermaid
classDiagram
  direction LR
  class TypeElement {
    <<enumeration>>
    PRESSE_PAPIER
    POST_IT
    SNIPPET
    LISTE_TACHES
    TACHE
    FICHIER
  }
  class TypeContenuPP {
    <<enumeration>>
    TEXTE
    LIEN
    IMAGE
  }
  class Priorite {
    <<enumeration>>
    BASSE
    NORMALE
    HAUTE
  }
  class Recurrence {
    <<enumeration>>
    QUOTIDIENNE
    HEBDOMADAIRE
    MENSUELLE
    ANNUELLE
  }
  class JourSemaine {
    <<enumeration>>
    LUNDI
    MARDI
    MERCREDI
    JEUDI
    VENDREDI
    SAMEDI
    DIMANCHE
  }
```

---

## Diagramme 3 — Fichiers, envois entre appareils et liens publics

```mermaid
classDiagram
  direction LR
  class Element {
    <<abstract>>
    voir diagramme 2
  }
  class Fichier {
    +nom : Chiffre~Texte~
    +typeMime : Chiffre~Texte~
    +tailleOctets : Entier
    +fournisseur : FournisseurStockage
    +statut : StatutFichier
    +idLuluFiles : UUID?
    +messageErreur : Texte?
  }
  class MorceauTelegram {
    +index : Entier
    +messageId : Entier
    +fileIdTelegram : Texte
    +tailleOctets : Entier
    +sha256 : Texte
  }
  class EnvoiAppareil {
    +id : UUID
    +contenu : Chiffre~Octets~?
    +statut : StatutEnvoi
    +envoyeLe : DateHeure
    +recupereLe : DateHeure?
    +expireLe : DateHeure
  }
  class LienPublic {
    +id : UUID
    +jetonHash : Texte
    +protegeParMotDePasse : Booleen
    +selDerivation : Octets?
    +cleElementEnveloppee : Octets?
    +verificateurMotDePasseHash : Texte?
    +duree : DureeConservation
    +expireLe : DateHeure?
    +nbTelechargements : Entier
    +creeLe : DateHeure
    +revoqueLe : DateHeure?
    +desactiveParAdminLe : DateHeure?
  }
  class Appareil {
    voir diagramme 1
  }

  Element <|-- Fichier
  Fichier "1" *-- "0..*" MorceauTelegram : découpé en (mode Telegram)
  Appareil "1" -- "0..*" EnvoiAppareil : expédie
  Appareil "0..1" -- "0..*" EnvoiAppareil : reçoit (vide = tous)
  EnvoiAppareil "0..*" -- "0..1" Element : porte sur
  Element "1" -- "0..*" LienPublic : partagé par

  note for Fichier "E1 E2 · 100 Mo max (tailleOctets lisible pour le contrôler)\nfournisseur figé à l'envoi : la variable ne touche que\nles nouveaux fichiers · suppression définitive"
  note for LienPublic "E3 H4 I19 I21 · contenu en DIRECT : le lien sert la version\nactuelle de l'élément. Sa cleElement est dans le lien (après #)\nou enveloppée par le mot de passe ; jamais en clair sur le serveur.\nexpireLe vide = durée infinie"
  note for EnvoiAppareil "D1 H3 · conservé 7 jours s'il n'est pas récupéré"
```

### Énumérations du diagramme 3

```mermaid
classDiagram
  direction LR
  class FournisseurStockage {
    <<enumeration>>
    LULUFILES
    TELEGRAM_DIRECT
  }
  class StatutFichier {
    <<enumeration>>
    EN_FILE
    ENVOI_EN_COURS
    PRET
    ECHEC
  }
  class StatutEnvoi {
    <<enumeration>>
    EN_ATTENTE
    REMIS
    EXPIRE
  }
```

---

## Diagramme 4 — Administration et conformité

```mermaid
classDiagram
  direction LR
  class Signalement {
    +id : UUID
    +motif : MotifSignalement
    +commentaire : Texte?
    +creeLe : DateHeure
    +statut : StatutSignalement
    +traiteLe : DateHeure?
  }
  class Suspension {
    +motif : Texte
    +debutLe : DateHeure
    +leveeLe : DateHeure?
  }
  class VersionConditions {
    +type : TypeConditions
    +numero : Texte
    +publieeLe : DateHeure
    +urlTexte : URL
  }
  class AcceptationConditions {
    +accepteeLe : DateHeure
  }
  class Annonce {
    +messageFr : Texte
    +messageEn : Texte
    +debutLe : DateHeure
    +finLe : DateHeure?
  }
  class DemandeSupport {
    +emailContact : Email
    +message : Texte
    +infosTechniques : Texte?
    +creeLe : DateHeure
  }
  class LienPublic {
    voir diagramme 3
  }
  class Compte {
    voir diagramme 1
  }

  LienPublic "1" -- "0..*" Signalement : fait l'objet de
  Compte "0..1" -- "0..*" Signalement : traité par (admin)
  Compte "1" -- "0..*" Suspension : subit
  Compte "1" -- "0..*" Suspension : décidée par (admin)
  Signalement "0..1" -- "0..*" Suspension : est à l'origine de
  Compte "1" -- "0..*" AcceptationConditions : accepte
  VersionConditions "1" -- "0..*" AcceptationConditions : acceptée via
  Compte "1" -- "0..*" Annonce : publiée par (admin)
  Compte "0..1" -- "0..*" DemandeSupport : envoie

  note for DemandeSupport "I22 · enregistrée ET transmise par e-mail à l'équipe"
  note for Signalement "I20 I28 · l'administrateur ne voit jamais le contenu"
  note for AcceptationConditions "G4 I23 · preuve du consentement (date + version)"
```

### Énumérations du diagramme 4

```mermaid
classDiagram
  direction LR
  class MotifSignalement {
    <<enumeration>>
    CONTENU_ILLICITE
    ATTEINTE_DROIT_AUTEUR
    LOGICIEL_MALVEILLANT
    HAMECONNAGE
    AUTRE
  }
  class StatutSignalement {
    <<enumeration>>
    OUVERT
    CLASSE_SANS_SUITE
    LIEN_DESACTIVE
    COMPTE_SUSPENDU
  }
  class TypeConditions {
    <<enumeration>>
    CONDITIONS_UTILISATION
    POLITIQUE_CONFIDENTIALITE
  }
```

---

## Ce qui n'est volontairement PAS dans le modèle

| Besoin | Pourquoi aucune classe |
|---|---|
| Export des données (A6) | généré sur l'appareil, rien n'est stocké |
| Mentions `[[…]]` (H6) | elles vivent dans le Markdown chiffré du post-it ou de la tâche |
| Annuler sous 10 s (H10) | délai géré par l'appareil avant l'envoi au serveur |
| Supervision (I29) | statistiques calculées à la volée |
| Blocage après 5 échecs (A2, I19) | compteurs techniques temporaires (cache), pas des données métier |
| Annonce fermée par l'utilisateur (I30) | mémorisée localement sur l'appareil |
| État de synchronisation (I5) | calculé par l'appareil |
| Post-it affiché au premier plan (C2) | réglage propre à chaque ordinateur, mémorisé localement ✅ |

## Ajouts du 2026-10-09 (imposés par le contrat d'API, validés ✅)

1. `Compte.clePubliqueVerification` : clé publique dérivée de la clé maître. Elle sert à prouver qu'un appareil déverrouillé par la clé de récupération possède bien la clé maître.
2. `Appareil.jetonPush` + `Appareil.typePush` (FCM ou WEB_PUSH) : nécessaires pour envoyer les notifications push.
3. `LienPublic.verificateurMotDePasseHash` : permet au serveur de bloquer après 5 essais faux (I19).
4. Les identifiants des éléments, tableaux, étiquettes et rappels sont **générés par le client** (UUID v7), pour permettre la création hors ligne.

## Décisions de modélisation

Déduites par moi, à valider :
1. **Administrateur = rôle sur le Compte** (`role`), et non une table séparée.
2. **Clé maître + enveloppes** (`EnveloppeCle`) : c'est le mécanisme qui réalise le chiffrement de bout en bout, la clé de récupération et le déverrouillage d'un appareil par un autre.
3. **Une clé par élément** (`cleElement`), enveloppée par la clé maître. C'est ce qui permet le lien public en direct : le lien ne donne accès qu'à cet élément, jamais au reste du compte. Les tâches utilisent la clé de leur liste, pour qu'un lien de liste montre aussi ses tâches et sous-tâches.
4. **Tout le contenu est chiffré, y compris les positions et les couleurs des post-it.** Seul ce que le serveur doit lire reste en clair : la taille des fichiers, les dates de rappel, l'expiration des liens.
5. **Pas de corbeille** : un élément supprimé reçoit seulement `supprimeLe`, pour que la suppression atteigne les autres appareils. Ses liens publics cessent alors de fonctionner.
6. **Limite du lien en direct** : révoquer un lien bloque l'accès par le serveur. En revanche, quelqu'un qui a déjà ouvert le lien a déjà vu le contenu de ce moment-là.

Tranchées par vous le 2026-10-08 ✅ :
- Le tableau ne contient **que des post-it**. Déposer un fichier sur le tableau (H5) crée un élément Fichier, rangé avec les fichiers, pas sur le tableau.
- Historique des versions : **post-it uniquement**.
- **Plusieurs rappels** par élément.
- Lien public : affiche les **modifications en direct**.
- Affichage au premier plan : **propre à chaque ordinateur**, mémorisé localement, donc absent du modèle serveur.
- Motifs de signalement : **validés**.
- Demande de support : **enregistrée en base et envoyée par e-mail**.

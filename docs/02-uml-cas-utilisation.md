# LuluBoard — Diagramme de cas d'utilisation (VALIDÉ le 2026-10-08)

> Étape 2 de la méthode, première partie. Ce diagramme est dérivé strictement de `docs/01-cas-utilisation.md` (validé le 2026-10-08) : chaque ovale porte l'identifiant du cas d'origine.
> Pour rester lisible (15 à 20 nœuds maximum par diagramme), il est découpé en une vue d'ensemble et cinq sous-systèmes.

## Acteurs

| Acteur | Type | Source |
|---|---|---|
| Visiteur | humain | rôle défini dans les cas d'utilisation |
| Utilisateur inscrit | humain, **hérite** du Visiteur (il peut tout ce que peut le visiteur, plus le reste) | rôle défini dans les cas d'utilisation |
| Destinataire d'un lien | humain, sans compte | UC-I19, UC-I20 |
| Administrateur | humain | rôle défini dans les cas d'utilisation |
| Planificateur (temps) | «système», **déduit** | purges de rétention (UC-B4), déclenchement des rappels (UC-F3), comptes inactifs (UC-I27), expiration des liens (UC-E3) et des sessions (UC-I17) |
| Google | «système» externe | UC-A1b, UC-I16 |
| Service d'e-mail | «système» externe, **déduit** | codes de vérification (UC-A1, UC-A3, UC-I14), rappels (UC-I26, UC-I27) |
| Stockage de fichiers | «système» externe : LuluFiles **ou** Telegram direct | section E |
| Service de notifications push | «système» externe, **déduit** | UC-D1, UC-F3, UC-I7, UC-I11 |
| Presse-papier du système | «système» externe (OS desktop) | UC-B1 |

---

## Diagramme 0 — Vue d'ensemble

```mermaid
flowchart LR
  V(["👤 Visiteur"])
  U(["👤 Utilisateur inscrit"])
  R(["👤 Destinataire d'un lien"])
  AD(["👤 Administrateur"])
  T(["⏱ «système» Planificateur"])
  EXT(["⚙ «systèmes» Google, e-mail, stockage, push, presse-papier OS"])

  subgraph LB["LuluBoard"]
    P1(["Accès, compte et sécurité<br/>A, I.1, I.3, I.6"])
    P2(["Contenus : presse-papier, post-it,<br/>snippets, tâches, rappels<br/>B, C, F"])
    P3(["Partage et fichiers<br/>D, E, I.4"])
    P4(["Passerelles et usage quotidien<br/>G1, G2, H, I.2"])
    P5(["Administration et conformité<br/>G3, G4, I.5, I.7"])
  end

  U -->|hérite de| V
  V --- P1
  V --- P2
  V --- P4
  U --- P3
  U --- P5
  R --- P3
  AD --- P5
  T --- P1
  T --- P2
  T --- P3
  P1 --- EXT
  P2 --- EXT
  P3 --- EXT
```

---

## Diagramme 1 — Accès, compte et sécurité

```mermaid
flowchart LR
  V(["👤 Visiteur"])
  U(["👤 Utilisateur inscrit"])
  T(["⏱ Planificateur"])
  G(["⚙ «système» Google"])
  M(["⚙ «système» Service e-mail"])

  subgraph SYS["LuluBoard — Accès, compte et sécurité"]
    I1(["I1 Découvrir la plateforme"])
    A0(["A0 Utiliser sans compte"])
    I2(["I2 Premier lancement"])
    A1(["A1 S'inscrire par e-mail"])
    A1b(["A1b S'inscrire / se connecter avec Google"])
    I3(["I3 Conserver ses données locales à l'inscription"])
    KEY(["A1 / I4 / I15 Sauvegarder ou régénérer<br/>sa clé de récupération"])
    A2(["A2 Se connecter / se déconnecter"])
    A3(["A3 Réinitialiser son mot de passe"])
    DEV(["A4 / I11 / I12 Gérer ses appareils<br/>ajouter, déverrouiller, révoquer"])
    I13(["I13 / I14 Changer mot de passe ou e-mail"])
    I16(["I16 Lier / délier Google"])
    I18(["I18 Verrouiller l'app localement"])
    DEL(["A5 / I26 Supprimer son compte<br/>ou annuler la suppression"])
    A6(["A6 Exporter ses données"])
    I17(["I17 Expirer une session inactive"])
    I27(["I27 Supprimer un compte inactif 12 mois"])
  end

  U -->|hérite de| V
  V --- I1
  V --- A0
  V --- I2
  V --- A1
  V --- A1b
  U --- A2
  U --- A3
  U --- KEY
  U --- DEV
  U --- I13
  U --- I16
  U --- I18
  U --- DEL
  U --- A6
  T --- I17
  T --- I27

  A1 -.->|«include»| KEY
  A1b -.->|«include»| KEY
  I3 -.->|«extend»| A1
  DEV -.->|«include» si déverrouillage par clé| KEY
  A1 --- M
  A3 --- M
  I13 --- M
  DEL --- M
  I27 --- M
  A1b --- G
  I16 --- G
```

---

## Diagramme 2 — Contenus : presse-papier, post-it, snippets, tâches, rappels

Le Visiteur fait tout cela **localement** (UC-A0) ; l'Utilisateur inscrit en hérite, avec la synchronisation en plus.

```mermaid
flowchart LR
  V(["👤 Visiteur"])
  OS(["⚙ «système» Presse-papier OS"])
  T(["⏱ Planificateur"])
  PU(["⚙ «système» Notifications push"])

  subgraph SYS["LuluBoard — Contenus"]
    B1(["B1 Capturer automatiquement les copies"])
    B2(["B2 Ajouter manuellement au presse-papier"])
    B3(["B3 Consulter, rechercher, recopier"])
    B4(["B4 Épingler, supprimer, régler la rétention"])
    PURGE(["B4 Purger les entrées expirées"])
    C1(["C1 Créer un post-it"])
    C2(["C2 Organiser le tableau libre"])
    TOP(["C2 Afficher un post-it au premier plan"])
    H12(["H12 Gérer les tableaux"])
    C3(["C3 Modifier, archiver, supprimer"])
    VER(["C3 Consulter / restaurer une version"])
    F1(["F1 Gérer ses snippets"])
    F2(["F2 Gérer ses listes de tâches"])
    F3(["F3 Programmer un rappel récurrent ou non"])
    FIRE(["F3 Déclencher un rappel"])
  end

  V --- B2
  V --- B3
  V --- B4
  V --- C1
  V --- C2
  V --- H12
  V --- C3
  V --- F1
  V --- F2
  V --- F3
  OS --- B1
  T --- PURGE
  T --- FIRE
  FIRE --- PU

  TOP -.->|«extend» desktop| C2
  VER -.->|«extend»| C3
```

---

## Diagramme 3 — Partage et fichiers

Réservé à l'Utilisateur inscrit (UC-A0 : fichiers et liens publics interdits aux visiteurs).

```mermaid
flowchart LR
  U(["👤 Utilisateur inscrit"])
  R(["👤 Destinataire d'un lien"])
  T(["⏱ Planificateur"])
  ST(["⚙ «système» Stockage<br/>LuluFiles ou Telegram"])
  PU(["⚙ «système» Notifications push"])

  subgraph SYS["LuluBoard — Partage et fichiers"]
    D1(["D1 / H3 Envoyer un élément à un appareil"])
    E1(["E1 Téléverser un fichier"])
    E2(["E2 Télécharger / supprimer un fichier"])
    E3(["E3 / H4 Créer un lien public<br/>fichier, post-it, snippet, liste"])
    PWD(["E3 Protéger le lien par mot de passe"])
    I21(["I21 Suivre, révoquer, prolonger ses liens"])
    EXP(["E3 Expirer un lien"])
    I19(["I19 Ouvrir un lien public"])
    I19p(["I19 Saisir le mot de passe du lien"])
    I20(["I20 Signaler un lien"])
  end

  U --- D1
  U --- E1
  U --- E2
  U --- E3
  U --- I21
  R --- I19
  R --- I20
  T --- EXP

  PWD -.->|«extend»| E3
  I19p -.->|«extend» si protégé| I19
  E1 --- ST
  E2 --- ST
  I19 --- ST
  D1 --- PU
```

---

## Diagramme 4 — Passerelles et usage quotidien

```mermaid
flowchart LR
  V(["👤 Visiteur"])
  U(["👤 Utilisateur inscrit"])

  subgraph SYS["LuluBoard — Passerelles et usage quotidien"]
    H1(["H1 Transformer un élément"])
    H5(["H5 Glisser-déposer entre modules"])
    H2(["H2 Attacher un rappel à un élément"])
    H6(["H6 Mentionner un élément"])
    H7(["H7 Étiqueter un élément"])
    H8(["H8 Épingler en accès rapide"])
    H9(["H9 Capture rapide"])
    H10(["H10 Annuler la dernière action"])
    H11(["H11 Dupliquer un élément"])
    G2(["G2 Rechercher dans tout le Board"])
    I8(["I8 Personnaliser l'interface"])
    I9(["I9 Démarrage automatique desktop"])
    I10(["I10 Mettre à jour l'application"])
    G1(["G1 Synchroniser, y compris après hors ligne"])
    I5(["I5 Voir l'état de synchronisation"])
    I6(["I6 Être informé d'un conflit résolu"])
    I7(["I7 Gérer ses notifications"])
  end

  U -->|hérite de| V
  V --- H1
  V --- H5
  V --- H2
  V --- H6
  V --- H7
  V --- H8
  V --- H9
  V --- H10
  V --- H11
  V --- G2
  V --- I8
  V --- I9
  V --- I10
  U --- G1
  U --- I5
  U --- I7

  H5 -.->|«include»| H1
  I6 -.->|«extend» si conflit| G1
```

---

## Diagramme 5 — Administration et conformité

```mermaid
flowchart LR
  U(["👤 Utilisateur inscrit"])
  AD(["👤 Administrateur"])
  M(["⚙ «système» Service e-mail"])

  subgraph SYS["LuluBoard — Administration et conformité"]
    G4(["G4 Donner son consentement"])
    I23(["I23 Accepter les nouvelles conditions"])
    I22(["I22 Obtenir de l'aide / contacter"])
    I24(["I24 Être informé d'une suspension et contester"])
    I29(["G3 / I29 Superviser la plateforme"])
    I28(["G3 / I28 Traiter un signalement"])
    OFF(["I28 Désactiver un lien"])
    SUS(["G3 / I28 Suspendre un compte"])
    I30(["I30 Publier une annonce"])
  end

  U --- G4
  U --- I23
  U --- I22
  U --- I24
  AD --- I29
  AD --- I28
  AD --- SUS
  AD --- I30

  OFF -.->|«extend»| I28
  SUS -.->|«extend»| I28
  I22 --- M
```

---

## Points déduits à valider

1. **Quatre acteurs « système » sont déduits** et n'étaient pas nommés dans les cas d'utilisation : le Planificateur, le Service d'e-mail, le Service de notifications push et le Presse-papier du système.
2. **Héritage** : l'Utilisateur inscrit hérite du Visiteur. Il peut donc faire tout ce que fait le visiteur (en local), plus la synchronisation, les fichiers et le partage.
3. **Regroupements** : pour éviter les doublons, des cas proches sont regroupés dans un même ovale (par exemple A4, I11 et I12 forment « Gérer ses appareils »). Aucun cas n'a été retiré.
4. **Cas d'utilisation non représentés** : UC-I25, doublon de UC-A6 dans le document validé.

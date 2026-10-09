# LuluBoard — Cas d'utilisation (VALIDÉS le 2026-10-08)

> Statut : **validé explicitement le 2026-10-08**, valeurs *(proposé)* comprises. Toute modification ultérieure doit être revalidée. *(proposé)* = suggestion à confirmer. ❓ = décision qui vous revient. ✅ = décidé par vous le 2026-10-08.

## Contraintes globales ✅

- Supports : web, mobile, desktop.
- Produit SaaS public, marché international.
- **Chiffrement de bout en bout (E2EE)** : le serveur ne voit jamais le contenu en clair (presse-papier, notes, snippets, tâches, fichiers).
- **Hors ligne dès la V1** : tout est utilisable sans réseau et se synchronise au retour de la connexion.
- Conformité : loi béninoise n° 2017-20 (Code du numérique, APDP) d'abord, puis RGPD.
- **Pas de Premium en V1**, pas de quota de stockage. Seule limite : 3 appareils par compte ✅.
- Stockage des fichiers : **LuluFiles** (notre service) par défaut ✅. Une **variable booléenne de configuration** bascule vers un **envoi direct dans un canal Telegram via l'API Bot de Telegram** ✅, utilisable en développement et, éventuellement, en production. Voir la section E.
- Le compte LuluFiles à quota illimité est reporté ✅.

## Rôles

- **Visiteur** : pas de compte, mais peut utiliser les fonctionnalités ✅. Voir UC-A0 pour les conséquences.
- **Utilisateur** : compte vérifié.
- **Administrateur** : gère la plateforme, mais ne peut pas lire les contenus (E2EE).

Ordre des sections = ordre d'usage réel (servira d'ordre de développement à l'étape 4).

---

## A. Accès, compte et appareils

**UC-A0 — Utiliser LuluBoard sans compte**
En tant que visiteur, je veux utiliser les fonctionnalités sans m'inscrire, afin d'essayer le produit immédiatement.
- *(proposé)* Les données du visiteur restent **uniquement sur son appareil** : il n'y a ni synchronisation, ni envoi entre appareils, ni historique de versions côté serveur.
- Les fichiers et les liens publics sont **réservés aux comptes** ✅ : un visiteur anonyme ne peut pas héberger de contenu.
- *(proposé)* S'il crée un compte, ses données locales sont rattachées à ce compte et chiffrées avant d'être synchronisées.

**UC-A1 — S'inscrire par e-mail**
En tant que visiteur, je veux créer un compte, afin de synchroniser mes contenus entre mes appareils.
- Champs : nom d'affichage, e-mail, mot de passe.
- E-mail unique et au format valide.
- Mot de passe : au moins 8 caractères, une majuscule, un chiffre *(proposé)*.
- Un code à 6 chiffres est envoyé par e-mail, valable 15 min *(proposé)*. Le compte n'est actif qu'après validation de ce code.
- **Conséquence de l'E2EE** : à l'inscription, l'application génère une **clé de récupération** (24 mots ou un code de 32 caractères) que l'utilisateur doit sauvegarder. L'inscription n'est terminée que lorsqu'il confirme l'avoir notée.

**UC-A1b — S'inscrire / se connecter avec Google** ✅
- La connexion Google prouve l'identité, mais ne fournit pas de clé de chiffrement. Le **premier** appareil crée donc la clé de récupération (comme en UC-A1). Ensuite, chaque nouvel appareil doit être déverrouillé, au choix :
  - par validation depuis un appareil déjà connecté ;
  - ou par saisie de la clé de récupération.

**UC-A2 — Se connecter / se déconnecter**
- Après 5 échecs en 15 min, la connexion est bloquée 15 min *(proposé)*.
- Message d'erreur générique : « identifiants incorrects », sans préciser lequel des deux.
- Un nouvel appareil doit être déverrouillé (voir UC-A1b) avant de voir les contenus.

**UC-A3 — Mot de passe oublié**
- Le mot de passe se réinitialise par code e-mail. **Conséquence de l'E2EE** : les contenus ne restent lisibles que si l'utilisateur fournit sa clé de récupération ou valide depuis un autre appareil connecté. Sinon, ils sont **définitivement perdus**. Ce message doit être affiché clairement.

**UC-A4 — Gérer ses appareils**
En tant qu'utilisateur, je veux voir la liste de mes appareils connectés (nom, type, dernière activité) et en révoquer un, afin de garder le contrôle si je perds un appareil.
- Un appareil révoqué est déconnecté immédiatement et ne reçoit plus rien.
- **3 appareils maximum** par compte ✅. Pour en ajouter un 4e, il faut d'abord en révoquer un ; le message l'indique *(proposé)*.

**UC-A5 — Supprimer son compte**
- Le mot de passe est redemandé. La suppression devient définitive après un délai de grâce de 30 jours *(proposé)*, et tout est effacé, fichiers LuluFiles compris.

**UC-A6 — Exporter ses données** *(proposé : obligation de portabilité, loi 2017-20 et RGPD)*
- L'export est fait en clair, côté appareil, au format JSON + fichiers.

---

## B. Historique presse-papier

**UC-B1 — Capturer automatiquement (desktop)**
- Chaque copie (texte, lien, image) est ajoutée automatiquement à l'historique. La capture peut être mise en pause à tout moment.
- Les copies venant des gestionnaires de mots de passe (contenus marqués « sensibles » par le système d'exploitation) sont ignorées. ✅ Il n'y a pas de liste d'exclusion réglable par l'utilisateur.
- Deux copies identiques qui se suivent ne créent qu'une seule entrée.
- Taille max d'une entrée : texte 100 Ko, image 5 Mo *(proposé)*. Au-delà, l'élément est à traiter comme un fichier.

**UC-B2 — Ajouter manuellement (web / mobile)**
- Sur web et mobile, l'ajout est manuel : on colle le contenu ou on passe par le menu « Partager » du mobile. Les navigateurs et les OS mobiles interdisent la capture en arrière-plan.

**UC-B3 — Consulter, rechercher, recopier**
- Filtrer par type (texte, lien, image) et chercher par mot-clé. La recherche se fait **sur l'appareil**, puisque le serveur ne peut pas lire les contenus (E2EE).
- Raccourci global sur desktop : **Ctrl + Alt + B** (Windows / Linux) et **Cmd + Option + B** (macOS) ✅ (choisi par moi). Raisons : Win + V et Ctrl + Shift + V sont déjà pris (historique Windows, « coller sans mise en forme »), et Ctrl + Alt + B ne produit aucun caractère sur les claviers AZERTY ni QWERTY. Le raccourci est modifiable dans les réglages *(proposé)*.

**UC-B4 — Épingler / supprimer / rétention**
- Une entrée épinglée n'est jamais purgée.
- L'utilisateur choisit la durée de rétention des entrées non épinglées : **Infinie, 90 jours, 30 jours, 7 jours, 24 h, 30 min** ✅. Valeur par défaut : 30 jours *(proposé)*.
- On peut supprimer une entrée ou vider tout l'historique.

---

## C. Post-it / notes

**UC-C1 — Créer un post-it**
- Contenu en Markdown (gras, italique, titres, listes, cases à cocher, code, liens) ✅. Taille du contenu illimitée ✅. Précision du 2026-10-09 ✅ : plafond technique de 10 Mo chiffrés par élément.
- Couleur : 6 couleurs prédéfinies, plus un **sélecteur de couleur libre** ✅.
- **Couleur du texte calculée automatiquement** ✅ pour rester lisible sur la couleur choisie. *(proposé)* Le texte prend une teinte foncée ou claire de la même couleur, ajustée jusqu'à un contraste d'au moins 4,5:1 (norme WCAG AA). Si aucune teinte n'y arrive, il passe en noir ou en blanc, ce qui garantit toujours ce seuil. L'utilisateur ne peut pas forcer une couleur de texte illisible.

**UC-C2 — Organiser sur un tableau**
- Tableau libre : les éléments se placent où l'on veut, se déplacent et se superposent à volonté ✅. L'ordre d'empilement se règle avec « mettre au premier plan » et « mettre en arrière-plan ».
- Un utilisateur peut avoir plusieurs tableaux.
- Desktop : un post-it ne s'affiche au-dessus des autres fenêtres **que si l'utilisateur le demande pour ce post-it précis** ✅. Précision du 2026-10-08 ✅ : ce réglage est propre à chaque ordinateur.

**UC-C3 — Modifier / archiver / supprimer**
- Conflit hors ligne : la dernière modification l'emporte ✅. **Toutes les versions sont conservées** dans un historique consultable, et une ancienne version peut être restaurée *(proposé)*.
- L'utilisateur choisit la durée de conservation des versions : **Illimitée (par défaut), 90 jours, 30 jours, 7 jours, 24 h, 1 h, 30 min** ✅.

---

## D. Partage entre appareils

**UC-D1 — Envoyer à un de mes appareils**
- On peut envoyer un texte, un lien ou un fichier à un appareil précis ou à tous. L'appareil cible reçoit une notification.
- Si l'appareil cible est hors ligne, l'envoi lui est remis à sa reconnexion.
- Un envoi non récupéré est conservé 7 jours *(proposé)*.

---

## E. Fichiers (via LuluFiles)

**UC-E1 — Téléverser un fichier**
- Taille max : **100 Mo** par fichier ✅. Quota illimité ✅.
- Tous les types de fichiers sont acceptés ✅. **LuluBoard n'ouvre ni ne prévisualise aucun fichier : il propose seulement le téléchargement** ✅.
- Le fichier est chiffré sur l'appareil avant d'être envoyé à LuluFiles.

**UC-E2 — Télécharger / supprimer un fichier**

**Règles de stockage (deux fournisseurs)** ✅
- Variable serveur booléenne, par exemple `FILES_USE_DIRECT_TELEGRAM` : `false` = LuluFiles, `true` = API Bot Telegram ✅.
- ✅ La variable ne s'applique qu'aux **nouveaux** envois. Chaque fichier enregistre le fournisseur qui le stocke, et reste téléchargeable même après un changement de la variable. Aucune migration automatique entre les deux fournisseurs.
- ✅ Mode Telegram direct : l'API Bot publique accepte au plus 50 Mo en envoi, mais ne permet de télécharger que 20 Mo par fichier. Les fichiers chiffrés sont donc découpés en **morceaux de 18 Mo** (comme LuluFiles), avec une empreinte SHA-256 par morceau, et réassemblés au téléchargement.
- ✅ Mode Telegram direct : l'URL de téléchargement Telegram contient le jeton du bot, qui ne doit jamais sortir du serveur. Les téléchargements **passent donc par le backend LuluBoard**, qui diffuse le contenu chiffré au client.
- ✅ Mode Telegram direct : le jeton du bot et l'identifiant du canal sont des secrets serveur. Il faut un canal distinct par environnement (dev / prod).
- ✅ **La production tourne en mode Telegram direct** jusqu'à la création d'un compte LuluFiles à quota illimité. Dans ce mode, il n'y a donc pas de plafond de transfert par utilisateur.
- ✅ Mode LuluFiles : le domaine LuluBoard est autorisé dans le CORS de la route des liens signés de LuluFiles (modification à faire dans LuluFiles). Le navigateur récupère le fichier chiffré directement depuis LuluFiles et le déchiffre localement.
- ✅ **Suppression d'un fichier : définitive et immédiate, sans corbeille** (dans LuluFiles, `?permanent=true`). Les copies chiffrées qui ne peuvent pas être effacées de Telegram (messages de plus de 48 h) deviennent illisibles une fois la clé du fichier détruite (effacement cryptographique).

**UC-E3 — Partager par lien public** ✅ (V1)
- Durées d'expiration au choix : Infinie, 90 jours, 30 jours, 7 jours, 24 h, 30 min ✅.
- La clé de déchiffrement est placée dans le lien lui-même, après le `#`. Le serveur ne la reçoit jamais : quiconque a le lien complet peut télécharger le fichier.
- Le propriétaire peut révoquer un lien à tout moment.
- Mot de passe optionnel sur le lien ✅. Il sert à dériver la clé de déchiffrement : sans lui, même le lien complet ne suffit pas *(proposé)*.
- **Signalement** : chaque page de téléchargement public affiche un bouton « Signaler ». L'administrateur peut désactiver le lien, mais pas lire le fichier.

---

## F. Snippets, to-do, rappels

**UC-F1 — Snippets**
- Chaque snippet a un titre, un contenu, un langage (facultatif) et des tags. On le copie en un clic.
- Les raccourcis d'expansion sont reportés en **V2** ✅.

**UC-F2 — To-do** ✅ (complet en V1)
- Listes de tâches, sous-tâches, échéance, priorité (basse / normale / haute *(proposé)*), case à cocher.
- Sous-tâches imbriquées sans limite de profondeur ✅.

**UC-F3 — Rappels** ✅ (récurrents inclus en V1)
- Un rappel peut être attaché à une note, une tâche ou un snippet.
- Récurrence : quotidienne, hebdomadaire (jours au choix), mensuelle, annuelle *(proposé)*.
- Fuseau horaire : celui de l'appareil qui crée le rappel *(proposé)*.
- **Conséquence de l'E2EE** ✅ : le serveur connaît la date et l'heure du rappel, mais pas son texte. La notification push affiche « Vous avez un rappel », et le texte apparaît une fois l'application ouverte.

---

## G. Transversal

**UC-G1 — Synchronisation et hors ligne** ✅
- Tout fonctionne hors ligne et se synchronise automatiquement au retour du réseau.

**UC-G2 — Recherche globale**
- Une seule barre de recherche couvre le presse-papier, les notes, les snippets, les tâches et les noms de fichiers. La recherche s'exécute sur l'appareil (E2EE).

**UC-G3 — Administration**
- Statistiques d'usage, sans accès aux contenus.
- Suspension d'un compte.
- Traitement des signalements de liens publics.

**UC-G4 — Conformité** *(proposé)*
- Le consentement est recueilli à l'inscription. Les mentions légales, la politique de confidentialité et le registre des traitements suivent la loi 2017-20 / APDP, puis le RGPD. Un audit dédié sera fait plus tard (skill droit-numerique-benin).


---

## H. Passerelles entre fonctionnalités (mini cas d'utilisation)

> Ces petites actions relient les services entre eux, pour que l'utilisateur n'ait jamais à recopier un contenu à la main d'un module à l'autre. Toutes respectent le chiffrement de bout en bout : les conversions se font sur l'appareil. Toutes les règles de cette section sont *(proposé)*, sauf mention contraire.

Vocabulaire : un **élément** est n'importe quel objet du Board (entrée de presse-papier, post-it, snippet, tâche, fichier).

**UC-H1 — Transformer un élément en un autre**
En tant qu'utilisateur, je veux transformer un élément en un autre type (par exemple une entrée de presse-papier en post-it, en snippet ou en tâche ; un post-it en tâche ou en snippet ; une image copiée en fichier), afin de ne rien ressaisir.
- Par défaut, l'action **crée une copie** et l'original reste en place. Une option « Déplacer » supprime l'original.
- Le nouvel élément garde un lien vers sa source (« créé depuis… »), cliquable tant que la source existe.
- Si le contenu dépasse la limite du type cible (par exemple une image de plus de 5 Mo vers le presse-papier), l'action propose automatiquement de créer un fichier à la place.

**UC-H2 — Attacher un rappel à n'importe quel élément**
- Un rappel peut être posé sur un post-it, une tâche, un snippet, une entrée épinglée ou un fichier. Il se règle depuis le menu de l'élément (voir UC-F3).

**UC-H3 — Envoyer n'importe quel élément à un appareil**
- L'action « Envoyer à… » (UC-D1) est disponible sur tous les éléments, pas seulement sur le texte.

**UC-H4 — Partager un élément par lien public**
- ✅ Le partage par lien public couvre en V1 les fichiers (UC-E3) **et** les post-it, snippets et listes de tâches. *(proposé)* Il est en lecture seule, avec les mêmes durées et le même mot de passe optionnel.

**UC-H5 — Glisser-déposer entre modules**
- On peut glisser un élément d'un panneau vers un autre : une entrée de presse-papier vers le tableau devient un post-it, un fichier du système vers le tableau devient un fichier, un post-it vers la liste de tâches devient une tâche. Même règle que UC-H1 : la copie est le comportement par défaut.
- Sur mobile, un appui long ouvre le même menu « Transformer / Envoyer / Partager ».
- Précision du 2026-10-08 ✅ : le tableau ne contient que des post-it. Un fichier déposé sur le tableau crée un élément Fichier, rangé avec les fichiers.

**UC-H6 — Mentionner un élément dans un autre**
- Dans un post-it ou une tâche (Markdown), on peut insérer un lien interne vers un autre élément (syntaxe `[[…]]` avec autocomplétion). Si l'élément cible est supprimé, le lien s'affiche barré.

**UC-H7 — Étiquettes communes**
- Les étiquettes (tags) sont partagées par tous les types d'éléments. La recherche globale (UC-G2) permet de filtrer par étiquette sur l'ensemble du Board.

**UC-H8 — Accès rapide transverse**
- Tout élément peut être épinglé dans une barre « Accès rapide » visible partout. Épingler une entrée de presse-papier la protège aussi de la purge (UC-B4).

**UC-H9 — Capture rapide universelle**
- Un raccourci global desktop (**Ctrl + Alt + N** / **Cmd + Option + N**), un widget mobile et le menu « Partager » ouvrent une mini-fenêtre de saisie. On choisit le type (post-it, tâche, snippet), sans ouvrir l'application complète.

**UC-H10 — Annuler la dernière action**
- Après une suppression, une transformation ou un déplacement, un bandeau « Annuler » reste affiché 10 secondes. Pour un fichier, la suppression définitive (✅) ne part vers le service de stockage qu'à la fin de ce délai.

**UC-H11 — Dupliquer un élément**

**UC-H12 — Gérer les tableaux**
- Créer, renommer, réordonner, supprimer un tableau. Déplacer un post-it d'un tableau à un autre.
- Supprimer un tableau qui contient des éléments demande une confirmation qui annonce le nombre d'éléments, et propose de les déplacer vers un autre tableau.

---

## I. Cycle de vie complet de l'utilisateur

> Le parcours de l'utilisateur sur la plateforme, de la découverte au départ. Il complète les sections A à H. Toutes les règles sont *(proposé)*, sauf mention contraire.

### I.1 Découverte et premiers pas

**UC-I1 — Découvrir la plateforme**
En tant que visiteur, je veux une page d'accueil qui présente les services et propose « Essayer sans compte » ou « Créer un compte », afin de choisir comment commencer.
- Les liens de téléchargement des apps desktop et mobile figurent sur cette page.

**UC-I2 — Premier lancement (onboarding)**
- 3 à 4 écrans maximum, que l'on peut passer : présentation des services, puis du raccourci global, puis demande d'autorisation des notifications, expliquée avant le dialogue du système.
- Le tableau contient au départ un post-it d'exemple, que l'on peut supprimer. Aucun écran n'est vide sans explication : chaque état vide propose une première action.

**UC-I3 — Passer de visiteur à utilisateur inscrit**
- Une invitation discrète à créer un compte apparaît **aux moments où il apporte quelque chose** : quand le visiteur essaie d'envoyer un fichier, de partager, ou d'utiliser un deuxième appareil. Jamais de fenêtre qui bloque l'usage.
- À l'inscription, le visiteur choisit de **conserver** ses données locales (elles sont chiffrées puis synchronisées) ou de **repartir de zéro**.

**UC-I4 — Sauvegarder sa clé de récupération (rappel)**
- Si l'utilisateur n'a pas confirmé sa sauvegarde, un rappel non bloquant s'affiche au bout de 7 jours, puis tous les 30 jours.
- Précision du 2026-10-09 ✅ : ce rappel ne concerne que les comptes créés avec Google. Pour une inscription par e-mail, la confirmation reste obligatoire (UC-A1).

### I.2 Usage quotidien

**UC-I5 — Voir l'état de synchronisation**
- Un indicateur permanent affiche l'état : synchronisé, en cours, hors ligne (avec le nombre de modifications en attente) ou en erreur, avec une action pour corriger.
- Chaque élément modifié hors ligne et pas encore synchronisé porte un petit marqueur.

**UC-I6 — Être informé d'un conflit résolu**
- Quand une modification hors ligne a été écrasée par une version plus récente (UC-C3), une notification discrète propose « Voir l'historique des versions ».

**UC-I7 — Gérer ses notifications**
- On peut activer ou désactiver les notifications par catégorie (rappels, envois entre appareils, nouvel appareil connecté, sécurité), et par appareil.
- Les notifications de sécurité ne peuvent pas être désactivées.

**UC-I8 — Personnaliser l'interface**
- Thème clair, sombre ou système. Langue : français et anglais en V1 (marché international). Fuseau horaire détecté automatiquement, modifiable. Modification des raccourcis clavier.
- Les préférences sont synchronisées entre appareils, sauf les raccourcis, qui sont propres à chaque appareil desktop.

**UC-I9 — Démarrage automatique (desktop)**
- L'app desktop peut se lancer au démarrage du système, réduite dans la zone de notification, pour capturer le presse-papier dès l'ouverture de session. Activé par défaut ; désactivable.

**UC-I10 — Mises à jour de l'application**
- Desktop : mise à jour automatique, installée au prochain redémarrage de l'app.
- Si une version est trop ancienne pour le serveur (protocole de synchronisation incompatible), la synchronisation se met en pause avec un message « Mettez à jour », sans aucune perte des données locales.

### I.3 Multi-appareils et sécurité

**UC-I11 — Ajouter un nouvel appareil**
- Déverrouillage par un appareil déjà connecté : un code ou QR code s'affiche sur le nouvel appareil et on le valide sur l'ancien. Ou bien par la clé de récupération (UC-A1b).
- Au-delà de 3 appareils (✅), l'écran affiche la liste des appareils existants pour en révoquer un sans quitter le parcours.
- Les autres appareils reçoivent la notification « Nouvel appareil connecté : [nom], [lieu approximatif] ».

**UC-I12 — Perdre un appareil**
- Depuis un autre appareil ou le web, on le révoque (UC-A4). L'appareil révoqué efface ses données locales dès qu'il se reconnecte.

**UC-I13 — Changer son mot de passe**
- L'ancien mot de passe est demandé. Les autres sessions restent actives, avec une option « Déconnecter tous les autres appareils ».

**UC-I14 — Changer son adresse e-mail**
- Un code de vérification est envoyé à la nouvelle adresse, et une alerte à l'ancienne. Le changement n'est effectif qu'après validation du code.

**UC-I15 — Régénérer sa clé de récupération**
- Le mot de passe est demandé. L'ancienne clé est invalidée immédiatement.

**UC-I16 — Lier / délier son compte Google**
- Un compte peut avoir e-mail + mot de passe, Google, ou les deux. Il est impossible de délier Google s'il n'existe pas de mot de passe ; l'application propose alors d'en créer un d'abord.

**UC-I17 — Expiration de session**
- Une session reste ouverte 30 jours sans activité. Au-delà, il faut se reconnecter, et les données locales restent sur l'appareil, chiffrées.

**UC-I18 — Verrouillage local de l'application**
- Option désactivée par défaut : un code PIN ou la biométrie (empreinte, visage) à l'ouverture de l'app mobile ou desktop.

### I.4 Partage avec l'extérieur (destinataire d'un lien)

**UC-I19 — Ouvrir un lien public**
En tant que destinataire (sans compte), je veux ouvrir un lien partagé, saisir le mot de passe s'il y en a un, puis télécharger le fichier ou lire l'élément, afin de récupérer ce qu'on m'a envoyé.
- Lien expiré, révoqué ou désactivé : une page claire l'indique, sans dire s'il a existé.
- 5 mots de passe faux en 15 min bloquent le lien pour cette adresse IP pendant 15 min.

**UC-I20 — Signaler un lien public**
- Bouton « Signaler », avec un motif choisi dans une liste et un champ libre facultatif. L'administrateur reçoit le signalement (UC-G3).

**UC-I21 — Suivre ses liens publics**
- L'utilisateur voit tous ses liens actifs (élément, date de création, expiration, nombre de téléchargements) et peut en révoquer un ou en prolonger un.

### I.5 Aide et relation avec la plateforme

**UC-I22 — Obtenir de l'aide**
- Un centre d'aide (FAQ) et un formulaire de contact, avec envoi facultatif d'informations techniques (version, système, journal d'erreurs **sans contenu utilisateur**).

**UC-I23 — Accepter les nouvelles conditions d'utilisation**
- Quand les conditions ou la politique de confidentialité changent, l'utilisateur est informé et doit les accepter à sa prochaine ouverture de l'app. La date et la version acceptées sont conservées (preuve du consentement).

**UC-I24 — Être informé d'une suspension**
- Un compte suspendu (UC-G3) voit un message avec le motif et un moyen de contester. Il garde l'accès en lecture et l'export de ses données, mais ne peut plus synchroniser ni partager.

### I.6 Départ

**UC-I25 — Exporter ses données** (déjà en UC-A6)

**UC-I26 — Supprimer son compte, puis changer d'avis**
- Pendant le délai de grâce de 30 jours (UC-A5), il suffit de se reconnecter pour annuler la suppression. Des e-mails de rappel sont envoyés à J-7 et J-1.

**UC-I27 — Compte inactif**
- ✅ Après **12 mois** sans connexion, un e-mail prévient l'utilisateur. Sans réaction dans les 30 jours, le compte est supprimé (principe de limitation de la durée de conservation, loi 2017-20 et RGPD).

### I.7 Administration (cycle de vie côté plateforme)

**UC-I28 — Traiter un signalement**
- L'administrateur peut classer le signalement sans suite, désactiver le lien, ou suspendre le compte. L'auteur du signalement n'est pas informé de la décision ; le propriétaire du lien l'est.

**UC-I29 — Superviser la plateforme**
- Tableau de bord : nombre d'inscriptions et d'utilisateurs actifs, volume de fichiers, état du fournisseur de stockage (LuluFiles ou Telegram direct), erreurs de synchronisation. Jamais aucun contenu.

**UC-I30 — Publier une annonce**
- Un message court (maintenance, nouveauté) affiché dans toutes les apps, que l'utilisateur peut fermer.

---

## Hors V1

- Premium, abonnements, paiements.
- Expansion de snippets au clavier.

## Questions encore ouvertes

Aucune. Prochaine étape après validation : diagrammes UML (cas d'utilisation, puis classes).

# LuluBoard — Journal des décisions

> Depuis le 2026-10-10, l'utilisateur m'a délégué toutes les décisions logiques nécessaires pour livrer un MVP fonctionnel. Chaque décision est notée ici avec sa raison, pour le bilan final.
> Les décisions antérieures (étapes 1 à 3) ont été validées explicitement : voir `01` à `05`.

| # | Date | Sujet | Décision | Raison |
|---|---|---|---|---|
| D1 | 10/10 | Réinscription | Un e-mail inscrit mais jamais vérifié peut être réinscrit. | Éviter qu'une faute de frappe bloque une adresse. |
| D2 | 10/10 | Google et compte e-mail | Pas de fusion automatique : se connecter par mot de passe, puis lier Google. | Empêcher la prise de contrôle d'un compte. |
| D3 | 10/10 | Compte non vérifié à la connexion | `403 email_non_verifie` + renvoi d'un code (bon mot de passe uniquement). | Débloquer l'utilisateur sans révéler l'existence des comptes. |
| D4 | 10/10 | Réponse de la réinitialisation | `204` sans corps ; le rappel A3 est affiché par l'app. | Un `204` ne peut pas porter de message. |
| D5 | 10/10 | `/health` | `503` si la base est injoignable. | Permettre à l'hébergeur de détecter la panne. |
| D6 | 10/10 | `X-App-Version` absent | Requête acceptée. | Pages publiques et outils de test. |
| D7 | 10/10 | Refuser un déverrouillage | L'appareil demandeur est révoqué. | Refuser veut dire « ce n'est pas moi ». |
| D8 | 10/10 | Régénérer la clé de récupération d'un compte Google sans mot de passe | Un jeton Google récent remplace le mot de passe. | Ces comptes n'ont pas de mot de passe à redemander. |
| D9 | 10/10 | Code de déverrouillage | Visible seulement sur le nouvel appareil ; l'approbateur doit le recopier ; `clePubliqueDemandeur` ajoutée à la demande. | Preuve de présence physique ; l'approbateur a besoin de la clé publique pour envelopper la clé maître. |
| D10 | 10/10 | Durées | Demande de déverrouillage : 10 min ; défi de récupération : 5 min, usage unique. | Courtes, pour limiter les attaques. |
| D11 | 10/10 | Enveloppes invalidées | Leur contenu est vidé, pas seulement marqué. | Une fuite de la base ne les rend pas exploitables. |
| D12 | 10/10 | Nouvelle clé de récupération | Doit être reconfirmée comme sauvegardée. | Même règle que A1. |
| D13 | 10/10 | `GET /appareils` | Les appareils révoqués ne sont pas listés. | Ils ne servent plus à rien côté utilisateur. |
| D14 | 10/10 | Actions sensibles d'un compte Google sans mot de passe (changer d'e-mail, supprimer le compte) | Confirmation par un jeton Google récent. | Même logique que D8. |
| D15 | 10/10 | `PATCH`/`DELETE /compte` | Restent possibles avec des conditions non acceptées ou une clé non confirmée. | Refuser les nouvelles conditions doit permettre de partir. |
| D16 | 10/10 | Notifications | Toutes les catégories actives par défaut ; `SECURITE` est toujours réactivée. | I7. |
| D17 | 10/10 | Jeton push | Envoyé par `PUT /appareils/courant/preferences`, jamais renvoyé dans les réponses. | C'est un secret de l'appareil. |
| D18 | 10/10 | Durée « 1 h » | Refusée pour le presse-papier, acceptée pour les versions. | Respect exact de B4 et de C3. |
| D19 | 10/10 | Suppression synchronisée | Définitive : un élément supprimé ne peut pas être recréé par une modification plus récente ; son contenu est effacé du serveur. | Pas de corbeille (décision validée) ; effacement réel. |
| D20 | 10/10 | Historique des post-it | Créé par le serveur à chaque modification acceptée, et pour le perdant d'un conflit ; le client ne pousse pas de versions. | Une seule source de vérité ; rien n'est perdu (C3, I6). |
| D21 | 10/10 | Rattachements (parent, étiquette, rappel) | Identifiants simples, sans clé étrangère. | Un lot hors ligne peut arriver dans n'importe quel ordre. |
| D22 | 10/10 | Celery en local | Exécution immédiate dans le processus web (`CELERY_TASK_ALWAYS_EAGER=true`) ; worker réel en production. | Pas de worker à lancer pendant le développement. |
| D23 | 10/10 | Téléchargements en mode LuluFiles | Passent par notre serveur tant que `LULUFILES_CORS_OUVERT=false`. | Le MVP fonctionne sans attendre la modification CORS de LuluFiles. |
| D24 | 10/10 | Tailles maximales | Corps JSON : 12 Mo ; envoi de fichier : 101 Mo ; lot de synchronisation : 500 changements. | Refus précoce des abus, avant lecture du corps. |
| D25 | 10/10 | Type d'un élément | Immuable : une transformation (H1) crée un nouvel élément. | Cohérent avec la règle « créer une copie par défaut ». |
| D26 | 10/10 | Fichier supprimé | Effacé chez le fournisseur ; un message Telegram de plus de 48 h reste dans le canal, mais chiffré et sans clé. | Limite de Telegram ; effacement cryptographique. |
| D27 | 10/10 | WebSocket | Route `/api/v1/ws` ; jeton dans le premier message ; fermeture `4401` (authentification) et `4403` (appareil révoqué). | Le jeton ne doit pas apparaître dans les URL. |
| D28 | 10/10 | Envoi « à tous mes appareils » | Un seul envoi, avec la liste des appareils qui l'ont récupéré. | Pas de duplication du contenu chiffré. |
| D29 | 10/10 | Notifications push | **FCM pour toutes les plateformes, web compris** (au lieu du Web Push standard prévu pour le web). | Tout aussi gratuit, un seul code d'envoi. |
| D30 | 10/10 | Format de chiffrement | Spécification v1 : `docs/07-format-chiffrement.md` (XChaCha20-Poly1305 avec données associées, `crypto_box_seal`, secretstream pour les fichiers, Argon2id pour les liens). | Format commun à l'app, à la page publique et aux tests. |
| D31 | 10/10 | Comptes jamais vérifiés | Supprimés après 7 jours. | Aucune donnée utile ; libère l'adresse. |
| D32 | 10/10 | Compteur de téléchargements d'un lien | Incrémenté uniquement au début d'un téléchargement (pas à chaque reprise `Range`). | Compter les vrais téléchargements. |
| D33 | 10/10 | Texte des notifications push | Générique, sans aucun contenu (« Vous avez un rappel »). | Chiffrement de bout en bout. |
| D34 | 10/10 | Suspension (administration) | Ferme les sessions, désactive le lien, informe le propriétaire par e-mail ; contestation par réponse à cet e-mail. | I24 sans développer d'interface dédiée. |
| D35 | 10/10 | Purge du presse-papier | Une entrée épinglée **ou** placée en accès rapide n'est jamais purgée. | H8. |
| D36 | 10/10 | Équivalent Postman de l'étape 5 | Scénario Python de bout en bout avec la vraie cryptographie (`backend/e2e/`). | Valide l'API **et** le format de chiffrement ; réutilisable. |
| D37 | 10/10 | Production | HTTPS forcé, HSTS d'un an, cookies sécurisés dès que `DJANGO_DEBUG=false`. | Durcissement standard (`check --deploy`). |
| D38 | 10/10 | Base locale de l'app | **sembast** (sans génération de code, web via IndexedDB) au lieu de drift/SQLite prévu dans l'ADR. | Fonctionne à l'identique sur les 6 plateformes, sans étape de génération ; suffisant pour le volume d'un utilisateur. |
| D39 | 10/10 | Recherche locale | Filtrage en mémoire sur les données déchiffrées (pas de FTS5). | Conséquence de D38 ; instantané jusqu'à plusieurs milliers d'éléments. |
| D40 | 10/10 | Étapes 6 et 7 de la méthode | App construite directement contre le backend validé, sans phase intermédiaire sur données fictives. | Le backend est déjà validé de bout en bout : la phase « mock » n'apporterait rien et doublerait le travail. |
| D41 | 10/10 | Données sur l'appareil | Contenus déchiffrés en base locale ; clé maître, clé privée d'appareil et jeton dans le stockage sécurisé du système. | L'appareil est de confiance ; le verrou local (I18) le protège en option. |
| D42 | 10/10 | Langue de l'interface MVP | Français d'abord, textes centralisés pour ajouter l'anglais ensuite. | Livrer vite un MVP cohérent. |
| D43 | 10/10 | Déconnexion | Efface les clés **et** les données locales de l'appareil (elles restent sur le compte). | Un appareil prêté ou vendu ne garde rien. |
| D44 | 10/10 | Bibliothèque libsodium sous Windows | Copie locale corrigée de `sodium` (`app/third_party/sodium`) : son hook de compilation exige MSBuild 17.8 (VS 2022) ; le correctif fonctionne avec VS 2019. | Évite d'installer Visual Studio 2022 (6 à 8 Go) sur un disque C: presque plein. |
| D45 | 10/10 | Compatibilité du chiffrement | Vecteurs de test produits par l'implémentation Python (validée de bout en bout) et vérifiés en Dart (`app/test/chiffrement_test.dart`). | Garantit que l'app et le serveur parlent exactement le même format. |
| D46 | 10/10 | Post-it « au premier plan » | Garde toute la fenêtre de l'app au-dessus des autres (pas de fenêtre séparée par post-it dans le MVP). | Les fenêtres multiples Flutter desktop demandent une dépendance lourde. |
| D47 | 10/10 | Rappels sans push configuré | Planificateur local dans l'app (notification système sur desktop) ; avec FCM configuré, le serveur envoie aussi un push. | Rappels fonctionnels dès le MVP, sans compte Firebase. |
| D48 | 10/10 | Capture des images du presse-papier (B1) | Reportée : le MVP capture le texte et les liens ; les images peuvent être ajoutées comme fichiers. | L'API de presse-papier de Flutter ne lit que le texte ; les plugins d'images exigent une chaîne Rust. |
| D49 | 10/10 | Liens publics déjà créés | L'URL complète (avec la clé après `#`) est mémorisée sur l'appareil qui l'a créée, pour pouvoir la recopier. | Le serveur ne connaît ni le jeton en clair ni la clé. |
| D50 | 10/10 | CORS pour Flutter Web | Activation de `django-cors-headers` avec `CORS_ALLOWED_ORIGINS` configurable (`http://localhost:5000` par défaut). | Permettre à l'application cliente compilée pour le Web d'interroger l'API Django sans blocage navigateur. |
| D51 | 10/10 | Pas de conteneurisation Docker | Déploiement direct sans Docker (PaaS natif Python/Node, services managés PostgreSQL et Redis, ou serveur bare-metal). | Décision et contrainte ferme exprimée par l'utilisateur. |

| D52 | 13/10 | Polices du design system | Rubik et Itim embarquées dans l'app (`app/assets/fonts/`) et la page d'accueil (`public/fonts/`) au lieu d'être téléchargées depuis Google ; licences OFL enregistrées. | Fonctionne hors ligne et n'envoie pas l'adresse IP des utilisateurs à Google (RGPD, cohérent avec la promesse de confidentialité). |
| D53 | 13/10 | Contraste des boutons d'accent | Texte `#020617` sur le vert `#22C55E` en sombre ; accent `#15803D` avec texte blanc en clair ; test automatique ≥ 4,5:1. | Le texte blanc sur `#22C55E` (≈ 2,3:1) échoue au niveau WCAG AA. |
| D54 | 13/10 | Esprit UX unifié | Filtre en direct sur chaque écran (surlignage, Échap pour vider, Ctrl+F), état « aucun résultat » avec action, confirmation explicite des actions risquées, messages proposant l'action suivante ; composants partagés dans `app/lib/ui/recherche_locale.dart`. | Généraliser les améliorations apportées à l'écran Réglages. |
| D55 | 13/10 | Page de consultation des liens publics | Page web statique autonome (`public/l/`) qui déchiffre le contenu dans le navigateur avec libsodium ; la clé reste dans le fragment `#`, jamais envoyée au serveur. | Le destinataire d'un lien n'a pas l'app ; le serveur ne doit jamais voir le contenu en clair. |

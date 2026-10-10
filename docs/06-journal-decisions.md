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

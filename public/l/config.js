// Configuration de la page publique des liens LuluBoard : seul endroit à modifier au déploiement.
// - apiUrl : origine de l'API (sans /api/v1). Chaîne vide "" = même origine que la page
//   (cas où le backend sert lui-même /l/*).
// - accueilUrl : page d'accueil LuluBoard.
// Pensez à garder la directive connect-src de la CSP (index.html) cohérente avec apiUrl.
window.LULUBOARD_CONFIG = Object.freeze({
  apiUrl: "http://127.0.0.1:8000",
  accueilUrl: "/",
});

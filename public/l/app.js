// Page publique d'un lien LuluBoard (contrat 2.10, format de chiffrement v1 : docs/07-format-chiffrement.md).
// Tout le déchiffrement a lieu ici, dans le navigateur ; la clé du lien (fragment #) n'est jamais envoyée.
(function () {
  "use strict";

  const CONFIG = window.LULUBOARD_CONFIG || { apiUrl: "http://127.0.0.1:8000", accueilUrl: "/" };
  const API = String(CONFIG.apiUrl).replace(/\/+$/, "") + "/api/v1";
  const VERSION_FORMAT = 0x01;
  const NONCE = 24;
  const BLOC_CLAIR = 64 * 1024;
  const ACTUALISATION_MS = 60 * 1000;
  const TYPES = { POST_IT: "Post-it", SNIPPET: "Snippet", LISTE_TACHES: "Liste de tâches", FICHIER: "Fichier" };

  const $ = (id) => document.getElementById(id);
  let sodium = null;

  // État de la session (en mémoire uniquement).
  const etat = {
    jeton: null,
    cleElement: null,          // K_el (Uint8Array)
    verificateur: null,        // pour réactualiser un lien protégé
    jetonTelechargement: null, // lien protégé + fichier
    type: null,
    telechargementEnCours: false,
    minuteur: null,
  };

  // --- Utilitaires ----------------------------------------------------------------------

  class ErreurLien extends Error {
    constructor(titre, message, options = {}) {
      super(message);
      this.titre = titre;
      this.statut = options.statut;
      this.code = options.code;
    }
  }

  function attendreSodium() {
    return new Promise((resoudre, rejeter) => {
      const debut = Date.now();
      (function verifier() {
        if (window.sodium && window.sodium.ready) {
          window.sodium.ready.then(() => resoudre(window.sodium), rejeter);
        } else if (Date.now() - debut > 20000) {
          rejeter(new Error("libsodium indisponible"));
        } else {
          setTimeout(verifier, 25);
        }
      })();
    });
  }

  const b64 = (texte) => sodium.from_base64(texte, sodium.base64_variants.URLSAFE_NO_PADDING);
  const vers64 = (octets) => sodium.to_base64(octets, sodium.base64_variants.URLSAFE_NO_PADDING);

  function ouvrir(cle, chiffre, ad) {
    if (!chiffre || chiffre.length < 1 + NONCE + 16 || chiffre[0] !== VERSION_FORMAT) throw new Error("format inconnu");
    return sodium.crypto_aead_xchacha20poly1305_ietf_decrypt(
      null, chiffre.subarray(1 + NONCE), sodium.from_string(ad), chiffre.subarray(1, 1 + NONCE), cle,
    );
  }

  function ouvrirJson(cle, contenu64, ad) {
    return JSON.parse(sodium.to_string(ouvrir(cle, b64(contenu64), ad)));
  }

  function lireJeton() {
    const chemin = /\/l\/([A-Za-z0-9_-]{8,})\/?$/.exec(window.location.pathname);
    if (chemin && chemin[1] !== "index") return chemin[1];
    const t = new URLSearchParams(window.location.search).get("t");
    return t && /^[A-Za-z0-9_-]+$/.test(t) ? t : null;
  }

  function lireCleFragment() {
    const brut = decodeURIComponent(window.location.hash.replace(/^#/, "")).trim();
    if (!brut) return null;
    try {
      const cle = b64(brut);
      return cle.length === 32 ? cle : "invalide";
    } catch (_) {
      return "invalide";
    }
  }

  function formatTaille(octets) {
    if (!Number.isFinite(octets) || octets < 0) return "taille inconnue";
    const unites = ["octets", "Ko", "Mo", "Go"];
    let v = octets, u = 0;
    while (v >= 1024 && u < unites.length - 1) { v /= 1024; u++; }
    return (u === 0 ? v : v.toLocaleString("fr-FR", { maximumFractionDigits: 1 })) + " " + unites[u];
  }

  function formatDate(iso) {
    const d = new Date(iso);
    return isNaN(d) ? "" : d.toLocaleString("fr-FR", { dateStyle: "medium", timeStyle: "short" });
  }

  function el(balise, classe, texte) {
    const n = document.createElement(balise);
    if (classe) n.className = classe;
    if (texte !== undefined && texte !== null) n.textContent = texte;
    return n;
  }

  // --- API ------------------------------------------------------------------------------

  async function appelApi(chemin, options = {}) {
    let reponse;
    try {
      reponse = await fetch(API + chemin, {
        method: options.method || "GET",
        headers: options.corps ? { "Content-Type": "application/json", Accept: "application/json" } : { Accept: "application/json" },
        body: options.corps ? JSON.stringify(options.corps) : undefined,
        credentials: "omit",
        cache: "no-store",
        referrerPolicy: "no-referrer",
      });
    } catch (_) {
      throw new ErreurLien("Serveur injoignable", "Impossible de joindre LuluBoard. Vérifiez votre connexion puis réessayez.");
    }
    let corps = null;
    try { corps = await reponse.json(); } catch (_) { /* corps vide */ }
    if (!reponse.ok) throw erreurDepuisReponse(reponse.status, corps && corps.erreur ? corps.erreur.code : null);
    return corps;
  }

  function erreurDepuisReponse(statut, code) {
    const o = { statut, code };
    if (statut === 410 || code === "lien_expire" || statut === 404)
      return new ErreurLien("Lien indisponible", "Ce lien a expiré, a été révoqué ou n'existe pas. Demandez un nouveau lien à la personne qui vous l'a envoyé.", o);
    if (statut === 423 || code === "lien_bloque")
      return new ErreurLien("Trop d'essais", "Trop de mots de passe incorrects. Réessayez dans 15 minutes.", o);
    if (statut === 422 && code === "validation")
      return new ErreurLien("Mot de passe incorrect", "Mot de passe incorrect. Vérifiez-le et réessayez.", o);
    if (statut === 429)
      return new ErreurLien("Trop de requêtes", "Trop de requêtes depuis votre connexion. Patientez une minute puis réessayez.", o);
    if (statut === 403)
      return new ErreurLien("Accès expiré", "L'autorisation de téléchargement a expiré. Actualisez la page et saisissez à nouveau le mot de passe.", o);
    if (statut === 409)
      return new ErreurLien("Fichier pas encore prêt", "Le fichier est encore en cours de traitement. Réessayez dans quelques instants.", o);
    return new ErreurLien("Erreur inattendue", "Le serveur a répondu de façon inattendue (HTTP " + statut + "). Réessayez plus tard.", o);
  }

  // --- Affichage des états ---------------------------------------------------------------

  function afficherChargement(message) {
    const bloc = $("etat");
    bloc.hidden = false;
    bloc.classList.remove("erreur-etat");
    bloc.replaceChildren(el("div", "chargeur"), el("p", null, message));
    bloc.firstChild.setAttribute("aria-hidden", "true");
  }

  function afficherErreur(titre, message) {
    arreterActualisation();
    $("formulaire-mdp").hidden = true;
    $("resultat").hidden = true;
    $("actions-live").hidden = true;
    const bloc = $("etat");
    bloc.hidden = false;
    bloc.classList.add("erreur-etat");
    const texte = el("div");
    texte.append(el("h1", null, titre), el("p", "texte-doux", message));
    bloc.replaceChildren(texte);
    bloc.setAttribute("role", "alert");
    document.title = titre + " · LuluBoard";
  }

  // --- Rendu par type ---------------------------------------------------------------------

  function entete(type, titre, meta) {
    const frag = document.createDocumentFragment();
    frag.appendChild(el("p", "sur-titre", TYPES[type] || type));
    if (titre) frag.appendChild(el("h1", "titre", titre));
    if (meta) frag.appendChild(el("p", "meta", meta));
    return frag;
  }

  function metaModifie(element) {
    return element.modifieLe ? "Dernière modification : " + formatDate(element.modifieLe) : "";
  }

  function rendrePostIt(element, donnees) {
    const zone = el("div", "post-it");
    if (/^#[0-9a-fA-F]{6}$/.test(donnees.couleurFond || "")) zone.style.setProperty("--couleur-post-it", donnees.couleurFond);
    const contenu = String(donnees.contenu || "");
    zone.appendChild(contenu.trim() ? window.LuluMarkdown.rendre(contenu) : el("p", "vide", "Ce post-it est vide."));
    return [entete("POST_IT", null, metaModifie(element)), zone];
  }

  function rendreSnippet(element, donnees) {
    const barre = el("div", "barre-code");
    barre.appendChild(el("span", "langage", donnees.langage || "texte"));
    const bouton = el("button", "bouton bouton-principal", "Copier");
    bouton.type = "button";
    const annonce = el("span", "texte-doux");
    annonce.setAttribute("aria-live", "polite");
    const actions = el("div");
    actions.append(annonce, document.createTextNode(" "), bouton);
    barre.appendChild(actions);
    const pre = el("pre");
    const code = el("code", null, String(donnees.contenu || ""));
    pre.appendChild(code);
    pre.tabIndex = 0;
    pre.setAttribute("aria-label", "Code du snippet");
    bouton.addEventListener("click", async () => {
      const ok = await copier(String(donnees.contenu || ""), code);
      annonce.textContent = ok ? "Copié dans le presse-papier." : "Copie impossible : sélectionnez le texte manuellement.";
      bouton.textContent = ok ? "Copié" : "Copier";
      setTimeout(() => { bouton.textContent = "Copier"; annonce.textContent = ""; }, 2500);
    });
    return [entete("SNIPPET", donnees.titre || "Snippet sans titre", metaModifie(element)), barre, pre];
  }

  async function copier(texte, noeud) {
    try {
      await navigator.clipboard.writeText(texte);
      return true;
    } catch (_) {
      try {
        const plage = document.createRange();
        plage.selectNodeContents(noeud);
        const sel = window.getSelection();
        sel.removeAllRanges();
        sel.addRange(plage);
        return document.execCommand("copy");
      } catch (__) {
        return false;
      }
    }
  }

  function rendreListeTaches(element, donnees) {
    const enfants = new Map();
    let total = 0, faites = 0, illisibles = 0;
    for (const t of element.taches || []) {
      let d;
      try {
        d = ouvrirJson(etat.cleElement, t.contenuChiffre, "el:" + t.id);
      } catch (_) {
        illisibles++;
        continue;
      }
      total++;
      if (d.faite) faites++;
      const parent = t.parentId || element.id;
      if (!enfants.has(parent)) enfants.set(parent, []);
      enfants.get(parent).push({ id: t.id, d });
    }
    const PRIO = { HAUTE: "Priorité haute", BASSE: "Priorité basse" };

    function construire(parentId, profondeur) {
      const items = (enfants.get(parentId) || []).sort((a, b) => (a.d.ordre ?? 0) - (b.d.ordre ?? 0));
      if (!items.length) return null;
      const ul = el("ul", profondeur === 0 ? "taches" : null);
      for (const { id, d } of items) {
        const li = el("li", "tache");
        const ligne = el("div", "tache-ligne");
        const caseT = el("span", "case" + (d.faite ? " faite" : ""));
        caseT.setAttribute("role", "img");
        caseT.setAttribute("aria-label", d.faite ? "Faite" : "À faire");
        const titre = el("div", "tache-titre" + (d.faite ? " faite" : ""));
        titre.appendChild(window.LuluMarkdown.enLigne(d.titre || "Sans titre"));
        if (PRIO[d.priorite]) titre.appendChild(el("span", "etiquette-tache" + (d.priorite === "HAUTE" ? " haute" : ""), PRIO[d.priorite]));
        if (d.echeance) titre.appendChild(el("span", "etiquette-tache", "Échéance : " + formatDate(d.echeance)));
        ligne.append(caseT, titre);
        li.appendChild(ligne);
        const sous = construire(id, profondeur + 1);
        if (sous) li.appendChild(sous);
        ul.appendChild(li);
      }
      return ul;
    }

    const meta = total ? faites + " sur " + total + " tâche" + (total > 1 ? "s" : "") + " terminée" + (faites > 1 ? "s" : "") : "";
    const blocs = [entete("LISTE_TACHES", donnees.titre || "Liste sans titre", [meta, metaModifie(element)].filter(Boolean).join(" · "))];
    const arbre = construire(element.id, 0);
    blocs.push(arbre || el("p", "vide", "Cette liste ne contient aucune tâche."));
    if (illisibles) blocs.push(el("p", "meta", illisibles + " tâche(s) n'ont pas pu être déchiffrées."));
    return blocs;
  }

  function rendreFichier(element, donnees) {
    const nom = String(donnees.nom || "fichier");
    const extension = (/\.([A-Za-z0-9]{1,5})$/.exec(nom) || [, "?"])[1];
    const bloc = el("div", "fichier");
    const icone = el("div", "icone-fichier", extension);
    icone.setAttribute("aria-hidden", "true");
    const info = el("div", "fichier-info");
    info.append(el("h1", "titre", nom), el("p", "meta", formatTaille(Number(donnees.taille)) + (donnees.typeMime ? " · " + donnees.typeMime : "")));
    const bouton = el("button", "bouton bouton-principal", "Télécharger");
    bouton.type = "button";
    bloc.append(icone, info, bouton);
    const progression = el("progress");
    progression.max = 100;
    progression.value = 0;
    progression.hidden = true;
    progression.setAttribute("aria-label", "Progression du téléchargement");
    const message = el("p", "meta");
    message.setAttribute("aria-live", "polite");
    bouton.addEventListener("click", () => telecharger(element, donnees, bouton, progression, message));
    const p = el("p", "sur-titre", TYPES.FICHIER);
    return [p, bloc, progression, message];
  }

  // --- Téléchargement d'un fichier (secretstream, blocs de 64 Kio) ---------------------------

  async function telecharger(element, donnees, bouton, progression, message) {
    if (etat.telechargementEnCours) return;
    etat.telechargementEnCours = true;
    bouton.disabled = true;
    progression.hidden = false;
    progression.value = 0;
    message.textContent = "Téléchargement et déchiffrement en cours…";
    try {
      let url = API + "/public/liens/" + encodeURIComponent(etat.jeton) + "/fichier";
      if (etat.jetonTelechargement) url += "?t=" + encodeURIComponent(etat.jetonTelechargement);
      let reponse;
      try {
        reponse = await fetch(url, { credentials: "omit", cache: "no-store", referrerPolicy: "no-referrer" });
      } catch (_) {
        throw new ErreurLien("Serveur injoignable", "Le téléchargement a échoué : serveur injoignable.");
      }
      if (!reponse.ok) {
        let code = null;
        try { code = (await reponse.json()).erreur.code; } catch (_) { /* rien */ }
        throw erreurDepuisReponse(reponse.status, code);
      }
      const total = Number(reponse.headers.get("Content-Length")) || Number(element.tailleOctets) || 0;
      const parties = await dechiffrerFlux(reponse.body.getReader(), total, (fait) => {
        if (total) progression.value = Math.min(100, Math.round((fait / total) * 100));
      });
      const blob = new Blob(parties, { type: donnees.typeMime || "application/octet-stream" });
      const a = document.createElement("a");
      a.href = URL.createObjectURL(blob);
      a.download = String(donnees.nom || "fichier").replace(/[\\/:*?"<>|\u0000-\u001f]/g, "_");
      document.body.appendChild(a);
      a.click();
      a.remove();
      setTimeout(() => URL.revokeObjectURL(a.href), 60000);
      progression.value = 100;
      message.textContent = "Fichier déchiffré et enregistré (" + formatTaille(blob.size) + ").";
    } catch (e) {
      message.textContent = e instanceof ErreurLien ? e.message : "Le fichier n'a pas pu être déchiffré : il est incomplet ou la clé est incorrecte.";
      progression.hidden = true;
    } finally {
      etat.telechargementEnCours = false;
      bouton.disabled = false;
    }
  }

  async function dechiffrerFlux(lecteur, total, surProgression) {
    const ENTETE = sodium.crypto_secretstream_xchacha20poly1305_HEADERBYTES;
    const BLOC = BLOC_CLAIR + sodium.crypto_secretstream_xchacha20poly1305_ABYTES;
    const FINAL = sodium.crypto_secretstream_xchacha20poly1305_TAG_FINAL;
    let tampon = new Uint8Array(0);
    let recu = 0, etatFlux = null, fini = false;
    const parties = [];

    const ajouter = (morceau) => {
      const n = new Uint8Array(tampon.length + morceau.length);
      n.set(tampon);
      n.set(morceau, tampon.length);
      tampon = n;
    };
    const traiterBloc = (bloc) => {
      if (fini) throw new Error("données après le bloc final");
      const r = sodium.crypto_secretstream_xchacha20poly1305_pull(etatFlux, bloc);
      if (!r || !r.message) throw new Error("bloc invalide");
      parties.push(r.message);
      if (r.tag === FINAL) fini = true;
    };

    for (;;) {
      const { done, value } = await lecteur.read();
      if (value) {
        ajouter(value);
        recu += value.length;
        surProgression(recu);
      }
      if (!etatFlux && tampon.length >= ENTETE) {
        etatFlux = sodium.crypto_secretstream_xchacha20poly1305_init_pull(tampon.slice(0, ENTETE), etat.cleElement);
        tampon = tampon.slice(ENTETE);
      }
      // On garde toujours au moins un bloc en réserve tant que le flux n'est pas terminé.
      let debut = 0;
      while (etatFlux && tampon.length - debut > BLOC) {
        traiterBloc(tampon.subarray(debut, debut + BLOC));
        debut += BLOC;
      }
      if (debut) tampon = tampon.slice(debut);
      if (done) break;
    }
    if (!etatFlux) throw new Error("fichier trop court");
    if (tampon.length) traiterBloc(tampon);
    if (!fini) throw new Error("fichier tronqué");
    return parties;
  }

  // --- Chargement ------------------------------------------------------------------------

  function afficherElement(element) {
    let donnees;
    try {
      donnees = ouvrirJson(etat.cleElement, element.contenuChiffre, "el:" + element.id);
    } catch (_) {
      throw new ErreurLien("Déchiffrement impossible", "La clé de ce lien est incorrecte ou incomplète. Vérifiez que vous avez copié le lien en entier, y compris la partie après « # ».");
    }
    const rendus = { POST_IT: rendrePostIt, SNIPPET: rendreSnippet, LISTE_TACHES: rendreListeTaches, FICHIER: rendreFichier };
    const rendu = rendus[element.type];
    if (!rendu) throw new ErreurLien("Type non pris en charge", "Ce type de contenu ne peut pas être affiché sur cette page.");
    const resultat = $("resultat");
    // Ne pas écraser l'écran d'un fichier pendant un téléchargement.
    if (element.type === "FICHIER" && etat.type === "FICHIER" && !resultat.hidden) return;
    resultat.replaceChildren(...rendu(element, donnees));
    resultat.hidden = false;
    etat.type = element.type;
    $("etat").hidden = true;
    $("formulaire-mdp").hidden = true;
    $("actions-live").hidden = element.type === "FICHIER";
    $("maj-texte").textContent = "Contenu en direct : dernière version, chargée à " + new Date().toLocaleTimeString("fr-FR", { hour: "2-digit", minute: "2-digit" }) + ".";
    const titre = element.type === "FICHIER" ? donnees.nom : donnees.titre;
    document.title = (titre || TYPES[element.type] || "Contenu partagé") + " · LuluBoard";
  }

  async function charger(silencieux) {
    if (!silencieux) afficherChargement("Chargement du contenu partagé…");
    if (etat.verificateur) {
      const r = await appelApi("/public/liens/" + encodeURIComponent(etat.jeton) + "/deverrouiller", {
        method: "POST", corps: { verificateurMotDePasse: vers64(etat.verificateur) },
      });
      etat.jetonTelechargement = r.jetonTelechargement || null;
      afficherElement(r.element);
      return;
    }
    const meta = await appelApi("/public/liens/" + encodeURIComponent(etat.jeton));
    if (meta.protegeParMotDePasse) {
      afficherFormulaire(meta);
      return;
    }
    const cle = lireCleFragment();
    if (!cle) throw new ErreurLien("Clé absente du lien", "Ce lien est incomplet : la clé de déchiffrement (la partie après « # ») manque. Demandez à nouveau le lien complet.");
    if (cle === "invalide") throw new ErreurLien("Clé invalide", "La clé contenue dans ce lien est mal formée. Vérifiez que vous avez copié le lien en entier.");
    etat.cleElement = cle;
    afficherElement(meta.element);
    demarrerActualisation();
  }

  function afficherFormulaire(meta) {
    $("etat").hidden = true;
    $("formulaire-mdp").hidden = false;
    document.title = "Lien protégé · LuluBoard";
    const champ = $("champ-mdp");
    champ.focus();
    const form = $("form-mdp");
    if (form.dataset.pret) return;
    form.dataset.pret = "1";
    form.addEventListener("submit", async (ev) => {
      ev.preventDefault();
      const erreur = $("erreur-mdp");
      const bouton = $("bouton-deverrouiller");
      const mdp = champ.value;
      erreur.hidden = true;
      champ.removeAttribute("aria-invalid");
      if (!mdp) {
        erreur.textContent = "Saisissez le mot de passe.";
        erreur.hidden = false;
        champ.setAttribute("aria-invalid", "true");
        champ.focus();
        return;
      }
      bouton.disabled = true;
      bouton.textContent = "Vérification…";
      await new Promise((r) => setTimeout(r, 30)); // laisser le navigateur afficher l'état avant Argon2id
      try {
        const sel = b64(meta.selDerivation);
        const s = sodium.crypto_pwhash(
          64, mdp, sel,
          sodium.crypto_pwhash_OPSLIMIT_INTERACTIVE, sodium.crypto_pwhash_MEMLIMIT_INTERACTIVE, sodium.crypto_pwhash_ALG_ARGON2ID13,
        );
        const cleLien = s.slice(0, 32);
        const verificateur = s.slice(32, 64);
        const r = await appelApi("/public/liens/" + encodeURIComponent(etat.jeton) + "/deverrouiller", {
          method: "POST", corps: { verificateurMotDePasse: vers64(verificateur) },
        });
        try {
          etat.cleElement = ouvrir(cleLien, b64(r.cleElementEnveloppee), "lien:" + r.element.id);
        } catch (_) {
          throw new ErreurLien("Déchiffrement impossible", "Le mot de passe est accepté mais la clé n'a pas pu être ouverte. Le lien est peut-être corrompu.");
        }
        etat.verificateur = verificateur;
        etat.jetonTelechargement = r.jetonTelechargement || null;
        champ.value = "";
        afficherElement(r.element);
        demarrerActualisation();
        $("contenu").focus();
      } catch (e) {
        if (e instanceof ErreurLien && (e.statut === 422 || e.statut === 423 || e.statut === 429)) {
          erreur.textContent = e.message;
          erreur.hidden = false;
          champ.setAttribute("aria-invalid", "true");
          champ.select();
          champ.focus();
        } else if (e instanceof ErreurLien) {
          afficherErreur(e.titre, e.message);
        } else {
          afficherErreur("Erreur inattendue", "Une erreur est survenue pendant le déverrouillage. Réessayez.");
        }
      } finally {
        bouton.disabled = false;
        bouton.textContent = "Déverrouiller";
      }
    });
  }

  // --- Contenu « en direct » --------------------------------------------------------------

  async function actualiser(silencieux) {
    if (etat.telechargementEnCours || etat.type === "FICHIER") return;
    const bouton = $("bouton-actualiser");
    bouton.disabled = true;
    try {
      await charger(true);
    } catch (e) {
      if (e instanceof ErreurLien && (e.statut === 410 || e.statut === 404)) afficherErreur(e.titre, e.message);
      else if (!silencieux) $("maj-texte").textContent = e instanceof ErreurLien ? e.message : "Actualisation impossible.";
    } finally {
      bouton.disabled = false;
    }
  }

  function demarrerActualisation() {
    if (etat.minuteur || etat.type === "FICHIER") return;
    etat.minuteur = setInterval(() => {
      if (document.visibilityState === "visible") actualiser(true);
    }, ACTUALISATION_MS);
  }

  function arreterActualisation() {
    if (etat.minuteur) clearInterval(etat.minuteur);
    etat.minuteur = null;
  }

  // --- Démarrage ------------------------------------------------------------------------------

  async function demarrer() {
    for (const id of ["lien-accueil", "lien-accueil-pied"]) $(id).href = CONFIG.accueilUrl || "/";
    $("bouton-actualiser").addEventListener("click", () => actualiser(false));
    etat.jeton = lireJeton();
    if (!etat.jeton) {
      afficherErreur("Lien introuvable", "Cette adresse ne contient pas de lien de partage valide. Vérifiez que vous avez copié le lien en entier.");
      return;
    }
    try {
      sodium = await attendreSodium();
    } catch (_) {
      afficherErreur("Navigateur non compatible", "Le module de déchiffrement n'a pas pu démarrer. Essayez avec un navigateur récent.");
      return;
    }
    try {
      await charger(false);
    } catch (e) {
      if (e instanceof ErreurLien) afficherErreur(e.titre, e.message);
      else afficherErreur("Erreur inattendue", "Le contenu n'a pas pu être affiché. Réessayez plus tard.");
    }
  }

  window.addEventListener("hashchange", () => window.location.reload());
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", demarrer);
  else demarrer();
})();

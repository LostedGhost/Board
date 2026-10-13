// Rendu Markdown minimal et sûr : construit des nœuds DOM (textContent), jamais de innerHTML.
// Pris en charge : titres #, paragraphes, **gras**, *italique* / _italique_, ~~barré~~, `code`,
// blocs ``` , listes - * + et 1., cases - [ ] / - [x], citations >, séparateurs ---,
// liens [texte](http(s)://… | mailto:…) et URL nues en http(s).
(function () {
  "use strict";

  const SCHEMAS_SURS = /^(https?:|mailto:)/i;

  function lienSur(url) {
    try {
      const u = new URL(url, window.location.href);
      return SCHEMAS_SURS.test(u.protocol) ? u.href : null;
    } catch (_) {
      return null;
    }
  }

  function creerLien(texte, url) {
    const href = lienSur(url);
    if (!href) return document.createTextNode(texte);
    const a = document.createElement("a");
    a.href = href;
    a.rel = "noopener noreferrer nofollow";
    a.target = "_blank";
    a.textContent = texte;
    return a;
  }

  // Motifs en ligne, essayés dans cet ordre au plus tôt dans le texte.
  const MOTIFS = [
    { re: /`([^`]+)`/, rendu: (m) => el("code", m[1]) },
    { re: /\[([^\]]+)\]\(([^)\s]+)\)/, rendu: (m) => creerLien(m[1], m[2]) },
    { re: /\*\*([^*]+?)\*\*|__([^_]+?)__/, rendu: (m) => imbrique("strong", m[1] || m[2]) },
    { re: /~~([^~]+?)~~/, rendu: (m) => imbrique("del", m[1]) },
    { re: /\*([^*\s][^*]*?)\*|(?:^|(?<=\W))_([^_\s][^_]*?)_(?=\W|$)/, rendu: (m) => imbrique("em", m[1] || m[2]) },
    { re: /https?:\/\/[^\s<>()]+[^\s<>().,;:!?'"]/, rendu: (m) => creerLien(m[0], m[0]) },
  ];

  function el(balise, texte) {
    const n = document.createElement(balise);
    if (texte !== undefined) n.textContent = texte;
    return n;
  }

  function imbrique(balise, texte) {
    const n = document.createElement(balise);
    enLigne(texte, n);
    return n;
  }

  function enLigne(texte, parent) {
    let reste = texte;
    while (reste.length) {
      let meilleur = null;
      for (const motif of MOTIFS) {
        const m = motif.re.exec(reste);
        if (m && (meilleur === null || m.index < meilleur.m.index)) meilleur = { m, motif };
      }
      if (!meilleur) {
        parent.appendChild(document.createTextNode(reste));
        break;
      }
      if (meilleur.m.index > 0) parent.appendChild(document.createTextNode(reste.slice(0, meilleur.m.index)));
      parent.appendChild(meilleur.motif.rendu(meilleur.m));
      reste = reste.slice(meilleur.m.index + meilleur.m[0].length);
    }
    return parent;
  }

  function ajouterLignesEnLigne(lignes, parent) {
    lignes.forEach((l, i) => {
      if (i > 0) parent.appendChild(document.createElement("br"));
      enLigne(l, parent);
    });
  }

  const RE_LISTE = /^(\s*)([-*+]|\d+[.)])\s+(.*)$/;

  function rendre(source) {
    const racine = document.createElement("div");
    racine.className = "md";
    const lignes = String(source || "").replace(/\r\n?/g, "\n").split("\n");
    let i = 0;
    while (i < lignes.length) {
      const ligne = lignes[i];
      if (!ligne.trim()) { i++; continue; }

      // Bloc de code
      const cloture = /^\s*```\s*([\w+-]*)\s*$/.exec(ligne);
      if (cloture) {
        const code = [];
        i++;
        while (i < lignes.length && !/^\s*```\s*$/.test(lignes[i])) code.push(lignes[i++]);
        i++;
        const pre = el("pre");
        pre.appendChild(el("code", code.join("\n")));
        racine.appendChild(pre);
        continue;
      }

      // Titre
      const titre = /^(#{1,6})\s+(.*?)\s*#*\s*$/.exec(ligne);
      if (titre) {
        racine.appendChild(enLigne(titre[2], el("h" + titre[1].length)));
        i++;
        continue;
      }

      // Séparateur
      if (/^\s*([-*_])(\s*\1){2,}\s*$/.test(ligne)) {
        racine.appendChild(el("hr"));
        i++;
        continue;
      }

      // Citation
      if (/^\s*>/.test(ligne)) {
        const bloc = [];
        while (i < lignes.length && /^\s*>/.test(lignes[i])) bloc.push(lignes[i++].replace(/^\s*>\s?/, ""));
        const bq = el("blockquote");
        bq.appendChild(rendre(bloc.join("\n")));
        racine.appendChild(bq);
        continue;
      }

      // Liste (un niveau d'imbrication géré par l'indentation)
      if (RE_LISTE.test(ligne)) {
        racine.appendChild(rendreListe(lignes, i, (fin) => { i = fin; }));
        continue;
      }

      // Paragraphe
      const para = [];
      while (
        i < lignes.length && lignes[i].trim() &&
        !/^\s*```/.test(lignes[i]) && !/^#{1,6}\s/.test(lignes[i]) && !/^\s*>/.test(lignes[i]) && !RE_LISTE.test(lignes[i])
      ) para.push(lignes[i++]);
      const p = el("p");
      ajouterLignesEnLigne(para, p);
      racine.appendChild(p);
    }
    return racine;
  }

  function rendreListe(lignes, debut, fixerFin) {
    const premier = RE_LISTE.exec(lignes[debut]);
    const indent = premier[1].length;
    const ordonnee = /\d/.test(premier[2]);
    const liste = el(ordonnee ? "ol" : "ul");
    let i = debut;
    let dernier = null;
    while (i < lignes.length) {
      const m = RE_LISTE.exec(lignes[i]);
      if (!m) {
        if (lignes[i].trim() && dernier && /^\s+/.test(lignes[i])) { // suite de l'élément
          dernier.appendChild(document.createTextNode(" "));
          enLigne(lignes[i].trim(), dernier);
          i++;
          continue;
        }
        break;
      }
      const niveau = m[1].length;
      if (niveau < indent) break;
      if (niveau > indent && dernier) {
        dernier.appendChild(rendreListe(lignes, i, (fin) => { i = fin; }));
        continue;
      }
      const li = el("li");
      const caseMd = /^\[([ xX])\]\s+(.*)$/.exec(m[3]);
      if (caseMd) {
        li.className = "coche";
        const c = el("span");
        c.className = "case" + (caseMd[1] !== " " ? " faite" : "");
        c.setAttribute("role", "img");
        c.setAttribute("aria-label", caseMd[1] !== " " ? "fait" : "à faire");
        const ligne = el("span");
        ligne.className = "tache-ligne";
        ligne.appendChild(c);
        ligne.appendChild(enLigne(caseMd[2], el("span")));
        li.appendChild(ligne);
      } else {
        enLigne(m[3], li);
      }
      liste.appendChild(li);
      dernier = li;
      i++;
    }
    fixerFin(i);
    return liste;
  }

  window.LuluMarkdown = { rendre, enLigne: (texte) => enLigne(String(texte || ""), document.createElement("span")) };
})();

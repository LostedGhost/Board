import 'dart:async';

import 'package:sembast/sembast.dart';
import 'package:uuid/uuid.dart';

import 'stockage/base_locale.dart';
import 'synchro/moteur_synchro.dart';

/// Types d'éléments (diagramme de classes, diagramme 2).
abstract class TypeEl {
  static const pressePapier = 'PRESSE_PAPIER';
  static const postIt = 'POST_IT';
  static const snippet = 'SNIPPET';
  static const liste = 'LISTE_TACHES';
  static const tache = 'TACHE';
  static const fichier = 'FICHIER';

  static const libelles = {
    pressePapier: 'Presse-papier',
    postIt: 'Post-it',
    snippet: 'Snippet',
    liste: 'Liste de tâches',
    tache: 'Tâche',
    fichier: 'Fichier',
  };
}

typedef Enr = Map<String, Object?>;

/// Opérations métier sur les données locales. Toute écriture déclenche une synchro différée.
class Depot {
  Depot(this.base, this.synchro);

  final BaseLocale base;
  final MoteurSynchro synchro;
  static const _uuid = Uuid();

  String nouvelId() => _uuid.v7();

  Future<void> _ecrire(Entite e, Enr valeur) async {
    await base.enregistrerLocal(e, valeur);
    synchro.signalerModification();
  }

  // --- Lecture -------------------------------------------------------------------------------

  Stream<List<Enr>> elements(String type, {String? parentId, bool? archive}) => base.observer(
        Entite.element,
        filtre: Filter.and([
          Filter.equals('type', type),
          if (parentId != null) Filter.equals('parentId', parentId),
          if (archive != null) Filter.equals('archive', archive),
        ]),
      );

  Stream<List<Enr>> tousLesElements() => base.observer(Entite.element);
  Stream<List<Enr>> tableaux() => base.observer(Entite.tableau);
  Stream<List<Enr>> rappelsDe(String elementId) =>
      base.observer(Entite.rappel, filtre: Filter.equals('elementId', elementId));
  Stream<List<Enr>> rappels() => base.observer(Entite.rappel);
  Stream<List<Enr>> versionsDe(String postItId) =>
      base.observer(Entite.versionPostIt, filtre: Filter.equals('postItId', postItId));

  Future<Enr?> element(String id) => base.lire(Entite.element, id);

  // --- Éléments ------------------------------------------------------------------------------

  Future<String> creer(
    String type,
    Map<String, Object?> donnees, {
    String? parentId,
    String? typeContenu,
    String? sourceId,
    bool epingle = false,
  }) async {
    final id = nouvelId();
    await _ecrire(Entite.element, {
      'id': id,
      'type': type,
      'parentId': parentId,
      'elementSourceId': sourceId,
      'typeContenu': typeContenu,
      'epingle': epingle,
      'epingleAccesRapide': false,
      'archive': false,
      'donnees': donnees,
      'creeLe': DateTime.now().toUtc().toIso8601String(),
    });
    return id;
  }

  Future<void> modifierDonnees(String id, Map<String, Object?> changements) async {
    final e = await element(id);
    if (e == null) return;
    final donnees = Map<String, Object?>.from((e['donnees'] as Map?) ?? {})..addAll(changements);
    await _ecrire(Entite.element, {...e, 'donnees': donnees});
  }

  Future<void> modifierChamps(String id, Map<String, Object?> champs) async {
    final e = await element(id);
    if (e == null) return;
    await _ecrire(Entite.element, {...e, ...champs});
  }

  /// Suppression définitive (D19), avec les enfants (tâches d'une liste, sous-tâches) et les rappels.
  Future<void> supprimer(String id) async {
    for (final enfant in await base.tous(Entite.element, filtre: Filter.equals('parentId', id))) {
      await supprimer(enfant['id']! as String);
    }
    for (final r in await base.tous(Entite.rappel, filtre: Filter.equals('elementId', id))) {
      await base.supprimerLocal(Entite.rappel, r['id']! as String);
    }
    await base.supprimerLocal(Entite.element, id);
    synchro.signalerModification();
  }

  // --- Suppression annulable (H10) ---------------------------------------------------------
  // L'élément disparaît tout de suite, mais la suppression n'est envoyée au serveur (où elle est
  // définitive, D19) qu'après 10 secondes, pour laisser le temps d'annuler.

  final _suppressionsDifferees = <String, (Timer, List<(Entite, Enr)>)>{};

  Future<void> supprimerAvecAnnulation(String id) async {
    final avant = <(Entite, Enr)>[];
    Future<void> collecter(String eid) async {
      for (final enfant in await base.tous(Entite.element, filtre: Filter.equals('parentId', eid))) {
        await collecter(enfant['id']! as String);
      }
      for (final r in await base.tous(Entite.rappel, filtre: Filter.equals('elementId', eid))) {
        avant.add((Entite.rappel, r));
      }
      final e = await element(eid);
      if (e != null) avant.add((Entite.element, e));
    }

    await collecter(id);
    final maintenant = DateTime.now().toUtc().toIso8601String();
    for (final (ent, r) in avant) {
      await base.store(ent).record(r['id']! as String).put(base.db, {
        ...r,
        'supprimeLe': maintenant,
        'modifieLe': maintenant,
        'donnees': <String, Object?>{},
        'sale': false,
        'suppressionNonEnvoyee': true,
      });
    }
    final minuterie = Timer(const Duration(seconds: 10), () => _validerSuppression(id));
    _suppressionsDifferees[id] = (minuterie, avant);
  }

  Future<void> annulerSuppression(String id) async {
    final attente = _suppressionsDifferees.remove(id);
    if (attente == null) return;
    attente.$1.cancel();
    for (final (ent, r) in attente.$2) {
      await base.store(ent).record(r['id']! as String).put(base.db, r);
    }
  }

  Future<void> _validerSuppression(String id) async {
    final attente = _suppressionsDifferees.remove(id);
    for (final (ent, r) in attente?.$2 ?? <(Entite, Enr)>[]) {
      await base.fusionner(ent, r['id']! as String, {'sale': true, 'suppressionNonEnvoyee': null});
    }
    synchro.signalerModification();
  }

  /// Au démarrage : une suppression interrompue (app fermée avant 10 s) est finalisée.
  Future<void> finaliserSuppressionsInterrompues() async {
    for (final ent in [Entite.element, Entite.rappel]) {
      final r = await base.store(ent).find(base.db, finder: Finder(filter: Filter.equals('suppressionNonEnvoyee', true)));
      for (final s in r) {
        await base.fusionner(ent, s.key, {'sale': true, 'suppressionNonEnvoyee': null});
      }
    }
  }

  Future<void> basculerAccesRapide(String id) async {
    final e = await element(id);
    if (e != null) await modifierChamps(id, {'epingleAccesRapide': !(e['epingleAccesRapide'] == true)});
  }

  /// H11 : copie d'un élément (nouvelle clé, nouvel identifiant).
  Future<String> dupliquer(String id) async {
    final e = (await element(id))!;
    return creer(e['type']! as String, Map<String, Object?>.from(e['donnees']! as Map),
        parentId: e['parentId'] as String?, typeContenu: e['typeContenu'] as String?, sourceId: id);
  }

  /// H1 : transformer un élément en un autre type (copie par défaut, « déplacer » supprime l'original).
  Future<String> transformer(String id, String versType, {String? parentId, bool deplacer = false}) async {
    final e = (await element(id))!;
    final texte = texteDe(e);
    final Map<String, Object?> donnees = switch (versType) {
      TypeEl.postIt => {'contenu': texte, 'couleurFond': '#FFE066', 'x': 40.0, 'y': 40.0, 'largeur': 240.0, 'hauteur': 200.0, 'ordreEmpilement': 0},
      TypeEl.snippet => {'titre': _premiereLigne(texte), 'contenu': texte, 'langage': null},
      TypeEl.tache => {'titre': texte, 'faite': false, 'echeance': null, 'priorite': 'NORMALE', 'ordre': 0},
      TypeEl.pressePapier => {'texte': texte},
      _ => throw ArgumentError(versType),
    };
    final etiquettes = (e['donnees'] as Map?)?['etiquettes'];
    if (etiquettes is List && etiquettes.isNotEmpty) donnees['etiquettes'] = List<Object?>.from(etiquettes); // H7 : les étiquettes suivent l'élément
    final nouveau = await creer(versType, donnees,
        parentId: parentId, sourceId: id, typeContenu: versType == TypeEl.pressePapier ? 'TEXTE' : null);
    if (deplacer) await supprimer(id);
    return nouveau;
  }

  static String _premiereLigne(String t) {
    final l = t.trim().split('\n').first;
    return l.length > 60 ? '${l.substring(0, 60)}…' : l;
  }

  /// Texte représentatif d'un élément (recherche, transformation, aperçu).
  static String texteDe(Enr e) {
    final d = (e['donnees'] as Map?) ?? {};
    return switch (e['type']) {
      TypeEl.pressePapier => (d['texte'] ?? '[image]').toString(),
      TypeEl.postIt => (d['contenu'] ?? '').toString(),
      TypeEl.snippet => '${d['titre'] ?? ''}\n${d['contenu'] ?? ''}'.trim(),
      TypeEl.liste => (d['titre'] ?? '').toString(),
      TypeEl.tache => (d['titre'] ?? '').toString(),
      TypeEl.fichier => (d['nom'] ?? '').toString(),
      _ => '',
    };
  }

  // --- Presse-papier (B1-B4) -----------------------------------------------------------------

  /// Ajoute une entrée, sauf si elle est identique à la plus récente (B1 : pas de doublon consécutif).
  Future<void> ajouterPressePapier(String texte, {String typeContenu = 'TEXTE'}) async {
    if (texte.trim().isEmpty) return;
    final existantes = await base.tous(Entite.element, filtre: Filter.equals('type', TypeEl.pressePapier));
    existantes.sort((a, b) => (b['creeLe'] as String? ?? '').compareTo(a['creeLe'] as String? ?? ''));
    if (existantes.isNotEmpty && ((existantes.first['donnees'] as Map?)?['texte']) == texte) return;
    final estLien = RegExp(r'^https?://\S+$').hasMatch(texte.trim());
    await creer(TypeEl.pressePapier, {'texte': texte}, typeContenu: estLien ? 'LIEN' : typeContenu);
  }

  Future<void> ajouterImagePressePapier(String imageB64, String mime) =>
      creer(TypeEl.pressePapier, {'image': imageB64, 'mime': mime}, typeContenu: 'IMAGE');

  // --- Tableaux (C2, H12) --------------------------------------------------------------------

  Future<String> creerTableau(String nom, int ordre) async {
    final id = nouvelId();
    await _ecrire(Entite.tableau, {'id': id, 'donnees': {'nom': nom, 'ordre': ordre}});
    return id;
  }

  Future<void> renommerTableau(String id, String nom) async {
    final t = await base.lire(Entite.tableau, id);
    if (t == null) return;
    await _ecrire(Entite.tableau, {...t, 'donnees': {...(t['donnees']! as Map), 'nom': nom}});
  }

  /// Supprime le tableau ; ses post-it sont déplacés vers [versTableau] ou supprimés.
  Future<void> supprimerTableau(String id, {String? versTableau}) async {
    for (final p in await base.tous(Entite.element, filtre: Filter.equals('parentId', id))) {
      if (versTableau != null) {
        await modifierChamps(p['id']! as String, {'parentId': versTableau});
      } else {
        await supprimer(p['id']! as String);
      }
    }
    await base.supprimerLocal(Entite.tableau, id);
    synchro.signalerModification();
  }

  // --- Rappels (F3, H2) ------------------------------------------------------------------------

  Future<void> creerRappel(String elementId, DateTime echeance,
      {String? recurrence, List<String> jours = const [], String fuseau = 'UTC'}) async {
    await _ecrire(Entite.rappel, {
      'id': nouvelId(),
      'elementId': elementId,
      'prochaineEcheance': echeance.toUtc().toIso8601String(),
      'recurrence': recurrence,
      'joursSemaine': jours,
      'fuseauHoraire': fuseau,
      'actif': true,
    });
  }

  Future<void> supprimerRappel(String id) async {
    await base.supprimerLocal(Entite.rappel, id);
    synchro.signalerModification();
  }

  Future<void> mettreAJourRappel(Enr rappel) => _ecrire(Entite.rappel, rappel);

  // --- Étiquettes communes (H7) --------------------------------------------------------------
  // Les étiquettes vivent dans `donnees['etiquettes']` (liste de textes) : elles sont donc chiffrées
  // avec le reste de l'élément et ne sont jamais visibles du serveur. `modifierDonnees` fusionne les
  // changements dans `donnees` : un écran qui enregistre ses propres champs (ex. l'éditeur de snippet)
  // conserve les étiquettes existantes. `definirEtiquettes` passe aussi par cette fusion.

  static const maxEtiquettes = 20;
  static const longueurMaxEtiquette = 40;

  /// Clé de comparaison : sans espaces superflus, en minuscules, sans `#` initial.
  static String cleEtiquette(String e) => normaliserUneEtiquette(e).toLowerCase();

  /// Une étiquette nettoyée, ou '' : trim, `#` initiaux retirés, espaces internes remplacés par `-`
  /// (pour pouvoir l'écrire `#mon-projet` dans la recherche), longueur bornée.
  static String normaliserUneEtiquette(String e) {
    var t = e.trim();
    while (t.startsWith('#')) {
      t = t.substring(1).trimLeft();
    }
    t = t.replaceAll(RegExp(r'\s+'), '-');
    if (t.length > longueurMaxEtiquette) t = t.substring(0, longueurMaxEtiquette).trimRight();
    return t;
  }

  /// Normalise une liste : trim, vides retirés, doublons (insensibles à la casse) retirés en gardant
  /// la première graphie, au plus [maxEtiquettes].
  static List<String> normaliserEtiquettes(Iterable<Object?> brutes) {
    final vues = <String>{};
    final res = <String>[];
    for (final b in brutes) {
      if (b == null) continue;
      final t = normaliserUneEtiquette(b.toString());
      if (t.isEmpty || !vues.add(t.toLowerCase())) continue;
      res.add(t);
      if (res.length >= maxEtiquettes) break;
    }
    return res;
  }

  /// Étiquettes d'un élément (lecture tolérante : ancien champ hors `donnees` accepté).
  static List<String> etiquettesDe(Enr element) {
    final brut = ((element['donnees'] as Map?)?['etiquettes']) ?? element['etiquettes'];
    return brut is List ? normaliserEtiquettes(brut) : const [];
  }

  /// Remplace les étiquettes de l'élément [id] (normalisées), sans toucher aux autres données.
  Future<List<String>> definirEtiquettes(String id, List<String> etiquettes) async {
    final propres = normaliserEtiquettes(etiquettes);
    await modifierDonnees(id, {'etiquettes': propres});
    return propres;
  }

  /// Compte d'utilisation par étiquette, sur un ensemble d'éléments déjà chargés.
  /// Clé : graphie la plus fréquente (à égalité, la première rencontrée) ; tri par usage décroissant puis nom.
  static List<({String nom, int nombre})> compterEtiquettes(Iterable<Enr> elements) {
    final nombres = <String, int>{};
    final graphies = <String, Map<String, int>>{};
    for (final e in elements) {
      for (final t in etiquettesDe(e)) {
        final k = t.toLowerCase();
        nombres[k] = (nombres[k] ?? 0) + 1;
        final g = graphies[k] ??= {};
        g[t] = (g[t] ?? 0) + 1;
      }
    }
    final res = [
      for (final k in nombres.keys)
        (
          nom: graphies[k]!.entries.reduce((a, b) => b.value > a.value ? b : a).key,
          nombre: nombres[k]!,
        ),
    ];
    res.sort((a, b) {
      final c = b.nombre.compareTo(a.nombre);
      return c != 0 ? c : a.nom.toLowerCase().compareTo(b.nom.toLowerCase());
    });
    return res;
  }

  /// Toutes les étiquettes du Board (éléments non supprimés), avec leur nombre d'utilisations.
  Future<List<({String nom, int nombre})>> toutesLesEtiquettes() async =>
      compterEtiquettes(await base.tous(Entite.element));

  /// Vrai si [element] porte l'étiquette [etiquette] (comparaison insensible à la casse).
  static bool aEtiquette(Enr element, String etiquette) {
    final k = cleEtiquette(etiquette);
    return k.isNotEmpty && etiquettesDe(element).any((t) => t.toLowerCase() == k);
  }
}

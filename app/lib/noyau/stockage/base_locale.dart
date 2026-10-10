import 'dart:async';

import 'package:sembast/sembast.dart';

import 'fabrique.dart';

/// Les entités synchronisées (contrat 2.5), une collection locale chacune.
enum Entite {
  element('element'),
  tableau('tableau'),
  etiquette('etiquette'),
  elementEtiquette('element_etiquette'),
  rappel('rappel'),
  versionPostIt('version_post_it');

  const Entite(this.nom);
  final String nom;

  static Entite depuis(String nom) => values.firstWhere((e) => e.nom == nom);
}

/// Base locale hors ligne (D38). Chaque enregistrement est la forme DÉCHIFFRÉE d'une entité :
/// `{id, modifieLe, supprimeLe, version, sale, ...champs lisibles, donnees: {...contenu clair}, cle: "<b64>"}`.
/// `sale = true` : modification locale pas encore envoyée au serveur.
class BaseLocale {
  BaseLocale._(this.db);

  final Database db;

  static Future<BaseLocale> ouvrir() async => BaseLocale._(await ouvrirBase('luluboard'));

  StoreRef<String, Map<String, Object?>> store(Entite e) => stringMapStoreFactory.store(e.nom);
  final _meta = StoreRef<String, Object?>('meta');

  // --- Méta-données (version de synchro, compte, réglages locaux) -------------------------

  Future<T?> lireMeta<T>(String cle) async => await _meta.record(cle).get(db) as T?;

  Future<void> ecrireMeta(String cle, Object? valeur) async {
    if (valeur == null) {
      await _meta.record(cle).delete(db);
    } else {
      await _meta.record(cle).put(db, valeur);
    }
  }

  Stream<T?> observerMeta<T>(String cle) => _meta.record(cle).onSnapshot(db).map((s) => s?.value as T?);

  // --- Entités ------------------------------------------------------------------------------

  Future<Map<String, Object?>?> lire(Entite e, String id) async {
    final v = await store(e).record(id).get(db);
    return v == null ? null : Map<String, Object?>.from(v);
  }

  Future<List<Map<String, Object?>>> tous(Entite e, {Filter? filtre, bool avecSupprimes = false}) async {
    final f = avecSupprimes ? filtre : Filter.and([?filtre, Filter.isNull('supprimeLe')]);
    final r = await store(e).find(db, finder: Finder(filter: f));
    return r.map((s) => Map<String, Object?>.from(s.value)).toList();
  }

  Stream<List<Map<String, Object?>>> observer(Entite e, {Filter? filtre}) {
    final f = Filter.and([?filtre, Filter.isNull('supprimeLe')]);
    return store(e).query(finder: Finder(filter: f)).onSnapshots(db).map(
          (liste) => liste.map((s) => Map<String, Object?>.from(s.value)).toList(),
        );
  }

  /// Modification locale : horodatée maintenant et marquée à envoyer.
  Future<void> enregistrerLocal(Entite e, Map<String, Object?> valeur) async {
    final copie = Map<String, Object?>.from(valeur)
      ..['modifieLe'] = DateTime.now().toUtc().toIso8601String()
      ..['sale'] = true;
    await store(e).record(copie['id']! as String).put(db, copie);
  }

  /// Suppression locale (définitive, propagée par la synchro : D19).
  Future<void> supprimerLocal(Entite e, String id) async {
    final existant = await lire(e, id);
    if (existant == null) return;
    final maintenant = DateTime.now().toUtc().toIso8601String();
    existant
      ..['supprimeLe'] = maintenant
      ..['modifieLe'] = maintenant
      ..['sale'] = true
      ..['donnees'] = <String, Object?>{};
    await store(e).record(id).put(db, existant);
  }

  /// Écriture venant du serveur (jamais marquée « sale »).
  Future<void> enregistrerDistant(Entite e, Map<String, Object?> valeur) =>
      store(e).record(valeur['id']! as String).put(db, Map<String, Object?>.from(valeur)..['sale'] = false);

  /// Met à jour quelques champs sans toucher à l'horodatage ni à l'état « à envoyer ».
  Future<void> fusionner(Entite e, String id, Map<String, Object?> champs) async {
    final r = store(e).record(id);
    final v = await r.get(db);
    if (v != null) await r.put(db, {...v, ...champs});
  }

  Future<List<(Entite, Map<String, Object?>)>> aEnvoyer() async {
    final resultat = <(Entite, Map<String, Object?>)>[];
    for (final e in Entite.values) {
      final r = await store(e).find(db, finder: Finder(filter: Filter.equals('sale', true)));
      resultat.addAll(r.map((s) => (e, Map<String, Object?>.from(s.value))));
    }
    return resultat;
  }

  Future<void> marquerPropre(Entite e, String id, {int? version}) async {
    final r = store(e).record(id);
    final v = await r.get(db);
    if (v == null) return;
    await r.put(db, {...v, 'sale': false, 'version': ?version});
  }

  /// Rend toutes les données « à envoyer » : passage du mode visiteur à un compte (I3).
  Future<void> toutMarquerAEnvoyer() async {
    for (final e in Entite.values) {
      await store(e).update(db, {'sale': true});
    }
  }

  Future<void> toutEffacer() async {
    for (final e in Entite.values) {
      await store(e).delete(db);
    }
    await _meta.delete(db);
  }
}

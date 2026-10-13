import 'package:flutter_test/flutter_test.dart';
import 'package:luluboard/noyau/depot.dart';

/// H7 : normalisation des étiquettes communes.
void main() {
  group('normaliserEtiquettes', () {
    test('trim, vides et # initiaux retirés', () {
      expect(Depot.normaliserEtiquettes(['  dev ', '', '   ', '#urgent', '## perso', null]), ['dev', 'urgent', 'perso']);
    });

    test('doublons insensibles à la casse, première graphie conservée', () {
      expect(Depot.normaliserEtiquettes(['Projet', 'projet', 'PROJET ', 'autre']), ['Projet', 'autre']);
    });

    test('espaces internes remplacés par un tiret', () {
      expect(Depot.normaliserEtiquettes(['mon   projet', ' a b ']), ['mon-projet', 'a-b']);
    });

    test('20 étiquettes au plus', () {
      final r = Depot.normaliserEtiquettes([for (var i = 0; i < 30; i++) 'e$i']);
      expect(r.length, Depot.maxEtiquettes);
      expect(r.first, 'e0');
      expect(r.last, 'e19');
    });

    test('longueur bornée', () {
      expect(Depot.normaliserUneEtiquette('x' * 100).length, Depot.longueurMaxEtiquette);
    });

    test('clé de comparaison en minuscules', () {
      expect(Depot.cleEtiquette('  #Dev '), 'dev');
    });
  });

  group('lecture et comptage', () {
    Enr el(List<Object?>? tags, {bool horsDonnees = false}) => {
          'id': 'x',
          'type': TypeEl.postIt,
          'donnees': {'contenu': 'c', if (!horsDonnees && tags != null) 'etiquettes': tags},
          if (horsDonnees) 'etiquettes': tags,
        };

    test('etiquettesDe lit donnees, tolère l\'ancien champ et l\'absence', () {
      expect(Depot.etiquettesDe(el(['A', 'a', ' b'])), ['A', 'b']);
      expect(Depot.etiquettesDe(el(['z'], horsDonnees: true)), ['z']);
      expect(Depot.etiquettesDe(el(null)), isEmpty);
      expect(Depot.etiquettesDe({'donnees': {'etiquettes': 'pas une liste'}}), isEmpty);
    });

    test('aEtiquette insensible à la casse', () {
      expect(Depot.aEtiquette(el(['Dev']), '#dev'), isTrue);
      expect(Depot.aEtiquette(el(['Dev']), 'de'), isFalse);
    });

    test('compterEtiquettes : regroupement, graphie majoritaire, tri par usage', () {
      final r = Depot.compterEtiquettes([
        el(['dev', 'perso']),
        el(['Dev']),
        el(['dev', 'zz']),
        el(null),
      ]);
      expect(r.map((e) => (e.nom, e.nombre)).toList(), [('dev', 3), ('perso', 1), ('zz', 1)]);
    });
  });
}

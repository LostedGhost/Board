import 'package:flutter_test/flutter_test.dart';
import 'package:luluboard/ui/theme.dart';
import 'package:flutter/material.dart';

void main() {
  test('C1 : le texte reste lisible (contraste ≥ 4,5:1) sur toute couleur de post-it', () {
    for (var r = 0; r <= 255; r += 51) {
      for (var g = 0; g <= 255; g += 51) {
        for (var b = 0; b <= 255; b += 51) {
          final fond = Color.fromARGB(255, r, g, b);
          expect(contraste(couleurTexte(fond), fond), greaterThanOrEqualTo(4.5), reason: 'fond $r,$g,$b');
        }
      }
    }
  });

  test('Les 6 couleurs par défaut donnent un texte teinté, pas forcément noir', () {
    for (final hex in ThemeLulu.couleursPostIt) {
      final fond = couleurDepuisHex(hex);
      expect(contraste(couleurTexte(fond), fond), greaterThanOrEqualTo(4.5));
    }
  });

  test('Design system : boutons, texte et liens lisibles (≥ 4,5:1) en clair et en sombre', () {
    for (final t in [ThemeLulu.clair(), ThemeLulu.sombre()]) {
      final s = t.colorScheme;
      expect(contraste(s.onPrimary, s.primary), greaterThanOrEqualTo(4.5), reason: '${t.brightness} bouton');
      expect(contraste(s.onSurface, s.surface), greaterThanOrEqualTo(4.5), reason: '${t.brightness} texte');
      expect(contraste(s.onSurfaceVariant, s.surface), greaterThanOrEqualTo(4.5), reason: '${t.brightness} texte secondaire');
      expect(contraste(s.primary, t.scaffoldBackgroundColor), greaterThanOrEqualTo(4.5), reason: '${t.brightness} lien');
    }
  });
}

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Système de design LuluBoard : Material 3, une couleur d'accent, clair et sombre.
class ThemeLulu {
  static const accent = Color(0xFF4F46E5); // indigo, contraste ≥ 4,5:1 sur blanc

  /// Les 6 couleurs de post-it par défaut (C1).
  static const couleursPostIt = <String>['#FFE066', '#FFADAD', '#A0E7E5', '#B4F8C8', '#CDB4DB', '#FFFFFF'];

  static ThemeData clair() => _theme(Brightness.light);
  static ThemeData sombre() => _theme(Brightness.dark);

  static ThemeData _theme(Brightness b) {
    final schema = ColorScheme.fromSeed(seedColor: accent, brightness: b);
    return ThemeData(
      colorScheme: schema,
      useMaterial3: true,
      visualDensity: VisualDensity.standard,
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
      cardTheme: const CardThemeData(margin: EdgeInsets.zero),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }
}

Color couleurDepuisHex(String? hex, [Color defaut = const Color(0xFFFFE066)]) {
  if (hex == null || !RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(hex)) return defaut;
  return Color(int.parse('FF${hex.substring(1)}', radix: 16));
}

String hexDepuisCouleur(Color c) {
  String h(double v) => (v * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  return '#${h(c.r)}${h(c.g)}${h(c.b)}'.toUpperCase();
}

/// Luminance relative WCAG 2.1.
double luminance(Color c) {
  double canal(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * canal(c.r) + 0.7152 * canal(c.g) + 0.0722 * canal(c.b);
}

double contraste(Color a, Color b) {
  final la = luminance(a), lb = luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// C1 : couleur du texte calculée pour rester lisible sur [fond] (contraste ≥ 4,5:1, WCAG AA).
/// On cherche d'abord une teinte foncée ou claire de la même couleur ; à défaut, noir ou blanc
/// (l'un des deux atteint toujours le seuil, quel que soit le fond).
Color couleurTexte(Color fond) {
  final hsl = HSLColor.fromColor(fond);
  final versSombre = luminance(fond) > 0.18;
  for (var i = 1; i <= 20; i++) {
    final l = versSombre ? (hsl.lightness * (1 - i / 20)) : (hsl.lightness + (1 - hsl.lightness) * i / 20);
    final candidat = hsl.withLightness(l.clamp(0.0, 1.0)).toColor();
    if (contraste(candidat, fond) >= 4.5) return candidat;
  }
  return contraste(Colors.black, fond) >= contraste(Colors.white, fond) ? Colors.black : Colors.white;
}

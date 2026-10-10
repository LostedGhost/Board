import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Système de design LuluBoard — palette LuluFiles.
///
/// Mode sombre  : fond #020617, surfaces #0F172A / #1E293B, accent vert #22C55E.
/// Mode clair   : fond blanc/gris très clair, accent vert #16A34A (contraste AA).
/// Typographie  : Rubik (disponible sur toutes les plateformes via Google Fonts
///                dans pubspec.yaml) avec fallback system-ui.
class ThemeLulu {
  /// Vert LuluFiles — utilisé comme couleur d'accent en mode sombre.
  static const accentSombre = Color(0xFF22C55E);

  /// Vert LuluFiles atténué — utilisé en mode clair (meilleur contraste sur blanc).
  static const accentClair = Color(0xFF16A34A);

  /// Les 6 couleurs de post-it par défaut (C1).
  static const couleursPostIt = <String>[
    '#FFE066', '#FFADAD', '#A0E7E5', '#B4F8C8', '#CDB4DB', '#FFFFFF',
  ];

  static ThemeData clair() => _theme(Brightness.light);
  static ThemeData sombre() => _theme(Brightness.dark);

  static ThemeData _theme(Brightness b) {
    final isDark = b == Brightness.dark;
    final seed = isDark ? accentSombre : accentClair;

    // Construction du ColorScheme Material 3 à partir de la graine LuluFiles.
    final schema = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: b,
      // En mode sombre, on force les surfaces vers la palette #020617 / #0F172A.
      surface:     isDark ? const Color(0xFF0F172A) : null,
      surfaceContainerHighest: isDark ? const Color(0xFF1E293B) : null,
    );

    return ThemeData(
      colorScheme: schema,
      useMaterial3: true,
      fontFamily: GoogleFonts.rubik().fontFamily,
      visualDensity: VisualDensity.standard,

      // AppBar épurée : pas d'élévation, titre en Rubik medium.
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: isDark ? const Color(0xFF0F172A) : schema.surface,
        foregroundColor: isDark ? const Color(0xFFF8FAFC) : schema.onSurface,
        titleTextStyle: GoogleFonts.rubik(
          fontWeight: FontWeight.w500,
          fontSize: 18,
          letterSpacing: -0.3,
          color: isDark ? const Color(0xFFF8FAFC) : schema.onSurface,
        ),
      ),

      // NavigationRail / NavigationBar : indicateur vert translucide.
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: isDark ? const Color(0xFF0B0E1A) : null,
        indicatorColor: seed.withValues(alpha: 0.18),
        selectedIconTheme: IconThemeData(color: seed),
        selectedLabelTextStyle: GoogleFonts.rubik(fontWeight: FontWeight.w600, color: seed),
        unselectedLabelTextStyle: GoogleFonts.rubik(
          color: isDark ? const Color(0xFF94A3B8) : schema.onSurfaceVariant,
        ),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? const Color(0xFF0B0E1A) : null,
        indicatorColor: seed.withValues(alpha: 0.18),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? seed
                : (isDark ? const Color(0xFF94A3B8) : schema.onSurfaceVariant),
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => GoogleFonts.rubik(
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600 : FontWeight.w400,
            color: states.contains(WidgetState.selected) ? seed
                : (isDark ? const Color(0xFF94A3B8) : schema.onSurfaceVariant),
          ),
        ),
      ),

      // Cartes glass-like en mode sombre.
      cardTheme: CardThemeData(
        margin: EdgeInsets.zero,
        color: isDark ? const Color(0xFF1E293B) : null,
        surfaceTintColor: Colors.transparent,
        elevation: isDark ? 0 : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: isDark
              ? BorderSide(color: Colors.white.withValues(alpha: 0.07), width: 1)
              : BorderSide.none,
        ),
      ),

      // Inputs sobres.
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: seed, width: 1.5),
        ),
      ),

      // SnackBar flottant, coins arrondis.
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        backgroundColor: isDark ? const Color(0xFF1E293B) : null,
      ),

      // FilledButton = vert LuluFiles.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: seed,
          foregroundColor: Colors.white,
          textStyle: GoogleFonts.rubik(fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),

      // ElevatedButton cohérent.
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          textStyle: GoogleFonts.rubik(fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),

      // Texte : Rubik à toutes les tailles via google_fonts.
      textTheme: GoogleFonts.rubikTextTheme(
        const TextTheme(
          displayLarge:  TextStyle(fontWeight: FontWeight.w800, letterSpacing: -1.5),
          displayMedium: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -1),
          displaySmall:  TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.5),
          headlineLarge: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.5),
          headlineMedium:TextStyle(fontWeight: FontWeight.w600, letterSpacing: -0.3),
          headlineSmall: TextStyle(fontWeight: FontWeight.w600),
          titleLarge:    TextStyle(fontWeight: FontWeight.w600),
          titleMedium:   TextStyle(fontWeight: FontWeight.w500),
          titleSmall:    TextStyle(fontWeight: FontWeight.w500),
          labelLarge:    TextStyle(fontWeight: FontWeight.w600),
          labelMedium:   TextStyle(fontWeight: FontWeight.w500),
          labelSmall:    TextStyle(fontWeight: FontWeight.w500, letterSpacing: 0.5),
        ),
      ),
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

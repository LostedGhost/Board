import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Jetons du système de design LuluBoard (palette LuluFiles), partagés avec `public/index.html`.
class Lulu {
  // Couleurs — mode sombre (identiques aux variables CSS de la page d'accueil).
  static const fond = Color(0xFF020617); // --bg
  static const surface = Color(0xFF0F172A); // --primary
  static const surfaceHaute = Color(0xFF1E293B); // --secondary
  static const navigation = Color(0xFF0B0E1A);
  static const bordure = Color(0xFF334155); // --border
  static const texte = Color(0xFFF8FAFC); // --fg
  static const texteDoux = Color(0xFF94A3B8); // --text-soft
  static const texteEteint = Color(0xFF64748B); // --text-dim
  static const accent = Color(0xFF22C55E); // --accent

  // Couleurs — mode clair (ardoise, accent vert assombri pour rester lisible sur blanc).
  static const fondClair = Color(0xFFF8FAFC);
  static const surfaceClaire = Color(0xFFFFFFFF);
  static const surfaceHauteClaire = Color(0xFFF1F5F9);
  static const bordureClaire = Color(0xFFE2E8F0);
  static const texteClair = Color(0xFF0F172A);
  static const texteDouxClair = Color(0xFF475569);
  static const accentClair = Color(0xFF15803D); // contraste 5:1 sur blanc (AA)

  // Espacements (--sp-*) et rayons (--r-*).
  static const xs = 4.0, sm = 8.0, md = 16.0, lg = 24.0, xl = 32.0;
  static const rSm = 6.0, rMd = 8.0, rLg = 12.0, rXl = 16.0;

  // Durées (--t-*).
  static const rapide = Duration(milliseconds: 150);
  static const normal = Duration(milliseconds: 200);

  // Polices embarquées (assets/fonts, licence OFL) : aucune requête vers Google au démarrage,
  // l'app reste identique hors ligne et l'adresse IP des utilisateurs n'est pas transmise.
  static const police = 'Rubik';
  static const policeMarque = 'Itim';
}

class ThemeLulu {
  /// Les 6 couleurs de post-it par défaut (C1).
  static const couleursPostIt = <String>[
    '#FFE066', '#FFADAD', '#A0E7E5', '#B4F8C8', '#CDB4DB', '#FFFFFF',
  ];

  static ThemeData clair() => _theme(Brightness.light);
  static ThemeData sombre() => _theme(Brightness.dark);

  static ThemeData _theme(Brightness b) {
    final sombre = b == Brightness.dark;
    final accent = sombre ? Lulu.accent : Lulu.accentClair;
    // Texte sur l'accent : foncé sur le vert vif (≈ 9:1), blanc sur le vert assombri (≈ 5:1).
    final surAccent = sombre ? Lulu.fond : Colors.white;
    final fond = sombre ? Lulu.fond : Lulu.fondClair;
    final surface = sombre ? Lulu.surface : Lulu.surfaceClaire;
    final surfaceHaute = sombre ? Lulu.surfaceHaute : Lulu.surfaceHauteClaire;
    final bordure = sombre ? Lulu.bordure : Lulu.bordureClaire;
    final texte = sombre ? Lulu.texte : Lulu.texteClair;
    final texteDoux = sombre ? Lulu.texteDoux : Lulu.texteDouxClair;

    final schema = ColorScheme.fromSeed(seedColor: accent, brightness: b).copyWith(
      primary: accent,
      onPrimary: surAccent,
      surface: surface,
      onSurface: texte,
      onSurfaceVariant: texteDoux,
      surfaceContainerLowest: fond,
      surfaceContainerLow: surface,
      surfaceContainer: surface,
      surfaceContainerHigh: surfaceHaute,
      surfaceContainerHighest: surfaceHaute,
      outline: bordure,
      outlineVariant: bordure.withValues(alpha: 0.6),
    );

    final rayonMd = BorderRadius.circular(Lulu.rMd);
    final rayonLg = BorderRadius.circular(Lulu.rLg);
    final base = ThemeData(brightness: b, fontFamily: Lulu.police);
    final textes = base.textTheme
        .copyWith(
          displayLarge: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: -1.5),
          displayMedium: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: -1),
          displaySmall: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.5),
          headlineLarge: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.5),
          headlineMedium: const TextStyle(fontWeight: FontWeight.w600, letterSpacing: -0.3),
          headlineSmall: const TextStyle(fontWeight: FontWeight.w600),
          titleLarge: const TextStyle(fontWeight: FontWeight.w600),
          titleMedium: const TextStyle(fontWeight: FontWeight.w500),
          titleSmall: const TextStyle(fontWeight: FontWeight.w500),
          labelLarge: const TextStyle(fontWeight: FontWeight.w600),
          labelMedium: const TextStyle(fontWeight: FontWeight.w500),
          labelSmall: const TextStyle(fontWeight: FontWeight.w500, letterSpacing: 0.5),
        )
        .apply(fontFamily: Lulu.police, bodyColor: texte, displayColor: texte);

    return ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: schema,
      fontFamily: Lulu.police,
      textTheme: textes,
      scaffoldBackgroundColor: fond,
      canvasColor: fond,
      dividerColor: bordure,
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,

      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: fond,
        surfaceTintColor: Colors.transparent,
        foregroundColor: texte,
        shape: Border(bottom: BorderSide(color: bordure.withValues(alpha: 0.6))),
        titleTextStyle: TextStyle(fontFamily: Lulu.police, fontWeight: FontWeight.w600, fontSize: 18, letterSpacing: -0.3, color: texte),
      ),

      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: sombre ? Lulu.navigation : surface,
        indicatorColor: accent.withValues(alpha: 0.18),
        selectedIconTheme: IconThemeData(color: accent),
        unselectedIconTheme: IconThemeData(color: texteDoux),
        selectedLabelTextStyle: TextStyle(fontFamily: Lulu.police, fontWeight: FontWeight.w600, color: accent, fontSize: 12),
        unselectedLabelTextStyle: TextStyle(fontFamily: Lulu.police, color: texteDoux, fontSize: 12),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: sombre ? Lulu.navigation : surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: accent.withValues(alpha: 0.18),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? accent : texteDoux),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => TextStyle(
            fontFamily: Lulu.police,
            fontSize: 12,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w400,
            color: s.contains(WidgetState.selected) ? accent : texteDoux,
          ),
        ),
      ),

      cardTheme: CardThemeData(
        margin: EdgeInsets.zero,
        color: sombre ? Lulu.surfaceHaute : surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: rayonLg,
          side: BorderSide(color: sombre ? Colors.white.withValues(alpha: 0.07) : bordure),
        ),
      ),

      listTileTheme: ListTileThemeData(
        iconColor: texteDoux,
        shape: RoundedRectangleBorder(borderRadius: rayonMd),
        subtitleTextStyle: TextStyle(fontFamily: Lulu.police, color: texteDoux, fontSize: 13),
      ),

      dividerTheme: DividerThemeData(color: bordure.withValues(alpha: 0.6), thickness: 1, space: 1),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: sombre ? Lulu.surface : surface,
        hintStyle: TextStyle(color: sombre ? Lulu.texteEteint : texteDoux),
        border: OutlineInputBorder(borderRadius: rayonMd, borderSide: BorderSide(color: bordure)),
        enabledBorder: OutlineInputBorder(borderRadius: rayonMd, borderSide: BorderSide(color: bordure)),
        focusedBorder: OutlineInputBorder(borderRadius: rayonMd, borderSide: BorderSide(color: accent, width: 1.5)),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: sombre ? Lulu.surface : surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Lulu.rXl), side: BorderSide(color: bordure.withValues(alpha: 0.6))),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: sombre ? Lulu.surface : surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: surfaceHaute,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: rayonMd, side: BorderSide(color: bordure.withValues(alpha: 0.6))),
      ),

      bannerTheme: MaterialBannerThemeData(backgroundColor: surfaceHaute, dividerColor: Colors.transparent),

      chipTheme: ChipThemeData(
        side: BorderSide(color: bordure),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        selectedColor: accent.withValues(alpha: 0.18),
        checkmarkColor: accent,
      ),

      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 400),
        decoration: BoxDecoration(color: sombre ? Lulu.surfaceHaute : Lulu.texteClair, borderRadius: BorderRadius.circular(Lulu.rSm)),
        textStyle: const TextStyle(fontFamily: Lulu.police, color: Lulu.texte, fontSize: 12),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Lulu.rLg - 2)),
        backgroundColor: sombre ? Lulu.surfaceHaute : Lulu.texteClair,
        contentTextStyle: const TextStyle(fontFamily: Lulu.police, color: Lulu.texte),
        actionTextColor: Lulu.accent,
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: surAccent,
          textStyle: const TextStyle(fontFamily: Lulu.police, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: rayonMd),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: texte,
          side: BorderSide(color: bordure),
          textStyle: const TextStyle(fontFamily: Lulu.police, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: rayonMd),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          textStyle: const TextStyle(fontFamily: Lulu.police, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: rayonMd),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          textStyle: const TextStyle(fontFamily: Lulu.police, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: rayonMd),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: surAccent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Lulu.rXl)),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          side: WidgetStatePropertyAll(BorderSide(color: bordure)),
          backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? accent.withValues(alpha: 0.18) : null),
          foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? accent : texte),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? surAccent : null),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? accent : null),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? accent : null),
        checkColor: WidgetStatePropertyAll(surAccent),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: accent),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: accent,
        selectionColor: accent.withValues(alpha: 0.3),
        selectionHandleColor: accent,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(bordure),
        radius: const Radius.circular(Lulu.rSm),
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

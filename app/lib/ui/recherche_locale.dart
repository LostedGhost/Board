import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'commun.dart';

/// Vrai si [texte] contient [recherche] (insensible à la casse). Une recherche vide correspond à tout.
bool concorde(String? texte, String recherche) {
  if (recherche.isEmpty) return true;
  if (texte == null) return false;
  return texte.toLowerCase().contains(recherche.toLowerCase());
}

/// Texte dont les occurrences de [recherche] sont surlignées avec la couleur d'accent.
class TexteSurligne extends StatelessWidget {
  const TexteSurligne(this.texte, this.recherche, {super.key, this.style, this.maxLines, this.overflow});

  final String texte;
  final String recherche;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    if (recherche.isEmpty) return Text(texte, style: style, maxLines: maxLines, overflow: overflow);
    final s = Theme.of(context).colorScheme;
    final reg = RegExp(RegExp.escape(recherche), caseSensitive: false);
    final spans = <TextSpan>[];
    var idx = 0;
    for (final m in reg.allMatches(texte)) {
      if (m.start > idx) spans.add(TextSpan(text: texte.substring(idx, m.start)));
      spans.add(TextSpan(
        text: m.group(0),
        style: TextStyle(color: s.primary, fontWeight: FontWeight.w700, backgroundColor: s.primary.withValues(alpha: 0.12)),
      ));
      idx = m.end;
    }
    if (idx < texte.length) spans.add(TextSpan(text: texte.substring(idx)));
    return Text.rich(TextSpan(style: style, children: spans), maxLines: maxLines, overflow: overflow);
  }
}

/// Champ de filtre d'un écran : filtre en direct, Échap ou la croix pour vider.
/// Ctrl+F (ou Cmd+F) le met au point quand [focusNode] est fourni et que l'écran l'enregistre.
class ChampRecherche extends StatelessWidget {
  const ChampRecherche({
    super.key,
    required this.controller,
    required this.onChanged,
    this.focusNode,
    this.indice = 'Filtrer',
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 8),
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final FocusNode? focusNode;
  final String indice;
  final EdgeInsets padding;

  void _vider() {
    controller.clear();
    onChanged('');
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: CallbackShortcuts(
          bindings: {const SingleActivator(LogicalKeyboardKey.escape): _vider},
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, v, _) => TextField(
              controller: controller,
              focusNode: focusNode,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                hintText: indice,
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: v.text.isEmpty
                    ? null
                    : IconButton(tooltip: 'Vider (Échap)', icon: const Icon(Icons.close, size: 18), onPressed: _vider),
              ),
            ),
          ),
        ),
      );
}

/// Raccourci Ctrl+F / Cmd+F qui donne le focus au champ de filtre de l'écran.
class RaccourciFiltre extends StatelessWidget {
  const RaccourciFiltre({super.key, required this.focusNode, required this.child});

  final FocusNode focusNode;
  final Widget child;

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyF, control: true): focusNode.requestFocus,
          const SingleActivator(LogicalKeyboardKey.keyF, meta: true): focusNode.requestFocus,
        },
        child: child,
      );
}

/// État « aucun résultat » : explique et propose de vider le filtre.
class AucunResultat extends StatelessWidget {
  const AucunResultat({super.key, required this.recherche, required this.onVider});

  final String recherche;
  final VoidCallback onVider;

  @override
  Widget build(BuildContext context) => EtatVide(
        icone: Icons.search_off,
        titre: 'Aucun résultat pour « $recherche »',
        texte: 'Vérifiez l\'orthographe ou essayez un autre mot.',
        action: OutlinedButton.icon(onPressed: onVider, icon: const Icon(Icons.close), label: const Text('Vider le filtre')),
      );
}

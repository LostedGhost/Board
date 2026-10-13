import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:markdown_widget/markdown_widget.dart';

import '../fonctionnalites/post_it/editeur_post_it.dart' show ouvrirEditeurPostIt;
import '../noyau/depot.dart';
import '../noyau/noyau.dart';
import 'coquille.dart';
import 'recherche_locale.dart';
import 'theme.dart';

// UC-H6 : mentionner un élément dans un autre.
// Stockage : `[[titre affiché|id]]`. L'identifiant rend le lien stable si la cible est renommée ;
// le titre sert de repli (lecture hors application, mention saisie à la main sans identifiant).

// --- Analyse de la syntaxe (pur Dart, testé dans test/mentions_test.dart) ---------------------

/// `[[titre]]` ou `[[titre|id]]` (sans crochet, barre verticale ni retour à la ligne).
final motifMention = RegExp(r'\[\[([^\[\]|\n]+)(?:\|([^\[\]|\n]+))?\]\]');

/// Préfixe des liens Markdown internes produits par [markdownAvecMentions].
const schemaMention = 'lulu-mention:';

class Mention {
  const Mention(this.titre, this.id, this.debut, this.fin);

  final String titre;

  /// `null` pour une mention saisie à la main sans identifiant : la cible est cherchée par titre.
  final String? id;
  final int debut;
  final int fin;

  @override
  bool operator ==(Object other) =>
      other is Mention && other.titre == titre && other.id == id && other.debut == debut && other.fin == fin;

  @override
  int get hashCode => Object.hash(titre, id, debut, fin);

  @override
  String toString() => 'Mention($titre, $id, $debut-$fin)';
}

/// Toutes les mentions de [texte], dans l'ordre.
List<Mention> analyserMentions(String texte) => [
      for (final m in motifMention.allMatches(texte))
        if (m.group(1)!.trim().isNotEmpty)
          Mention(
            m.group(1)!.trim(),
            (m.group(2)?.trim().isEmpty ?? true) ? null : m.group(2)!.trim(),
            m.start,
            m.end,
          ),
    ];

/// Morceau de texte : soit du texte brut ([mention] nulle), soit une mention.
class Segment {
  const Segment.texte(this.texte) : mention = null;
  const Segment.mention(Mention this.mention) : texte = '';

  final String texte;
  final Mention? mention;
}

/// Découpe [texte] en texte brut et mentions, pour un rendu sans Markdown (titres de tâches).
List<Segment> segmenter(String texte) {
  final segments = <Segment>[];
  var i = 0;
  for (final m in analyserMentions(texte)) {
    if (m.debut > i) segments.add(Segment.texte(texte.substring(i, m.debut)));
    segments.add(Segment.mention(m));
    i = m.fin;
  }
  if (i < texte.length) segments.add(Segment.texte(texte.substring(i)));
  return segments;
}

/// Titre utilisable dans la syntaxe : ni crochets, ni barre verticale, ni retour à la ligne.
String nettoyerTitre(String titre) {
  final t = titre.replaceAll(RegExp(r'[\[\]|\n\r]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  return t.length > 60 ? '${t.substring(0, 60).trimRight()}…' : t;
}

String formaterMention(String titre, String id) {
  final t = nettoyerTitre(titre);
  return '[[${t.isEmpty ? 'Sans titre' : t}|$id]]';
}

/// Remplace chaque mention par son titre (recherche, aperçu en texte brut).
String texteSansMentions(String texte) => texte.replaceAllMapped(motifMention, (m) => m.group(1)!.trim());

/// Saisie de mention en cours : `[[` suivi de [requete], juste avant le curseur.
class RequeteMention {
  const RequeteMention(this.debut, this.requete);

  /// Position du premier `[` de `[[`.
  final int debut;
  final String requete;

  @override
  bool operator ==(Object other) => other is RequeteMention && other.debut == debut && other.requete == requete;

  @override
  int get hashCode => Object.hash(debut, requete);

  @override
  String toString() => 'RequeteMention($debut, "$requete")';
}

/// Détecte une mention en cours de saisie avant [curseur] ; `null` s'il n'y en a pas.
RequeteMention? requeteEnCours(String texte, int curseur) {
  if (curseur < 2 || curseur > texte.length) return null;
  final avant = texte.substring(0, curseur);
  final debut = avant.lastIndexOf('[[');
  if (debut < 0) return null;
  final requete = avant.substring(debut + 2);
  if (requete.length > 60 || requete.contains(RegExp(r'[\[\]|\n]'))) return null;
  return RequeteMention(debut, requete);
}

/// Insère la mention à la place de la saisie en cours ; renvoie le texte et la nouvelle position du curseur.
({String texte, int curseur}) insererMention(String texte, int curseur, RequeteMention r, String titre, String id) {
  var fin = curseur;
  if (texte.startsWith(']]', fin)) fin += 2; // crochets fermants déjà tapés
  final mention = formaterMention(titre, id);
  return (texte: texte.replaceRange(r.debut, fin, mention), curseur: r.debut + mention.length);
}

/// Convertit les mentions en liens Markdown internes (`[titre](lulu-mention:id)`), hors code.
String markdownAvecMentions(String texte) {
  if (!texte.contains('[[')) return texte;
  var dansBlocCode = false;
  final lignes = texte.split('\n');
  for (var i = 0; i < lignes.length; i++) {
    final l = lignes[i];
    if (l.trimLeft().startsWith('```') || l.trimLeft().startsWith('~~~')) {
      dansBlocCode = !dansBlocCode;
      continue;
    }
    if (dansBlocCode || !l.contains('[[')) continue;
    // Les morceaux impairs sont dans du code en ligne (`…`) : on n'y touche pas.
    final morceaux = l.split('`');
    for (var j = 0; j < morceaux.length; j += 2) {
      morceaux[j] = morceaux[j].replaceAllMapped(motifMention, (m) {
        final titre = m.group(1)!.trim().replaceAllMapped(RegExp(r'([\\`*_~<>!])'), (c) => '\\${c.group(1)}');
        return '[$titre]($schemaMention${Uri.encodeComponent(m.group(2)?.trim() ?? '')})';
      });
    }
    lignes[i] = morceaux.join('`');
  }
  return lignes.join('\n');
}

/// Libellé court d'un élément pour l'autocomplétion et l'affichage d'une mention.
String titreElement(Enr e) {
  final d = (e['donnees'] as Map?) ?? const {};
  if (e['type'] == TypeEl.pressePapier && d['texte'] == null) return 'Image';
  final lignes = texteSansMentions(Depot.texteDe(e)).split('\n');
  final ligne = lignes.firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
  final propre = ligne
      .replaceFirst(RegExp(r'^\s*(#{1,6}\s+|>\s*|[-*+]\s+(\[[ xX]\]\s+)?|\d+[.)]\s+)'), '')
      .replaceAll(RegExp(r'[*_`~]'), '');
  final t = nettoyerTitre(propre);
  return t.isEmpty ? 'Sans titre' : t;
}

IconData iconeType(Object? type) => switch (type) {
      TypeEl.postIt => Icons.sticky_note_2_outlined,
      TypeEl.tache => Icons.check_box_outlined,
      TypeEl.liste => Icons.checklist,
      TypeEl.snippet => Icons.code,
      TypeEl.fichier => Icons.insert_drive_file_outlined,
      TypeEl.pressePapier => Icons.content_paste,
      _ => Icons.link,
    };

// --- Index des éléments ---------------------------------------------------------------------

/// Tous les éléments non supprimés, par identifiant, partagés par les puces et l'autocomplétion.
/// `null` tant que la première lecture n'est pas arrivée (on n'affiche alors rien de barré).
class IndexMentions {
  static final _parDepot = Expando<ValueNotifier<Map<String, Enr>?>>();

  static ValueNotifier<Map<String, Enr>?> de(Depot depot) => _parDepot[depot] ??= _creer(depot);

  static ValueNotifier<Map<String, Enr>?> _creer(Depot depot) {
    final n = ValueNotifier<Map<String, Enr>?>(null);
    depot.tousLesElements().listen((l) => n.value = {for (final e in l) e['id']! as String: e});
    return n;
  }

  /// Cible d'une mention : par identifiant, sinon par titre (mention saisie à la main).
  static Enr? resoudre(Map<String, Enr> index, Mention m) {
    if (m.id != null) return index[m.id];
    final t = m.titre.toLowerCase();
    for (final e in index.values) {
      if (titreElement(e).toLowerCase() == t) return e;
    }
    return null;
  }
}

/// Élément à mettre en avant à l'arrivée sur une section (écouté par l'écran des tâches).
final elementMentionneDemande = ValueNotifier<String?>(null);

/// Ouvre la cible d'une mention : un post-it s'ouvre dans son éditeur, le reste dans sa section.
Future<void> ouvrirMention(BuildContext context, Enr e) async {
  final type = e['type'];
  if (type == TypeEl.postIt) {
    await ouvrirEditeurPostIt(context, e);
    return;
  }
  final titreSection = switch (type) {
    TypeEl.pressePapier => 'Presse-papier',
    TypeEl.snippet => 'Snippets',
    TypeEl.liste || TypeEl.tache => 'Tâches',
    TypeEl.fichier => 'Fichiers',
    _ => null,
  };
  final i = sections.indexWhere((s) => s.titre == titreSection);
  if (i < 0) return;
  final messager = ScaffoldMessenger.maybeOf(context);
  Navigator.of(context, rootNavigator: true).popUntil((r) => r.isFirst);
  elementMentionneDemande.value = e['id']! as String;
  Coquille.sectionDemandee.value = i;
  messager
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text('« ${titreElement(e)} » se trouve dans $titreSection.')));
}

// --- Rendu ----------------------------------------------------------------------------------

/// Puce cliquable d'une mention. Cible supprimée : texte barré atténué, infobulle « Élément supprimé ».
class PuceMention extends StatelessWidget {
  const PuceMention(this.mention, {super.key, this.couleur, this.taille = 14});

  final Mention mention;

  /// Couleur du texte (par défaut l'accent du thème). Sur un post-it : sa couleur de texte, pour le contraste.
  final Color? couleur;
  final double taille;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final accent = couleur ?? s.primary;
    return ValueListenableBuilder<Map<String, Enr>?>(
      valueListenable: IndexMentions.de(context.noyau.depot),
      builder: (context, index, _) {
        final cible = index == null ? null : IndexMentions.resoudre(index, mention);
        final perdue = index != null && cible == null;
        final titre = cible == null ? mention.titre : titreElement(cible);
        if (perdue) {
          final attenue = (couleur ?? s.onSurfaceVariant).withValues(alpha: 0.6);
          final raison = mention.id == null ? 'Élément introuvable' : 'Élément supprimé';
          return Tooltip(
            message: raison,
            child: Semantics(
              label: '$titre, ${raison.toLowerCase()}',
              excludeSemantics: true,
              child: Text(
                titre,
                style: TextStyle(
                  fontSize: taille,
                  color: attenue,
                  decoration: TextDecoration.lineThrough,
                  decorationColor: attenue,
                ),
              ),
            ),
          );
        }
        final libelleType = TypeEl.libelles[cible?['type']] ?? 'Élément';
        return Semantics(
          link: true,
          label: 'Mention : $titre ($libelleType)',
          excludeSemantics: true,
          child: Tooltip(
            message: 'Ouvrir « $titre » ($libelleType)',
            child: Material(
              color: accent.withValues(alpha: 0.12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Lulu.rSm),
                side: BorderSide(color: accent.withValues(alpha: 0.35)),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(Lulu.rSm),
                onTap: cible == null ? null : () => ouvrirMention(context, cible),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Lulu.xs + 2, vertical: 1),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(iconeType(cible?['type']), size: taille, color: accent),
                      const SizedBox(width: Lulu.xs),
                      Flexible(
                        child: Text(
                          titre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: taille, color: accent, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Texte brut (titre de tâche…) dont les mentions deviennent des puces et la recherche est surlignée.
class TexteAvecMentions extends StatelessWidget {
  const TexteAvecMentions(this.texte, {super.key, this.recherche = '', this.style, this.maxLines, this.overflow});

  final String texte;
  final String recherche;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    final segments = segmenter(texte);
    if (segments.every((s) => s.mention == null)) {
      return TexteSurligne(texte, recherche, style: style, maxLines: maxLines, overflow: overflow);
    }
    final s = Theme.of(context).colorScheme;
    final surligne = TextStyle(color: s.primary, fontWeight: FontWeight.w700, backgroundColor: s.primary.withValues(alpha: 0.12));
    final spans = <InlineSpan>[];
    for (final seg in segments) {
      final m = seg.mention;
      if (m != null) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: PuceMention(m, taille: math.max(12, (style?.fontSize ?? 14) - 1)),
        ));
      } else if (recherche.isEmpty) {
        spans.add(TextSpan(text: seg.texte));
      } else {
        final reg = RegExp(RegExp.escape(recherche), caseSensitive: false);
        var i = 0;
        for (final r in reg.allMatches(seg.texte)) {
          if (r.start > i) spans.add(TextSpan(text: seg.texte.substring(i, r.start)));
          spans.add(TextSpan(text: r.group(0), style: surligne));
          i = r.end;
        }
        if (i < seg.texte.length) spans.add(TextSpan(text: seg.texte.substring(i)));
      }
    }
    return Text.rich(TextSpan(style: style, children: spans), maxLines: maxLines, overflow: overflow);
  }
}

/// Générateur Markdown : les liens `lulu-mention:` produits par [markdownAvecMentions] deviennent des puces.
/// À utiliser avec `MarkdownBlock(data: markdownAvecMentions(texte), generator: generateurMentions(...))`.
MarkdownGenerator generateurMentions({Color? couleur}) => MarkdownGenerator(
      generators: [
        SpanNodeGeneratorWithTag(
          tag: 'a',
          generator: (e, config, visitor) {
            final href = e.attributes['href'] ?? '';
            if (!href.startsWith(schemaMention)) return LinkNode(e.attributes, config.a);
            final id = Uri.decodeComponent(href.substring(schemaMention.length));
            return _NoeudMention(Mention(e.textContent, id.isEmpty ? null : id, 0, 0), couleur);
          },
        ),
      ],
    );

class _NoeudMention extends ElementNode {
  _NoeudMention(this.mention, this.couleur);

  final Mention mention;
  final Color? couleur;

  // Les enfants (le texte du lien) sont ignorés : la puce affiche le titre actuel de la cible.
  @override
  InlineSpan build() => WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: PuceMention(mention, couleur: couleur, taille: math.max(12, (parentStyle?.fontSize ?? 14) - 1)),
      );
}

// --- Autocomplétion -------------------------------------------------------------------------

/// Enveloppe un champ de texte : taper `[[` ouvre une liste filtrée d'éléments à mentionner.
/// Flèches haut/bas pour choisir, Entrée ou Tab (ou clic) pour insérer, Échap pour fermer.
class AutocompletionMentions extends StatefulWidget {
  const AutocompletionMentions({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.child,
    this.exclureId,
    this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final Widget child;

  /// L'élément en cours d'édition, qu'on ne se propose pas de mentionner lui-même.
  final String? exclureId;

  /// Appelé après une insertion (une modification par programme ne déclenche pas `onChanged` du champ).
  final ValueChanged<String>? onChanged;

  @override
  State<AutocompletionMentions> createState() => _AutocompletionMentionsState();
}

class _AutocompletionMentionsState extends State<AutocompletionMentions> {
  final _portail = OverlayPortalController();
  final _lien = LayerLink();
  final _defilement = ScrollController();
  ValueNotifier<Map<String, Enr>?>? _index;
  RequeteMention? _requete;
  List<Enr> _suggestions = const [];
  int _choix = 0;
  int? _fermeeA; // Échap : on ne rouvre pas tant qu'on reste dans la même saisie.
  double _largeur = 320;

  static const _max = 8;
  static const _hauteurLigne = 44.0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_maj);
    widget.focusNode.addListener(_maj);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final index = IndexMentions.de(context.noyau.depot);
    if (!identical(index, _index)) {
      _index?.removeListener(_maj);
      _index = index..addListener(_maj);
    }
  }

  @override
  void didUpdateWidget(AutocompletionMentions ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.controller != widget.controller) {
      ancien.controller.removeListener(_maj);
      widget.controller.addListener(_maj);
    }
    if (ancien.focusNode != widget.focusNode) {
      ancien.focusNode.removeListener(_maj);
      widget.focusNode.addListener(_maj);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_maj);
    widget.focusNode.removeListener(_maj);
    _index?.removeListener(_maj);
    _defilement.dispose();
    super.dispose();
  }

  void _maj() {
    final v = widget.controller.value;
    RequeteMention? r;
    if (widget.focusNode.hasFocus && v.selection.isValid && v.selection.isCollapsed) {
      r = requeteEnCours(v.text, v.selection.baseOffset);
    }
    if (r == null || r.debut != _fermeeA) _fermeeA = null;
    if (r != null && r.debut == _fermeeA) r = null;

    final suggestions = r == null ? const <Enr>[] : _filtrer(r.requete);
    final changement = r != _requete;
    if (!mounted) return;
    setState(() {
      _requete = r;
      _suggestions = suggestions;
      if (changement) _choix = 0;
      _choix = _suggestions.isEmpty ? 0 : _choix.clamp(0, _suggestions.length - 1);
    });
    if (r != null) {
      _portail.show();
    } else {
      _portail.hide();
    }
  }

  List<Enr> _filtrer(String requete) {
    final index = _index?.value;
    if (index == null) return const [];
    final q = requete.trim().toLowerCase();
    final candidats = <(int, String, Enr)>[];
    for (final e in index.values) {
      if (e['id'] == widget.exclureId) continue;
      final titre = titreElement(e).toLowerCase();
      final int rang;
      if (q.isEmpty || titre.startsWith(q)) {
        rang = 0;
      } else if (titre.contains(q)) {
        rang = 1;
      } else if (Depot.texteDe(e).toLowerCase().contains(q)) {
        rang = 2;
      } else {
        continue;
      }
      candidats.add((rang, (e['modifieLe'] ?? e['creeLe'] ?? '').toString(), e));
    }
    candidats.sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : b.$2.compareTo(a.$2));
    return [for (final c in candidats.take(_max)) c.$3];
  }

  void _inserer(Enr e) {
    final r = _requete;
    if (r == null) return;
    final v = widget.controller.value;
    final res = insererMention(v.text, v.selection.baseOffset, r, titreElement(e), e['id']! as String);
    widget.controller.value = TextEditingValue(text: res.texte, selection: TextSelection.collapsed(offset: res.curseur));
    widget.focusNode.requestFocus();
    widget.onChanged?.call(res.texte);
  }

  void _deplacer(int delta) {
    if (_suggestions.isEmpty) return;
    setState(() => _choix = (_choix + delta) % _suggestions.length);
    // Garde la ligne choisie visible.
    if (_defilement.hasClients) {
      final haut = _choix * _hauteurLigne;
      final pos = _defilement.position;
      if (haut < pos.pixels) {
        _defilement.jumpTo(haut);
      } else if (haut + _hauteurLigne > pos.pixels + pos.viewportDimension) {
        _defilement.jumpTo(haut + _hauteurLigne - pos.viewportDimension);
      }
    }
  }

  KeyEventResult _touche(FocusNode _, KeyEvent ev) {
    if (_requete == null || ev is KeyUpEvent) return KeyEventResult.ignored;
    final k = ev.logicalKey;
    if (k == LogicalKeyboardKey.arrowDown) {
      _deplacer(1);
    } else if (k == LogicalKeyboardKey.arrowUp) {
      _deplacer(-1);
    } else if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter || k == LogicalKeyboardKey.tab) {
      if (_suggestions.isEmpty) return KeyEventResult.ignored;
      _inserer(_suggestions[_choix]);
    } else if (k == LogicalKeyboardKey.escape) {
      _fermeeA = _requete!.debut;
      _maj();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  Widget _liste(BuildContext context) {
    final t = Theme.of(context);
    final s = t.colorScheme;
    final r = _requete;
    final Widget contenu;
    if (_index?.value == null) {
      contenu = const Padding(padding: EdgeInsets.all(Lulu.md), child: LinearProgressIndicator());
    } else if (_suggestions.isEmpty) {
      contenu = Padding(
        padding: const EdgeInsets.all(Lulu.md),
        child: Text(
          r == null || r.requete.trim().isEmpty ? 'Aucun élément à mentionner pour l\'instant.' : 'Aucun élément ne correspond à « ${r.requete.trim()} ».',
          style: t.textTheme.bodySmall?.copyWith(color: s.onSurfaceVariant),
        ),
      );
    } else {
      contenu = ListView.builder(
        controller: _defilement,
        padding: const EdgeInsets.symmetric(vertical: Lulu.xs),
        shrinkWrap: true,
        itemExtent: _hauteurLigne,
        itemCount: _suggestions.length,
        itemBuilder: (context, i) {
          final e = _suggestions[i];
          final choisi = i == _choix;
          return Semantics(
            selected: choisi,
            button: true,
            child: InkWell(
              onTap: () => _inserer(e),
              child: Container(
                color: choisi ? s.primary.withValues(alpha: 0.12) : null,
                padding: const EdgeInsets.symmetric(horizontal: Lulu.md),
                child: Row(
                  children: [
                    Icon(iconeType(e['type']), size: 18, color: choisi ? s.primary : s.onSurfaceVariant),
                    const SizedBox(width: Lulu.sm),
                    Expanded(
                      child: TexteSurligne(titreElement(e), r?.requete.trim() ?? '',
                          style: t.textTheme.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: Lulu.sm),
                    Text(TypeEl.libelles[e['type']] ?? '', style: t.textTheme.labelSmall?.copyWith(color: s.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }
    return Align(
      alignment: Alignment.topLeft,
      child: CompositedTransformFollower(
        link: _lien,
        targetAnchor: Alignment.bottomLeft,
        offset: const Offset(0, Lulu.xs),
        // Un clic dans la liste compte comme un clic dans le champ : il ne lui retire pas le focus.
        child: TextFieldTapRegion(
          child: Material(
            elevation: 6,
            color: s.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(Lulu.rMd),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: _largeur, minWidth: _largeur, maxHeight: _hauteurLigne * 6 + 2 * Lulu.xs + 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Lulu.md, Lulu.sm, Lulu.md, 0),
                    child: Text('Mentionner un élément · ↑↓ Entrée · Échap',
                        style: t.textTheme.labelSmall?.copyWith(color: s.onSurfaceVariant)),
                  ),
                  Flexible(child: contenu),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, contraintes) {
          if (contraintes.maxWidth.isFinite) _largeur = contraintes.maxWidth.clamp(260.0, 420.0);
          return OverlayPortal(
            controller: _portail,
            overlayChildBuilder: _liste,
            child: CompositedTransformTarget(
              link: _lien,
              child: Focus(
                canRequestFocus: false,
                skipTraversal: true,
                onKeyEvent: _touche,
                child: widget.child,
              ),
            ),
          );
        },
      );
}

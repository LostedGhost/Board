import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:markdown_widget/markdown_widget.dart';

import '../../noyau/depot.dart';
import '../../noyau/noyau.dart';
import '../../noyau/stockage/base_locale.dart';
import '../../ui/commun.dart';
import '../../ui/mentions.dart';
import '../../ui/recherche_locale.dart';
import '../../ui/theme.dart';
import '../commun/actions_element.dart';
import 'editeur_post_it.dart';

export 'editeur_post_it.dart' show ouvrirEditeurPostIt, choisirCouleur;

/// C1-C3, H12 : tableaux libres de post-it.
class EcranPostIt extends StatefulWidget {
  const EcranPostIt({super.key});

  @override
  State<EcranPostIt> createState() => _EcranPostItState();
}

class _EcranPostItState extends State<EcranPostIt> {
  String? _tableau;
  bool _archives = false;
  final _recherche = TextEditingController();
  final _focusRecherche = FocusNode();
  String _filtre = '';

  @override
  void dispose() {
    _recherche.dispose();
    _focusRecherche.dispose();
    super.dispose();
  }

  void _viderFiltre() {
    _recherche.clear();
    setState(() => _filtre = '');
  }

  @override
  Widget build(BuildContext context) {
    final depot = context.noyau.depot;
    final schema = Theme.of(context).colorScheme;
    return StreamBuilder<List<Enr>>(
      stream: depot.tableaux(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final tableaux = snap.data!..sort((a, b) => ((a['donnees'] as Map)['ordre'] as num? ?? 0).compareTo((b['donnees'] as Map)['ordre'] as num? ?? 0));
        if (tableaux.isEmpty) {
          return EtatVide(
            icone: Icons.dashboard_customize_outlined,
            titre: 'Aucun tableau',
            texte: 'Un tableau est un espace libre où poser vos post-it, les déplacer et les superposer.',
            action: FilledButton.icon(
              onPressed: () => depot.creerTableau('Mon tableau', 0),
              icon: const Icon(Icons.add),
              label: const Text('Créer mon premier tableau'),
            ),
          );
        }
        final courant = tableaux.firstWhere((t) => t['id'] == _tableau, orElse: () => tableaux.first);
        final large = MediaQuery.sizeOf(context).width >= 720;
        final champ = ChampRecherche(
          controller: _recherche,
          focusNode: _focusRecherche,
          indice: 'Filtrer les post-it (Ctrl+F)',
          padding: EdgeInsets.zero,
          onChanged: (v) => setState(() => _filtre = v.trim()),
        );
        return RaccourciFiltre(
          focusNode: _focusRecherche,
          child: Column(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: schema.surface,
                  border: Border(bottom: BorderSide(color: schema.outlineVariant)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(Lulu.sm),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: _ongletsTableaux(context, tableaux, courant)),
                          if (large) ...[
                            const SizedBox(width: Lulu.sm),
                            SizedBox(width: 260, child: champ),
                          ],
                          const SizedBox(width: Lulu.sm),
                          Tooltip(
                            message: _archives ? 'Revenir aux post-it actifs' : 'Afficher les post-it archivés',
                            child: FilterChip(
                              avatar: _archives ? null : const Icon(Icons.archive_outlined, size: 18),
                              label: const Text('Archivés'),
                              selected: _archives,
                              onSelected: (v) => setState(() => _archives = v),
                            ),
                          ),
                          const SizedBox(width: Lulu.sm),
                          Tooltip(
                            message: 'Ajouter un post-it sur ce tableau',
                            child: FilledButton.icon(
                              onPressed: () => _nouveauPostIt(context, courant['id']! as String),
                              icon: const Icon(Icons.add),
                              label: const Text('Post-it'),
                            ),
                          ),
                        ],
                      ),
                      if (!large) Padding(padding: const EdgeInsets.only(top: Lulu.sm), child: champ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: _Tableau(
                  tableauId: courant['id']! as String,
                  archives: _archives,
                  recherche: _filtre,
                  onViderFiltre: _viderFiltre,
                  onNouveau: () => _nouveauPostIt(context, courant['id']! as String),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _ongletsTableaux(BuildContext context, List<Enr> tableaux, Enr courant) {
    final depot = context.noyau.depot;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final t in tableaux)
            Padding(
              padding: const EdgeInsets.only(right: Lulu.sm),
              child: InputChip(
                label: Text(((t['donnees'] as Map)['nom'] ?? 'Sans nom').toString()),
                selected: t['id'] == courant['id'],
                showCheckmark: false,
                tooltip: 'Ouvrir ce tableau',
                onPressed: () => setState(() => _tableau = t['id'] as String),
                onDeleted: t['id'] == courant['id'] ? () => _menuTableau(context, t, tableaux) : null,
                deleteIcon: const Icon(Icons.more_horiz, size: 18),
                deleteButtonTooltipMessage: 'Gérer le tableau',
              ),
            ),
          IconButton(
            tooltip: 'Nouveau tableau',
            icon: const Icon(Icons.add),
            onPressed: () async {
              final nom = await demanderTexte(context, 'Nouveau tableau');
              if (nom != null && nom.isNotEmpty) {
                final id = await depot.creerTableau(nom, tableaux.length);
                setState(() => _tableau = id);
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _nouveauPostIt(BuildContext context, String tableauId) async {
    final depot = context.noyau.depot;
    final r = math.Random();
    // Couleur au hasard parmi les 5 premières (le blanc reste un choix explicite).
    final id = await depot.creer(TypeEl.postIt, {
      'contenu': '',
      'couleurFond': ThemeLulu.couleursPostIt[r.nextInt(5)],
      'x': 40.0 + r.nextInt(200),
      'y': 40.0 + r.nextInt(120),
      'largeur': 240.0,
      'hauteur': 200.0,
      'ordreEmpilement': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    }, parentId: tableauId);
    if (_archives) setState(() => _archives = false);
    final e = await depot.element(id);
    if (e != null && context.mounted) await ouvrirEditeurPostIt(context, e);
  }

  Future<void> _menuTableau(BuildContext context, Enr t, List<Enr> tableaux) async {
    final depot = context.noyau.depot;
    final action = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text(((t['donnees'] as Map)['nom'] ?? '').toString()),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, 'renommer'),
            child: const ListTile(leading: Icon(Icons.edit_outlined), title: Text('Renommer')),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, 'supprimer'),
            child: const ListTile(leading: Icon(Icons.delete_outline), title: Text('Supprimer')),
          ),
        ],
      ),
    );
    if (!context.mounted) return;
    if (action == 'renommer') {
      final nom = await demanderTexte(context, 'Renommer le tableau', initial: ((t['donnees'] as Map)['nom'] ?? '').toString());
      if (nom != null && nom.isNotEmpty) await depot.renommerTableau(t['id']! as String, nom);
    } else if (action == 'supprimer') {
      final postIts = (await depot.base.tous(Entite.element)).where((e) => e['parentId'] == t['id']).length;
      if (!context.mounted) return;
      final autres = tableaux.where((x) => x['id'] != t['id']).toList();
      final choix = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Supprimer le tableau ?'),
          content: Text(postIts == 0
              ? 'Ce tableau est vide.'
              : 'Il contient $postIts post-it. Déplacez-les vers un autre tableau, ou supprimez-les définitivement avec le tableau.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
            if (postIts > 0 && autres.isNotEmpty)
              TextButton(onPressed: () => Navigator.pop(c, 'deplacer'), child: Text('Déplacer vers « ${(autres.first['donnees'] as Map)['nom']} »')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error, foregroundColor: Theme.of(c).colorScheme.onError),
              onPressed: () => Navigator.pop(c, 'supprimer'),
              child: Text(postIts > 0 ? 'Tout supprimer' : 'Supprimer'),
            ),
          ],
        ),
      );
      if (choix == null) return;
      await depot.supprimerTableau(t['id']! as String, versTableau: choix == 'deplacer' ? autres.first['id'] as String : null);
      setState(() => _tableau = null);
      if (context.mounted) {
        afficherMessage(context, choix == 'deplacer' ? 'Tableau supprimé, ses post-it ont été déplacés.' : 'Tableau supprimé.');
      }
    }
  }
}

class _Tableau extends StatelessWidget {
  const _Tableau({
    required this.tableauId,
    required this.archives,
    required this.recherche,
    required this.onViderFiltre,
    required this.onNouveau,
  });

  final String tableauId;
  final bool archives;
  final String recherche;
  final VoidCallback onViderFiltre;
  final VoidCallback onNouveau;

  @override
  Widget build(BuildContext context) {
    final depot = context.noyau.depot;
    return StreamBuilder<List<Enr>>(
      stream: depot.elements(TypeEl.postIt, parentId: tableauId, archive: archives),
      builder: (context, snap) {
        final postIts = snap.data ?? [];
        if (snap.hasData && postIts.isEmpty) {
          return EtatVide(
            icone: archives ? Icons.archive_outlined : Icons.sticky_note_2_outlined,
            titre: archives ? 'Aucun post-it archivé' : 'Ce tableau attend vos idées',
            texte: archives
                ? 'Les post-it archivés apparaissent ici. Archivez-en un depuis son éditeur.'
                : 'Notez une idée, une liste ou un lien en Markdown, puis déplacez et superposez librement vos post-it.',
            action: archives
                ? null
                : FilledButton.icon(onPressed: onNouveau, icon: const Icon(Icons.add), label: const Text('Créer mon premier post-it')),
          );
        }
        bool correspond(Enr p) => concorde(texteSansMentions(((p['donnees'] as Map?)?['contenu'] ?? '').toString()), recherche);
        final nbConcordants = postIts.where(correspond).length;
        if (snap.hasData && recherche.isNotEmpty && nbConcordants == 0) {
          return AucunResultat(recherche: recherche, onVider: onViderFiltre);
        }
        // Pendant un filtrage, les post-it concordants passent au-dessus des autres.
        int rang(Enr p) => recherche.isNotEmpty && correspond(p) ? 1 : 0;
        postIts.sort((a, b) {
          final r = rang(a).compareTo(rang(b));
          if (r != 0) return r;
          return (((a['donnees'] as Map)['ordreEmpilement'] as num?) ?? 0).compareTo(((b['donnees'] as Map)['ordreEmpilement'] as num?) ?? 0);
        });
        final schema = Theme.of(context).colorScheme;
        return Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                constrained: false,
                minScale: 0.4,
                maxScale: 2,
                boundaryMargin: const EdgeInsets.all(400),
                child: SizedBox(
                  width: 3000,
                  height: 2000,
                  child: Stack(
                    children: [
                      for (final p in postIts)
                        _PostIt(key: ValueKey(p['id']), postIt: p, recherche: recherche, concorde: correspond(p)),
                    ],
                  ),
                ),
              ),
            ),
            if (recherche.isNotEmpty)
              Positioned(
                top: Lulu.sm,
                left: Lulu.sm,
                child: Semantics(
                  liveRegion: true,
                  child: Material(
                    color: schema.surfaceContainerHigh,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Lulu.rLg),
                      side: BorderSide(color: schema.outlineVariant),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(Lulu.md, Lulu.xs, Lulu.xs, Lulu.xs),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('$nbConcordants post-it sur ${postIts.length} correspond${nbConcordants > 1 ? 'ent' : ''}',
                              style: Theme.of(context).textTheme.bodySmall),
                          const SizedBox(width: Lulu.xs),
                          TextButton(onPressed: onViderFiltre, child: const Text('Tout afficher')),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PostIt extends StatefulWidget {
  const _PostIt({super.key, required this.postIt, required this.recherche, required this.concorde});

  final Enr postIt;
  final String recherche;
  final bool concorde;

  @override
  State<_PostIt> createState() => _PostItState();
}

class _PostItState extends State<_PostIt> {
  Offset? _position;
  Size? _taille;

  Map get _d => (widget.postIt['donnees'] as Map?) ?? {};

  @override
  void didUpdateWidget(covariant _PostIt old) {
    super.didUpdateWidget(old);
    _position = null;
    _taille = null;
  }

  Future<void> _premierPlan() async {
    await context.noyau.depot.modifierDonnees(widget.postIt['id']! as String,
        {'ordreEmpilement': DateTime.now().millisecondsSinceEpoch ~/ 1000});
  }

  @override
  Widget build(BuildContext context) {
    final pos = _position ?? Offset((_d['x'] as num? ?? 40).toDouble(), (_d['y'] as num? ?? 40).toDouble());
    final taille = _taille ?? Size((_d['largeur'] as num? ?? 240).toDouble(), (_d['hauteur'] as num? ?? 200).toDouble());
    final fond = couleurDepuisHex(_d['couleurFond'] as String?);
    final texte = couleurTexte(fond);
    final depot = context.noyau.depot;
    final id = widget.postIt['id']! as String;
    final contenu = _d['contenu'] as String? ?? '';
    final filtre = widget.recherche.isNotEmpty;
    final misEnAvant = filtre && widget.concorde;
    final schema = Theme.of(context).colorScheme;

    final Widget corps;
    if (contenu.isEmpty) {
      corps = Text('Double-cliquez pour écrire…', style: TextStyle(color: texte.withValues(alpha: 0.75), fontStyle: FontStyle.italic));
    } else if (misEnAvant) {
      // Pendant le filtrage : texte brut, occurrences surlignées (lisibles sur le fond du post-it).
      corps = _TexteSurlignePostIt(texteSansMentions(contenu), widget.recherche, texte);
    } else {
      corps = MarkdownBlock(
        data: markdownAvecMentions(contenu),
        selectable: false,
        config: configMarkdownPostIt(texte),
        generator: generateurMentions(couleur: texte),
      );
    }

    return Positioned(
      left: pos.dx,
      top: pos.dy,
      width: taille.width,
      height: taille.height,
      child: AnimatedOpacity(
        duration: Lulu.normal,
        opacity: filtre && !widget.concorde ? 0.2 : 1,
        child: Semantics(
          label: contenu.isEmpty ? 'Post-it vide' : 'Post-it : ${texteSansMentions(contenu).split('\n').first}',
          hint: 'Double-toucher pour modifier',
          onTap: () => ouvrirEditeurPostIt(context, widget.postIt),
          child: GestureDetector(
            onTapDown: (_) => _premierPlan(),
            onDoubleTap: () => ouvrirEditeurPostIt(context, widget.postIt),
            onPanUpdate: (d) => setState(() => _position = (_position ?? pos) + d.delta),
            onPanEnd: (_) => depot.modifierDonnees(id, {'x': _position!.dx.clamp(0, 2800), 'y': _position!.dy.clamp(0, 1800)}),
            child: Material(
              color: fond,
              elevation: misEnAvant ? 8 : 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Lulu.rMd),
                side: misEnAvant ? BorderSide(color: schema.primary, width: 2) : BorderSide(color: texte.withValues(alpha: 0.12)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Lulu.md, Lulu.md, Lulu.xl, Lulu.lg),
                    child: DefaultTextStyle.merge(
                      style: TextStyle(color: texte),
                      child: ClipRect(child: corps),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Theme(
                      data: Theme.of(context).copyWith(iconTheme: IconThemeData(color: texte)),
                      child: MenuElement(element: widget.postIt),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Tooltip(
                      message: 'Redimensionner',
                      child: GestureDetector(
                        onPanUpdate: (d) => setState(() {
                          final t = _taille ?? taille;
                          _taille = Size(math.max(140, t.width + d.delta.dx), math.max(100, t.height + d.delta.dy));
                        }),
                        onPanEnd: (_) => depot.modifierDonnees(id, {'largeur': _taille!.width, 'hauteur': _taille!.height}),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.resizeDownRight,
                          child: Padding(
                            padding: const EdgeInsets.all(Lulu.xs),
                            child: Icon(Icons.south_east, size: 16, color: texte.withValues(alpha: 0.6)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Surlignage adapté aux post-it : on garde la couleur de texte (contraste garanti) et on
/// marque l'occurrence par un fond teinté, du gras et un soulignement.
class _TexteSurlignePostIt extends StatelessWidget {
  const _TexteSurlignePostIt(this.texte, this.recherche, this.couleur);

  final String texte;
  final String recherche;
  final Color couleur;

  @override
  Widget build(BuildContext context) {
    final reg = RegExp(RegExp.escape(recherche), caseSensitive: false);
    final spans = <TextSpan>[];
    var idx = 0;
    for (final m in reg.allMatches(texte)) {
      if (m.start > idx) spans.add(TextSpan(text: texte.substring(idx, m.start)));
      spans.add(TextSpan(
        text: m.group(0),
        style: TextStyle(
          fontWeight: FontWeight.w700,
          decoration: TextDecoration.underline,
          decorationColor: couleur,
          backgroundColor: couleur.withValues(alpha: 0.16),
        ),
      ));
      idx = m.end;
    }
    if (idx < texte.length) spans.add(TextSpan(text: texte.substring(idx)));
    return Text.rich(TextSpan(style: TextStyle(color: couleur, fontSize: 14), children: spans));
  }
}

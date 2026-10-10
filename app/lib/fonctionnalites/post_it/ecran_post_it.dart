import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:markdown_widget/markdown_widget.dart';

import '../../noyau/depot.dart';
import '../../noyau/noyau.dart';
import '../../noyau/stockage/base_locale.dart';
import '../../plateformes/desktop.dart';
import '../../ui/commun.dart';
import '../../ui/theme.dart';
import '../commun/actions_element.dart';

/// C1-C3, H12 : tableaux libres de post-it.
class EcranPostIt extends StatefulWidget {
  const EcranPostIt({super.key});

  @override
  State<EcranPostIt> createState() => _EcranPostItState();
}

class _EcranPostItState extends State<EcranPostIt> {
  String? _tableau;
  bool _archives = false;

  @override
  Widget build(BuildContext context) {
    final depot = context.noyau.depot;
    return StreamBuilder<List<Enr>>(
      stream: depot.tableaux(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final tableaux = snap.data!..sort((a, b) => ((a['donnees'] as Map)['ordre'] as num? ?? 0).compareTo((b['donnees'] as Map)['ordre'] as num? ?? 0));
        if (tableaux.isEmpty) {
          return EtatVide(
            icone: Icons.sticky_note_2,
            titre: 'Aucun tableau',
            texte: 'Un tableau est un espace libre où poser vos post-it, les déplacer et les superposer.',
            action: FilledButton(onPressed: () => depot.creerTableau('Mon tableau', 0), child: const Text('Créer mon premier tableau')),
          );
        }
        final courant = tableaux.firstWhere((t) => t['id'] == _tableau, orElse: () => tableaux.first);
        return Column(
          children: [
            Material(
              elevation: 1,
              child: Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: Row(
                        children: [
                          for (final t in tableaux)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: InputChip(
                                label: Text(((t['donnees'] as Map)['nom'] ?? 'Sans nom').toString()),
                                selected: t['id'] == courant['id'],
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
                    ),
                  ),
                  FilterChip(label: const Text('Archivés'), selected: _archives, onSelected: (v) => setState(() => _archives = v)),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => _nouveauPostIt(context, courant['id']! as String),
                    icon: const Icon(Icons.add),
                    label: const Text('Post-it'),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
            Expanded(child: _Tableau(tableauId: courant['id']! as String, archives: _archives)),
          ],
        );
      },
    );
  }

  Future<void> _nouveauPostIt(BuildContext context, String tableauId) async {
    final depot = context.noyau.depot;
    final r = math.Random();
    final id = await depot.creer(TypeEl.postIt, {
      'contenu': '',
      'couleurFond': ThemeLulu.couleursPostIt[r.nextInt(5)],
      'x': 40.0 + r.nextInt(200),
      'y': 40.0 + r.nextInt(120),
      'largeur': 240.0,
      'hauteur': 200.0,
      'ordreEmpilement': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    }, parentId: tableauId);
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
          SimpleDialogOption(onPressed: () => Navigator.pop(c, 'renommer'), child: const Text('Renommer')),
          SimpleDialogOption(onPressed: () => Navigator.pop(c, 'supprimer'), child: const Text('Supprimer')),
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
          content: Text(postIts == 0 ? 'Ce tableau est vide.' : 'Il contient $postIts post-it.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
            if (postIts > 0 && autres.isNotEmpty)
              TextButton(onPressed: () => Navigator.pop(c, 'deplacer'), child: Text('Déplacer vers « ${(autres.first['donnees'] as Map)['nom']} »')),
            FilledButton(onPressed: () => Navigator.pop(c, 'supprimer'), child: Text(postIts > 0 ? 'Tout supprimer' : 'Supprimer')),
          ],
        ),
      );
      if (choix == null) return;
      await depot.supprimerTableau(t['id']! as String, versTableau: choix == 'deplacer' ? autres.first['id'] as String : null);
      setState(() => _tableau = null);
    }
  }
}

class _Tableau extends StatelessWidget {
  const _Tableau({required this.tableauId, required this.archives});

  final String tableauId;
  final bool archives;

  @override
  Widget build(BuildContext context) {
    final depot = context.noyau.depot;
    return StreamBuilder<List<Enr>>(
      stream: depot.elements(TypeEl.postIt, parentId: tableauId, archive: archives),
      builder: (context, snap) {
        final postIts = (snap.data ?? [])
          ..sort((a, b) => (((a['donnees'] as Map)['ordreEmpilement'] as num?) ?? 0)
              .compareTo(((b['donnees'] as Map)['ordreEmpilement'] as num?) ?? 0));
        if (snap.hasData && postIts.isEmpty) {
          return EtatVide(
            icone: archives ? Icons.archive_outlined : Icons.sticky_note_2_outlined,
            titre: archives ? 'Aucun post-it archivé' : 'Tableau vide',
            texte: archives ? 'Les post-it archivés apparaissent ici.' : 'Ajoutez un post-it avec le bouton « Post-it ».',
          );
        }
        return InteractiveViewer(
          constrained: false,
          minScale: 0.4,
          maxScale: 2,
          boundaryMargin: const EdgeInsets.all(400),
          child: SizedBox(
            width: 3000,
            height: 2000,
            child: Stack(children: [for (final p in postIts) _PostIt(key: ValueKey(p['id']), postIt: p)]),
          ),
        );
      },
    );
  }
}

class _PostIt extends StatefulWidget {
  const _PostIt({super.key, required this.postIt});

  final Enr postIt;

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

    return Positioned(
      left: pos.dx,
      top: pos.dy,
      width: taille.width,
      height: taille.height,
      child: GestureDetector(
        onTapDown: (_) => _premierPlan(),
        onDoubleTap: () => ouvrirEditeurPostIt(context, widget.postIt),
        onPanUpdate: (d) => setState(() => _position = (_position ?? pos) + d.delta),
        onPanEnd: (_) => depot.modifierDonnees(id, {'x': _position!.dx.clamp(0, 2800), 'y': _position!.dy.clamp(0, 1800)}),
        child: Material(
          color: fond,
          elevation: 3,
          borderRadius: BorderRadius.circular(6),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
                child: DefaultTextStyle.merge(
                  style: TextStyle(color: texte),
                  child: (_d['contenu'] as String? ?? '').isEmpty
                      ? Text('Double-cliquez pour écrire…', style: TextStyle(color: texte.withValues(alpha: 0.7), fontStyle: FontStyle.italic))
                      : ClipRect(
                          child: MarkdownBlock(
                            data: _d['contenu'] as String,
                            selectable: false,
                            config: MarkdownConfig(configs: [
                              PConfig(textStyle: TextStyle(color: texte, fontSize: 14)),
                              H1Config(style: TextStyle(color: texte, fontSize: 22, fontWeight: FontWeight.bold)),
                              H2Config(style: TextStyle(color: texte, fontSize: 18, fontWeight: FontWeight.bold)),
                              LinkConfig(style: TextStyle(color: texte, decoration: TextDecoration.underline)),
                            ]),
                          ),
                        ),
                ),
              ),
              Positioned(
                top: 0,
                right: 0,
                child: Theme(
                  data: Theme.of(context).copyWith(iconTheme: IconThemeData(color: texte)),
                  child: MenuElement(
                    element: widget.postIt,
                    extra: const [],
                  ),
                ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: GestureDetector(
                  onPanUpdate: (d) => setState(() {
                    final t = _taille ?? taille;
                    _taille = Size(math.max(140, t.width + d.delta.dx), math.max(100, t.height + d.delta.dy));
                  }),
                  onPanEnd: (_) => depot.modifierDonnees(id, {'largeur': _taille!.width, 'hauteur': _taille!.height}),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeDownRight,
                    child: Icon(Icons.drag_handle, size: 18, color: texte.withValues(alpha: 0.6)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Édition d'un post-it : Markdown, couleur (C1), archivage, historique (C3), premier plan (C2).
Future<void> ouvrirEditeurPostIt(BuildContext context, Enr postIt) =>
    showDialog<void>(context: context, builder: (_) => _EditeurPostIt(postIt));

class _EditeurPostIt extends StatefulWidget {
  const _EditeurPostIt(this.postIt);

  final Enr postIt;

  @override
  State<_EditeurPostIt> createState() => _EditeurPostItState();
}

class _EditeurPostItState extends State<_EditeurPostIt> {
  late final TextEditingController _contenu =
      TextEditingController(text: ((widget.postIt['donnees'] as Map?)?['contenu'] ?? '').toString());
  late String _couleur = ((widget.postIt['donnees'] as Map?)?['couleurFond'] ?? '#FFE066').toString();
  bool _apercu = false;

  String get _id => widget.postIt['id']! as String;

  @override
  Widget build(BuildContext context) {
    final depot = context.noyau.depot;
    final fond = couleurDepuisHex(_couleur);
    final texte = couleurTexte(fond);
    return AlertDialog(
      backgroundColor: fond,
      title: Row(
        children: [
          Text('Post-it', style: TextStyle(color: texte)),
          const Spacer(),
          IconButton(
            tooltip: _apercu ? 'Modifier' : 'Aperçu',
            icon: Icon(_apercu ? Icons.edit : Icons.visibility, color: texte),
            onPressed: () => setState(() => _apercu = !_apercu),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 240,
              child: _apercu
                  ? SingleChildScrollView(child: MarkdownBlock(data: _contenu.text, config: MarkdownConfig(configs: [PConfig(textStyle: TextStyle(color: texte))])))
                  : TextField(
                      controller: _contenu,
                      autofocus: true,
                      expands: true,
                      maxLines: null,
                      style: TextStyle(color: texte),
                      cursorColor: texte,
                      decoration: InputDecoration(
                        hintText: 'Markdown accepté : **gras**, *italique*, # titre, - liste, [ ] case',
                        hintStyle: TextStyle(color: texte.withValues(alpha: 0.6)),
                        border: InputBorder.none,
                      ),
                    ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                for (final c in ThemeLulu.couleursPostIt)
                  _PastilleCouleur(hex: c, choisie: c == _couleur, onTap: () => setState(() => _couleur = c)),
                ActionChip(
                  avatar: const Icon(Icons.palette_outlined, size: 18),
                  label: const Text('Autre…'),
                  onPressed: () async {
                    final c = await choisirCouleur(context, fond);
                    if (c != null) setState(() => _couleur = hexDepuisCouleur(c));
                  },
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('Contraste du texte : ${contraste(texte, fond).toStringAsFixed(1)}:1 (minimum 4,5:1)',
                style: TextStyle(color: texte, fontSize: 11)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await depot.modifierChamps(_id, {'archive': widget.postIt['archive'] != true});
            if (context.mounted) Navigator.pop(context);
          },
          child: Text(widget.postIt['archive'] == true ? 'Désarchiver' : 'Archiver', style: TextStyle(color: texte)),
        ),
        TextButton(
          onPressed: () => showDialog<void>(context: context, builder: (_) => _Historique(_id)),
          child: Text('Historique', style: TextStyle(color: texte)),
        ),
        if (IntegrationDesktop.captureDisponible)
          TextButton(
            onPressed: () => IntegrationDesktop.basculerPremierPlan(true),
            child: Text('Garder au premier plan', style: TextStyle(color: texte)),
          ),
        FilledButton(
          onPressed: () async {
            await depot.modifierDonnees(_id, {'contenu': _contenu.text, 'couleurFond': _couleur});
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

class _PastilleCouleur extends StatelessWidget {
  const _PastilleCouleur({required this.hex, required this.choisie, required this.onTap});

  final String hex;
  final bool choisie;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: choisie,
        label: 'Couleur $hex',
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: couleurDepuisHex(hex),
              shape: BoxShape.circle,
              border: Border.all(color: choisie ? Colors.black : Colors.black26, width: choisie ? 3 : 1),
            ),
          ),
        ),
      );
}

/// Sélecteur de couleur libre (teinte, saturation, luminosité).
Future<Color?> choisirCouleur(BuildContext context, Color initiale) {
  var hsl = HSLColor.fromColor(initiale);
  return showDialog<Color>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) {
        final couleur = hsl.toColor();
        return AlertDialog(
          title: const Text('Couleur du post-it'),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 64,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: couleur, borderRadius: BorderRadius.circular(8)),
                  child: Text('Aperçu du texte', style: TextStyle(color: couleurTexte(couleur), fontSize: 18)),
                ),
                const SizedBox(height: 12),
                Text('Teinte', style: Theme.of(c).textTheme.labelMedium),
                Slider(value: hsl.hue, max: 360, onChanged: (v) => setState(() => hsl = hsl.withHue(v))),
                Text('Saturation', style: Theme.of(c).textTheme.labelMedium),
                Slider(value: hsl.saturation, onChanged: (v) => setState(() => hsl = hsl.withSaturation(v))),
                Text('Luminosité', style: Theme.of(c).textTheme.labelMedium),
                Slider(value: hsl.lightness, onChanged: (v) => setState(() => hsl = hsl.withLightness(v))),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(c, couleur), child: const Text('Choisir')),
          ],
        );
      },
    ),
  );
}

/// C3 : historique des versions, restauration d'une ancienne version.
class _Historique extends StatelessWidget {
  const _Historique(this.postItId);

  final String postItId;

  @override
  Widget build(BuildContext context) {
    final depot = context.noyau.depot;
    return AlertDialog(
      title: const Text('Historique des versions'),
      content: SizedBox(
        width: 460,
        height: 400,
        child: StreamBuilder<List<Enr>>(
          stream: depot.versionsDe(postItId),
          builder: (context, snap) {
            final versions = (snap.data ?? [])..sort((a, b) => (b['creeLe'] as String? ?? '').compareTo(a['creeLe'] as String? ?? ''));
            if (versions.isEmpty) {
              return const Center(child: Text('Aucune version antérieure (l\'historique se remplit après synchronisation).'));
            }
            return ListView(
              children: [
                for (final v in versions)
                  ListTile(
                    title: Text(((v['donnees'] as Map)['contenu'] ?? '').toString(), maxLines: 3, overflow: TextOverflow.ellipsis),
                    subtitle: Text(dateCourte(v['creeLe'] as String?)),
                    trailing: TextButton(
                      onPressed: () async {
                        final d = Map<String, Object?>.from(v['donnees'] as Map);
                        await depot.modifierDonnees(postItId, {'contenu': d['contenu'], 'couleurFond': d['couleurFond']});
                        if (context.mounted) {
                          Navigator.pop(context);
                          afficherMessage(context, 'Version restaurée.');
                        }
                      },
                      child: const Text('Restaurer'),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer'))],
    );
  }
}

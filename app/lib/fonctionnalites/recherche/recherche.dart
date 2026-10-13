import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../noyau/depot.dart';
import '../../noyau/noyau.dart';
import '../../ui/commun.dart';
import '../../ui/recherche_locale.dart';
import '../../ui/theme.dart';
import '../commun/actions_element.dart';

/// G2 / H8 : une seule recherche sur tout le Board, faite sur l'appareil (données chiffrées côté serveur).
Future<void> ouvrirRecherche(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _Recherche());

/// Ordre d'affichage des groupes de résultats.
const _ordreTypes = [TypeEl.postIt, TypeEl.snippet, TypeEl.tache, TypeEl.liste, TypeEl.pressePapier, TypeEl.fichier];

const _icones = {
  TypeEl.pressePapier: Icons.content_paste,
  TypeEl.postIt: Icons.sticky_note_2_outlined,
  TypeEl.snippet: Icons.code,
  TypeEl.liste: Icons.list_alt,
  TypeEl.tache: Icons.check_box_outlined,
  TypeEl.fichier: Icons.insert_drive_file_outlined,
};

const _pluriels = {
  TypeEl.pressePapier: 'Presse-papier',
  TypeEl.postIt: 'Post-it',
  TypeEl.snippet: 'Snippets',
  TypeEl.liste: 'Listes de tâches',
  TypeEl.tache: 'Tâches',
  TypeEl.fichier: 'Fichiers',
};

const _maxResultats = 100;

class _Recherche extends StatefulWidget {
  const _Recherche();

  @override
  State<_Recherche> createState() => _RechercheState();
}

class _RechercheState extends State<_Recherche> {
  final _q = TextEditingController();
  final _focus = FocusNode();
  final _cleSelection = GlobalKey();
  Stream<List<Enr>>? _flux;
  int _selection = 0;
  List<Enr> _resultats = const []; // ordre d'affichage, pour la navigation clavier

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _flux ??= context.noyau.depot.tousLesElements();
  }

  @override
  void dispose() {
    _q.dispose();
    _focus.dispose();
    super.dispose();
  }

  String get _recherche => _q.text.trim();

  /// Ligne la plus parlante : la première qui contient la recherche, sinon la première.
  String _titre(Enr e) {
    final lignes = Depot.texteDe(e).split('\n');
    final r = _recherche;
    final l = r.isEmpty ? lignes.first : lignes.firstWhere((l) => concorde(l, r), orElse: () => lignes.first);
    final t = l.trim();
    return t.isEmpty ? '(sans texte)' : t;
  }

  Future<void> _activer(Enr e) async {
    await Clipboard.setData(ClipboardData(text: Depot.texteDe(e)));
    if (mounted) afficherMessage(context, '${TypeEl.libelles[e['type']] ?? 'Élément'} copié dans le presse-papier.');
  }

  void _deplacer(int delta) {
    if (_resultats.isEmpty) return;
    setState(() => _selection = (_selection + delta).clamp(0, _resultats.length - 1));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _cleSelection.currentContext;
      if (c == null) return;
      Scrollable.ensureVisible(
        c,
        duration: Lulu.rapide,
        alignmentPolicy: delta > 0 ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      );
    });
  }

  KeyEventResult _touche(FocusNode _, KeyEvent ev) {
    if (ev is! KeyDownEvent && ev is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = ev.logicalKey;
    if (k == LogicalKeyboardKey.arrowDown) {
      _deplacer(1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp) {
      _deplacer(-1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      if (_resultats.isNotEmpty && ev is KeyDownEvent) _activer(_resultats[_selection.clamp(0, _resultats.length - 1)]);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape && ev is KeyDownEvent) {
      if (_q.text.isNotEmpty) {
        _vider();
      } else {
        Navigator.maybePop(context);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _vider() {
    _q.clear();
    setState(() => _selection = 0);
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.fromLTRB(Lulu.md, Lulu.xl + Lulu.md, Lulu.md, Lulu.md),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 560),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(Lulu.md - Lulu.xs),
              child: Focus(
                onKeyEvent: _touche,
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _q,
                  builder: (context, v, _) => TextField(
                    controller: _q,
                    focusNode: _focus,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'Rechercher dans tout le Board…',
                      suffixIcon: v.text.isEmpty
                          ? null
                          : IconButton(tooltip: 'Vider (Échap)', icon: const Icon(Icons.close), onPressed: _vider),
                    ),
                    onChanged: (_) => setState(() => _selection = 0),
                  ),
                ),
              ),
            ),
            Expanded(
              child: StreamBuilder<List<Enr>>(
                stream: _flux,
                builder: (context, snap) {
                  if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                  return _liste(snap.data!);
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Lulu.md, vertical: Lulu.sm),
              child: Text(
                '↑ ↓ naviguer · Entrée copier · Échap ${_q.text.isEmpty ? 'fermer' : 'vider'}',
                style: t.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _liste(List<Enr> tous) {
    final r = _recherche;
    final trouves = r.isEmpty
        ? tous.where((e) => e['epingleAccesRapide'] == true).toList()
        : tous.where((e) => concorde(Depot.texteDe(e), r)).toList();
    trouves.sort((a, b) => (b['modifieLe'] as String? ?? '').compareTo(a['modifieLe'] as String? ?? ''));
    final limite = trouves.length > _maxResultats;

    // Groupement par type, dans un ordre stable.
    final groupes = <String, List<Enr>>{};
    for (final e in trouves.take(_maxResultats)) {
      (groupes[e['type'] as String? ?? ''] ??= []).add(e);
    }
    final types = [..._ordreTypes.where(groupes.containsKey), ...groupes.keys.where((k) => !_ordreTypes.contains(k))];
    _resultats = [for (final ty in types) ...groupes[ty]!];
    if (_selection >= _resultats.length) _selection = _resultats.isEmpty ? 0 : _resultats.length - 1;

    if (_resultats.isEmpty) {
      if (r.isNotEmpty) return AucunResultat(recherche: r, onVider: _vider);
      return const EtatVide(
        icone: Icons.star_border,
        titre: 'Tapez pour chercher',
        texte: 'La recherche porte sur tout le Board et se fait sur cet appareil. '
            'Les éléments épinglés en accès rapide apparaissent ici.',
      );
    }

    final t = Theme.of(context);
    var index = 0;
    return ListView(
      padding: const EdgeInsets.only(bottom: Lulu.sm),
      children: [
        if (r.isEmpty) _entete('Accès rapide', _resultats.length),
        for (final ty in types) ...[
          if (r.isNotEmpty) _entete(_pluriels[ty] ?? TypeEl.libelles[ty] ?? 'Autres', groupes[ty]!.length),
          for (final e in groupes[ty]!) _ligne(e, index++, t),
        ],
        if (limite)
          Padding(
            padding: const EdgeInsets.all(Lulu.md),
            child: Text('Seuls les $_maxResultats résultats les plus récents sont affichés : précisez la recherche.',
                style: t.textTheme.bodySmall, textAlign: TextAlign.center),
          ),
      ],
    );
  }

  Widget _entete(String titre, int nombre) => Padding(
        padding: const EdgeInsets.fromLTRB(Lulu.md, Lulu.md, Lulu.md, Lulu.xs),
        child: Semantics(
          header: true,
          child: Text(
            '${titre.toUpperCase()} · $nombre',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 0.8, fontWeight: FontWeight.w600),
          ),
        ),
      );

  Widget _ligne(Enr e, int index, ThemeData t) {
    final selectionne = index == _selection;
    final libelle = TypeEl.libelles[e['type']] ?? 'Élément';
    return Padding(
      key: selectionne ? _cleSelection : null,
      padding: const EdgeInsets.symmetric(horizontal: Lulu.sm),
      child: ListTile(
        selected: selectionne,
        selectedTileColor: t.colorScheme.primary.withValues(alpha: 0.10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Lulu.rMd)),
        dense: true,
        leading: Tooltip(message: libelle, child: Icon(_icones[e['type']] ?? Icons.notes, semanticLabel: libelle)),
        title: TexteSurligne(_titre(e), _recherche, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('$libelle · ${dateCourte(e['modifieLe'] as String?)}'),
        onTap: () {
          setState(() => _selection = index);
          _activer(e);
        },
        trailing: MenuElement(element: e),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../noyau/depot.dart';
import '../../noyau/noyau.dart';
import '../../ui/commun.dart';
import '../../ui/recherche_locale.dart';
import '../../ui/theme.dart';
import '../commun/actions_element.dart';
import '../commun/etiquettes.dart';

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
const _maxSuggestions = 8;

/// Requête décomposée (H7) : texte libre + filtres `#etiquette`.
/// [etiquettes] : filtres validés (correspondance exacte, insensible à la casse) ;
/// [enCours] : étiquette en cours de frappe (dernier mot commençant par `#`, correspondance par préfixe).
typedef _Requete = ({String texte, List<String> etiquettes, String? enCours});

_Requete _analyser(String brut) {
  final mots = brut.trim().split(RegExp(r'\s+')).where((m) => m.isNotEmpty).toList();
  if (!mots.any((m) => m.startsWith('#'))) return (texte: brut.trim(), etiquettes: const [], enCours: null);
  final finitParEspace = RegExp(r'\s$').hasMatch(brut);
  final texte = <String>[];
  final etiquettes = <String>[];
  String? enCours;
  for (var i = 0; i < mots.length; i++) {
    final m = mots[i];
    if (!m.startsWith('#')) {
      texte.add(m);
      continue;
    }
    final k = Depot.cleEtiquette(m);
    if (i == mots.length - 1 && !finitParEspace) {
      enCours = k;
    } else if (k.isNotEmpty && !etiquettes.contains(k)) {
      etiquettes.add(k);
    }
  }
  return (texte: texte.join(' '), etiquettes: etiquettes, enCours: enCours);
}

bool _correspond(Enr e, _Requete r) {
  final tags = [for (final t in Depot.etiquettesDe(e)) t.toLowerCase()];
  if (!r.etiquettes.every(tags.contains)) return false;
  if (r.enCours != null && !tags.any((t) => t.startsWith(r.enCours!))) return false;
  return r.texte.isEmpty || concorde(Depot.texteDe(e), r.texte) || tags.any((t) => concorde(t, r.texte));
}

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
  List<String> _suggestions = const []; // étiquettes proposées quand on tape `#`

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
  _Requete get _requete => _analyser(_q.text);

  void _remplacer(String texte) {
    _q.value = TextEditingValue(text: texte, selection: TextSelection.collapsed(offset: texte.length));
    setState(() => _selection = 0);
    _focus.requestFocus();
  }

  /// Remplace l'étiquette en cours de frappe par [tag] (suggestion choisie ou Tab).
  void _completer(String tag) {
    final base = _q.text.replaceFirst(RegExp(r'#\S*$'), '');
    _remplacer('$base#$tag ');
  }

  /// Clic sur une puce : ajoute le filtre `#tag`, ou le retire s'il est déjà actif.
  void _basculerEtiquette(String tag) {
    final k = Depot.cleEtiquette(tag);
    final mots = _q.text.trim().split(RegExp(r'\s+')).where((m) => m.isNotEmpty).toList();
    final sans = mots.where((m) => !(m.startsWith('#') && Depot.cleEtiquette(m) == k)).toList();
    if (sans.length == mots.length) sans.add('#$tag');
    _remplacer(sans.isEmpty ? '' : '${sans.join(' ')} ');
  }

  /// Ligne la plus parlante : la première qui contient la recherche, sinon la première.
  String _titre(Enr e) {
    final lignes = Depot.texteDe(e).split('\n');
    final r = _requete.texte;
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
    if (k == LogicalKeyboardKey.tab && _suggestions.isNotEmpty) {
      if (ev is KeyDownEvent) _completer(_suggestions.first);
      return KeyEventResult.handled;
    }
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
                      hintText: 'Rechercher dans tout le Board… (#étiquette pour filtrer)',
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
                '↑ ↓ naviguer · Entrée copier · #étiquette filtrer · Échap ${_q.text.isEmpty ? 'fermer' : 'vider'}',
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
    final req = _requete;
    final enCours = req.enCours;
    final compte = enCours == null ? const <({String nom, int nombre})>[] : Depot.compterEtiquettes(tous);
    _suggestions = [
      for (final t in compte)
        if (t.nom.toLowerCase().startsWith(enCours!) && !req.etiquettes.contains(t.nom.toLowerCase())) t.nom,
    ].take(_maxSuggestions).toList();
    final suggestions = _suggestions;
    final liste = _resultatsListe(tous, r, req);
    if (suggestions.isEmpty) return liste;
    final nombres = {for (final t in compte) t.nom: t.nombre};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Lulu.md, 0, Lulu.md, Lulu.sm),
          child: Semantics(
            label: 'Étiquettes suggérées',
            container: true,
            child: Wrap(
              spacing: Lulu.sm,
              runSpacing: Lulu.xs,
              children: [
                for (final (i, s) in suggestions.indexed)
                  ActionChip(
                    avatar: const Icon(Icons.sell_outlined, size: 16),
                    label: Text('#$s · ${nombres[s] ?? 0}'),
                    tooltip: i == 0 ? 'Tab pour compléter' : null,
                    onPressed: () => _completer(s),
                  ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(child: liste),
      ],
    );
  }

  Widget _resultatsListe(List<Enr> tous, String r, _Requete req) {
    final filtre = req.texte.isNotEmpty || req.etiquettes.isNotEmpty || req.enCours != null;
    final trouves = !filtre
        ? tous.where((e) => e['epingleAccesRapide'] == true).toList()
        : tous.where((e) => _correspond(e, req)).toList();
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
        title: TexteSurligne(_titre(e), _requete.texte, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Depot.etiquettesDe(e).isEmpty
            ? Text('$libelle · ${dateCourte(e['modifieLe'] as String?)}')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$libelle · ${dateCourte(e['modifieLe'] as String?)}'),
                  const SizedBox(height: Lulu.xs),
                  PucesEtiquettes(
                    e,
                    max: 6,
                    recherche: _requete.enCours ?? '',
                    actives: _requete.etiquettes.toSet(),
                    onTap: _basculerEtiquette,
                  ),
                ],
              ),
        onTap: () {
          setState(() => _selection = index);
          _activer(e);
        },
        trailing: MenuElement(element: e),
      ),
    );
  }
}

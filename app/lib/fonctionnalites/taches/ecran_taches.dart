import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../noyau/depot.dart';
import '../../noyau/noyau.dart';
import '../../ui/commun.dart';
import '../../ui/mentions.dart';
import '../../ui/recherche_locale.dart';
import '../../ui/theme.dart';
import '../commun/actions_element.dart';

/// F2 : listes de tâches, sous-tâches sans limite de profondeur, échéance, priorité.
class EcranTaches extends StatefulWidget {
  const EcranTaches({super.key});

  @override
  State<EcranTaches> createState() => _EcranTachesState();
}

class _EcranTachesState extends State<EcranTaches> {
  String? _liste;
  final _recherche = TextEditingController();
  final _focusRecherche = FocusNode();
  String _filtre = '';

  @override
  void initState() {
    super.initState();
    elementMentionneDemande.addListener(_surMention);
    // L'écran peut être construit juste après la demande (changement de section) : on la traite.
    WidgetsBinding.instance.addPostFrameCallback((_) => _surMention());
  }

  /// H6 : une mention de tâche ou de liste ouvre la liste qui la contient.
  Future<void> _surMention() async {
    final id = elementMentionneDemande.value;
    if (id == null || !mounted) return;
    final depot = context.noyau.depot;
    Enr? e = await depot.element(id);
    if (e == null || (e['type'] != TypeEl.tache && e['type'] != TypeEl.liste)) return;
    elementMentionneDemande.value = null;
    // On remonte les sous-tâches jusqu'à la liste (garde-fou contre une boucle de parents).
    for (var i = 0; i < 64 && e != null && e['type'] == TypeEl.tache; i++) {
      final parent = e['parentId'] as String?;
      e = parent == null ? null : await depot.element(parent);
    }
    final liste = e?['id'] as String?;
    if (liste == null || !mounted) return;
    _recherche.clear();
    setState(() {
      _filtre = '';
      _liste = liste;
    });
  }

  @override
  void dispose() {
    elementMentionneDemande.removeListener(_surMention);
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
    final large = MediaQuery.sizeOf(context).width >= 900;
    return StreamBuilder<List<Enr>>(
      stream: depot.elements(TypeEl.liste),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final listes = snap.data!..sort((a, b) => (a['creeLe'] as String? ?? '').compareTo(b['creeLe'] as String? ?? ''));
        if (listes.isEmpty) {
          return EtatVide(
            icone: Icons.checklist,
            titre: 'Aucune liste',
            texte: 'Créez une liste pour suivre vos tâches, avec sous-tâches, échéances et rappels.',
            action: FilledButton.icon(
              onPressed: () => _nouvelleListe(context),
              icon: const Icon(Icons.add),
              label: const Text('Créer ma première liste'),
            ),
          );
        }
        final courante = listes.firstWhere((l) => l['id'] == _liste, orElse: () => listes.first);
        final contenu = _Liste(
          key: ValueKey(courante['id']),
          liste: courante,
          recherche: _filtre,
          onViderFiltre: _viderFiltre,
          champRecherche: ChampRecherche(
            controller: _recherche,
            focusNode: _focusRecherche,
            indice: 'Filtrer les tâches (Ctrl+F)',
            padding: EdgeInsets.zero,
            onChanged: (v) => setState(() => _filtre = v.trim()),
          ),
        );
        final Widget corps;
        if (large) {
          final menuListes = Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(Lulu.sm),
                  children: [
                    for (final l in listes)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Lulu.xs),
                        child: ListTile(
                          selected: l['id'] == courante['id'],
                          leading: const Icon(Icons.list_alt),
                          title: Text(((l['donnees'] as Map)['titre'] ?? 'Sans titre').toString(), maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () => setState(() => _liste = l['id'] as String),
                          trailing: l['id'] == courante['id'] ? MenuElement(element: l) : null,
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(Lulu.sm),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(onPressed: () => _nouvelleListe(context), icon: const Icon(Icons.add), label: const Text('Nouvelle liste')),
                ),
              ),
            ],
          );
          corps = Row(children: [SizedBox(width: 260, child: menuListes), const VerticalDivider(width: 1), Expanded(child: contenu)]);
        } else {
          corps = Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Lulu.md, Lulu.sm, Lulu.sm, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: courante['id'] as String,
                        decoration: const InputDecoration(labelText: 'Liste', isDense: true),
                        items: [
                          for (final l in listes)
                            DropdownMenuItem(value: l['id'] as String, child: Text(((l['donnees'] as Map)['titre'] ?? '').toString())),
                        ],
                        onChanged: (v) => setState(() => _liste = v),
                      ),
                    ),
                    IconButton(tooltip: 'Nouvelle liste', icon: const Icon(Icons.playlist_add), onPressed: () => _nouvelleListe(context)),
                    MenuElement(element: courante),
                  ],
                ),
              ),
              Expanded(child: contenu),
            ],
          );
        }
        return RaccourciFiltre(focusNode: _focusRecherche, child: corps);
      },
    );
  }

  Future<void> _nouvelleListe(BuildContext context) async {
    final titre = await demanderTexte(context, 'Nouvelle liste', libelle: 'Titre');
    if (titre == null || titre.isEmpty || !context.mounted) return;
    final id = await context.noyau.depot.creer(TypeEl.liste, {'titre': titre});
    setState(() => _liste = id);
  }
}

bool _faite(Enr t) => (t['donnees'] as Map?)?['faite'] == true;
String _titre(Enr t) => ((t['donnees'] as Map?)?['titre'] ?? '').toString();
String _notes(Enr t) => ((t['donnees'] as Map?)?['notes'] ?? '').toString();

/// Texte sur lequel porte le filtre : titre et notes, mentions réduites à leur titre.
String _texteFiltre(Enr t) => texteSansMentions('${_titre(t)}\n${_notes(t)}');

class _Liste extends StatelessWidget {
  const _Liste({super.key, required this.liste, required this.recherche, required this.onViderFiltre, required this.champRecherche});

  final Enr liste;
  final String recherche;
  final VoidCallback onViderFiltre;
  final Widget champRecherche;

  @override
  Widget build(BuildContext context) {
    final depot = context.noyau.depot;
    final t = Theme.of(context);
    final listeId = liste['id']! as String;
    return StreamBuilder<List<Enr>>(
      stream: depot.elements(TypeEl.tache),
      builder: (context, snap) {
        final toutes = snap.data ?? [];
        final parParent = <String, List<Enr>>{};
        for (final t in toutes) {
          parParent.putIfAbsent(t['parentId'] as String? ?? '', () => []).add(t);
        }
        for (final l in parParent.values) {
          l.sort((a, b) {
            final fa = _faite(a) ? 1 : 0, fb = _faite(b) ? 1 : 0;
            if (fa != fb) return fa - fb;
            return ((a['donnees'] as Map)['ordre'] as num? ?? 0).compareTo((b['donnees'] as Map)['ordre'] as num? ?? 0);
          });
        }
        final racines = parParent[listeId] ?? [];

        // Toutes les tâches de la liste, quelle que soit leur profondeur.
        final descendants = <Enr>[];
        void parcourir(String id) {
          for (final e in parParent[id] ?? const <Enr>[]) {
            descendants.add(e);
            parcourir(e['id']! as String);
          }
        }

        parcourir(listeId);
        final total = descendants.length;
        final faites = descendants.where(_faite).length;

        // Filtre : une tâche reste visible si elle concorde ou si l'une de ses sous-tâches concorde.
        final visibles = <String>{};
        bool marquer(Enr e) {
          var garde = concorde(_texteFiltre(e), recherche);
          for (final s in parParent[e['id']] ?? const <Enr>[]) {
            if (marquer(s)) garde = true;
          }
          if (garde) visibles.add(e['id']! as String);
          return garde;
        }

        for (final r in racines) {
          marquer(r);
        }
        final racinesVisibles = racines.where((r) => visibles.contains(r['id'])).toList();

        return ListView(
          padding: const EdgeInsets.fromLTRB(Lulu.md, Lulu.md, Lulu.md, Lulu.xl),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(_titre(liste).isEmpty ? 'Sans titre' : _titre(liste),
                      style: t.textTheme.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                if (total > 0)
                  Semantics(
                    label: '$faites tâche${faites > 1 ? 's' : ''} terminée${faites > 1 ? 's' : ''} sur $total',
                    excludeSemantics: true,
                    child: Text('$faites/$total', style: t.textTheme.labelLarge?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                  ),
                if (faites > 0) ...[
                  const SizedBox(width: Lulu.sm),
                  TextButton.icon(
                    onPressed: () => _effacerTerminees(context, descendants, parParent),
                    icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                    label: const Text('Effacer les terminées'),
                  ),
                ],
              ],
            ),
            if (total > 0) ...[
              const SizedBox(height: Lulu.sm),
              ClipRRect(
                borderRadius: BorderRadius.circular(Lulu.rSm),
                child: LinearProgressIndicator(
                  value: faites / total,
                  minHeight: 4,
                  backgroundColor: t.colorScheme.outlineVariant,
                  semanticsLabel: 'Progression de la liste',
                  semanticsValue: '${(faites * 100 / total).round()} %',
                ),
              ),
            ],
            const SizedBox(height: Lulu.md),
            if (total > 0) ...[champRecherche, const SizedBox(height: Lulu.sm)],
            _ChampNouvelleTache(key: ValueKey('ajout-$listeId'), parentId: listeId),
            const SizedBox(height: Lulu.sm),
            if (racines.isEmpty)
              const Padding(
                padding: EdgeInsets.all(Lulu.lg),
                child: EtatVide(
                  icone: Icons.task_alt,
                  titre: 'Aucune tâche pour l\'instant',
                  texte: 'Tapez une tâche ci-dessus puis Entrée : le champ reste prêt pour enchaîner la suivante.',
                ),
              )
            else if (racinesVisibles.isEmpty)
              AucunResultat(recherche: recherche, onVider: onViderFiltre)
            else
              for (final r in racinesVisibles)
                _Tache(key: ValueKey(r['id']), tache: r, enfants: parParent, visibles: visibles, recherche: recherche, profondeur: 0),
          ],
        );
      },
    );
  }

  /// Supprime les tâches terminées dont toutes les sous-tâches sont terminées, avec annulation.
  Future<void> _effacerTerminees(BuildContext context, List<Enr> descendants, Map<String, List<Enr>> parParent) async {
    final depot = context.noyau.depot;
    bool touteFaite(Enr e) => _faite(e) && (parParent[e['id']] ?? const <Enr>[]).every(touteFaite);
    final candidates = descendants.where(touteFaite).toList();
    final ids = candidates.map((e) => e['id']! as String).toSet();
    // Une sous-tâche part avec son parent : on ne supprime que les tâches de plus haut niveau.
    final cibles = candidates.where((e) => !ids.contains(e['parentId'])).map((e) => e['id']! as String).toList();
    if (cibles.isEmpty) {
      afficherMessage(context, 'Les tâches terminées ont encore des sous-tâches à faire : rien n\'a été effacé.');
      return;
    }
    for (final id in cibles) {
      await depot.supprimerAvecAnnulation(id);
    }
    if (!context.mounted) return;
    proposerAnnulation(context, '${candidates.length} tâche${candidates.length > 1 ? 's terminées effacées' : ' terminée effacée'}.', () async {
      for (final id in cibles) {
        await depot.annulerSuppression(id);
      }
    });
  }
}

/// Ajout rapide : Entrée crée la tâche et garde le focus pour enchaîner.
class _ChampNouvelleTache extends StatefulWidget {
  const _ChampNouvelleTache({super.key, required this.parentId, this.compact = false, this.onFermer});

  final String parentId;
  final bool compact;
  final VoidCallback? onFermer;

  @override
  State<_ChampNouvelleTache> createState() => _ChampNouvelleTacheState();
}

class _ChampNouvelleTacheState extends State<_ChampNouvelleTache> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _ajouter() async {
    final t = _ctrl.text.trim();
    _focus.requestFocus();
    if (t.isEmpty) return;
    _ctrl.clear();
    await context.noyau.depot.creer(TypeEl.tache,
        {'titre': t, 'faite': false, 'echeance': null, 'priorite': 'NORMALE', 'ordre': DateTime.now().millisecondsSinceEpoch},
        parentId: widget.parentId);
    if (mounted) _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (_ctrl.text.isNotEmpty) {
              _ctrl.clear();
            } else {
              widget.onFermer?.call();
            }
          },
        },
        child: ValueListenableBuilder<TextEditingValue>(
          valueListenable: _ctrl,
          builder: (context, v, _) => AutocompletionMentions(
            controller: _ctrl,
            focusNode: _focus,
            child: TextField(
              controller: _ctrl,
              focusNode: _focus,
              autofocus: widget.compact,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                hintText: widget.compact ? 'Nouvelle sous-tâche, puis Entrée' : 'Ajouter une tâche, puis Entrée',
                prefixIcon: const Icon(Icons.add, size: 20),
                isDense: true,
                suffixIcon: v.text.trim().isEmpty
                    ? (widget.onFermer == null
                        ? null
                        : IconButton(tooltip: 'Fermer (Échap)', icon: const Icon(Icons.close, size: 18), onPressed: widget.onFermer))
                    : IconButton(tooltip: 'Ajouter (Entrée)', icon: const Icon(Icons.keyboard_return, size: 18), onPressed: _ajouter),
              ),
              onSubmitted: (_) => _ajouter(),
              // Sans ceci, Entrée retire le focus du champ : on veut pouvoir enchaîner les saisies.
              onEditingComplete: () {},
            ),
          ),
        ),
      );
}

class _Tache extends StatefulWidget {
  const _Tache({
    super.key,
    required this.tache,
    required this.enfants,
    required this.visibles,
    required this.recherche,
    required this.profondeur,
  });

  final Enr tache;
  final Map<String, List<Enr>> enfants;
  final Set<String> visibles;
  final String recherche;
  final int profondeur;

  @override
  State<_Tache> createState() => _TacheState();
}

class _TacheState extends State<_Tache> {
  bool _ajoutSousTache = false;

  static const _libellesPriorite = {'HAUTE': 'haute', 'NORMALE': 'normale', 'BASSE': 'basse'};

  Color _couleurPriorite(ColorScheme s, String p) => switch (p) {
        'HAUTE' => s.error,
        'BASSE' => s.outline,
        _ => s.onSurfaceVariant,
      };

  Future<void> _choisirEcheance(DateTime? echeance) async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      initialDate: echeance ?? DateTime.now(),
      helpText: 'Échéance de la tâche',
    );
    if (date == null || !mounted) return; // Annuler ne touche pas à l'échéance existante.
    await context.noyau.depot.modifierDonnees(widget.tache['id']! as String, {'echeance': date.toUtc().toIso8601String()});
  }

  @override
  Widget build(BuildContext context) {
    final depot = context.noyau.depot;
    final t = Theme.of(context);
    final s = t.colorScheme;
    final d = (widget.tache['donnees'] as Map?) ?? {};
    final id = widget.tache['id']! as String;
    final titre = (d['titre'] ?? '').toString();
    final notes = (d['notes'] ?? '').toString().trim();
    final faite = d['faite'] == true;
    final priorite = (d['priorite'] ?? 'NORMALE').toString();
    final echeance = DateTime.tryParse(d['echeance'] as String? ?? '');
    final enRetard = echeance != null && !faite && echeance.isBefore(DateTime.now());
    final sousTaches = widget.enfants[id] ?? const <Enr>[];
    final sousVisibles = sousTaches.where((e) => widget.visibles.contains(e['id'])).toList();
    final sousFaites = sousTaches.where(_faite).length;
    final concordeTitre = concorde(_texteFiltre(widget.tache), widget.recherche);
    final attenuee = faite || (widget.recherche.isNotEmpty && !concordeTitre);

    final infos = <Widget>[
      if (echeance != null)
        InputChip(
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          avatar: Icon(enRetard ? Icons.warning_amber_rounded : Icons.event, size: 16, color: enRetard ? s.error : null),
          label: Text(
            '${enRetard ? 'En retard · ' : ''}${dateCourte(echeance.toUtc().toIso8601String())}',
            style: TextStyle(color: enRetard ? s.error : null, fontSize: 12),
          ),
          tooltip: 'Changer l\'échéance',
          onPressed: () => _choisirEcheance(echeance),
          onDeleted: () => depot.modifierDonnees(id, {'echeance': null}),
          deleteButtonTooltipMessage: 'Retirer l\'échéance',
        ),
      if (sousTaches.isNotEmpty)
        Text('$sousFaites/${sousTaches.length} sous-tâche${sousTaches.length > 1 ? 's' : ''}',
            style: t.textTheme.bodySmall?.copyWith(color: s.onSurfaceVariant)),
    ];

    final ligne = ListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(left: Lulu.xs, right: 0),
      minLeadingWidth: 40,
      horizontalTitleGap: Lulu.sm,
      leading: SizedBox(
        width: 40,
        height: 40,
        child: Checkbox(
          value: faite,
          semanticLabel: faite
              ? 'Marquer « ${texteSansMentions(titre)} » comme à faire'
              : 'Marquer « ${texteSansMentions(titre)} » comme terminée',
          onChanged: (v) => depot.modifierDonnees(id, {'faite': v ?? false}),
        ),
      ),
      title: TexteAvecMentions(
        titre,
        recherche: widget.recherche,
        style: t.textTheme.bodyLarge?.copyWith(
          decoration: faite ? TextDecoration.lineThrough : null,
          color: attenuee ? s.onSurfaceVariant : null,
        ),
      ),
      subtitle: infos.isEmpty && notes.isEmpty
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: Lulu.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (notes.isNotEmpty)
                    TexteAvecMentions(
                      notes,
                      recherche: widget.recherche,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: t.textTheme.bodySmall?.copyWith(color: s.onSurfaceVariant),
                    ),
                  if (notes.isNotEmpty && infos.isNotEmpty) const SizedBox(height: Lulu.xs),
                  if (infos.isNotEmpty)
                    Wrap(spacing: Lulu.sm, runSpacing: Lulu.xs, crossAxisAlignment: WrapCrossAlignment.center, children: infos),
                ],
              ),
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Priorité ${_libellesPriorite[priorite] ?? 'normale'} (cliquer pour changer)',
            icon: Icon(priorite == 'BASSE' ? Icons.outlined_flag : Icons.flag, size: 20, color: _couleurPriorite(s, priorite)),
            onPressed: () {
              const ordre = ['BASSE', 'NORMALE', 'HAUTE'];
              final i = ordre.indexOf(priorite);
              depot.modifierDonnees(id, {'priorite': ordre[(i + 1) % 3]});
            },
          ),
          IconButton(
            tooltip: echeance == null ? 'Ajouter une échéance' : 'Changer l\'échéance',
            icon: const Icon(Icons.event, size: 20),
            onPressed: () => _choisirEcheance(echeance),
          ),
          IconButton(
            tooltip: _ajoutSousTache ? 'Fermer l\'ajout de sous-tâche' : 'Ajouter une sous-tâche',
            isSelected: _ajoutSousTache,
            icon: const Icon(Icons.subdirectory_arrow_right, size: 20),
            onPressed: () => setState(() => _ajoutSousTache = !_ajoutSousTache),
          ),
          MenuElement(element: widget.tache),
        ],
      ),
      onTap: () async {
        final r = await showDialog<({String titre, String notes})>(
          context: context,
          builder: (_) => _EditionTache(id: id, titre: titre, notes: (d['notes'] ?? '').toString()),
        );
        if (r != null && r.titre.isNotEmpty) await depot.modifierDonnees(id, {'titre': r.titre, 'notes': r.notes});
      },
    );

    // Au-delà de 8 niveaux, on n'indente plus pour garder de la place au texte.
    final indente = widget.profondeur < 8;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ligne,
        if (_ajoutSousTache || sousVisibles.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(left: indente ? Lulu.lg : 0),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: indente ? Border(left: BorderSide(color: s.outlineVariant, width: 2)) : null,
              ),
              child: Padding(
                padding: EdgeInsets.only(left: indente ? Lulu.sm : 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_ajoutSousTache)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(0, Lulu.xs, Lulu.sm, Lulu.sm),
                        child: _ChampNouvelleTache(
                          parentId: id,
                          compact: true,
                          onFermer: () => setState(() => _ajoutSousTache = false),
                        ),
                      ),
                    for (final st in sousVisibles)
                      _Tache(
                        key: ValueKey(st['id']),
                        tache: st,
                        enfants: widget.enfants,
                        visibles: widget.visibles,
                        recherche: widget.recherche,
                        profondeur: widget.profondeur + 1,
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Édition du titre et des notes d'une tâche ; « [[ » ouvre l'autocomplétion des mentions (H6).
class _EditionTache extends StatefulWidget {
  const _EditionTache({required this.id, required this.titre, required this.notes});

  final String id;
  final String titre;
  final String notes;

  @override
  State<_EditionTache> createState() => _EditionTacheState();
}

class _EditionTacheState extends State<_EditionTache> {
  late final _titre = TextEditingController(text: widget.titre);
  late final _notes = TextEditingController(text: widget.notes);
  final _focusTitre = FocusNode();
  final _focusNotes = FocusNode();

  @override
  void dispose() {
    _titre.dispose();
    _notes.dispose();
    _focusTitre.dispose();
    _focusNotes.dispose();
    super.dispose();
  }

  void _valider() => Navigator.pop(context, (titre: _titre.text.trim(), notes: _notes.text.trim()));

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return AlertDialog(
      title: const Text('Modifier la tâche'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AutocompletionMentions(
              controller: _titre,
              focusNode: _focusTitre,
              exclureId: widget.id,
              child: TextField(
                controller: _titre,
                focusNode: _focusTitre,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Titre'),
                onSubmitted: (_) => _valider(),
              ),
            ),
            const SizedBox(height: Lulu.md),
            AutocompletionMentions(
              controller: _notes,
              focusNode: _focusNotes,
              exclureId: widget.id,
              child: TextField(
                controller: _notes,
                focusNode: _focusNotes,
                minLines: 3,
                maxLines: 8,
                decoration: const InputDecoration(labelText: 'Notes', alignLabelWithHint: true),
              ),
            ),
            const SizedBox(height: Lulu.sm),
            Text('Astuce : tapez [[ pour mentionner un post-it, une tâche, un snippet ou un fichier.',
                style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(onPressed: _valider, child: const Text('Valider')),
      ],
    );
  }
}

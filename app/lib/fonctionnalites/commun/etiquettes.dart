/// H7 : étiquettes communes à tous les types d'éléments.
///
/// Stockage : `donnees['etiquettes']` de l'élément (liste de textes), donc chiffré de bout en bout
/// avec le reste de l'élément. Lecture / écriture via `Depot.etiquettesDe(element)` et
/// `depot.definirEtiquettes(id, liste)` (normalisation : trim, `#` retiré, espaces -> `-`,
/// doublons insensibles à la casse retirés, 20 au plus).
///
/// Intégration dans un écran (post-it, tâches, snippets, fichiers, presse-papier…) :
///
/// ```dart
/// import '../commun/etiquettes.dart';
///
/// // sous le titre / l'aperçu d'un élément (n'affiche rien s'il n'a pas d'étiquette) :
/// PucesEtiquettes(element),
/// // variantes : surlignage du filtre local, clic pour filtrer, nombre maximal affiché
/// PucesEtiquettes(element, recherche: q, onTap: (e) => filtrerPar(e), max: 3),
/// ```
///
/// L'édition passe par l'action « Étiquettes… » du menu commun (`MenuElement`), ou directement
/// par `editerEtiquettes(context, elementId)`.
library;

import 'package:flutter/material.dart';

import '../../noyau/depot.dart';
import '../../noyau/noyau.dart';
import '../../ui/commun.dart';
import '../../ui/recherche_locale.dart';
import '../../ui/theme.dart';

/// Puces compactes (« #etiquette ») d'un élément. Ne prend aucune place si l'élément n'en a pas.
class PucesEtiquettes extends StatelessWidget {
  const PucesEtiquettes(this.element, {super.key, this.onTap, this.recherche = '', this.max, this.actives = const {}});

  final Enr element;

  /// Clic sur une puce (par exemple pour filtrer). Sans rappel, les puces ne sont pas cliquables.
  final ValueChanged<String>? onTap;

  /// Texte à surligner dans les puces.
  final String recherche;

  /// Nombre maximal de puces affichées (les autres sont résumées par « +n »).
  final int? max;

  /// Étiquettes à mettre en évidence (comparaison insensible à la casse), ex. filtres actifs.
  final Set<String> actives;

  @override
  Widget build(BuildContext context) {
    final toutes = Depot.etiquettesDe(element);
    if (toutes.isEmpty) return const SizedBox.shrink();
    final visibles = max == null || toutes.length <= max! ? toutes : toutes.take(max!).toList();
    final reste = toutes.length - visibles.length;
    final cles = {for (final a in actives) a.toLowerCase()};
    return Wrap(
      spacing: Lulu.xs,
      runSpacing: Lulu.xs,
      children: [
        for (final e in visibles)
          PuceEtiquette(e, recherche: recherche, active: cles.contains(e.toLowerCase()), onTap: onTap == null ? null : () => onTap!(e)),
        if (reste > 0)
          Tooltip(
            message: toutes.skip(visibles.length).map((e) => '#$e').join(' '),
            child: PuceEtiquette('+$reste', diese: false),
          ),
      ],
    );
  }
}

/// Une puce d'étiquette, compacte, accessible (cible cliquable avec libellé).
class PuceEtiquette extends StatelessWidget {
  const PuceEtiquette(this.etiquette, {super.key, this.onTap, this.recherche = '', this.active = false, this.diese = true});

  final String etiquette;
  final VoidCallback? onTap;
  final String recherche;
  final bool active;
  final bool diese;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final texte = diese ? '#$etiquette' : etiquette;
    final puce = Container(
      padding: const EdgeInsets.symmetric(horizontal: Lulu.sm - 2, vertical: 1),
      decoration: BoxDecoration(
        color: active ? c.primary.withValues(alpha: 0.18) : c.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(Lulu.rSm),
        border: Border.all(color: c.primary.withValues(alpha: active ? 0.6 : 0.25)),
      ),
      child: TexteSurligne(
        texte,
        recherche,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: c.primary, fontWeight: active ? FontWeight.w700 : FontWeight.w500),
      ),
    );
    if (onTap == null) return Semantics(label: 'Étiquette $etiquette', excludeSemantics: true, child: puce);
    return Semantics(
      button: true,
      label: 'Filtrer par l\'étiquette $etiquette',
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(Lulu.rSm),
          onTap: onTap,
          child: Tooltip(message: 'Filtrer par #$etiquette', child: puce),
        ),
      ),
    );
  }
}

/// Ouvre le dialogue d'édition des étiquettes de l'élément [id] et enregistre le résultat.
Future<void> editerEtiquettes(BuildContext context, String id) async {
  final depot = context.noyau.depot;
  final element = await depot.element(id);
  if (element == null || !context.mounted) return;
  final existantes = await depot.toutesLesEtiquettes();
  if (!context.mounted) return;
  final res = await showDialog<List<String>>(
    context: context,
    builder: (_) => _DialogueEtiquettes(initiales: Depot.etiquettesDe(element), existantes: existantes),
  );
  if (res == null) return;
  await depot.definirEtiquettes(id, res);
  if (context.mounted) afficherMessage(context, res.isEmpty ? 'Étiquettes retirées.' : 'Étiquettes enregistrées.');
}

class _DialogueEtiquettes extends StatefulWidget {
  const _DialogueEtiquettes({required this.initiales, required this.existantes});

  final List<String> initiales;
  final List<({String nom, int nombre})> existantes;

  @override
  State<_DialogueEtiquettes> createState() => _DialogueEtiquettesState();
}

class _DialogueEtiquettesState extends State<_DialogueEtiquettes> {
  late final List<String> _etiquettes = [...widget.initiales];
  final _champ = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _champ.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _plein => _etiquettes.length >= Depot.maxEtiquettes;

  void _ajouter(String brut) {
    final nouvelles = Depot.normaliserEtiquettes([..._etiquettes, ...brut.split(',')]);
    setState(() {
      _etiquettes
        ..clear()
        ..addAll(nouvelles);
    });
    _champ.clear();
    _focus.requestFocus();
  }

  Iterable<String> _suggestions(TextEditingValue v) {
    final q = Depot.cleEtiquette(v.text);
    final deja = {for (final e in _etiquettes) e.toLowerCase()};
    return widget.existantes
        .where((e) => !deja.contains(e.nom.toLowerCase()) && (q.isEmpty || e.nom.toLowerCase().contains(q)))
        .map((e) => e.nom)
        .take(8);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final nombres = {for (final e in widget.existantes) e.nom.toLowerCase(): e.nombre};
    return AlertDialog(
      title: const Text('Étiquettes'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Les étiquettes sont communes à tous les modules et chiffrées avec l\'élément. '
                'Tapez # suivi d\'une étiquette dans la recherche (Ctrl+K) pour filtrer.',
                style: t.textTheme.bodySmall),
            const SizedBox(height: Lulu.md),
            if (_etiquettes.isEmpty)
              Text('Aucune étiquette.', style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant))
            else
              Wrap(
                spacing: Lulu.sm,
                runSpacing: Lulu.sm,
                children: [
                  for (final e in _etiquettes)
                    InputChip(
                      label: Text('#$e'),
                      onDeleted: () => setState(() => _etiquettes.remove(e)),
                      deleteButtonTooltipMessage: 'Retirer #$e',
                    ),
                ],
              ),
            const SizedBox(height: Lulu.md),
            RawAutocomplete<String>(
              textEditingController: _champ,
              focusNode: _focus,
              optionsBuilder: _suggestions,
              onSelected: _ajouter,
              fieldViewBuilder: (context, controller, focusNode, _) => TextField(
                controller: controller,
                focusNode: focusNode,
                autofocus: true,
                enabled: !_plein,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'Ajouter une étiquette',
                  hintText: _plein ? '${Depot.maxEtiquettes} étiquettes au maximum' : 'Entrée pour ajouter, virgule pour plusieurs',
                  prefixText: '# ',
                  suffixIcon: IconButton(
                    tooltip: 'Ajouter',
                    icon: const Icon(Icons.add),
                    onPressed: _plein ? null : () => _ajouter(controller.text),
                  ),
                ),
                onSubmitted: _ajouter,
              ),
              optionsViewBuilder: (context, onSelected, options) => Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(Lulu.rMd),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240, maxWidth: 420),
                    child: ListView(
                      padding: const EdgeInsets.symmetric(vertical: Lulu.xs),
                      shrinkWrap: true,
                      children: [
                        for (final o in options)
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.sell_outlined, size: 18),
                            title: Text('#$o'),
                            trailing: Text('${nombres[o.toLowerCase()] ?? 0}', style: t.textTheme.bodySmall),
                            onTap: () => onSelected(o),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          onPressed: () {
            // Une saisie non validée par Entrée est ajoutée aussi.
            final tout = Depot.normaliserEtiquettes([..._etiquettes, ..._champ.text.split(',')]);
            Navigator.pop(context, tout);
          },
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

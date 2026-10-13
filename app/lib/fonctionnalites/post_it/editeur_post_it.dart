import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:markdown_widget/markdown_widget.dart';

import '../../noyau/depot.dart';
import '../../noyau/noyau.dart';
import '../../plateformes/desktop.dart';
import '../../ui/commun.dart';
import '../../ui/mentions.dart';
import '../../ui/theme.dart';

/// Noms lisibles des 6 couleurs par défaut (même ordre que [ThemeLulu.couleursPostIt]).
const nomsCouleursPostIt = <String>['Jaune', 'Rose', 'Turquoise', 'Vert menthe', 'Lavande', 'Blanc'];

/// Rendu Markdown d'un post-it, avec une couleur de texte lisible sur son fond.
MarkdownConfig configMarkdownPostIt(Color texte) => MarkdownConfig(configs: [
      PConfig(textStyle: TextStyle(color: texte, fontSize: 14)),
      H1Config(style: TextStyle(color: texte, fontSize: 22, fontWeight: FontWeight.bold)),
      H2Config(style: TextStyle(color: texte, fontSize: 18, fontWeight: FontWeight.bold)),
      H3Config(style: TextStyle(color: texte, fontSize: 16, fontWeight: FontWeight.bold)),
      LinkConfig(style: TextStyle(color: texte, decoration: TextDecoration.underline)),
      CodeConfig(style: TextStyle(color: texte, backgroundColor: texte.withValues(alpha: 0.1))),
    ]);

/// Édition d'un post-it : Markdown, couleur (C1), archivage, historique (C3), premier plan (C2).
/// Les modifications sont enregistrées automatiquement.
Future<void> ouvrirEditeurPostIt(BuildContext context, Enr postIt) =>
    showDialog<void>(context: context, builder: (_) => _EditeurPostIt(postIt));

enum _EtatSauvegarde { aucune, modifie, enCours, enregistre }

class _EditeurPostIt extends StatefulWidget {
  const _EditeurPostIt(this.postIt);

  final Enr postIt;

  @override
  State<_EditeurPostIt> createState() => _EditeurPostItState();
}

class _EditeurPostItState extends State<_EditeurPostIt> {
  late final TextEditingController _contenu = TextEditingController(text: _contenuSauve);
  late String _contenuSauve = ((widget.postIt['donnees'] as Map?)?['contenu'] ?? '').toString();
  late String _couleurSauvee = ((widget.postIt['donnees'] as Map?)?['couleurFond'] ?? ThemeLulu.couleursPostIt.first).toString();
  late String _couleur = _couleurSauvee;
  late Depot _depot;
  final _focus = FocusNode();
  bool _apercu = false;
  Timer? _minuterie;
  var _etat = _EtatSauvegarde.aucune;

  String get _id => widget.postIt['id']! as String;
  bool get _modifie => _contenu.text != _contenuSauve || _couleur != _couleurSauvee;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _depot = context.noyau.depot;
  }

  @override
  void dispose() {
    _minuterie?.cancel();
    // Fermeture (Échap, clic hors du dialogue) : rien ne doit être perdu.
    if (_modifie) _depot.modifierDonnees(_id, {'contenu': _contenu.text, 'couleurFond': _couleur});
    _contenu.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _planifier() {
    _minuterie?.cancel();
    if (!_modifie) {
      setState(() => _etat = _etat == _EtatSauvegarde.aucune ? _EtatSauvegarde.aucune : _EtatSauvegarde.enregistre);
      return;
    }
    setState(() => _etat = _EtatSauvegarde.modifie);
    _minuterie = Timer(const Duration(milliseconds: 800), _enregistrer);
  }

  Future<void> _enregistrer() async {
    _minuterie?.cancel();
    if (!_modifie) return;
    final contenu = _contenu.text, couleur = _couleur;
    if (mounted) setState(() => _etat = _EtatSauvegarde.enCours);
    await _depot.modifierDonnees(_id, {'contenu': contenu, 'couleurFond': couleur});
    _contenuSauve = contenu;
    _couleurSauvee = couleur;
    if (mounted) setState(() => _etat = _modifie ? _EtatSauvegarde.modifie : _EtatSauvegarde.enregistre);
  }

  void _changerCouleur(String hex) {
    setState(() => _couleur = hex);
    _planifier();
  }

  void _basculerApercu() {
    setState(() => _apercu = !_apercu);
    if (!_apercu) _focus.requestFocus();
  }

  Future<void> _archiver() async {
    await _enregistrer();
    final archive = widget.postIt['archive'] == true;
    await _depot.modifierChamps(_id, {'archive': !archive});
    if (!mounted) return;
    final messager = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messager
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(archive ? 'Post-it désarchivé : il est de retour sur le tableau.' : 'Post-it archivé. Retrouvez-le avec le filtre « Archivés ».'),
        action: SnackBarAction(label: 'Annuler', onPressed: () => _depot.modifierChamps(_id, {'archive': archive})),
      ));
  }

  Future<void> _historique() async {
    await _enregistrer();
    if (!mounted) return;
    final version = await showDialog<Map>(context: context, builder: (_) => _Historique(_id));
    if (version == null || !mounted) return;
    // La version restaurée est déjà enregistrée : on aligne l'éditeur sans déclencher de sauvegarde.
    setState(() {
      _contenuSauve = (version['contenu'] ?? '').toString();
      _couleurSauvee = (version['couleurFond'] ?? _couleur).toString();
      _contenu.text = _contenuSauve;
      _couleur = _couleurSauvee;
      _etat = _EtatSauvegarde.enregistre;
    });
    afficherMessage(context, 'Version restaurée.');
  }

  Widget _statut(Color texte) {
    final style = TextStyle(color: texte.withValues(alpha: 0.8), fontSize: 12);
    final (IconData icone, String libelle) = switch (_etat) {
      _EtatSauvegarde.aucune => (Icons.cloud_done_outlined, 'Enregistrement automatique'),
      _EtatSauvegarde.modifie => (Icons.edit_outlined, 'Modifications en cours…'),
      _EtatSauvegarde.enCours => (Icons.sync, 'Enregistrement…'),
      _EtatSauvegarde.enregistre => (Icons.check, 'Enregistré'),
    };
    return Semantics(
      liveRegion: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 14, color: style.color),
          const SizedBox(width: Lulu.xs),
          Text(libelle, style: style),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fond = couleurDepuisHex(_couleur);
    final texte = couleurTexte(fond);
    final contenu = _contenu.text;
    final mots = contenu.trim().isEmpty ? 0 : contenu.trim().split(RegExp(r'\s+')).length;
    final styleBouton = TextButton.styleFrom(foregroundColor: texte);
    final personnalisee = !ThemeLulu.couleursPostIt.contains(_couleur);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _enregistrer,
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _enregistrer,
        const SingleActivator(LogicalKeyboardKey.keyE, control: true): _basculerApercu,
        const SingleActivator(LogicalKeyboardKey.keyE, meta: true): _basculerApercu,
      },
      child: AlertDialog(
        backgroundColor: fond,
        titlePadding: const EdgeInsets.fromLTRB(Lulu.lg, Lulu.lg, Lulu.lg, 0),
        contentPadding: const EdgeInsets.fromLTRB(Lulu.lg, Lulu.md, Lulu.lg, 0),
        title: Row(
          children: [
            Text('Post-it', style: TextStyle(color: texte)),
            const Spacer(),
            _statut(texte),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    style: SegmentedButton.styleFrom(
                      foregroundColor: texte,
                      selectedForegroundColor: texte,
                      selectedBackgroundColor: texte.withValues(alpha: 0.14),
                      side: BorderSide(color: texte.withValues(alpha: 0.3)),
                      visualDensity: VisualDensity.compact,
                    ),
                    segments: const [
                      ButtonSegment(value: false, icon: Icon(Icons.edit_outlined, size: 18), label: Text('Écrire'), tooltip: 'Écrire en Markdown (Ctrl+E)'),
                      ButtonSegment(value: true, icon: Icon(Icons.visibility_outlined, size: 18), label: Text('Aperçu'), tooltip: 'Voir le rendu (Ctrl+E)'),
                    ],
                    selected: {_apercu},
                    onSelectionChanged: (s) {
                      if (s.first != _apercu) _basculerApercu();
                    },
                  ),
                  const Spacer(),
                  Text('$mots mot${mots > 1 ? 's' : ''} · ${contenu.length} caractère${contenu.length > 1 ? 's' : ''}',
                      style: TextStyle(color: texte.withValues(alpha: 0.75), fontSize: 12)),
                ],
              ),
              const SizedBox(height: Lulu.sm),
              Container(
                height: 260,
                padding: const EdgeInsets.symmetric(horizontal: Lulu.md, vertical: Lulu.sm),
                decoration: BoxDecoration(
                  color: texte.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(Lulu.rMd),
                  border: Border.all(color: texte.withValues(alpha: 0.2)),
                ),
                child: _apercu
                    ? (contenu.trim().isEmpty
                        ? Center(child: Text('Rien à afficher pour l\'instant.', style: TextStyle(color: texte.withValues(alpha: 0.7), fontStyle: FontStyle.italic)))
                        : SingleChildScrollView(
                            child: MarkdownBlock(
                              data: markdownAvecMentions(contenu),
                              config: configMarkdownPostIt(texte),
                              generator: generateurMentions(couleur: texte),
                            ),
                          ))
                    // H6 : « [[ » ouvre l'autocomplétion des mentions.
                    : AutocompletionMentions(
                        controller: _contenu,
                        focusNode: _focus,
                        exclureId: _id,
                        onChanged: (_) => _planifier(),
                        child: TextField(
                          controller: _contenu,
                          focusNode: _focus,
                          autofocus: true,
                          expands: true,
                          maxLines: null,
                          textAlignVertical: TextAlignVertical.top,
                          style: TextStyle(color: texte),
                          cursorColor: texte,
                          onChanged: (_) => _planifier(),
                          decoration: InputDecoration(
                            hintText: 'Markdown accepté : **gras**, *italique*, # titre, - liste, - [ ] case à cocher, [[ pour mentionner',
                            hintStyle: TextStyle(color: texte.withValues(alpha: 0.6)),
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: Lulu.md),
              Text('Couleur', style: TextStyle(color: texte, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: Lulu.sm),
              Wrap(
                spacing: Lulu.sm,
                runSpacing: Lulu.sm,
                children: [
                  for (var i = 0; i < ThemeLulu.couleursPostIt.length; i++)
                    PastilleCouleur(
                      couleur: couleurDepuisHex(ThemeLulu.couleursPostIt[i]),
                      nom: nomsCouleursPostIt[i],
                      choisie: ThemeLulu.couleursPostIt[i] == _couleur,
                      contour: texte,
                      onTap: () => _changerCouleur(ThemeLulu.couleursPostIt[i]),
                    ),
                  PastilleCouleur(
                    couleur: personnalisee ? fond : null,
                    nom: personnalisee ? 'Couleur personnalisée $_couleur, modifier' : 'Choisir une autre couleur',
                    choisie: personnalisee,
                    contour: texte,
                    icone: Icons.palette_outlined,
                    onTap: () async {
                      final c = await choisirCouleur(context, fond);
                      if (c != null) _changerCouleur(hexDepuisCouleur(c));
                    },
                  ),
                ],
              ),
              const SizedBox(height: Lulu.sm),
              Text('Contraste du texte : ${contraste(texte, fond).toStringAsFixed(1)}:1 (minimum 4,5:1)',
                  style: TextStyle(color: texte.withValues(alpha: 0.85), fontSize: 11)),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.all(Lulu.md),
        actions: [
          TextButton.icon(
            style: styleBouton,
            onPressed: _archiver,
            icon: Icon(widget.postIt['archive'] == true ? Icons.unarchive_outlined : Icons.archive_outlined, size: 18),
            label: Text(widget.postIt['archive'] == true ? 'Désarchiver' : 'Archiver'),
          ),
          TextButton.icon(
            style: styleBouton,
            onPressed: _historique,
            icon: const Icon(Icons.history, size: 18),
            label: const Text('Historique'),
          ),
          if (IntegrationDesktop.captureDisponible)
            Tooltip(
              message: 'Garder la fenêtre LuluBoard au-dessus des autres applications',
              child: TextButton.icon(
                style: styleBouton,
                onPressed: () async {
                  await IntegrationDesktop.basculerPremierPlan(true);
                  if (context.mounted) afficherMessage(context, 'Fenêtre gardée au premier plan.');
                },
                icon: const Icon(Icons.push_pin_outlined, size: 18),
                label: const Text('Garder au premier plan'),
              ),
            ),
          FilledButton(
            onPressed: () async {
              await _enregistrer();
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Terminé'),
          ),
        ],
      ),
    );
  }
}

/// Pastille de couleur accessible : nom lu par les lecteurs d'écran, coche sur la sélection.
class PastilleCouleur extends StatelessWidget {
  const PastilleCouleur({
    super.key,
    required this.couleur,
    required this.nom,
    required this.choisie,
    required this.contour,
    required this.onTap,
    this.icone,
  });

  /// Couleur de remplissage ; `null` = pastille vide (bouton « autre couleur »).
  final Color? couleur;
  final String nom;
  final bool choisie;

  /// Couleur du contour, lisible sur le fond où la pastille est posée.
  final Color contour;
  final VoidCallback onTap;
  final IconData? icone;

  @override
  Widget build(BuildContext context) {
    final marque = couleur != null ? couleurTexte(couleur!) : contour;
    return Semantics(
      button: true,
      selected: choisie,
      inMutuallyExclusiveGroup: true,
      label: nom,
      excludeSemantics: true,
      child: Tooltip(
        message: nom,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: AnimatedContainer(
            duration: Lulu.rapide,
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: couleur,
              shape: BoxShape.circle,
              border: Border.all(color: choisie ? contour : contour.withValues(alpha: 0.3), width: choisie ? 3 : 1),
            ),
            child: choisie
                ? Icon(Icons.check, size: 20, color: marque)
                : (icone != null ? Icon(icone, size: 20, color: marque) : null),
          ),
        ),
      ),
    );
  }
}

/// Sélecteur de couleur libre (teinte, saturation, luminosité).
Future<Color?> choisirCouleur(BuildContext context, Color initiale) {
  var hsl = HSLColor.fromColor(initiale);
  return showDialog<Color>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) {
        final couleur = hsl.toColor();
        final texte = couleurTexte(couleur);
        return AlertDialog(
          title: const Text('Couleur du post-it'),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  height: 72,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: couleur,
                    borderRadius: BorderRadius.circular(Lulu.rMd),
                    border: Border.all(color: Theme.of(c).colorScheme.outline),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Aperçu du texte', style: TextStyle(color: texte, fontSize: 18)),
                      Text('Contraste ${contraste(texte, couleur).toStringAsFixed(1)}:1', style: TextStyle(color: texte, fontSize: 11)),
                    ],
                  ),
                ),
                const SizedBox(height: Lulu.md),
                Text('Teinte', style: Theme.of(c).textTheme.labelMedium),
                Slider(value: hsl.hue, max: 360, label: 'Teinte', onChanged: (v) => setState(() => hsl = hsl.withHue(v))),
                Text('Saturation', style: Theme.of(c).textTheme.labelMedium),
                Slider(value: hsl.saturation, label: 'Saturation', onChanged: (v) => setState(() => hsl = hsl.withSaturation(v))),
                Text('Luminosité', style: Theme.of(c).textTheme.labelMedium),
                Slider(value: hsl.lightness, label: 'Luminosité', onChanged: (v) => setState(() => hsl = hsl.withLightness(v))),
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

/// C3 : historique des versions, restauration d'une ancienne version (après confirmation).
/// Renvoie les données restaurées, pour que l'éditeur ouvert se mette à jour.
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
              return const EtatVide(
                icone: Icons.history,
                titre: 'Aucune version antérieure',
                texte: 'L\'historique se remplit après synchronisation : chaque modification enregistrée y apparaîtra.',
              );
            }
            return ListView.separated(
              itemCount: versions.length,
              separatorBuilder: (_, _) => const Divider(),
              itemBuilder: (context, i) {
                final v = versions[i];
                final d = Map<String, Object?>.from(v['donnees'] as Map);
                final contenu = (d['contenu'] ?? '').toString();
                return ListTile(
                  leading: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: couleurDepuisHex(d['couleurFond'] as String?),
                      shape: BoxShape.circle,
                      border: Border.all(color: Theme.of(context).colorScheme.outline),
                    ),
                  ),
                  title: Text(contenu.isEmpty ? '(vide)' : contenu, maxLines: 3, overflow: TextOverflow.ellipsis),
                  subtitle: Text(dateCourte(v['creeLe'] as String?)),
                  trailing: TextButton(
                    onPressed: () async {
                      final ok = await confirmer(context, 'Restaurer cette version ?',
                          'Le contenu et la couleur actuels du post-it seront remplacés par cette version.',
                          action: 'Restaurer');
                      if (!ok) return;
                      await depot.modifierDonnees(postItId, {'contenu': d['contenu'], 'couleurFond': d['couleurFond']});
                      if (context.mounted) Navigator.pop(context, d);
                    },
                    child: const Text('Restaurer'),
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer'))],
    );
  }
}

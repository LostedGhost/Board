import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../fonctionnalites/commun/actions_element.dart';
import '../noyau/depot.dart';
import '../noyau/noyau.dart';
import '../noyau/session/service_compte.dart';
import '../noyau/stockage/base_locale.dart';
import 'commun.dart';
import 'theme.dart';

/// H5 : glisser-déposer un élément sur une section du menu pour l'y copier (Maj = déplacer).
/// Même règle que H1 : la copie est le comportement par défaut, l'original reste en place.

/// Modules capables de recevoir un élément déposé.
enum DestinationDepot {
  pressePapier(TypeEl.pressePapier, 'Presse-papier'),
  postIt(TypeEl.postIt, 'Post-it'),
  taches(TypeEl.tache, 'Tâches'),
  snippets(TypeEl.snippet, 'Snippets'),
  envois(null, 'Envois');

  const DestinationDepot(this.typeCible, this.libelle);

  /// Type créé par le dépôt (`null` : envoi à un appareil, aucun élément créé).
  final String? typeCible;
  final String libelle;
}

/// Clé de métadonnée locale : l'astuce a été vue (ou un premier dépôt a réussi).
const _metaAstuce = 'astuce_glisser_vue';

/// Libellé de l'action en cours, affiché sous la carte glissée (infobulle qui suit le pointeur).
final _actionSurvolee = ValueNotifier<({String texte, bool possible})?>(null);

bool get _mobile =>
    defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;

IconData iconeType(Enr e) => switch (e['type']) {
      TypeEl.pressePapier => e['typeContenu'] == 'IMAGE'
          ? Icons.image_outlined
          : (e['typeContenu'] == 'LIEN' ? Icons.link : Icons.content_paste),
      TypeEl.postIt => Icons.sticky_note_2_outlined,
      TypeEl.snippet => Icons.code,
      TypeEl.tache || TypeEl.liste => Icons.checklist,
      TypeEl.fichier => Icons.insert_drive_file_outlined,
      _ => Icons.article_outlined,
    };

/// Pourquoi [e] ne peut pas aller vers [d] (`null` : dépôt possible).
String? motifRefus(BuildContext context, Enr e, DestinationDepot d) {
  final type = e['type'] as String?;
  final libelle = TypeEl.libelles[type] ?? 'Élément';
  if (d == DestinationDepot.envois) {
    return context.noyau.compte.etat.mode == ModeSession.actif ? null : 'Envoi réservé aux comptes';
  }
  if (type == d.typeCible) return 'Déjà dans ${d.libelle}';
  if (type == TypeEl.fichier) return 'Un fichier ne peut pas aller dans ${d.libelle}';
  if (type == TypeEl.pressePapier && e['typeContenu'] == 'IMAGE') return 'Une image ne peut pas aller dans ${d.libelle}';
  if (type == TypeEl.liste) return '$libelle : ne se transforme pas';
  return null;
}

String _verbe(DestinationDepot d, {required bool deplacer}) {
  if (d == DestinationDepot.envois) return 'Envoyer à un appareil';
  return '${deplacer ? 'Déplacer' : 'Copier'} vers ${d.libelle}';
}

// ---------------------------------------------------------------------------------------------
// Source : élément glissable.

/// Rend [child] glissable : appui long sur mobile, glisser direct à la souris (desktop/web).
class Glissable extends StatelessWidget {
  const Glissable({super.key, required this.element, required this.child});

  final Enr element;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final retour = _CarteGlissee(element);
    final fantome = Opacity(opacity: 0.4, child: child);
    void fin() => _actionSurvolee.value = null;
    if (_mobile) {
      return LongPressDraggable<Enr>(
        data: element,
        feedback: retour,
        childWhenDragging: fantome,
        hapticFeedbackOnStart: true,
        onDragEnd: (_) => fin(),
        child: child,
      );
    }
    return Draggable<Enr>(
      data: element,
      feedback: retour,
      childWhenDragging: fantome,
      onDragEnd: (_) => fin(),
      child: MouseRegion(cursor: SystemMouseCursors.grab, child: child),
    );
  }
}

/// Retour visuel : carte réduite avec l'icône du type, et l'action prévue juste en dessous.
class _CarteGlissee extends StatelessWidget {
  const _CarteGlissee(this.e);

  final Enr e;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = t.colorScheme;
    final texte = Depot.texteDe(e).trim();
    return Material(
      type: MaterialType.transparency,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Material(
              elevation: 6,
              color: c.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(Lulu.rLg),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Lulu.md - Lulu.xs, vertical: Lulu.sm),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: c.primary.withValues(alpha: 0.12),
                      foregroundColor: c.primary,
                      child: Icon(iconeType(e), size: 16),
                    ),
                    const SizedBox(width: Lulu.sm),
                    Flexible(
                      child: Text(
                        texte.isEmpty ? (TypeEl.libelles[e['type']] ?? 'Élément') : texte,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ValueListenableBuilder(
              valueListenable: _actionSurvolee,
              builder: (context, action, _) {
                if (action == null) return const SizedBox.shrink();
                final fond = action.possible ? c.primary : c.error;
                final texteCouleur = action.possible ? c.onPrimary : c.onError;
                return Padding(
                  padding: const EdgeInsets.only(top: Lulu.xs, left: Lulu.sm),
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: fond, borderRadius: BorderRadius.circular(Lulu.rSm)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Lulu.sm, vertical: Lulu.xs),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(action.possible ? Icons.add : Icons.block, size: 14, color: texteCouleur),
                          const SizedBox(width: Lulu.xs),
                          Text(action.texte, style: t.textTheme.labelMedium?.copyWith(color: texteCouleur)),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Cible : destination de la navigation.

/// Enveloppe l'icône d'une destination de navigation : surbrillance accent au survol compatible,
/// curseur « interdit » au survol incompatible.
class CibleDepot extends StatelessWidget {
  const CibleDepot({super.key, required this.destination, required this.child, required this.onOuvrir});

  final DestinationDepot? destination;
  final Widget child;

  /// Bascule vers la section (action « Ouvrir » de la confirmation).
  final VoidCallback onOuvrir;

  @override
  Widget build(BuildContext context) {
    final d = destination;
    return DragTarget<Enr>(
      onWillAcceptWithDetails: (det) => d != null && motifRefus(context, det.data, d) == null,
      onMove: (det) {
        final refus = d == null ? 'Impossible ici' : motifRefus(context, det.data, d);
        final deplacer = HardwareKeyboard.instance.isShiftPressed;
        _actionSurvolee.value = refus != null
            ? (texte: refus, possible: false)
            : (texte: _verbe(d!, deplacer: deplacer), possible: true);
      },
      onLeave: (_) => _actionSurvolee.value = null,
      onAcceptWithDetails: (det) {
        _actionSurvolee.value = null;
        deposer(context, det.data, d!, deplacer: HardwareKeyboard.instance.isShiftPressed, onOuvrir: onOuvrir);
      },
      builder: (context, candidats, rejetes) {
        final c = Theme.of(context).colorScheme;
        final actif = candidats.isNotEmpty;
        return MouseRegion(
          cursor: rejetes.isNotEmpty ? SystemMouseCursors.forbidden : MouseCursor.defer,
          child: AnimatedContainer(
            duration: Lulu.rapide,
            width: 48,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: actif ? c.primary.withValues(alpha: 0.18) : Colors.transparent,
              border: Border.all(color: actif ? c.primary : Colors.transparent, width: 2),
              borderRadius: BorderRadius.circular(Lulu.rXl),
            ),
            child: IconTheme.merge(
              data: IconThemeData(color: actif ? c.primary : null),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// Exécute le dépôt de [e] sur [d] : copie (H1) ou déplacement annulable, envoi à un appareil.
Future<void> deposer(
  BuildContext context,
  Enr e,
  DestinationDepot d, {
  required bool deplacer,
  required VoidCallback onOuvrir,
}) async {
  final noyau = context.noyau;
  final depot = noyau.depot;
  await marquerAstuceVue(noyau.base);
  if (!context.mounted) return;
  if (d == DestinationDepot.envois) {
    await envoyerAUnAppareil(context, e);
    return;
  }
  final cible = d.typeCible!;
  final id = e['id']! as String;
  String? parent;
  if (cible == TypeEl.postIt) {
    parent = await _tableauParDefaut(depot);
  } else if (cible == TypeEl.tache) {
    parent = await _choisirListe(context, depot);
    if (parent == null) return;
  }
  if (!context.mounted) return;
  final nouveau = await executer(context, () => depot.transformer(id, cible, parentId: parent));
  if (nouveau == null || !context.mounted) return;
  if (!deplacer) {
    afficherMessage(context, 'Copié vers ${d.libelle}.',
        action: SnackBarAction(label: 'Ouvrir', onPressed: onOuvrir));
    return;
  }
  await depot.supprimerAvecAnnulation(id);
  if (!context.mounted) return;
  proposerAnnulation(context, 'Déplacé vers ${d.libelle}.', () async {
    await depot.annulerSuppression(id);
    await depot.supprimer(nouveau);
  });
}

Future<String> _tableauParDefaut(Depot depot) async {
  final tableaux = await depot.base.tous(Entite.tableau);
  if (tableaux.isNotEmpty) return tableaux.first['id']! as String;
  return depot.creerTableau('Mon tableau', 0);
}

Future<String?> _choisirListe(BuildContext context, Depot depot) async {
  final listes = (await depot.base.tous(Entite.element)).where((e) => e['type'] == TypeEl.liste).toList();
  if (listes.isEmpty) return depot.creer(TypeEl.liste, {'titre': 'À faire'});
  if (listes.length == 1) return listes.first['id']! as String;
  if (!context.mounted) return null;
  return showDialog<String>(
    context: context,
    builder: (c) => SimpleDialog(
      title: const Text('Dans quelle liste ?'),
      children: [
        for (final l in listes)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, l['id'] as String),
            child: Text(((l['donnees'] as Map?)?['titre'] ?? 'Sans titre').toString()),
          ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------------------------
// Astuce affichée une seule fois.

final _astuceVue = ValueNotifier<bool?>(null);

Future<void> marquerAstuceVue(BaseLocale base) async {
  if (_astuceVue.value == true) return;
  _astuceVue.value = true;
  await base.ecrireMeta(_metaAstuce, true);
}

/// « Astuce : glissez un élément sur une section du menu pour l'y copier », jusqu'à ce qu'on la ferme
/// (ou qu'un premier dépôt réussisse). L'état est mémorisé localement.
class AstuceGlisser extends StatefulWidget {
  const AstuceGlisser({super.key, this.padding = const EdgeInsets.fromLTRB(Lulu.md, Lulu.sm, Lulu.md, 0)});

  final EdgeInsetsGeometry padding;

  @override
  State<AstuceGlisser> createState() => _AstuceGlisserState();
}

class _AstuceGlisserState extends State<AstuceGlisser> {
  @override
  void initState() {
    super.initState();
    if (_astuceVue.value == null) {
      context.noyau.base.lireMeta<bool>(_metaAstuce).then((v) => _astuceVue.value ??= v ?? false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: _astuceVue,
      builder: (context, vue, _) {
        if (vue != false) return const SizedBox.shrink();
        final t = Theme.of(context);
        final c = t.colorScheme;
        return Padding(
          padding: widget.padding,
          child: Container(
            padding: const EdgeInsets.only(left: Lulu.md - Lulu.xs),
            decoration: BoxDecoration(
              color: c.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(Lulu.rMd),
              border: Border.all(color: c.primary.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.lightbulb_outline, size: 18, color: c.primary),
                const SizedBox(width: Lulu.sm),
                Expanded(
                  child: Text(
                    _mobile
                        ? 'Astuce : maintenez un élément puis glissez-le sur une section du menu pour l\'y copier.'
                        : 'Astuce : glissez un élément sur une section du menu pour l\'y copier (Maj pour le déplacer).',
                    style: t.textTheme.bodySmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Masquer l\'astuce',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => marquerAstuceVue(context.noyau.base),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

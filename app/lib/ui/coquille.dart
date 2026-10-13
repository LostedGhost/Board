import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../fonctionnalites/annonces/bandeau_annonces.dart';
import '../fonctionnalites/compte/ecrans_auth.dart';
import '../fonctionnalites/envois/ecran_envois.dart';
import '../fonctionnalites/fichiers/ecran_fichiers.dart';
import '../fonctionnalites/post_it/ecran_post_it.dart';
import '../fonctionnalites/presse_papier/ecran_presse_papier.dart';
import '../fonctionnalites/rappels/planificateur_rappels.dart';
import '../fonctionnalites/recherche/recherche.dart';
import '../fonctionnalites/reglages/ecran_reglages.dart';
import '../fonctionnalites/snippets/ecran_snippets.dart';
import '../fonctionnalites/taches/ecran_taches.dart';
import '../noyau/noyau.dart';
import '../noyau/session/service_compte.dart';
import '../noyau/synchro/moteur_synchro.dart';
import 'capture_rapide.dart';
import 'commun.dart';
import 'glisser.dart';
import 'theme.dart';

class Section {
  const Section(this.titre, this.icone, this.iconeActive, this.construire, {this.compteRequis = false, this.cible});

  final String titre;
  final IconData icone;
  final IconData iconeActive;
  final Widget Function() construire;
  final bool compteRequis;

  /// H5 : module recevant les éléments glissés sur cette destination (`null` : aucun dépôt).
  final DestinationDepot? cible;
}

final sections = <Section>[
  Section(
    'Presse-papier',
    Icons.content_paste_outlined,
    Icons.content_paste,
    () => const EcranPressePapier(),
    cible: DestinationDepot.pressePapier,
  ),
  Section('Post-it', Icons.sticky_note_2_outlined, Icons.sticky_note_2, () => const EcranPostIt(), cible: DestinationDepot.postIt),
  Section('Tâches', Icons.checklist_outlined, Icons.checklist, () => const EcranTaches(), cible: DestinationDepot.taches),
  Section('Snippets', Icons.code_outlined, Icons.code, () => const EcranSnippets(), cible: DestinationDepot.snippets),
  Section('Fichiers', Icons.folder_outlined, Icons.folder, () => const EcranFichiers(), compteRequis: true),
  Section(
    'Envois',
    Icons.send_to_mobile_outlined,
    Icons.send_to_mobile,
    () => const EcranEnvois(),
    compteRequis: true,
    cible: DestinationDepot.envois,
  ),
  Section('Réglages', Icons.settings_outlined, Icons.settings, () => const EcranReglages()),
];

/// Navigation mobile : 4 onglets au lieu de 7. Les sections proches sont regroupées
/// (bascule en haut de l'écran) et les réglages passent dans la barre du haut.
class GroupeNav {
  const GroupeNav(this.titre, this.icone, this.iconeActive, this.sections);

  final String titre;
  final IconData icone;
  final IconData iconeActive;

  /// Index dans [sections].
  final List<int> sections;
}

const indexReglages = 6;

const groupesMobile = <GroupeNav>[
  GroupeNav('Presse-papier', Icons.content_paste_outlined, Icons.content_paste, [0]),
  GroupeNav('Notes', Icons.sticky_note_2_outlined, Icons.sticky_note_2, [1, 3]),
  GroupeNav('Tâches', Icons.task_alt_outlined, Icons.task_alt, [2]),
  GroupeNav('Partage', Icons.devices_outlined, Icons.devices, [4, 5]),
];

int? groupeDe(int section) {
  for (final (g, groupe) in groupesMobile.indexed) {
    if (groupe.sections.contains(section)) return g;
  }
  return null;
}

/// Navigation principale : raccourcis clavier, recherche globale (G2) et état de synchro (I5).
class Coquille extends StatefulWidget {
  const Coquille({super.key});

  /// Permet aux autres écrans (raccourci global, notifications) de changer de section.
  static final sectionDemandee = ValueNotifier<int?>(null);

  @override
  State<Coquille> createState() => _CoquilleState();
}

class _CoquilleState extends State<Coquille> {
  int _index = 0;

  /// Dernière section ouverte dans chaque groupe mobile (on y revient en touchant l'onglet).
  final _derniereDuGroupe = [for (final g in groupesMobile) g.sections.first];
  StreamSubscription<Map<String, dynamic>>? _evenements;
  PlanificateurRappels? _rappels;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final noyau = context.noyau;
    _evenements ??= noyau.synchro.evenements.stream.listen(_surEvenement);
    _rappels ??= PlanificateurRappels(noyau, context)..demarrer();
    Coquille.sectionDemandee.addListener(_surSectionDemandee);
    CaptureRapide.demandes.addListener(_surCapture);
  }

  void _surCapture() {
    if (mounted) CaptureRapide.ouvrir(context);
  }

  bool get _large => MediaQuery.sizeOf(context).width >= 760;

  /// Ouvre une section ; sur mobile, les réglages s'ouvrent en page à part (hors barre d'onglets).
  void _ouvrir(int i) {
    if (!mounted) return;
    if (i == indexReglages && !_large) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Réglages')),
            body: sections[i].construire(),
          ),
        ),
      );
      return;
    }
    final g = groupeDe(i);
    setState(() {
      _index = i;
      if (g != null) _derniereDuGroupe[g] = i;
    });
  }

  void _surSectionDemandee() {
    final i = Coquille.sectionDemandee.value;
    if (i != null) _ouvrir(i);
    Coquille.sectionDemandee.value = null;
  }

  void _surEvenement(Map<String, dynamic> ev) {
    if (!mounted) return;
    switch (ev['type']) {
      case 'envoi_recu':
        afficherMessage(
          context,
          'Nouvel élément reçu d\'un de vos appareils.',
          action: SnackBarAction(label: 'Voir', onPressed: () => _ouvrir(5)),
        );
      case 'deverrouillage_demande':
        afficherMessage(
          context,
          'Un nouvel appareil demande l\'accès à votre compte.',
          action: SnackBarAction(label: 'Examiner', onPressed: () => _ouvrir(indexReglages)),
        );
      case 'conflit':
        afficherMessage(
          context,
          'Une modification faite hors ligne a été remplacée par une plus récente. '
          'L\'ancienne version reste dans l\'historique du post-it.',
        );
    }
  }

  @override
  void dispose() {
    _evenements?.cancel();
    _rappels?.arreter();
    Coquille.sectionDemandee.removeListener(_surSectionDemandee);
    CaptureRapide.demandes.removeListener(_surCapture);
    super.dispose();
  }

  /// Icône de destination servant aussi de cible de dépôt (H5).
  Widget _icone(int i, {required bool active}) {
    final s = sections[i];
    return CibleDepot(destination: s.cible, onOuvrir: () => _ouvrir(i), child: Icon(active ? s.iconeActive : s.icone));
  }

  /// Bascule entre les sections d'un groupe mobile (ex. Post-it | Snippets).
  PreferredSizeWidget? _bascule(GroupeNav? groupe) {
    if (groupe == null || groupe.sections.length < 2) return null;
    return PreferredSize(
      preferredSize: const Size.fromHeight(52),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Lulu.md, 0, Lulu.md, Lulu.sm + 2),
        child: SizedBox(
          width: double.infinity,
          child: SegmentedButton<int>(
            showSelectedIcon: false,
            segments: [
              for (final i in groupe.sections)
                ButtonSegment(value: i, label: Text(sections[i].titre), icon: Icon(sections[i].icone, size: 18)),
            ],
            selected: {_index},
            onSelectionChanged: (choix) => _ouvrir(choix.first),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final noyau = context.noyau;
    final large = _large;
    // Les réglages ne sont pas un onglet mobile : si l'écran rétrécit, on revient au premier onglet.
    if (!large && _index == indexReglages) _index = 0;
    final section = sections[_index];
    final groupeMobile = large ? null : groupeDe(_index);
    final groupe = groupeMobile == null ? null : groupesMobile[groupeMobile];
    final contenu = ListenableBuilder(
      listenable: noyau.compte,
      builder: (context, _) {
        final etat = noyau.compte.etat;
        if (section.compteRequis && etat.mode != ModeSession.actif) {
          return EtatVide(
            icone: section.iconeActive,
            titre: '${section.titre} : réservé aux comptes',
            texte:
                'Créez un compte gratuit pour envoyer des fichiers et partager entre vos appareils. '
                'Vos données locales seront conservées.',
            action: FilledButton(onPressed: () => ouvrirInscription(context), child: const Text('Créer un compte')),
          );
        }
        return section.construire();
      },
    );

    final scaffold = Scaffold(
      appBar: AppBar(
        title: Text(groupe?.titre ?? section.titre),
        bottom: _bascule(groupe),
        actions: [
          // Sur mobile, chaque écran a son propre bouton « Ajouter » : la capture rapide reste au bureau.
          if (large)
            IconButton(
              tooltip: 'Capture rapide (Ctrl+Alt+N)',
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () => CaptureRapide.ouvrir(context),
            ),
          IconButton(tooltip: 'Rechercher partout (Ctrl+K)', icon: const Icon(Icons.search), onPressed: () => ouvrirRecherche(context)),
          const IndicateurSynchro(),
          if (!large) IconButton(tooltip: 'Réglages', icon: const Icon(Icons.settings_outlined), onPressed: () => _ouvrir(indexReglages)),
          const SizedBox(width: Lulu.xs),
        ],
      ),
      body: Column(
        children: [
          const BandeauVisiteur(),
          const BandeauCleRecuperation(),
          const BandeauAnnonces(),
          Expanded(child: contenu),
        ],
      ),
      bottomNavigationBar: large
          ? null
          : DecoratedBox(
              // Fine séparation plutôt qu'une ombre : la barre reste légère.
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
              ),
              child: NavigationBar(
                selectedIndex: groupeMobile ?? 0,
                onDestinationSelected: (g) => _ouvrir(_derniereDuGroupe[g]),
                destinations: [
                  for (final g in groupesMobile)
                    NavigationDestination(
                      icon: CibleDepot(
                        destination: sections[g.sections.first].cible,
                        onOuvrir: () => _ouvrir(g.sections.first),
                        child: Icon(g.icone),
                      ),
                      selectedIcon: Icon(g.iconeActive),
                      label: g.titre,
                    ),
                ],
              ),
            ),
    );

    final avecRaccourcis = CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () => ouvrirRecherche(context),
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () => ouvrirRecherche(context),
      },
      child: Focus(autofocus: true, child: scaffold),
    );

    if (!large) return avecRaccourcis;
    return Row(
      children: [
        NavigationRail(
          selectedIndex: _index,
          onDestinationSelected: _ouvrir,
          labelType: NavigationRailLabelType.all,
          leading: Padding(
            padding: const EdgeInsets.symmetric(vertical: Lulu.sm + 4),
            child: Semantics(
              label: 'LuluBoard',
              child: ExcludeSemantics(
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(Lulu.rMd),
                      child: Image.asset('assets/logo/logo.png', width: 36, height: 36, filterQuality: FilterQuality.medium),
                    ),
                    const SizedBox(height: Lulu.xs),
                    Text(
                      'Lulu',
                      style: TextStyle(fontFamily: Lulu.policeMarque, fontSize: 18, color: Theme.of(context).colorScheme.primary),
                    ),
                  ],
                ),
              ),
            ),
          ),
          destinations: [
            for (final (i, s) in sections.indexed)
              NavigationRailDestination(icon: _icone(i, active: false), selectedIcon: _icone(i, active: true), label: Text(s.titre)),
          ],
        ),
        const VerticalDivider(width: 1),
        Expanded(child: avecRaccourcis),
      ],
    );
  }
}

/// I5 : état de la synchronisation, toujours visible.
class IndicateurSynchro extends StatelessWidget {
  const IndicateurSynchro({super.key});

  @override
  Widget build(BuildContext context) {
    final noyau = context.noyau;
    return ListenableBuilder(
      listenable: Listenable.merge([noyau.synchro, noyau.compte]),
      builder: (context, _) {
        if (noyau.compte.etat.mode != ModeSession.actif) {
          return const Tooltip(message: 'Mode local : rien ne quitte cet appareil', child: Icon(Icons.phonelink_lock));
        }
        final s = noyau.synchro;
        final (icone, texte) = switch (s.etat) {
          EtatSynchro.enCours => (Icons.sync, 'Synchronisation…'),
          EtatSynchro.aJour => (Icons.cloud_done_outlined, 'Synchronisé'),
          EtatSynchro.horsLigne => (Icons.cloud_off, 'Hors ligne : ${s.enAttente} modification(s) en attente'),
          EtatSynchro.erreur => (Icons.sync_problem, 'Erreur de synchro : ${s.derniereErreur ?? ''}'),
          EtatSynchro.inactif => (Icons.cloud_outlined, 'Synchro inactive'),
        };
        return IconButton(tooltip: '$texte\nCliquer pour synchroniser', icon: Icon(icone), onPressed: s.synchroniser);
      },
    );
  }
}

/// I3 : invitation discrète à créer un compte, jamais bloquante.
class BandeauVisiteur extends StatelessWidget {
  const BandeauVisiteur({super.key});

  @override
  Widget build(BuildContext context) {
    final compte = context.noyau.compte;
    return ListenableBuilder(
      listenable: compte,
      builder: (context, _) {
        if (compte.etat.mode != ModeSession.visiteur) return const SizedBox.shrink();
        if (MediaQuery.sizeOf(context).width < 760) {
          // Mobile : une seule ligne discrète, pour laisser la place au contenu.
          final couleurs = Theme.of(context).colorScheme;
          return Material(
            color: couleurs.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Lulu.md, Lulu.xs, Lulu.sm, Lulu.xs),
              child: Row(children: [
                Icon(Icons.phonelink_lock, size: 18, color: couleurs.onSurfaceVariant),
                const SizedBox(width: Lulu.sm),
                Expanded(
                  child: Text('Mode local (cet appareil)',
                      style: Theme.of(context).textTheme.bodySmall, overflow: TextOverflow.ellipsis),
                ),
                TextButton(onPressed: () => ouvrirInscription(context), child: const Text('Créer un compte')),
              ]),
            ),
          );
        }
        return MaterialBanner(
          leading: const Icon(Icons.info_outline),
          content: const Text(
            'Mode local : vos données restent sur cet appareil. '
            'Créez un compte pour les retrouver partout, chiffrées de bout en bout.',
          ),
          actions: [
            TextButton(onPressed: () => ouvrirConnexion(context), child: const Text('Se connecter')),
            FilledButton.tonal(onPressed: () => ouvrirInscription(context), child: const Text('Créer un compte')),
          ],
        );
      },
    );
  }
}

/// I4 : rappel non bloquant tant que la clé de récupération n'est pas confirmée (comptes Google).
class BandeauCleRecuperation extends StatelessWidget {
  const BandeauCleRecuperation({super.key});

  @override
  Widget build(BuildContext context) {
    final compte = context.noyau.compte;
    return ListenableBuilder(
      listenable: compte,
      builder: (context, _) {
        final e = compte.etat;
        if (e.mode != ModeSession.actif || !e.cleRecuperationAConfirmer) return const SizedBox.shrink();
        return MaterialBanner(
          leading: const Icon(Icons.key),
          content: const Text(
            'Sauvegardez votre clé de récupération : sans elle, vos données sont perdues '
            'si vous oubliez votre mot de passe et perdez vos appareils.',
          ),
          actions: [TextButton(onPressed: () => ouvrirRegenerationCle(context), child: const Text('Obtenir ma clé'))],
        );
      },
    );
  }
}

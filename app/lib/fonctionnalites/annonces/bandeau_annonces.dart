// UC-I30 « Publier une annonce » : bandeau affiché en haut de l'app.
//
// INTÉGRATION (lib/ui/coquille.dart, dans le `body: Column(children: [...])` du Scaffold,
// juste après `const BandeauCleRecuperation(),`) :
//
//     const BandeauAnnonces(),
//
// avec l'import en tête de coquille.dart :
//
//     import '../fonctionnalites/annonces/bandeau_annonces.dart';
//
// Comportement :
// - Source : GET /api/v1/annonces/actives (contrat 2.11, backend apps/conformite, publiée via /admin/).
// - Rien en mode visiteur ni hors ligne ; un échec de la route n'affiche aucune erreur.
// - « Masquer » mémorise l'id localement (noyau.base.ecrireMeta('annonces_masquees', [...])).
// - Rechargement : au démarrage, à la connexion, au retour du réseau, sur l'événement WebSocket
//   `annonce` (prévu au contrat) et toutes les 30 minutes.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../noyau/noyau.dart';
import '../../noyau/session/service_compte.dart';
import '../../noyau/synchro/moteur_synchro.dart';
import '../../ui/theme.dart';
import 'service_annonces.dart';

class BandeauAnnonces extends StatefulWidget {
  const BandeauAnnonces({super.key});

  @override
  State<BandeauAnnonces> createState() => _BandeauAnnoncesState();
}

class _BandeauAnnoncesState extends State<BandeauAnnonces> {
  late final Noyau _noyau;
  late final ServiceAnnonces _service;
  StreamSubscription<Map<String, dynamic>>? _evenements;
  Timer? _minuteur;
  List<Annonce> _annonces = const [];
  bool _connecte = false;
  EtatSynchro? _etatSynchro;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _noyau = context.noyau;
    _service = ServiceAnnonces(_noyau.api, _noyau.base);
    _connecte = _estConnecte;
    _etatSynchro = _noyau.synchro.etat;
    _noyau.compte.addListener(_surCompte);
    _noyau.synchro.addListener(_surSynchro);
    _evenements = _noyau.synchro.evenements.stream.listen((ev) {
      if (ev['type'] == 'annonce') _charger();
    });
    _minuteur = Timer.periodic(const Duration(minutes: 30), (_) => _charger());
    _charger();
  }

  @override
  void dispose() {
    _noyau.compte.removeListener(_surCompte);
    _noyau.synchro.removeListener(_surSynchro);
    _evenements?.cancel();
    _minuteur?.cancel();
    super.dispose();
  }

  bool get _estConnecte => _noyau.compte.etat.connecte;

  bool get _horsLigne => _noyau.synchro.etat == EtatSynchro.horsLigne;

  void _surCompte() {
    final c = _estConnecte;
    if (c == _connecte) return;
    _connecte = c;
    _charger();
  }

  void _surSynchro() {
    final avant = _etatSynchro;
    _etatSynchro = _noyau.synchro.etat;
    if (_etatSynchro == EtatSynchro.horsLigne) {
      if (_annonces.isNotEmpty && mounted) setState(() => _annonces = const []);
    } else if (avant == EtatSynchro.horsLigne) {
      _charger();
    }
  }

  Future<void> _charger() async {
    final generation = ++_generation;
    if (!_estConnecte || _horsLigne || _noyau.compte.etat.mode == ModeSession.visiteur) {
      if (_annonces.isNotEmpty && mounted) setState(() => _annonces = const []);
      return;
    }
    final annonces = await _service.visibles();
    if (!mounted || generation != _generation) return;
    setState(() => _annonces = annonces);
  }

  Future<void> _masquer(Annonce a) async {
    setState(() => _annonces = [for (final x in _annonces) if (x.id != a.id) x]);
    try {
      await _service.masquer(a.id);
    } catch (_) {
      // Masquage local seulement : un échec d'écriture ne doit rien afficher.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_annonces.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final a in _annonces) _Annonce(annonce: a, onMasquer: () => _masquer(a))],
    );
  }
}

class _Annonce extends StatelessWidget {
  const _Annonce({required this.annonce, required this.onMasquer});

  final Annonce annonce;
  final VoidCallback onMasquer;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final avertissement = annonce.estAvertissement;
    final fond = avertissement ? s.errorContainer : s.secondaryContainer;
    final texte = avertissement ? s.onErrorContainer : s.onSecondaryContainer;
    return Semantics(
      liveRegion: true,
      label: avertissement ? 'Avertissement' : 'Annonce',
      child: MaterialBanner(
        backgroundColor: fond,
        padding: const EdgeInsetsDirectional.only(start: Lulu.md, top: Lulu.sm, end: Lulu.sm),
        leading: Icon(avertissement ? Icons.warning_amber_rounded : Icons.campaign_outlined, color: texte),
        content: Text(annonce.messageFr, style: TextStyle(color: texte)),
        actions: [
          TextButton(
            onPressed: onMasquer,
            style: TextButton.styleFrom(foregroundColor: texte),
            child: const Text('Masquer'),
          ),
        ],
      ),
    );
  }
}

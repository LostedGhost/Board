import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'api/client_api.dart';
import 'crypto/chiffrement.dart';
import 'depot.dart';
import 'securite/coffre.dart';
import 'session/service_compte.dart';
import 'stockage/base_locale.dart';
import 'synchro/moteur_synchro.dart';

/// Tous les services de l'app, créés une fois au démarrage.
class Noyau {
  Noyau._(this.crypto, this.api, this.base, this.coffre, this.compte, this.synchro, this.depot, this.reglagesUi);

  final Chiffrement crypto;
  final ClientApi api;
  final BaseLocale base;
  final Coffre coffre;
  final ServiceCompte compte;
  final MoteurSynchro synchro;
  final Depot depot;
  final ReglagesUi reglagesUi;

  static Future<Noyau> demarrer() async {
    final crypto = await Chiffrement.initialiser();
    final api = ClientApi();
    final base = await BaseLocale.ouvrir();
    final coffre = Coffre();
    final compte = ServiceCompte(api, crypto, coffre, base);
    final synchro = MoteurSynchro(api, crypto, base, compte);
    final depot = Depot(base, synchro);
    final reglagesUi = ReglagesUi(base);
    await reglagesUi.charger();
    await compte.demarrer();
    await depot.finaliserSuppressionsInterrompues();
    return Noyau._(crypto, api, base, coffre, compte, synchro, depot, reglagesUi);
  }

  bool get estDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  /// Description de cet appareil, envoyée au serveur à l'inscription ou à la connexion.
  ({String nom, String type, String plateforme}) get descriptionAppareil {
    if (kIsWeb) return (nom: 'Navigateur', type: 'WEB', plateforme: 'Web');
    final p = switch (defaultTargetPlatform) {
      TargetPlatform.windows => 'Windows',
      TargetPlatform.macOS => 'macOS',
      TargetPlatform.linux => 'Linux',
      TargetPlatform.android => 'Android',
      TargetPlatform.iOS => 'iOS',
      _ => 'Inconnu',
    };
    final mobile = defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;
    return (nom: mobile ? 'Téléphone $p' : 'Ordinateur $p', type: mobile ? 'MOBILE' : 'DESKTOP', plateforme: p);
  }
}

class PorteurNoyau extends InheritedWidget {
  const PorteurNoyau({super.key, required this.noyau, required super.child});

  final Noyau noyau;

  static Noyau of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<PorteurNoyau>()!.noyau;

  @override
  bool updateShouldNotify(PorteurNoyau oldWidget) => oldWidget.noyau != noyau;
}

extension NoyauContexte on BuildContext {
  Noyau get noyau => PorteurNoyau.of(this);
}


/// Réglages d'interface propres à l'appareil (thème) ; mémorisés localement.
class ReglagesUi extends ChangeNotifier {
  ReglagesUi(this.base);

  final BaseLocale base;
  ThemeMode mode = ThemeMode.system;

  Future<void> charger() async {
    final v = await base.lireMeta<String>('theme');
    mode = ThemeMode.values.firstWhere((m) => m.name == v, orElse: () => ThemeMode.system);
  }

  Future<void> changerTheme(ThemeMode m) async {
    mode = m;
    notifyListeners();
    await base.ecrireMeta('theme', m.name);
  }
}

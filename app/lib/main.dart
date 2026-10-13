import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'fonctionnalites/compte/ecran_appareil_en_attente.dart';
import 'noyau/noyau.dart';
import 'noyau/session/service_compte.dart';
import 'plateformes/desktop.dart';
import 'ui/coquille.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    for (final (police, fichier) in [('Rubik', 'OFL-Rubik.txt'), ('Itim', 'OFL-Itim.txt')]) {
      yield LicenseEntryWithLineBreaks([police], await rootBundle.loadString('assets/fonts/$fichier'));
    }
  });
  final noyau = await Noyau.demarrer();
  if (noyau.estDesktop) await IntegrationDesktop.initialiser(noyau);
  runApp(PorteurNoyau(noyau: noyau, child: const LuluBoard()));
}

class LuluBoard extends StatelessWidget {
  const LuluBoard({super.key});

  @override
  Widget build(BuildContext context) {
    final noyau = context.noyau;
    return ListenableBuilder(
      listenable: noyau.reglagesUi,
      builder: (context, _) => MaterialApp(
        title: 'LuluBoard',
        debugShowCheckedModeBanner: false,
        theme: ThemeLulu.clair(),
        darkTheme: ThemeLulu.sombre(),
        themeMode: noyau.reglagesUi.mode,
        locale: const Locale('fr'),
        supportedLocales: const [Locale('fr'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: ListenableBuilder(
          listenable: noyau.compte,
          builder: (context, _) => switch (noyau.compte.etat.mode) {
            ModeSession.chargement => const Scaffold(body: Center(child: CircularProgressIndicator())),
            ModeSession.enAttente => const EcranAppareilEnAttente(),
            _ => const Coquille(),
          },
        ),
      ),
    );
  }
}

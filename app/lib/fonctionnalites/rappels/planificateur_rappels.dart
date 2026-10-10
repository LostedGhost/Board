import 'dart:async';

import 'package:flutter/material.dart';

import '../../noyau/depot.dart';
import '../../noyau/noyau.dart';
import '../../noyau/session/service_compte.dart';
import '../../noyau/stockage/base_locale.dart';
import '../../plateformes/desktop.dart';
import '../../ui/commun.dart';

/// Déclenchement local des rappels tant que l'app tourne (desktop : en zone de notification).
/// Avec un compte, le serveur envoie aussi un push (FCM) ; en mode visiteur, seul ce planificateur agit.
/// Pour une occurrence récurrente, le serveur calcule la suivante ; hors compte, on la calcule ici.
class PlanificateurRappels {
  PlanificateurRappels(this.noyau, this.context);

  final Noyau noyau;
  final BuildContext context;
  Timer? _minuterie;
  final _dejaNotifies = <String>{};

  void demarrer() {
    _minuterie = Timer.periodic(const Duration(seconds: 20), (_) => _verifier());
    _verifier();
  }

  void arreter() => _minuterie?.cancel();

  Future<void> _verifier() async {
    final maintenant = DateTime.now().toUtc();
    final rappels = await noyau.base.tous(Entite.rappel);
    for (final r in rappels) {
      if (r['actif'] != true) continue;
      final echeance = DateTime.tryParse(r['prochaineEcheance'] as String? ?? '');
      if (echeance == null || echeance.isAfter(maintenant)) continue;
      final cle = '${r['id']}@${r['prochaineEcheance']}';
      if (_dejaNotifies.contains(cle)) continue;
      _dejaNotifies.add(cle);
      // Une échéance manquée depuis plus de 12 h n'est pas notifiée (app restée fermée).
      if (maintenant.difference(echeance) < const Duration(hours: 12)) {
        final element = await noyau.depot.element(r['elementId']! as String);
        final texte = element == null ? 'Rappel' : Depot.texteDe(element).split('\n').first;
        await IntegrationDesktop.notifier('Rappel LuluBoard', texte.isEmpty ? 'Vous avez un rappel' : texte);
        if (context.mounted) afficherMessage(context, '⏰ $texte');
      }
      if (noyau.compte.etat.mode != ModeSession.actif) await _avancerLocalement(r, maintenant);
    }
  }

  Future<void> _avancerLocalement(Map<String, Object?> r, DateTime maintenant) async {
    var prochaine = DateTime.parse(r['prochaineEcheance']! as String).toLocal();
    final rec = r['recurrence'] as String?;
    if (rec == null) {
      await noyau.depot.mettreAJourRappel({...r, 'actif': false});
      return;
    }
    final jours = ((r['joursSemaine'] as List?) ?? []).cast<String>();
    const noms = ['LUNDI', 'MARDI', 'MERCREDI', 'JEUDI', 'VENDREDI', 'SAMEDI', 'DIMANCHE'];
    for (var i = 0; i < 1000 && !prochaine.toUtc().isAfter(maintenant); i++) {
      prochaine = switch (rec) {
        'QUOTIDIENNE' => DateTime(prochaine.year, prochaine.month, prochaine.day + 1, prochaine.hour, prochaine.minute),
        'HEBDOMADAIRE' => () {
            for (var e = 1; e <= 7; e++) {
              final c = DateTime(prochaine.year, prochaine.month, prochaine.day + e, prochaine.hour, prochaine.minute);
              if (jours.isEmpty ? e == 7 : jours.contains(noms[c.weekday - 1])) return c;
            }
            return prochaine.add(const Duration(days: 7));
          }(),
        'MENSUELLE' => DateTime(prochaine.year, prochaine.month + 1, prochaine.day, prochaine.hour, prochaine.minute),
        _ => DateTime(prochaine.year + 1, prochaine.month, prochaine.day, prochaine.hour, prochaine.minute),
      };
    }
    await noyau.depot.mettreAJourRappel({...r, 'prochaineEcheance': prochaine.toUtc().toIso8601String()});
  }
}

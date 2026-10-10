import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../noyau/api/client_api.dart';

void afficherMessage(BuildContext context, String message, {SnackBarAction? action}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), action: action));
}

/// Message d'erreur clair et actionnable à partir d'une erreur de l'API.
String messageErreur(Object e) {
  if (e is ErreurApi) {
    return switch (e.code) {
      'hors_ligne' => 'Impossible de joindre le serveur. Vérifiez votre connexion, puis réessayez.',
      'identifiants_incorrects' => 'E-mail ou mot de passe incorrect.',
      'connexion_bloquee' => 'Trop de tentatives. Réessayez dans 15 minutes.',
      'email_deja_utilise' => 'Cette adresse est déjà utilisée. Connectez-vous plutôt.',
      'limite_appareils' => 'Vous avez déjà 3 appareils. Révoquez-en un depuis un appareil connecté (Réglages › Appareils).',
      'code_expire' => 'Ce code a expiré. Demandez-en un nouveau.',
      'trop_de_requetes' => 'Trop de demandes. Patientez un peu avant de réessayer.',
      'compte_suspendu' => 'Ce compte est suspendu. Consultez l\'e-mail reçu pour contester.',
      'mise_a_jour_requise' => 'Mettez l\'application à jour pour continuer.',
      'fichier_trop_volumineux' => 'Fichier trop volumineux : 100 Mo maximum.',
      'validation' => e.details?['essaisRestants'] != null
          ? '${e.message} Essais restants : ${e.details!['essaisRestants']}.'
          : e.message,
      _ => e.message,
    };
  }
  return 'Une erreur inattendue est survenue.';
}

/// Exécute une action avec indicateur d'attente et affichage de l'erreur éventuelle.
Future<T?> executer<T>(BuildContext context, Future<T> Function() action, {String? succes}) async {
  try {
    final r = await action();
    if (succes != null && context.mounted) afficherMessage(context, succes);
    return r;
  } catch (e) {
    if (context.mounted) afficherMessage(context, messageErreur(e));
    return null;
  }
}

/// I2 : aucun écran vide sans explication ; chaque état vide propose une action.
class EtatVide extends StatelessWidget {
  const EtatVide({super.key, required this.icone, required this.titre, required this.texte, this.action});

  final IconData icone;
  final String titre;
  final String texte;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icone, size: 56, color: t.colorScheme.primary),
              const SizedBox(height: 16),
              Text(titre, style: t.textTheme.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(texte, style: t.textTheme.bodyMedium, textAlign: TextAlign.center),
              if (action != null) ...[const SizedBox(height: 20), action!],
            ],
          ),
        ),
      ),
    );
  }
}

Future<bool> confirmer(BuildContext context, String titre, String texte, {String action = 'Supprimer'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(titre),
      content: Text(texte),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(action)),
      ],
    ),
  );
  return r ?? false;
}

Future<String?> demanderTexte(BuildContext context, String titre, {String initial = '', String libelle = 'Nom'}) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(titre),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: InputDecoration(labelText: libelle),
        onSubmitted: (v) => Navigator.pop(c, v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('Valider')),
      ],
    ),
  );
}

String dateCourte(String? iso) {
  if (iso == null) return '';
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return '';
  final maintenant = DateTime.now();
  if (d.year == maintenant.year && d.month == maintenant.month && d.day == maintenant.day) {
    return DateFormat.Hm('fr').format(d);
  }
  return DateFormat('d MMM HH:mm', 'fr').format(d);
}

/// Bandeau « Annuler » de 10 secondes après une suppression (H10).
void proposerAnnulation(BuildContext context, String message, Future<void> Function() annuler) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 10),
      action: SnackBarAction(label: 'Annuler', onPressed: annuler),
    ));
}

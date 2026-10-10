import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../noyau/config.dart';
import '../../noyau/crypto/base64url.dart';
import '../../noyau/depot.dart';
import '../../noyau/noyau.dart';
import '../../noyau/session/service_compte.dart';
import '../../noyau/stockage/base_locale.dart';
import '../../ui/commun.dart';
import '../rappels/dialogue_rappel.dart';

/// Types partageables par lien public (H4).
const _partageables = {TypeEl.postIt, TypeEl.snippet, TypeEl.liste, TypeEl.fichier};

/// Menu commun à tous les éléments : passerelles H1-H11.
class MenuElement extends StatelessWidget {
  const MenuElement({super.key, required this.element, this.extra = const []});

  final Enr element;
  final List<PopupMenuEntry<String>> extra;

  @override
  Widget build(BuildContext context) {
    final type = element['type']! as String;
    final actif = context.noyau.compte.etat.mode == ModeSession.actif;
    return PopupMenuButton<String>(
      tooltip: 'Actions',
      onSelected: (a) => executerAction(context, element, a),
      itemBuilder: (_) => [
        ...extra,
        const PopupMenuItem(value: 'copier', child: ListTile(leading: Icon(Icons.copy), title: Text('Copier le texte'))),
        if (type != TypeEl.fichier && type != TypeEl.liste)
          const PopupMenuItem(value: 'transformer', child: ListTile(leading: Icon(Icons.transform), title: Text('Transformer en…'))),
        const PopupMenuItem(value: 'rappel', child: ListTile(leading: Icon(Icons.alarm_add), title: Text('Ajouter un rappel'))),
        PopupMenuItem(
          value: 'acces',
          child: ListTile(
            leading: Icon(element['epingleAccesRapide'] == true ? Icons.star : Icons.star_border),
            title: Text(element['epingleAccesRapide'] == true ? 'Retirer de l\'accès rapide' : 'Épingler en accès rapide'),
          ),
        ),
        if (actif) const PopupMenuItem(value: 'envoyer', child: ListTile(leading: Icon(Icons.send_to_mobile), title: Text('Envoyer à un appareil'))),
        if (actif && _partageables.contains(type))
          const PopupMenuItem(value: 'partager', child: ListTile(leading: Icon(Icons.link), title: Text('Partager par lien'))),
        if (type != TypeEl.fichier)
          const PopupMenuItem(value: 'dupliquer', child: ListTile(leading: Icon(Icons.control_point_duplicate), title: Text('Dupliquer'))),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'supprimer', child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Supprimer'))),
      ],
    );
  }
}

Future<void> executerAction(BuildContext context, Enr element, String action) async {
  final noyau = context.noyau;
  final depot = noyau.depot;
  final id = element['id']! as String;
  switch (action) {
    case 'copier':
      await Clipboard.setData(ClipboardData(text: Depot.texteDe(element)));
      if (context.mounted) afficherMessage(context, 'Copié.');
    case 'transformer':
      final cible = await _choisirType(context, element['type']! as String);
      if (cible == null || !context.mounted) return;
      String? parent;
      if (cible == TypeEl.tache) {
        parent = await _choisirListe(context);
        if (parent == null) return;
      } else if (cible == TypeEl.postIt) {
        parent = await _tableauParDefaut(context);
      }
      await depot.transformer(id, cible, parentId: parent);
      if (context.mounted) afficherMessage(context, '${TypeEl.libelles[cible]} créé (l\'original est conservé).');
    case 'rappel':
      await ouvrirDialogueRappel(context, id);
    case 'acces':
      await depot.basculerAccesRapide(id);
    case 'dupliquer':
      await depot.dupliquer(id);
      if (context.mounted) afficherMessage(context, 'Copie créée.');
    case 'envoyer':
      await envoyerAUnAppareil(context, element);
    case 'partager':
      await partagerParLien(context, element);
    case 'supprimer':
      await depot.supprimerAvecAnnulation(id);
      if (context.mounted) {
        proposerAnnulation(context, '${TypeEl.libelles[element['type']] ?? 'Élément'} supprimé.', () => depot.annulerSuppression(id));
      }
  }
}

Future<String?> _choisirType(BuildContext context, String actuel) => showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Transformer en'),
        children: [
          for (final t in [TypeEl.postIt, TypeEl.snippet, TypeEl.tache, TypeEl.pressePapier])
            if (t != actuel)
              SimpleDialogOption(onPressed: () => Navigator.pop(c, t), child: Text(TypeEl.libelles[t]!)),
        ],
      ),
    );

Future<String?> _choisirListe(BuildContext context) async {
  final depot = context.noyau.depot;
  final listes = await depot.base.tous(Entite.element, filtre: null).then(
        (l) => l.where((e) => e['type'] == TypeEl.liste).toList(),
      );
  if (!context.mounted) return null;
  if (listes.isEmpty) {
    return depot.creer(TypeEl.liste, {'titre': 'À faire'});
  }
  if (listes.length == 1) return listes.first['id']! as String;
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

Future<String> _tableauParDefaut(BuildContext context) async {
  final depot = context.noyau.depot;
  final tableaux = await depot.base.tous(Entite.tableau);
  if (tableaux.isNotEmpty) return tableaux.first['id']! as String;
  return depot.creerTableau('Mon tableau', 0);
}

/// D1 / H3 : envoi chiffré (clé maître, données associées « envoi:<id> »).
Future<void> envoyerAUnAppareil(BuildContext context, Enr element) async {
  final noyau = context.noyau;
  final appareils = await executer(context, () async => (await noyau.api.get('/appareils') as List).cast<Map<String, dynamic>>());
  if (appareils == null || !context.mounted) return;
  final autres = appareils.where((a) => a['courant'] != true && a['statut'] == 'ACTIF').toList();
  if (autres.isEmpty) {
    afficherMessage(context, 'Aucun autre appareil déverrouillé. Connectez-vous d\'abord sur un autre appareil.');
    return;
  }
  final cible = await showDialog<Object>(
    context: context,
    builder: (c) => SimpleDialog(
      title: const Text('Envoyer à'),
      children: [
        SimpleDialogOption(onPressed: () => Navigator.pop(c, 'tous'), child: const Text('Tous mes autres appareils')),
        for (final a in autres)
          SimpleDialogOption(onPressed: () => Navigator.pop(c, a), child: Text('${a['nom']} (${a['plateforme']})')),
      ],
    ),
  );
  if (cible == null || !context.mounted) return;
  final envoiId = noyau.depot.nouvelId();
  final contenu = noyau.crypto.aead(
    noyau.compte.cleMaitre!,
    utf8.encode(jsonEncode({'type': element['type'], 'typeContenu': element['typeContenu'], 'donnees': element['donnees']})),
    'envoi:$envoiId',
  );
  await executer(
    context,
    () => noyau.api.post('/envois', {
      'id': envoiId,
      'appareilCibleId': cible is Map ? cible['id'] : null,
      'contenuChiffre': encoderB64(contenu),
    }),
    succes: 'Envoyé.',
  );
}

/// E3 / H4 : lien public en direct. Sans mot de passe, la clé est dans le fragment (#) de l'URL.
Future<void> partagerParLien(BuildContext context, Enr element) async {
  final noyau = context.noyau;
  if (element['version'] == null || element['sale'] == true) {
    await noyau.synchro.synchroniser(); // l'élément doit exister côté serveur
  }
  if (!context.mounted) return;
  final options = await showDialog<({String duree, String? motDePasse})>(context: context, builder: (_) => const _DialogueLien());
  if (options == null || !context.mounted) return;
  final id = element['id']! as String;
  final frais = await noyau.depot.element(id);
  final cle = frais == null ? null : await noyau.synchro.cleDe(frais);
  if (cle == null) {
    if (context.mounted) afficherMessage(context, 'Synchronisez d\'abord cet élément, puis réessayez.');
    return;
  }
  final corps = <String, Object?>{'elementId': id, 'duree': options.duree, 'protegeParMotDePasse': options.motDePasse != null};
  if (options.motDePasse != null) {
    final sel = noyau.crypto.aleatoire(16);
    final d = noyau.crypto.deriverLien(options.motDePasse!, sel);
    corps.addAll({
      'selDerivation': encoderB64(sel),
      'cleElementEnveloppee': encoderB64(noyau.crypto.aead(d.cleLien, cle, 'lien:$id')),
      'verificateurMotDePasse': encoderB64(d.verificateur),
    });
  }
  if (!context.mounted) return;
  final r = await executer(context, () async => await noyau.api.post('/liens', corps) as Map<String, dynamic>);
  if (r == null || !context.mounted) return;
  final url = Config.lienPublic(r['jeton'] as String, fragment: options.motDePasse == null ? encoderB64(cle) : null);
  final liens = Map<String, Object?>.from(await noyau.base.lireMeta<Map<String, Object?>>('liens') ?? {});
  liens[(r['lien'] as Map)['id'] as String] = url;
  await noyau.base.ecrireMeta('liens', liens);
  await Clipboard.setData(ClipboardData(text: url));
  if (context.mounted) {
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Lien créé et copié'),
        content: SelectableText(url),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
      ),
    );
  }
}

class _DialogueLien extends StatefulWidget {
  const _DialogueLien();

  @override
  State<_DialogueLien> createState() => _DialogueLienState();
}

class _DialogueLienState extends State<_DialogueLien> {
  String _duree = 'J7';
  bool _protege = false;
  final _mdp = TextEditingController();

  static const _durees = {'MIN30': '30 minutes', 'H1': '1 heure', 'H24': '24 heures', 'J7': '7 jours', 'J30': '30 jours', 'J90': '90 jours', 'INFINIE': 'Sans limite'};

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Partager par lien'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Toute personne ayant le lien verra la version actuelle de l\'élément, en lecture seule.'),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _duree,
              decoration: const InputDecoration(labelText: 'Durée de validité'),
              items: [for (final e in _durees.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() => _duree = v!),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _protege,
              onChanged: (v) => setState(() => _protege = v),
              title: const Text('Protéger par un mot de passe'),
            ),
            if (_protege) TextField(controller: _mdp, obscureText: true, decoration: const InputDecoration(labelText: 'Mot de passe du lien')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              if (_protege && _mdp.text.length < 6) {
                afficherMessage(context, 'Mot de passe du lien : 6 caractères minimum.');
                return;
              }
              Navigator.pop(context, (duree: _duree, motDePasse: _protege ? _mdp.text : null));
            },
            child: const Text('Créer le lien'),
          ),
        ],
      );
}

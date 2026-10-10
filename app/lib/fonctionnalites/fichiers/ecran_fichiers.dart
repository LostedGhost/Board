import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../noyau/crypto/base64url.dart';
import '../../noyau/depot.dart';
import '../../noyau/noyau.dart';
import '../../noyau/stockage/base_locale.dart';
import '../../ui/commun.dart';
import '../commun/actions_element.dart';

const _tailleMax = 100 * 1024 * 1024; // E1

/// E1-E2 : fichiers chiffrés sur l'appareil avant l'envoi ; LuluBoard ne les ouvre jamais.
class EcranFichiers extends StatefulWidget {
  const EcranFichiers({super.key});

  @override
  State<EcranFichiers> createState() => _EcranFichiersState();
}

class _EcranFichiersState extends State<EcranFichiers> {
  final _statuts = <String, String>{};
  final _enCours = <String, String>{}; // id → « Chiffrement… », « Envoi… »

  Future<void> _televerser() async {
    final choisis = await FilePicker.pickFiles(dialogTitle: 'Choisir un fichier');
    if (choisis.isEmpty || !mounted) return;
    final noyau = context.noyau;
    for (final f in choisis) {
      final taille = await f.length() ?? 0;
      if (taille > _tailleMax) {
        if (mounted) afficherMessage(context, '« ${f.name} » dépasse 100 Mo.');
        continue;
      }
      final id = noyau.depot.nouvelId();
      setState(() => _enCours[id] = 'Chiffrement de ${f.name}…');
      try {
        final clair = await f.readAsBytes();
        final cle = noyau.crypto.aleatoire(32);
        final chiffre = await noyau.crypto.chiffrerFichier(cle, clair);
        final donnees = {'nom': f.name, 'typeMime': _mime(f.name), 'taille': clair.length};
        setState(() => _enCours[id] = 'Envoi de ${f.name}…');
        await noyau.api.televerser({
          'id': id,
          'modifieLe': DateTime.now().toUtc().toIso8601String(),
          'tailleOctets': chiffre.length,
          'cleElementEnveloppee': encoderB64(noyau.crypto.envelopperCleElement(noyau.compte.cleMaitre!, id, cle)),
          'contenuChiffre': encoderB64(noyau.crypto.aeadJson(cle, donnees, 'el:$id')),
        }, chiffre);
        await noyau.base.enregistrerDistant(Entite.element, {
          'id': id,
          'type': TypeEl.fichier,
          'modifieLe': DateTime.now().toUtc().toIso8601String(),
          'creeLe': DateTime.now().toUtc().toIso8601String(),
          'cle': encoderB64(cle),
          'donnees': donnees,
          'version': 0,
        });
        _statuts[id] = 'EN_FILE';
        noyau.synchro.signalerModification();
      } catch (e) {
        if (mounted) afficherMessage(context, messageErreur(e));
      } finally {
        if (mounted) setState(() => _enCours.remove(id));
      }
    }
  }

  Future<void> _telecharger(Enr e) async {
    final noyau = context.noyau;
    final id = e['id']! as String;
    final d = (e['donnees'] as Map?) ?? {};
    setState(() => _enCours[id] = 'Téléchargement…');
    try {
      final acces = await noyau.api.get('/fichiers/$id/acces') as Map<String, dynamic>;
      final chiffre = await noyau.api.telecharger(acces['url'] as String);
      final cle = decoderB64(e['cle']! as String);
      final clair = await noyau.crypto.dechiffrerFichier(cle, chiffre);
      await FilePicker.saveFile(fileName: (d['nom'] ?? 'fichier').toString(), bytes: Uint8List.fromList(clair), dialogTitle: 'Enregistrer sous');
    } catch (err) {
      if (mounted) afficherMessage(context, messageErreur(err));
    } finally {
      if (mounted) setState(() => _enCours.remove(id));
    }
  }

  Future<void> _rafraichirStatut(String id) async {
    try {
      final f = await context.noyau.api.get('/fichiers/$id') as Map<String, dynamic>;
      if (mounted) setState(() => _statuts[id] = f['statut'] as String);
    } catch (_) {}
  }

  static String _mime(String nom) {
    final ext = nom.contains('.') ? nom.split('.').last.toLowerCase() : '';
    return const {
          'pdf': 'application/pdf',
          'png': 'image/png',
          'jpg': 'image/jpeg',
          'jpeg': 'image/jpeg',
          'txt': 'text/plain',
          'zip': 'application/zip',
          'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
          'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          'mp4': 'video/mp4',
          'mp3': 'audio/mpeg',
        }[ext] ??
        'application/octet-stream';
  }

  static String _taille(num octets) {
    if (octets < 1024) return '$octets o';
    if (octets < 1024 * 1024) return '${(octets / 1024).toStringAsFixed(1)} Ko';
    return '${(octets / 1024 / 1024).toStringAsFixed(1)} Mo';
  }

  @override
  Widget build(BuildContext context) {
    final depot = context.noyau.depot;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(onPressed: _televerser, icon: const Icon(Icons.upload_file), label: const Text('Envoyer un fichier')),
      body: StreamBuilder<List<Enr>>(
        stream: depot.elements(TypeEl.fichier),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final fichiers = snap.data!..sort((a, b) => (b['modifieLe'] as String? ?? '').compareTo(a['modifieLe'] as String? ?? ''));
          if (fichiers.isEmpty && _enCours.isEmpty) {
            return EtatVide(
              icone: Icons.folder,
              titre: 'Aucun fichier',
              texte: 'Déposez des fichiers jusqu\'à 100 Mo : ils sont chiffrés sur cet appareil avant l\'envoi, '
                  'et téléchargeables depuis tous vos appareils.',
              action: FilledButton.icon(onPressed: _televerser, icon: const Icon(Icons.upload_file), label: const Text('Envoyer un fichier')),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
            children: [
              for (final etape in _enCours.entries.where((e) => !fichiers.any((f) => f['id'] == e.key)))
                Card(child: ListTile(leading: const CircularProgressIndicator(), title: Text(etape.value))),
              for (final f in fichiers) _ligne(f),
            ],
          );
        },
      ),
    );
  }

  Widget _ligne(Enr f) {
    final id = f['id']! as String;
    final d = (f['donnees'] as Map?) ?? {};
    final statut = _statuts[id];
    if (statut == null) {
      _statuts[id] = '…';
      _rafraichirStatut(id);
    }
    final pret = statut == 'PRET';
    return Card(
      child: ListTile(
        leading: const Icon(Icons.insert_drive_file_outlined),
        title: Text((d['nom'] ?? 'Fichier').toString()),
        subtitle: Text([
          _taille(d['taille'] as num? ?? 0),
          dateCourte(f['modifieLe'] as String?),
          if (_enCours[id] != null) _enCours[id]! else if (!pret && statut != '…') 'Transfert : ${statut?.toLowerCase().replaceAll('_', ' ')}',
        ].join(' · ')),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (statut == 'ECHEC')
              IconButton(
                tooltip: 'Réessayer le transfert',
                icon: const Icon(Icons.refresh),
                onPressed: () async {
                  await executer(context, () => context.noyau.api.post('/fichiers/$id/reessayer'));
                  _rafraichirStatut(id);
                },
              )
            else if (!pret)
              IconButton(tooltip: 'Actualiser', icon: const Icon(Icons.sync), onPressed: () => _rafraichirStatut(id)),
            IconButton(
              tooltip: 'Télécharger et déchiffrer',
              icon: const Icon(Icons.download),
              onPressed: pret && _enCours[id] == null ? () => _telecharger(f) : null,
            ),
            MenuElement(element: f),
          ],
        ),
      ),
    );
  }
}

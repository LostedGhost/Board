import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../noyau/crypto/base64url.dart';
import '../../noyau/depot.dart';
import '../../noyau/noyau.dart';
import '../../ui/commun.dart';

/// D1 : éléments reçus de mes autres appareils.
class EcranEnvois extends StatefulWidget {
  const EcranEnvois({super.key});

  @override
  State<EcranEnvois> createState() => _EcranEnvoisState();
}

class _EcranEnvoisState extends State<EcranEnvois> {
  List<Map<String, dynamic>>? _recus;
  StreamSubscription<Map<String, dynamic>>? _abonnement;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _abonnement ??= context.noyau.synchro.evenements.stream.where((e) => e['type'] == 'envoi_recu').listen((_) => _charger());
    if (_recus == null) _charger();
  }

  @override
  void dispose() {
    _abonnement?.cancel();
    super.dispose();
  }

  Future<void> _charger() async {
    final noyau = context.noyau;
    try {
      final liste = (await noyau.api.get('/envois/recus') as List).cast<Map<String, dynamic>>();
      final dechiffres = <Map<String, dynamic>>[];
      for (final env in liste) {
        Map<String, dynamic>? contenu;
        if (env['contenuChiffre'] != null) {
          try {
            contenu = jsonDecode(utf8.decode(noyau.crypto.ouvrir(noyau.compte.cleMaitre!, decoderB64(env['contenuChiffre'] as String), 'envoi:${env['id']}')))
                as Map<String, dynamic>;
          } catch (_) {}
        }
        dechiffres.add({...env, 'clair': contenu});
      }
      if (mounted) setState(() => _recus = dechiffres);
    } catch (e) {
      if (mounted) {
        setState(() => _recus = []);
        afficherMessage(context, messageErreur(e));
      }
    }
  }

  Future<void> _recuperer(Map<String, dynamic> env, {required bool garder}) async {
    final noyau = context.noyau;
    final clair = env['clair'] as Map<String, dynamic>?;
    if (garder && clair != null) {
      final type = clair['type'] as String? ?? TypeEl.pressePapier;
      final donnees = Map<String, Object?>.from(clair['donnees'] as Map? ?? {});
      if (type == TypeEl.pressePapier) {
        await noyau.depot.ajouterPressePapier((donnees['texte'] ?? '').toString(), typeContenu: clair['typeContenu'] as String? ?? 'TEXTE');
      } else if (type != TypeEl.fichier && type != TypeEl.tache && type != TypeEl.liste) {
        await noyau.depot.creer(type, donnees);
      } else {
        await noyau.depot.ajouterPressePapier(Depot.texteDe({'type': type, 'donnees': donnees}));
      }
    }
    if (!mounted) return;
    await executer(context, () => noyau.api.post('/envois/${env['id']}/recupere'));
    _charger();
  }

  @override
  Widget build(BuildContext context) {
    if (_recus == null) return const Center(child: CircularProgressIndicator());
    if (_recus!.isEmpty) {
      return EtatVide(
        icone: Icons.send_to_mobile,
        titre: 'Rien de reçu',
        texte: 'Depuis un autre appareil, ouvrez le menu d\'un élément puis « Envoyer à un appareil ». '
            'Les envois non récupérés sont conservés 7 jours.',
        action: OutlinedButton(onPressed: _charger, child: const Text('Actualiser')),
      );
    }
    return RefreshIndicator(
      onRefresh: _charger,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          for (final env in _recus!)
            Card(
              child: ListTile(
                leading: const Icon(Icons.inbox),
                title: Text(env['clair'] == null
                    ? 'Contenu illisible'
                    : Depot.texteDe({'type': env['clair']['type'], 'donnees': env['clair']['donnees']}),
                    maxLines: 3, overflow: TextOverflow.ellipsis),
                subtitle: Text('Reçu ${dateCourte(env['envoyeLe'] as String?)} · ${TypeEl.libelles[env['clair']?['type']] ?? ''}'),
                trailing: Wrap(
                  children: [
                    IconButton(
                      tooltip: 'Copier',
                      icon: const Icon(Icons.copy),
                      onPressed: () {
                        final t = env['clair'] == null ? '' : Depot.texteDe({'type': env['clair']['type'], 'donnees': env['clair']['donnees']});
                        Clipboard.setData(ClipboardData(text: t));
                        afficherMessage(context, 'Copié.');
                      },
                    ),
                    if (env['clair']?['typeContenu'] == 'LIEN')
                      IconButton(
                        tooltip: 'Ouvrir le lien',
                        icon: const Icon(Icons.open_in_new),
                        onPressed: () => launchUrl(Uri.parse(Depot.texteDe({'type': env['clair']['type'], 'donnees': env['clair']['donnees']}).trim())),
                      ),
                    IconButton(tooltip: 'Garder dans mon Board', icon: const Icon(Icons.save_alt), onPressed: () => _recuperer(env, garder: true)),
                    IconButton(tooltip: 'Marquer comme lu', icon: const Icon(Icons.done), onPressed: () => _recuperer(env, garder: false)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

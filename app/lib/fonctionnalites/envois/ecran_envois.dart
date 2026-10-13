import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../noyau/crypto/base64url.dart';
import '../../noyau/depot.dart';
import '../../noyau/noyau.dart';
import '../../ui/commun.dart';
import '../../ui/theme.dart';
import '../fichiers/types_fichier.dart';

const _icones = {
  TypeEl.pressePapier: Icons.content_paste,
  TypeEl.postIt: Icons.sticky_note_2_outlined,
  TypeEl.snippet: Icons.code,
  TypeEl.liste: Icons.list_alt,
  TypeEl.tache: Icons.check_box_outlined,
  TypeEl.fichier: Icons.insert_drive_file_outlined,
};

/// D1 : éléments reçus de mes autres appareils (3 appareils max par compte).
class EcranEnvois extends StatefulWidget {
  const EcranEnvois({super.key});

  @override
  State<EcranEnvois> createState() => _EcranEnvoisState();
}

class _EcranEnvoisState extends State<EcranEnvois> {
  List<Map<String, dynamic>>? _recus;
  Map<String, Map<String, dynamic>> _appareils = {};
  final _traites = <String>{}; // envois en cours de récupération (bouton désactivé)
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
      try {
        final appareils = (await noyau.api.get('/appareils') as List).cast<Map<String, dynamic>>();
        _appareils = {for (final a in appareils) a['id'].toString(): a};
      } catch (_) {
        // Le nom de l'appareil source est un confort : la liste reste utilisable sans lui.
      }
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
      // Le plus récent en premier.
      dechiffres.sort((a, b) => (b['envoyeLe'] as String? ?? '').compareTo(a['envoyeLe'] as String? ?? ''));
      if (mounted) setState(() => _recus = dechiffres);
    } catch (e) {
      if (mounted) {
        setState(() => _recus = []);
        afficherMessage(context, messageErreur(e));
      }
    }
  }

  static String _texte(Map<String, dynamic> env) {
    final clair = env['clair'] as Map<String, dynamic>?;
    return clair == null ? '' : Depot.texteDe({'type': clair['type'], 'donnees': clair['donnees']});
  }

  /// Marque l'envoi comme récupéré (il disparaît de cet appareil) ; [garder] l'ajoute d'abord au Board.
  Future<void> _recuperer(Map<String, dynamic> env, {required bool garder}) async {
    final noyau = context.noyau;
    final id = env['id'].toString();
    final clair = env['clair'] as Map<String, dynamic>?;
    setState(() => _traites.add(id));
    try {
      String? message;
      if (garder && clair != null) {
        final type = clair['type'] as String? ?? TypeEl.pressePapier;
        final donnees = Map<String, Object?>.from(clair['donnees'] as Map? ?? {});
        if (type == TypeEl.pressePapier) {
          await noyau.depot.ajouterPressePapier((donnees['texte'] ?? '').toString(), typeContenu: clair['typeContenu'] as String? ?? 'TEXTE');
          message = 'Ajouté au presse-papier de LuluBoard.';
        } else if (type != TypeEl.fichier && type != TypeEl.tache && type != TypeEl.liste) {
          await noyau.depot.creer(type, donnees);
          message = '${TypeEl.libelles[type]} enregistré dans votre Board.';
        } else {
          await noyau.depot.ajouterPressePapier(Depot.texteDe({'type': type, 'donnees': donnees}));
          message = 'Texte ajouté au presse-papier de LuluBoard.';
        }
      }
      if (!mounted) return;
      final ok = await executer(context, () async {
        await noyau.api.post('/envois/$id/recupere');
        return true;
      });
      if (ok == true && mounted) afficherMessage(context, message ?? 'Marqué comme lu.');
      await _charger();
    } finally {
      if (mounted) setState(() => _traites.remove(id));
    }
  }

  Future<void> _copier(Map<String, dynamic> env) async {
    await Clipboard.setData(ClipboardData(text: _texte(env)));
    if (!mounted) return;
    afficherMessage(
      context,
      'Copié dans le presse-papier.',
      action: SnackBarAction(label: 'Marquer comme lu', onPressed: () => _recuperer(env, garder: false)),
    );
  }

  String _source(Map<String, dynamic> env) {
    final a = _appareils[env['appareilSourceId']?.toString()];
    if (a == null) return 'un autre appareil';
    final plateforme = a['plateforme'] == null ? '' : ' (${a['plateforme']})';
    return '${a['nom'] ?? 'Appareil'}$plateforme';
  }

  @override
  Widget build(BuildContext context) {
    if (_recus == null) return const Center(child: CircularProgressIndicator());
    if (_recus!.isEmpty) {
      return RefreshIndicator(
        onRefresh: _charger,
        child: LayoutBuilder(
          builder: (context, c) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: SizedBox(
              height: c.maxHeight,
              child: EtatVide(
                icone: Icons.send_to_mobile,
                titre: 'Rien à récupérer',
                texte: 'Pour envoyer quelque chose ici depuis un autre de vos appareils (3 maximum), ouvrez le menu ⋮ '
                    'd\'un élément puis « Envoyer à un appareil ». Les envois non récupérés sont conservés 7 jours.',
                action: OutlinedButton.icon(onPressed: _charger, icon: const Icon(Icons.refresh), label: const Text('Actualiser')),
              ),
            ),
          ),
        ),
      );
    }
    final t = Theme.of(context);
    final n = _recus!.length;
    return RefreshIndicator(
      onRefresh: _charger,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Lulu.md, Lulu.md, Lulu.md, Lulu.xl),
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text('Reçus · $n à récupérer', style: t.textTheme.titleMedium),
                ),
              ),
              IconButton(tooltip: 'Actualiser', icon: const Icon(Icons.refresh), onPressed: _charger),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: Lulu.sm),
            child: Text(
              'Envoyés depuis vos autres appareils, chiffrés de bout en bout. Pour envoyer : menu ⋮ d\'un élément › « Envoyer à un appareil ».',
              style: t.textTheme.bodySmall,
            ),
          ),
          for (final env in _recus!) _carte(env),
        ],
      ),
    );
  }

  Widget _carte(Map<String, dynamic> env) {
    final t = Theme.of(context);
    final s = t.colorScheme;
    final id = env['id'].toString();
    final clair = env['clair'] as Map<String, dynamic>?;
    final type = clair?['type'] as String?;
    final libelleType = TypeEl.libelles[type] ?? 'Élément';
    final occupe = _traites.contains(id);
    final texte = _texte(env);
    final estLien = clair?['typeContenu'] == 'LIEN';
    final donnees = (clair?['donnees'] as Map?) ?? {};
    final icone = type == TypeEl.fichier ? familleDe(texte).icone : (_icones[type] ?? Icons.inbox);

    // Action principale : copier un texte, enregistrer un post-it ou un snippet.
    final Widget principale;
    final List<Widget> secondaires;
    final marquerLu = TextButton(
      onPressed: occupe ? null : () => _recuperer(env, garder: false),
      child: const Text('Marquer comme lu'),
    );
    if (clair == null) {
      principale = FilledButton.tonal(onPressed: occupe ? null : () => _recuperer(env, garder: false), child: const Text('Retirer'));
      secondaires = const [];
    } else if (type == TypeEl.fichier) {
      principale = FilledButton.tonal(onPressed: occupe ? null : () => _recuperer(env, garder: false), child: const Text('Marquer comme lu'));
      secondaires = const [];
    } else if (type == TypeEl.postIt || type == TypeEl.snippet) {
      principale = FilledButton.icon(
        onPressed: occupe ? null : () => _recuperer(env, garder: true),
        icon: const Icon(Icons.save_alt),
        label: const Text('Enregistrer dans mon Board'),
      );
      secondaires = [
        TextButton.icon(onPressed: () => _copier(env), icon: const Icon(Icons.copy, size: 18), label: const Text('Copier')),
        marquerLu,
      ];
    } else {
      principale = FilledButton.icon(onPressed: () => _copier(env), icon: const Icon(Icons.copy), label: const Text('Copier'));
      secondaires = [
        if (estLien)
          TextButton.icon(
            onPressed: () => launchUrl(Uri.parse(texte.trim())),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('Ouvrir le lien'),
          ),
        TextButton.icon(
          onPressed: occupe ? null : () => _recuperer(env, garder: true),
          icon: const Icon(Icons.save_alt, size: 18),
          label: const Text('Garder dans LuluBoard'),
        ),
        marquerLu,
      ];
    }

    return Card(
      margin: const EdgeInsets.only(bottom: Lulu.sm),
      child: Padding(
        padding: const EdgeInsets.all(Lulu.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Tooltip(
                  message: libelleType,
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: s.primary.withValues(alpha: 0.12),
                    foregroundColor: s.primary,
                    child: Icon(icone, size: 20, semanticLabel: libelleType),
                  ),
                ),
                const SizedBox(width: Lulu.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(libelleType, style: t.textTheme.labelLarge),
                      Text(
                        'De ${_source(env)} · ${dateCourte(env['envoyeLe'] as String?)}',
                        style: t.textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: Lulu.md),
            if (clair == null)
              Text('Contenu illisible sur cet appareil (clé différente ou envoi corrompu).', style: TextStyle(color: s.error))
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(Lulu.md - Lulu.xs),
                decoration: BoxDecoration(
                  color: s.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(Lulu.rMd),
                ),
                child: Text(
                  type == TypeEl.fichier
                      ? '$texte · ${tailleLisible(donnees['taille'] as num? ?? 0)}\nDéjà disponible dans l\'onglet Fichiers.'
                      : texte,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: type == TypeEl.snippet ? const TextStyle(fontFamily: 'monospace') : null,
                ),
              ),
            const SizedBox(height: Lulu.md),
            Wrap(
              spacing: Lulu.sm,
              runSpacing: Lulu.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [principale, ...secondaires],
            ),
          ],
        ),
      ),
    );
  }
}

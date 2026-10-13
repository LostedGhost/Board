import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../noyau/crypto/base64url.dart';
import '../../noyau/depot.dart';
import '../../noyau/noyau.dart';
import '../../noyau/session/service_compte.dart';
import '../../noyau/stockage/base_locale.dart';
import '../../plateformes/desktop.dart';
import '../commun/etiquettes.dart';
import '../../ui/commun.dart';
import '../../ui/glisser.dart';
import '../../ui/recherche_locale.dart';
import '../../ui/theme.dart';
import '../commun/actions_element.dart';
import 'types_fichier.dart';

/// Transfert en cours (envoi ou téléchargement) affiché avec sa progression.
class _Transfert {
  _Transfert(this.nom, this.taille, this.etape, this.libelle);
  final String nom;
  final num taille;
  int etape;
  String libelle;
  final int total = 3;
}

/// E1-E2 : fichiers chiffrés sur l'appareil avant l'envoi ; LuluBoard ne les ouvre jamais.
class EcranFichiers extends StatefulWidget {
  const EcranFichiers({super.key});

  @override
  State<EcranFichiers> createState() => _EcranFichiersState();
}

class _EcranFichiersState extends State<EcranFichiers> {
  final _statuts = <String, String>{};
  final _enCours = <String, _Transfert>{}; // id → progression
  final _filtre = TextEditingController();
  final _focusFiltre = FocusNode();
  String _recherche = '';

  @override
  void dispose() {
    _filtre.dispose();
    _focusFiltre.dispose();
    super.dispose();
  }

  void _etape(String id, int etape, String libelle) {
    if (!mounted) return;
    final t = _enCours[id];
    if (t == null) return;
    setState(() {
      t.etape = etape;
      t.libelle = libelle;
    });
  }

  // --- Envoi ---------------------------------------------------------------------------------

  Future<void> _televerser() async {
    final choisis = await FilePicker.pickFiles(dialogTitle: 'Choisir des fichiers à ajouter');
    if (choisis.isEmpty || !mounted) return;
    final noyau = context.noyau;

    // Refus clair AVANT tout chiffrement ou envoi (E1).
    final acceptes = <(PlatformFile, int)>[];
    final refuses = <(String, int)>[];
    for (final f in choisis) {
      final taille = await f.length() ?? 0;
      if (taille > tailleMaxFichier) {
        refuses.add((f.name, taille));
      } else {
        acceptes.add((f, taille));
      }
    }
    if (refuses.isNotEmpty && mounted) await _signalerRefus(refuses, acceptes.length);
    if (!mounted) return;

    var reussis = 0;
    for (final (f, taille) in acceptes) {
      final id = noyau.depot.nouvelId();
      setState(() => _enCours[id] = _Transfert(f.name, taille, 1, 'Lecture du fichier…'));
      try {
        final clair = await f.readAsBytes();
        _etape(id, 2, 'Chiffrement sur cet appareil…');
        final cle = noyau.crypto.aleatoire(32);
        final chiffre = await noyau.crypto.chiffrerFichier(cle, clair);
        final donnees = {'nom': f.name, 'typeMime': mimeDe(f.name), 'taille': clair.length};
        _etape(id, 3, 'Envoi chiffré vers vos appareils…');
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
        reussis++;
      } catch (e) {
        if (mounted) afficherMessage(context, '« ${f.name} » : ${messageErreur(e)}');
      } finally {
        if (mounted) setState(() => _enCours.remove(id));
      }
    }
    if (mounted && reussis > 0) {
      afficherMessage(context, reussis == 1 ? 'Fichier chiffré et ajouté.' : '$reussis fichiers chiffrés et ajoutés.');
    }
  }

  Future<void> _signalerRefus(List<(String, int)> refuses, int restants) => showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          icon: const Icon(Icons.block),
          title: Text(refuses.length == 1 ? 'Fichier trop volumineux' : 'Fichiers trop volumineux'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('La limite est de 100 Mo par fichier. Rien n\'a été envoyé pour :'),
              const SizedBox(height: Lulu.sm),
              for (final (nom, taille) in refuses)
                Padding(
                  padding: const EdgeInsets.only(bottom: Lulu.xs),
                  child: Text('• $nom (${tailleLisible(taille)})', maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
              if (restants > 0) ...[
                const SizedBox(height: Lulu.sm),
                Text(restants == 1 ? 'L\'autre fichier va être envoyé.' : 'Les $restants autres fichiers vont être envoyés.'),
              ],
            ],
          ),
          actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Compris'))],
        ),
      );

  // --- Téléchargement ------------------------------------------------------------------------

  Future<void> _telecharger(Enr e) async {
    final noyau = context.noyau;
    final id = e['id']! as String;
    final d = (e['donnees'] as Map?) ?? {};
    final nom = (d['nom'] ?? 'fichier').toString();
    setState(() => _enCours[id] = _Transfert(nom, d['taille'] as num? ?? 0, 1, 'Téléchargement…'));
    try {
      final acces = await noyau.api.get('/fichiers/$id/acces') as Map<String, dynamic>;
      final chiffre = await noyau.api.telecharger(acces['url'] as String);
      _etape(id, 2, 'Déchiffrement sur cet appareil…');
      final cle = decoderB64(e['cle']! as String);
      final clair = await noyau.crypto.dechiffrerFichier(cle, chiffre);
      _etape(id, 3, 'Enregistrement…');
      final chemin = await FilePicker.saveFile(
        fileName: nom,
        bytes: Uint8List.fromList(clair),
        mimeType: (d['typeMime'] ?? 'application/octet-stream').toString(),
        dialogTitle: 'Enregistrer « $nom » sous',
      );
      if (!mounted || chemin == null) return; // annulé par l'utilisateur
      if (chemin.scheme != 'file') return afficherMessage(context, '« $nom » déchiffré et téléchargé.');
      final path = chemin.toFilePath();
      afficherMessage(
        context,
        '« $nom » enregistré.',
        action: IntegrationDesktop.captureDisponible
            ? SnackBarAction(label: 'Ouvrir le dossier', onPressed: () => IntegrationDesktop.ouvrirDossier(path))
            : null,
      );
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

  // --- Suppression définitive (D19) ----------------------------------------------------------

  Future<void> _supprimer(Enr f) async {
    final nom = ((f['donnees'] as Map?)?['nom'] ?? 'ce fichier').toString();
    final depot = context.noyau.depot;
    final ok = await confirmer(
      context,
      'Supprimer définitivement ?',
      '« $nom » sera supprimé définitivement de tous vos appareils et du serveur. '
          'Cette suppression est définitive : elle ne pourra pas être annulée.',
      action: 'Supprimer définitivement',
    );
    if (!ok) return;
    await depot.supprimer(f['id']! as String);
    if (mounted) afficherMessage(context, '« $nom » supprimé définitivement.');
  }

  void _vider() {
    _filtre.clear();
    setState(() => _recherche = '');
  }

  // --- Interface -----------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final depot = context.noyau.depot;
    return RaccourciFiltre(
      focusNode: _focusFiltre,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyO, control: true): _televerser,
          const SingleActivator(LogicalKeyboardKey.keyO, meta: true): _televerser,
        },
        child: Focus(
          child: StreamBuilder<List<Enr>>(
            stream: depot.elements(TypeEl.fichier),
            builder: (context, snap) {
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final fichiers = snap.data!
                ..sort((a, b) => (b['modifieLe'] as String? ?? '').compareTo(a['modifieLe'] as String? ?? ''));
              final transferts = _enCours.entries.where((e) => !fichiers.any((f) => f['id'] == e.key)).toList();

              if (fichiers.isEmpty && transferts.isEmpty) {
                return EtatVide(
                  icone: Icons.cloud_upload_outlined,
                  titre: 'Vos fichiers, sur tous vos appareils',
                  texte: 'Ajoutez n\'importe quel fichier jusqu\'à 100 Mo. Il est chiffré sur cet appareil avant l\'envoi : '
                      'personne d\'autre que vous ne peut le lire, pas même LuluBoard.',
                  action: FilledButton.icon(
                    onPressed: _televerser,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Ajouter des fichiers'),
                  ),
                );
              }

              final visibles = [
                for (final f in fichiers)
                  if (concorde(_nom(f), _recherche) || concorde(familleDe(_nom(f)).libelle, _recherche)) f,
              ];
              final total = fichiers.fold<num>(0, (s, f) => s + ((f['donnees'] as Map?)?['taille'] as num? ?? 0));

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Lulu.md, Lulu.md, Lulu.md, 0),
                    child: _ZoneAjout(onTap: _televerser),
                  ),
                  for (final t in transferts)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Lulu.md, Lulu.sm, Lulu.md, 0),
                      child: _CarteTransfert(t.value),
                    ),
                  if (fichiers.isNotEmpty) ...[
                    ChampRecherche(
                      controller: _filtre,
                      focusNode: _focusFiltre,
                      indice: 'Filtrer par nom ou type (Ctrl+F)',
                      padding: const EdgeInsets.fromLTRB(Lulu.md, Lulu.md, Lulu.md, Lulu.xs),
                      onChanged: (v) => setState(() => _recherche = v.trim()),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Lulu.md + Lulu.xs, vertical: Lulu.xs),
                      child: Text(
                        _recherche.isEmpty
                            ? '${fichiers.length} fichier${fichiers.length > 1 ? 's' : ''} · ${tailleLisible(total)}'
                            : '${visibles.length} sur ${fichiers.length} fichier${fichiers.length > 1 ? 's' : ''}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                  Expanded(
                    child: visibles.isEmpty && _recherche.isNotEmpty
                        ? AucunResultat(recherche: _recherche, onVider: _vider)
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(Lulu.md, Lulu.xs, Lulu.md, Lulu.xl),
                            // H5 : un fichier se glisse sur « Envois » pour l'envoyer à un appareil.
                            children: [for (final f in visibles) Glissable(element: f, child: _ligne(f))],
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  static String _nom(Enr f) => ((f['donnees'] as Map?)?['nom'] ?? 'Fichier').toString();

  Widget _ligne(Enr f) {
    final id = f['id']! as String;
    final d = (f['donnees'] as Map?) ?? {};
    final nom = _nom(f);
    final famille = familleDe(nom);
    final statut = _statuts[id];
    if (statut == null) {
      _statuts[id] = '…';
      _rafraichirStatut(id);
    }
    final pret = statut == 'PRET';
    final transfert = _enCours[id];
    final schema = Theme.of(context).colorScheme;
    final libelleStatut = switch (statut) {
      'PRET' || '…' || null => null,
      'ECHEC' => 'Échec du transfert',
      'EN_FILE' => 'En attente de transfert',
      _ => 'Transfert en cours',
    };

    return Card(
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.only(left: Lulu.md, right: Lulu.xs),
            leading: Tooltip(
              message: famille.libelle,
              child: Semantics(
                label: famille.libelle,
                child: CircleAvatar(
                  backgroundColor: schema.primary.withValues(alpha: 0.12),
                  foregroundColor: schema.primary,
                  child: Icon(famille.icone),
                ),
              ),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TexteSurligne(nom, _recherche, maxLines: 1, overflow: TextOverflow.ellipsis),
                PucesEtiquettes(f, recherche: _recherche, max: 4),
              ],
            ),
            subtitle: Text(
              [
                tailleLisible(d['taille'] as num? ?? 0),
                dateCourte(f['modifieLe'] as String?),
                transfert?.libelle ?? libelleStatut ?? '',
              ].where((s) => s.isNotEmpty).join(' · '),
              style: statut == 'ECHEC' ? TextStyle(color: schema.error) : null,
            ),
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
                else if (!pret && statut != '…')
                  IconButton(tooltip: 'Actualiser l\'état du transfert', icon: const Icon(Icons.sync), onPressed: () => _rafraichirStatut(id)),
                IconButton(
                  tooltip: pret ? 'Télécharger et déchiffrer' : 'Disponible une fois le transfert terminé',
                  icon: const Icon(Icons.download),
                  onPressed: pret && transfert == null ? () => _telecharger(f) : null,
                ),
                _MenuFichier(element: f, onSupprimer: () => _supprimer(f)),
              ],
            ),
          ),
          if (transfert != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(Lulu.md, 0, Lulu.md, Lulu.sm),
              child: _Progression(transfert),
            ),
        ],
      ),
    );
  }
}

/// Zone d'ajout bien visible en tête d'écran (clic ou Ctrl+O).
class _ZoneAjout extends StatelessWidget {
  const _ZoneAjout({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final s = t.colorScheme;
    return Semantics(
      button: true,
      label: 'Ajouter des fichiers',
      excludeSemantics: true,
      child: Material(
        color: s.primary.withValues(alpha: 0.06),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Lulu.rLg),
          side: BorderSide(color: s.primary.withValues(alpha: 0.5), width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Lulu.md, vertical: Lulu.md),
            child: Row(
              children: [
                Icon(Icons.cloud_upload_outlined, color: s.primary, size: 32),
                const SizedBox(width: Lulu.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Ajouter des fichiers', style: t.textTheme.titleMedium),
                      const SizedBox(height: Lulu.xs),
                      Text('Tous types, 100 Mo max par fichier · chiffrés sur cet appareil avant l\'envoi',
                          style: t.textTheme.bodySmall),
                    ],
                  ),
                ),
                const SizedBox(width: Lulu.sm),
                Tooltip(
                  message: 'Raccourci : Ctrl+O',
                  child: FilledButton.icon(onPressed: onTap, icon: const Icon(Icons.add), label: const Text('Choisir')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Carte d'un envoi qui n'a pas encore de ligne dans la liste.
class _CarteTransfert extends StatelessWidget {
  const _CarteTransfert(this.t);

  final _Transfert t;

  @override
  Widget build(BuildContext context) {
    final famille = familleDe(t.nom);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Lulu.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(famille.icone, semanticLabel: famille.libelle),
                const SizedBox(width: Lulu.md),
                Expanded(child: Text(t.nom, maxLines: 1, overflow: TextOverflow.ellipsis)),
                Text(tailleLisible(t.taille), style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: Lulu.sm),
            _Progression(t),
          ],
        ),
      ),
    );
  }
}

/// Barre de progression par étape : « Étape 2/3 · Chiffrement… ».
class _Progression extends StatelessWidget {
  const _Progression(this.t);

  final _Transfert t;

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        label: 'Étape ${t.etape} sur ${t.total} : ${t.libelle}',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(Lulu.rSm),
              child: Stack(
                children: [
                  // Avancement par étape + activité de l'étape en cours.
                  LinearProgressIndicator(value: (t.etape - 1) / t.total, minHeight: 6),
                  const Opacity(opacity: 0.35, child: LinearProgressIndicator(minHeight: 6, backgroundColor: Colors.transparent)),
                ],
              ),
            ),
            const SizedBox(height: Lulu.xs),
            Text('Étape ${t.etape}/${t.total} · ${t.libelle}', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
}

/// Menu d'un fichier : actions communes, mais suppression définitive avec confirmation explicite.
class _MenuFichier extends StatelessWidget {
  const _MenuFichier({required this.element, required this.onSupprimer});

  final Enr element;
  final VoidCallback onSupprimer;

  @override
  Widget build(BuildContext context) {
    final actif = context.noyau.compte.etat.mode == ModeSession.actif;
    final epingle = element['epingleAccesRapide'] == true;
    final erreur = Theme.of(context).colorScheme.error;
    return PopupMenuButton<String>(
      tooltip: 'Actions sur le fichier',
      onSelected: (a) => a == 'supprimer' ? onSupprimer() : executerAction(context, element, a),
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'copier', child: ListTile(leading: Icon(Icons.copy), title: Text('Copier le nom'))),
        const PopupMenuItem(value: 'rappel', child: ListTile(leading: Icon(Icons.alarm_add), title: Text('Ajouter un rappel'))),
        PopupMenuItem(
          value: 'acces',
          child: ListTile(
            leading: Icon(epingle ? Icons.star : Icons.star_border),
            title: Text(epingle ? 'Retirer de l\'accès rapide' : 'Épingler en accès rapide'),
          ),
        ),
        if (actif) ...const [
          PopupMenuItem(value: 'envoyer', child: ListTile(leading: Icon(Icons.send_to_mobile), title: Text('Envoyer à un appareil'))),
          PopupMenuItem(value: 'partager', child: ListTile(leading: Icon(Icons.link), title: Text('Partager par lien'))),
        ],
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'supprimer',
          child: ListTile(
            leading: Icon(Icons.delete_forever_outlined, color: erreur),
            title: Text('Supprimer définitivement…', style: TextStyle(color: erreur)),
          ),
        ),
      ],
    );
  }
}

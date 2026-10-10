import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../noyau/depot.dart';
import '../../noyau/noyau.dart';
import '../../noyau/session/service_compte.dart';
import '../../noyau/stockage/base_locale.dart';
import '../../plateformes/desktop.dart';
import '../../ui/commun.dart';
import '../compte/ecrans_auth.dart';

/// Réglages : compte, appareils, sécurité, préférences, liens, données (sections A, I).
class EcranReglages extends StatelessWidget {
  const EcranReglages({super.key});

  @override
  Widget build(BuildContext context) {
    final noyau = context.noyau;
    return ListenableBuilder(
      listenable: noyau.compte,
      builder: (context, _) {
        final etat = noyau.compte.etat;
        final actif = etat.mode == ModeSession.actif;
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            if (!actif) ...[
              const _Titre('Compte'),
              ListTile(
                leading: const Icon(Icons.person_add),
                title: const Text('Créer un compte'),
                subtitle: const Text('Synchronisation chiffrée de bout en bout, fichiers, partage'),
                onTap: () => ouvrirInscription(context),
              ),
              ListTile(leading: const Icon(Icons.login), title: const Text('Se connecter'), onTap: () => ouvrirConnexion(context)),
            ] else ...[
              const _Titre('Compte'),
              ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: Text((etat.compte?['nomAffichage'] ?? '').toString()),
                subtitle: Text((etat.compte?['email'] ?? '').toString()),
                trailing: const Icon(Icons.edit),
                onTap: () async {
                  final nom = await demanderTexte(context, 'Nom d\'affichage', initial: (etat.compte?['nomAffichage'] ?? '').toString());
                  if (nom != null && nom.isNotEmpty && context.mounted) {
                    await executer(context, () async {
                      await noyau.api.patch('/compte', {'nomAffichage': nom});
                      await noyau.compte.rafraichirCompte();
                    });
                  }
                },
              ),
              const _Titre('Appareils'),
              const _Appareils(),
              const _Titre('Sécurité'),
              ListTile(leading: const Icon(Icons.password), title: const Text('Changer de mot de passe'), onTap: () => _changerMotDePasse(context)),
              ListTile(
                leading: const Icon(Icons.key),
                title: const Text('Nouvelle clé de récupération'),
                subtitle: const Text('L\'ancienne cessera de fonctionner'),
                onTap: () => ouvrirRegenerationCle(context),
              ),
              const _Titre('Rétention'),
              const _Retention(),
              const _Titre('Liens publics'),
              const _Liens(),
            ],
            const _Titre('Apparence'),
            ListenableBuilder(
              listenable: noyau.reglagesUi,
              builder: (context, _) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(value: ThemeMode.system, label: Text('Système'), icon: Icon(Icons.brightness_auto)),
                    ButtonSegment(value: ThemeMode.light, label: Text('Clair'), icon: Icon(Icons.light_mode)),
                    ButtonSegment(value: ThemeMode.dark, label: Text('Sombre'), icon: Icon(Icons.dark_mode)),
                  ],
                  selected: {noyau.reglagesUi.mode},
                  onSelectionChanged: (s) => noyau.reglagesUi.changerTheme(s.first),
                ),
              ),
            ),
            if (IntegrationDesktop.captureDisponible) ...[
              const _Titre('Ordinateur'),
              const _DemarrageAuto(),
              const ListTile(
                leading: Icon(Icons.keyboard),
                title: Text('Raccourcis'),
                subtitle: Text('Ctrl+Alt+B : historique du presse-papier · Ctrl+Alt+N : capture rapide · Ctrl+K : recherche'),
              ),
            ],
            const _Titre('Données'),
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('Exporter mes données'),
              subtitle: const Text('Fichier JSON en clair, généré sur cet appareil'),
              onTap: () => _exporter(context),
            ),
            if (actif) ...[
              ListTile(leading: const Icon(Icons.logout), title: const Text('Se déconnecter de cet appareil'), onTap: () => _deconnecter(context)),
              ListTile(
                leading: Icon(Icons.delete_forever, color: Theme.of(context).colorScheme.error),
                title: Text('Supprimer mon compte', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                subtitle: const Text('Délai de grâce de 30 jours : se reconnecter annule la suppression'),
                onTap: () => _supprimerCompte(context),
              ),
            ],
            const _Titre('À propos'),
            const ListTile(
              leading: Icon(Icons.lock_outline),
              title: Text('LuluBoard 0.1.0'),
              subtitle: Text('Vos contenus sont chiffrés sur vos appareils avant tout envoi. Le serveur ne peut pas les lire.'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _changerMotDePasse(BuildContext context) async {
    final ancien = TextEditingController(), nouveau = TextEditingController();
    var autres = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) => AlertDialog(
          title: const Text('Changer de mot de passe'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: ancien, obscureText: true, decoration: const InputDecoration(labelText: 'Mot de passe actuel')),
              const SizedBox(height: 8),
              TextField(controller: nouveau, obscureText: true, decoration: const InputDecoration(labelText: 'Nouveau mot de passe')),
              CheckboxListTile(
                value: autres,
                onChanged: (v) => setState(() => autres = v ?? true),
                title: const Text('Déconnecter mes autres appareils'),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Changer')),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    final erreur = validerMotDePasse(nouveau.text);
    if (erreur != null) return afficherMessage(context, erreur);
    await executer(
      context,
      () => context.noyau.api.post('/compte/mot-de-passe', {
        'ancienMotDePasse': ancien.text,
        'nouveauMotDePasse': nouveau.text,
        'deconnecterAutresAppareils': autres,
      }),
      succes: 'Mot de passe changé.',
    );
  }

  Future<void> _exporter(BuildContext context) async {
    final base = context.noyau.base;
    final export = <String, Object?>{'exporteLe': DateTime.now().toUtc().toIso8601String(), 'format': 'luluboard-export-v1'};
    for (final e in Entite.values) {
      export[e.nom] = (await base.tous(e)).map((r) => Map<String, Object?>.from(r)..remove('cle')..remove('sale')).toList();
    }
    final octets = Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent('  ').convert(export)));
    await FilePicker.saveFile(fileName: 'luluboard-export.json', bytes: octets, mimeType: 'application/json', dialogTitle: 'Exporter mes données');
  }

  Future<void> _deconnecter(BuildContext context) async {
    final noyau = context.noyau;
    final enAttente = (await noyau.base.aEnvoyer()).length;
    if (!context.mounted) return;
    final ok = await confirmer(
      context,
      'Se déconnecter ?',
      '${enAttente > 0 ? 'Attention : $enAttente modification(s) ne sont pas encore synchronisées et seront perdues. ' : ''}'
          'Les données et les clés seront effacées de cet appareil ; elles restent sur votre compte.',
      action: 'Se déconnecter',
    );
    if (ok) await noyau.compte.deconnecter();
  }

  Future<void> _supprimerCompte(BuildContext context) async {
    final mdp = await demanderTexte(context, 'Confirmez avec votre mot de passe', libelle: 'Mot de passe');
    if (mdp == null || !context.mounted) return;
    final r = await executer(context, () => context.noyau.api.delete('/compte', {'motDePasse': mdp}));
    if (r != null && context.mounted) {
      afficherMessage(context, 'Suppression programmée dans 30 jours. Reconnectez-vous d\'ici là pour l\'annuler.');
      await context.noyau.compte.deconnecter();
    }
  }
}

class _Titre extends StatelessWidget {
  const _Titre(this.texte);
  final String texte;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
        child: Text(texte.toUpperCase(), style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}

/// A4, I11, I12 : appareils, demandes de déverrouillage en attente.
class _Appareils extends StatefulWidget {
  const _Appareils();

  @override
  State<_Appareils> createState() => _AppareilsState();
}

class _AppareilsState extends State<_Appareils> {
  List<Map<String, dynamic>> _appareils = [];
  List<Map<String, dynamic>> _demandes = [];

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final api = context.noyau.api;
    try {
      final a = (await api.get('/appareils') as List).cast<Map<String, dynamic>>();
      final d = (await api.get('/deverrouillages/en-attente') as List).cast<Map<String, dynamic>>();
      if (mounted) {
        setState(() {
          _appareils = a;
          _demandes = d;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final noyau = context.noyau;
    return Column(
      children: [
        for (final d in _demandes)
          Card(
            color: Theme.of(context).colorScheme.tertiaryContainer,
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.phonelink_lock),
                    const SizedBox(width: 12),
                    Expanded(child: Text("« ${(d['appareilDemandeur'] as Map)['nom']} » demande l'accès", style: Theme.of(context).textTheme.titleSmall)),
                  ]),
                  const SizedBox(height: 6),
                  const Text("Saisissez le code affiché sur ce nouvel appareil. Si ce n'est pas vous, refusez."),
                  OverflowBar(
                    alignment: MainAxisAlignment.end,
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: () async {
                          await executer(context, () => noyau.compte.refuser(d['id'] as String), succes: "Refusé : l'appareil a été révoqué.");
                          _charger();
                        },
                        child: const Text('Refuser'),
                      ),
                      FilledButton(
                        onPressed: () async {
                          final code = await demanderTexte(context, 'Code affiché sur le nouvel appareil', libelle: 'Code à 6 chiffres');
                          if (code == null || !context.mounted) return;
                          await executer(context, () => noyau.compte.approuver(d, code), succes: 'Appareil déverrouillé.');
                          _charger();
                        },
                        child: const Text('Approuver'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        for (final a in _appareils)
          ListTile(
            leading: Icon(switch (a['type']) { 'MOBILE' => Icons.smartphone, 'WEB' => Icons.public, _ => Icons.computer }),
            title: Text('${a['nom']}${a['courant'] == true ? ' (cet appareil)' : ''}'),
            subtitle: Text('${a['plateforme']} · ${a['statut'] == 'ACTIF' ? 'actif' : 'en attente de déverrouillage'} · vu ${dateCourte(a['derniereActiviteLe'] as String?)}'),
            trailing: PopupMenuButton<String>(
              onSelected: (action) async {
                if (action == 'renommer') {
                  final nom = await demanderTexte(context, 'Renommer l\'appareil', initial: a['nom'] as String);
                  if (nom != null && nom.isNotEmpty && context.mounted) {
                    await executer(context, () => noyau.api.patch('/appareils/${a['id']}', {'nom': nom}));
                  }
                } else if (action == 'revoquer') {
                  final ok = await confirmer(context, 'Révoquer « ${a['nom']} » ?',
                      'Il sera déconnecté immédiatement et ses données locales seront effacées à sa prochaine connexion.',
                      action: 'Révoquer');
                  if (ok && context.mounted) await executer(context, () => noyau.api.delete('/appareils/${a['id']}'), succes: 'Appareil révoqué.');
                }
                _charger();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'renommer', child: Text('Renommer')),
                if (a['courant'] != true) const PopupMenuItem(value: 'revoquer', child: Text('Révoquer')),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextButton.icon(onPressed: _charger, icon: const Icon(Icons.refresh), label: const Text('Actualiser · 3 appareils maximum')),
          ),
        ),
      ],
    );
  }
}

/// B4 / C3 : durées de conservation.
class _Retention extends StatefulWidget {
  const _Retention();

  @override
  State<_Retention> createState() => _RetentionState();
}

class _RetentionState extends State<_Retention> {
  Map<String, dynamic>? _prefs;
  static const _libelles = {'INFINIE': 'Illimitée', 'J90': '90 jours', 'J30': '30 jours', 'J7': '7 jours', 'H24': '24 heures', 'H1': '1 heure', 'MIN30': '30 minutes'};

  @override
  void initState() {
    super.initState();
    context.noyau.api.get('/compte/preferences').then((p) {
      if (mounted) setState(() => _prefs = Map<String, dynamic>.from(p as Map));
    }).catchError((_) {});
  }

  Future<void> _changer(String champ, String valeur) async {
    final nouvelles = {..._prefs!, champ: valeur};
    final r = await executer(context, () => context.noyau.api.put('/compte/preferences', nouvelles));
    if (r != null && mounted) setState(() => _prefs = Map<String, dynamic>.from(r as Map));
  }

  @override
  Widget build(BuildContext context) {
    if (_prefs == null) return const ListTile(title: Text('Chargement…'));
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.content_paste),
          title: const Text('Historique du presse-papier'),
          subtitle: const Text('Les entrées épinglées ne sont jamais supprimées'),
          trailing: DropdownButton<String>(
            value: _prefs!['retentionPressePapier'] as String,
            items: [for (final e in _libelles.entries) if (e.key != 'H1') DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => _changer('retentionPressePapier', v!),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.history),
          title: const Text('Versions des post-it'),
          trailing: DropdownButton<String>(
            value: _prefs!['retentionVersions'] as String,
            items: [for (final e in _libelles.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => _changer('retentionVersions', v!),
          ),
        ),
      ],
    );
  }
}

/// I21 : liens publics actifs, révocation, prolongation.
class _Liens extends StatefulWidget {
  const _Liens();

  @override
  State<_Liens> createState() => _LiensState();
}

class _LiensState extends State<_Liens> {
  List<Map<String, dynamic>> _liens = [];
  Map<String, Object?> _urls = {};

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final noyau = context.noyau;
    try {
      final l = (await noyau.api.get('/liens') as List).cast<Map<String, dynamic>>();
      final urls = await noyau.base.lireMeta<Map<String, Object?>>('liens') ?? {};
      final elements = {for (final e in await noyau.base.tous(Entite.element)) e['id']: e};
      if (mounted) {
        setState(() {
          _liens = [for (final x in l) {...x, 'titre': elements[x['elementId']] == null ? null : Depot.texteDe(elements[x['elementId']]!)}];
          _urls = urls;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final actifs = _liens.where((l) => l['statut'] == 'ACTIF').toList();
    if (actifs.isEmpty) {
      return const ListTile(leading: Icon(Icons.link_off), title: Text('Aucun lien actif'), subtitle: Text('Partagez un post-it, un snippet, une liste ou un fichier depuis son menu.'));
    }
    return Column(
      children: [
        for (final l in actifs)
          ListTile(
            leading: Icon(l['protegeParMotDePasse'] == true ? Icons.lock : Icons.link),
            title: Text((l['titre'] ?? TypeEl.libelles[l['typeElement']] ?? 'Élément').toString().split('\n').first, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${l['nbTelechargements']} ouverture(s) · ${l['expireLe'] == null ? 'sans limite' : 'expire ${dateCourte(l['expireLe'] as String)}'}'),
            trailing: Wrap(
              children: [
                if (_urls[l['id']] != null)
                  IconButton(
                    tooltip: 'Copier le lien',
                    icon: const Icon(Icons.copy),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _urls[l['id']]! as String));
                      afficherMessage(context, 'Lien copié.');
                    },
                  ),
                IconButton(
                  tooltip: 'Révoquer',
                  icon: const Icon(Icons.link_off),
                  onPressed: () async {
                    await executer(context, () => context.noyau.api.delete('/liens/${l['id']}'), succes: 'Lien révoqué.');
                    _charger();
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _DemarrageAuto extends StatefulWidget {
  const _DemarrageAuto();

  @override
  State<_DemarrageAuto> createState() => _DemarrageAutoState();
}

class _DemarrageAutoState extends State<_DemarrageAuto> {
  bool _actif = true;

  @override
  void initState() {
    super.initState();
    context.noyau.base.lireMeta<bool>('demarrage_auto').then((v) {
      if (mounted) setState(() => _actif = v ?? true);
    });
  }

  @override
  Widget build(BuildContext context) => SwitchListTile(
        secondary: const Icon(Icons.power_settings_new),
        title: const Text('Lancer LuluBoard au démarrage'),
        subtitle: const Text('Pour capturer le presse-papier dès l\'ouverture de session'),
        value: _actif,
        onChanged: (v) async {
          await IntegrationDesktop.definirDemarrageAuto(v);
          setState(() => _actif = v);
        },
      );
}

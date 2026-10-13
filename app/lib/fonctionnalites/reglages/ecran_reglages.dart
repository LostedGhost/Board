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
import '../../ui/recherche_locale.dart';
import '../aide/ecran_aide.dart';
import '../compte/ecrans_auth.dart';

List<T> _filtrerPar<T>(List<T> items, String recherche, String Function(T) label) {
  if (recherche.isEmpty) return items;
  return [for (final x in items) if (concorde(label(x), recherche)) x];
}

/// Titre d'une ligne, utilisable pour le filtrage.
class _Item {
  const _Item({this.icone, required this.titre, this.sousTitre, this.trailing, this.onTap, this.enfant, this.estErreur = false});
  final IconData? icone;
  final String titre;
  final String? sousTitre;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Widget? enfant;
  final bool estErreur;
}

bool _itemConcorde(_Item item, String recherche) => concorde(item.titre, recherche) || concorde(item.sousTitre, recherche);

/// Une section de réglages : titre + lignes associées.
class _Section {
  const _Section(this.titre, this.items, {this.sousTitre});
  final String titre;
  final String? sousTitre;
  final List<_Item> items;
}

/// Barre de recherche en haut de l'écran : filtre en temps réel, Échap / clic vide pour vider.
class _BarreRecherche extends StatelessWidget {
  const _BarreRecherche({required this.controller, required this.recherche, required this.onChanged, required this.onVider});
  final TextEditingController controller;
  final String recherche;
  final ValueChanged<String> onChanged;
  final VoidCallback onVider;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: CallbackShortcuts(
          bindings: {const SingleActivator(LogicalKeyboardKey.escape): onVider},
          child: Focus(
            canRequestFocus: false,
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              decoration: InputDecoration(
                hintText: 'Rechercher dans les réglages',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: recherche.isNotEmpty
                    ? IconButton(tooltip: 'Vider la recherche', icon: const Icon(Icons.close), onPressed: onVider)
                    : null,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        ),
      );
}

/// Réglages : compte, appareils, sécurité, préférences, liens, données (sections A, I).
class EcranReglages extends StatefulWidget {
  const EcranReglages({super.key});

  @override
  State<EcranReglages> createState() => _EcranReglagesState();
}

class _EcranReglagesState extends State<EcranReglages> {
  final _ctrl = TextEditingController();
  String _recherche = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _vider() {
    _ctrl.clear();
    setState(() => _recherche = '');
  }

  @override
  Widget build(BuildContext context) {
    final noyau = context.noyau;
    return ListenableBuilder(
      listenable: noyau.compte,
      builder: (context, _) {
        final actif = noyau.compte.etat.mode == ModeSession.actif;
        return Column(
          children: [
            _BarreRecherche(controller: _ctrl, recherche: _recherche, onChanged: (v) => setState(() => _recherche = v), onVider: _vider),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _recherche.isEmpty ? null : _vider,
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: _enfants(context, noyau, actif),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  List<Widget> _enfants(BuildContext context, Noyau noyau, bool actif) {
    final r = _recherche;
    final enfants = <Widget>[];
    if (!actif) {
      enfants.add(_SectionReglage(_Section('Compte', [
        _Item(icone: Icons.person_add, titre: 'Créer un compte', sousTitre: 'Synchronisation chiffrée de bout en bout, fichiers, partage', onTap: () => ouvrirInscription(context)),
        _Item(icone: Icons.login, titre: 'Se connecter', onTap: () => ouvrirConnexion(context)),
      ]), r));
    } else {
      final etat = noyau.compte.etat;
      enfants.add(_SectionReglage(_Section('Compte', [
        _Item(
          icone: Icons.badge_outlined,
          titre: (etat.compte?['nomAffichage'] ?? '').toString(),
          sousTitre: (etat.compte?['email'] ?? '').toString(),
          trailing: const Icon(Icons.edit),
          onTap: () => _renommer(context),
        ),
      ]), r));
      enfants.add(_Appareils(r));
      enfants.add(_SectionReglage(_Section('Sécurité', [
        _Item(icone: Icons.password, titre: 'Changer de mot de passe', onTap: () => _changerMotDePasse(context)),
        _Item(icone: Icons.key, titre: 'Nouvelle clé de récupération', sousTitre: "L'ancienne cessera de fonctionner", onTap: () => ouvrirRegenerationCle(context)),
      ]), r));
      enfants.add(_Retention(r));
      enfants.add(_Liens(r));
    }
    enfants.add(_SectionReglage(_Section('Apparence', [
      _Item(
        titre: 'Thème de l\'application',
        sousTitre: 'Système · Clair · Sombre',
        enfant: ListenableBuilder(
          listenable: noyau.reglagesUi,
          builder: (context, _) => SegmentedButton<ThemeMode>(
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
    ], sousTitre: 'Thème · Système · Clair · Sombre'), r));
    if (IntegrationDesktop.captureDisponible) {
      enfants.add(_SectionReglage(_Section('Ordinateur', [
        _Item(icone: Icons.power_settings_new, titre: 'Lancer LuluBoard au démarrage', sousTitre: 'Pour capturer le presse-papier dès l\'ouverture de session', enfant: const _DemarrageAuto()),
        _Item(icone: Icons.keyboard, titre: 'Raccourcis', sousTitre: 'Ctrl+Alt+B : historique du presse-papier · Ctrl+Alt+N : capture rapide · Ctrl+K : recherche'),
      ], sousTitre: 'Démarrage · Raccourcis · Capture'), r));
    }
    enfants.add(_SectionReglage(_Section('Données', [
      _Item(icone: Icons.download, titre: 'Exporter mes données', sousTitre: 'Fichier JSON en clair, généré sur cet appareil', onTap: () => _exporter(context)),
      if (actif) ...[
        _Item(icone: Icons.logout, titre: 'Se déconnecter de cet appareil', onTap: () => _deconnecter(context)),
        _Item(icone: Icons.delete_forever, titre: 'Supprimer mon compte', sousTitre: 'Délai de grâce de 30 jours : se reconnecter annule la suppression', estErreur: true, onTap: () => _supprimerCompte(context)),
      ],
    ], sousTitre: 'Export · Connexion · Suppression'), r));
    enfants.add(_SectionReglage(_Section('Aide', [
      _Item(
        icone: Icons.help_outline,
        titre: 'Aide et raccourcis',
        sousTitre: 'Questions fréquentes, raccourcis clavier, confidentialité, contact',
        trailing: const Icon(Icons.chevron_right),
        onTap: () => ouvrirAide(context),
      ),
    ], sousTitre: 'FAQ · Raccourcis · Support'), r));
    enfants.add(_SectionReglage(_Section('À propos', [
      _Item(icone: Icons.lock_outline, titre: 'LuluBoard 0.1.0', sousTitre: 'Vos contenus sont chiffrés sur vos appareils avant tout envoi. Le serveur ne peut pas les lire.'),
    ]), r));
    return enfants;
  }

  Future<void> _renommer(BuildContext context) async {
    final noyau = context.noyau;
    final etat = noyau.compte.etat;
    final nom = await demanderTexte(context, 'Nom d\'affichage', initial: (etat.compte?['nomAffichage'] ?? '').toString());
    if (nom != null && nom.isNotEmpty && context.mounted) {
      await executer(context, () async {
        await noyau.api.patch('/compte', {'nomAffichage': nom});
        await noyau.compte.rafraichirCompte();
      });
    }
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
    var confirme = false;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (c) => StatefulBuilder(
        builder: (c, setEtat) => AlertDialog(
          title: const Text('Exporter mes données'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('⚠️ Ce fichier contient TOUTES vos données en clair (texte, notes, tâches, snippets, fichiers).'),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: confirme,
                onChanged: (v) => setEtat(() => confirme = v ?? false),
                title: const Text('J\'ai compris, exporter quand même'),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
            FilledButton(onPressed: confirme ? () => Navigator.pop(c, true) : null, child: const Text('Exporter')),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    final base = context.noyau.base;
    final export = <String, Object?>{'exporteLe': DateTime.now().toUtc().toIso8601String(), 'format': 'luluboard-export-v1'};
    for (final e in Entite.values) {
      export[e.nom] = (await base.tous(e)).map((r) => Map<String, Object?>.from(r)..remove('cle')..remove('sale')).toList();
    }
    final octets = Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent('  ').convert(export)));
    final chemin = await FilePicker.saveFile(
      fileName: 'luluboard-export.json',
      bytes: octets,
      mimeType: 'application/json',
      dialogTitle: 'Exporter mes données',
    );
    if (!context.mounted) return;
    // Sur le web, le navigateur gère le téléchargement : pas de chemin local à afficher.
    if (chemin == null || chemin.scheme != 'file') return afficherMessage(context, 'Export généré.');
    final path = chemin.toFilePath();
    final action = IntegrationDesktop.captureDisponible
        ? SnackBarAction(label: 'Ouvrir le dossier', onPressed: () => IntegrationDesktop.ouvrirDossier(path))
        : null;
    afficherMessage(context, 'Exporté vers $path', action: action);
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

/// Section filtrable : masquée (sans détruire d'état) quand aucune ligne ne correspond.
class _SectionReglage extends StatelessWidget {
  const _SectionReglage(this.section, this.recherche);
  final _Section section;
  final String recherche;

  @override
  Widget build(BuildContext context) {
    final itemsVisibles = recherche.isEmpty
        ? section.items
        : [for (final i in section.items) if (_itemConcorde(i, recherche)) i];
    final titreConcorde = concorde(section.titre, recherche) || concorde(section.sousTitre, recherche);
    if (recherche.isNotEmpty && !titreConcorde && itemsVisibles.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Titre(section.titre),
      for (final i in itemsVisibles)
        i.enfant != null
            ? Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), child: i.enfant)
            : _buildItem(context, i, recherche),
    ]);
  }
}

Widget _buildItem(BuildContext context, _Item item, String recherche) {
  final couleur = item.estErreur ? Theme.of(context).colorScheme.error : null;
  final titreStyle = item.estErreur ? TextStyle(color: Theme.of(context).colorScheme.error) : null;
  return ListTile(
    leading: item.icone != null ? Icon(item.icone, color: couleur) : null,
    title: TexteSurligne(item.titre, recherche, style: titreStyle),
    subtitle: item.sousTitre != null ? TexteSurligne(item.sousTitre!, recherche) : null,
    trailing: item.trailing,
    onTap: item.onTap,
  );
}

/// A4, I11, I12 : appareils, demandes de déverrouillage en attente.
class _Appareils extends StatefulWidget {
  const _Appareils(this.recherche);
  final String recherche;

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

  String _libelleAppareil(Map<String, dynamic> a) =>
      '${a['nom']} ${a['plateforme']} ${a['statut'] == 'ACTIF' ? 'actif' : 'en attente de déverrouillage'} vu ${dateCourte(a['derniereActiviteLe'] as String?)}';

  @override
  Widget build(BuildContext context) {
    final r = widget.recherche;
    final demandes = _filtrerPar(_demandes, r, (d) => "${(d['appareilDemandeur'] as Map)['nom']}");
    final appareils = _filtrerPar(_appareils, r, _libelleAppareil);
    if (r.isNotEmpty && !concorde('Appareils', r) && demandes.isEmpty && appareils.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Titre('Appareils'),
      for (final d in demandes)
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
                  Expanded(child: TexteSurligne("« ${(d['appareilDemandeur'] as Map)['nom']} » demande l'accès", r, style: Theme.of(context).textTheme.titleSmall)),
                ]),
                const SizedBox(height: 6),
                const Text("Saisissez le code affiché sur ce nouvel appareil. Si ce n'est pas vous, refusez."),
                OverflowBar(
                  alignment: MainAxisAlignment.end,
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: () async {
                        await executer(context, () => context.noyau.compte.refuser(d['id'] as String), succes: "Refusé : l'appareil a été révoqué.");
                        _charger();
                      },
                      child: const Text('Refuser'),
                    ),
                    FilledButton(
                      onPressed: () async {
                        final code = await demanderTexte(context, 'Code affiché sur le nouvel appareil', libelle: 'Code à 6 chiffres');
                        if (code == null || !context.mounted) return;
                        await executer(context, () => context.noyau.compte.approuver(d, code), succes: 'Appareil déverrouillé.');
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
      for (final a in appareils)
        ListTile(
          leading: Icon(switch (a['type']) { 'MOBILE' => Icons.smartphone, 'WEB' => Icons.public, _ => Icons.computer }),
          title: TexteSurligne('${a['nom']}${a['courant'] == true ? ' (cet appareil)' : ''}', r),
          subtitle: TexteSurligne('${a['plateforme']} · ${a['statut'] == 'ACTIF' ? 'actif' : 'en attente de déverrouillage'} · vu ${dateCourte(a['derniereActiviteLe'] as String?)}', r),
          trailing: PopupMenuButton<String>(
            onSelected: (action) async {
              if (action == 'renommer') {
                final nom = await demanderTexte(context, 'Renommer l\'appareil', initial: a['nom'] as String);
                if (nom != null && nom.isNotEmpty && context.mounted) {
                  await executer(context, () => context.noyau.api.patch('/appareils/${a['id']}', {'nom': nom}));
                }
              } else if (action == 'revoquer') {
                final ok = await confirmer(context, 'Révoquer « ${a['nom']} » ?',
                    'Il sera déconnecté immédiatement et ses données locales seront effacées à sa prochaine connexion.',
                    action: 'Révoquer');
                if (ok && context.mounted) await executer(context, () => context.noyau.api.delete('/appareils/${a['id']}'), succes: 'Appareil révoqué.');
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
    ]);
  }
}

/// B4 / C3 : durées de conservation.
class _Retention extends StatefulWidget {
  const _Retention(this.recherche);
  final String recherche;

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
    final r = widget.recherche;
    if (_prefs == null) {
      if (r.isNotEmpty && !concorde('Rétention', r)) return const SizedBox.shrink();
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _Titre('Rétention'),
        const ListTile(title: Text('Chargement…')),
      ]);
    }
    final lignes = <_Item>[
      _Item(
        icone: Icons.content_paste,
        titre: 'Historique du presse-papier',
        sousTitre: 'Les entrées épinglées ne sont jamais supprimées',
        trailing: DropdownButton<String>(
          value: _prefs!['retentionPressePapier'] as String,
          items: [for (final e in _libelles.entries) if (e.key != 'H1') DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: (v) => _changer('retentionPressePapier', v!),
        ),
      ),
      _Item(
        icone: Icons.history,
        titre: 'Versions des post-it',
        trailing: DropdownButton<String>(
          value: _prefs!['retentionVersions'] as String,
          items: [for (final e in _libelles.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: (v) => _changer('retentionVersions', v!),
        ),
      ),
    ];
    final visibles = r.isEmpty ? lignes : [for (final l in lignes) if (_itemConcorde(l, r)) l];
    if (r.isNotEmpty && !concorde('Rétention', r) && visibles.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Titre('Rétention'),
      for (final l in visibles) _buildItem(context, l, r),
    ]);
  }
}

/// I21 : liens publics actifs, révocation, prolongation.
class _Liens extends StatefulWidget {
  const _Liens(this.recherche);
  final String recherche;

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

  String _titreLien(Map<String, dynamic> l) => (l['titre'] ?? TypeEl.libelles[l['typeElement']] ?? 'Élément').toString().split('\n').first;

  String _sousTitreLien(Map<String, dynamic> l) =>
      '${l['nbTelechargements']} ouverture(s) · ${l['expireLe'] == null ? 'sans limite' : 'expire ${dateCourte(l['expireLe'] as String)}'}';

  @override
  Widget build(BuildContext context) {
    final r = widget.recherche;
    final actifs = _liens.where((l) => l['statut'] == 'ACTIF').toList();
    final filtres = _filtrerPar(actifs, r, (l) => '${_titreLien(l)} ${_sousTitreLien(l)}');
    if (r.isNotEmpty && !concorde('Liens publics', r) && filtres.isEmpty) return const SizedBox.shrink();
    final children = <Widget>[_Titre('Liens publics')];
    if (filtres.isNotEmpty) {
      children.addAll([
        for (final l in filtres)
          ListTile(
            leading: Icon(l['protegeParMotDePasse'] == true ? Icons.lock : Icons.link),
            title: TexteSurligne(_titreLien(l), r, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: TexteSurligne(_sousTitreLien(l), r),
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
      ]);
    } else if (r.isEmpty) {
      children.add(const ListTile(
        leading: Icon(Icons.link_off),
        title: Text('Aucun lien actif'),
        subtitle: Text('Partagez un post-it, un snippet, une liste ou un fichier depuis son menu.'),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
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

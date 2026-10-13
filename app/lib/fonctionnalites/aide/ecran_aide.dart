import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../noyau/noyau.dart';
import '../../ui/commun.dart';
import '../../ui/recherche_locale.dart';
import '../../ui/theme.dart';

/// UC-I22 : centre d'aide in-app (FAQ filtrable, raccourcis, confidentialité, contact).
///
/// Chaque réponse a été vérifiée dans le code ou les docs (sources en commentaire).
void ouvrirAide(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EcranAide()));

/// Adresse de contact du support. À COMPLÉTER avant la mise en production
/// (même placeholder que public/confidentialite.html).
const String? emailSupport = null;

class _Question {
  const _Question(this.question, this.reponse, {this.motsCles = ''});
  final String question;
  final String reponse;

  /// Termes supplémentaires pour le filtre (non affichés).
  final String motsCles;

  bool correspond(String r) => concorde(question, r) || concorde(reponse, r) || concorde(motsCles, r);
}


const _faq = <_Question>[
  // docs/01 A1, A3, I15 ; ecrans_auth.dart
  _Question(
    'Qui peut lire mes contenus ?',
    'Personne d\'autre que vous. Vos contenus sont chiffrés sur vos appareils avant tout envoi '
        '(chiffrement de bout en bout) : le serveur ne stocke que des données illisibles.',
    motsCles: 'chiffrement E2EE sécurité confidentialité serveur',
  ),
  _Question(
    'À quoi sert la clé de récupération ?',
    'Elle est créée à l\'inscription et n\'est affichée qu\'une fois : rangez-la dans un gestionnaire de mots de passe '
        'ou sur papier. Elle permet de déverrouiller un nouvel appareil et de garder vos contenus après un mot de passe oublié. '
        'Sans elle ni autre appareil connecté, vos contenus sont définitivement perdus. '
        'Vous pouvez en générer une nouvelle dans Réglages › Sécurité ; l\'ancienne cesse alors de fonctionner.',
    motsCles: 'mot de passe oublié perte récupération chiffrement',
  ),
  // backend appareils/models.py LIMITE_APPAREILS_ACTIFS = 3 ; deverrouillage.py (6 chiffres, 10 min)
  _Question(
    'Combien d\'appareils puis-je utiliser ?',
    'Jusqu\'à 3 appareils par compte. Au-delà, révoquez-en un depuis Réglages › Appareils sur un appareil connecté.',
    motsCles: 'limite révoquer téléphone ordinateur',
  ),
  _Question(
    'Comment ajouter un nouvel appareil ?',
    'Connectez-vous sur le nouvel appareil : il affiche un code à 6 chiffres, valable 10 minutes. '
        'Sur un appareil déjà connecté, ouvrez Réglages › Appareils, puis approuvez la demande en recopiant ce code. '
        'Vous pouvez aussi saisir votre clé de récupération à la place.',
    motsCles: 'déverrouiller approuver code appareil',
  ),
  // docs/01 A0, I3
  _Question(
    'Puis-je utiliser LuluBoard sans compte ?',
    'Oui. Sans compte, vos données restent uniquement sur cet appareil : pas de synchronisation, pas d\'envoi entre appareils. '
        'Les fichiers et les liens publics sont réservés aux comptes. '
        'En créant un compte, vous pouvez conserver vos données locales ou repartir de zéro.',
    motsCles: 'visiteur mode sans compte inscription',
  ),
  // backend fichiers/services.py TAILLE_MAX_FICHIER ; docs/01 E1, E2
  _Question(
    'Quelle taille de fichier puis-je envoyer ?',
    '100 Mo maximum par fichier, sans limite sur le nombre total. Chaque fichier est chiffré sur votre appareil avant l\'envoi. '
        'La suppression d\'un fichier est immédiate et définitive (pas de corbeille).',
    motsCles: 'fichiers limite quota taille 100 Mo',
  ),
  // backend liens/services.py DUREES ; actions_element.dart ; docs/01 E3, H4, I19, I21
  _Question(
    'Comment fonctionnent les liens publics ?',
    'Avec un compte, partagez un fichier, un post-it, un snippet ou une liste de tâches par lien, en lecture seule. '
        'Durée au choix : 30 minutes, 1 heure, 24 heures, 7 jours, 30 jours, 90 jours ou sans limite. '
        'Un mot de passe facultatif protège le lien : sans lui, même le lien complet ne suffit pas à lire le contenu. '
        'Suivez, prolongez ou révoquez vos liens dans Réglages › Liens publics.',
    motsCles: 'partage lien public expiration mot de passe révoquer',
  ),
  // docs/01 G1, I8 ; moteur_synchro.dart
  _Question(
    'LuluBoard fonctionne-t-il hors ligne ?',
    'Oui, tout reste utilisable sans réseau. Vos modifications sont synchronisées automatiquement au retour de la connexion. '
        'En cas de conflit, la dernière modification l\'emporte et les versions précédentes des post-it restent dans leur historique.',
    motsCles: 'hors ligne synchronisation réseau conflit',
  ),
  // backend elements/taches.py purger_retention ; ecran_reglages.dart _Retention
  _Question(
    'Combien de temps l\'historique du presse-papier est-il gardé ?',
    'Avec un compte, les entrées non épinglées sont supprimées après la durée choisie dans Réglages › Rétention : '
        'illimitée, 90 jours, 30 jours (par défaut), 7 jours, 24 heures ou 30 minutes. Les entrées épinglées sont toujours gardées. '
        'Sans compte, l\'historique reste sur cet appareil jusqu\'à ce que vous le supprimiez.',
    motsCles: 'rétention presse-papier historique épingler conservation',
  ),
];

class _Raccourci {
  const _Raccourci(this.touches, this.action, {this.ordinateurSeulement = false});
  final String touches;
  final String action;
  final bool ordinateurSeulement;
}

// coquille.dart (Ctrl+K), recherche_locale.dart (Ctrl+F, Échap), plateformes/desktop_io.dart (Ctrl+Alt+B / N)
const _raccourcis = <_Raccourci>[
  _Raccourci('Ctrl+K', 'Rechercher partout'),
  _Raccourci('Ctrl+F', 'Filtrer la liste de l\'écran (presse-papier, post-it, fichiers…)'),
  _Raccourci('Ctrl+Alt+B', 'Ouvrir LuluBoard sur l\'historique du presse-papier, depuis n\'importe quelle application', ordinateurSeulement: true),
  _Raccourci('Ctrl+Alt+N', 'Capture rapide d\'une note, depuis n\'importe quelle application', ordinateurSeulement: true),
  _Raccourci('Échap', 'Vider le filtre, fermer la recherche ou la capture rapide'),
];

class EcranAide extends StatefulWidget {
  const EcranAide({super.key});

  @override
  State<EcranAide> createState() => _EcranAideState();
}

class _EcranAideState extends State<EcranAide> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  String _recherche = '';

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _vider() {
    _ctrl.clear();
    setState(() => _recherche = '');
  }

  @override
  Widget build(BuildContext context) {
    final r = _recherche;
    final desktop = context.noyau.estDesktop;
    final questions = [for (final q in _faq) if (q.correspond(r)) q];
    final raccourcis = [
      for (final k in _raccourcis)
        if (concorde(k.touches, r) || concorde(k.action, r) || concorde('Raccourcis clavier', r)) k,
    ];
    final contactVisible = concorde('Contact support aide e-mail', r);
    final confidentialiteVisible = concorde('Politique de confidentialité données personnelles', r);
    final rien = questions.isEmpty && raccourcis.isEmpty && !contactVisible && !confidentialiteVisible;

    return Scaffold(
      appBar: AppBar(title: const Text('Aide et raccourcis')),
      body: RaccourciFiltre(
        focusNode: _focus,
        child: Column(
          children: [
            ChampRecherche(
              controller: _ctrl,
              focusNode: _focus,
              indice: 'Rechercher dans l\'aide (Ctrl+F)',
              onChanged: (v) => setState(() => _recherche = v.trim()),
            ),
            Expanded(
              child: rien
                  ? AucunResultat(recherche: r, onVider: _vider)
                  : Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: ListView(
                          padding: const EdgeInsets.only(bottom: Lulu.lg),
                          children: [
                            if (questions.isNotEmpty) ...[
                              const _Titre('Questions fréquentes'),
                              for (final q in questions)
                                ExpansionTile(
                                  key: ValueKey('${q.question}|${r.isNotEmpty}'),
                                  initiallyExpanded: r.isNotEmpty,
                                  title: TexteSurligne(q.question, r),
                                  childrenPadding: const EdgeInsets.fromLTRB(Lulu.md, 0, Lulu.md, Lulu.md),
                                  expandedAlignment: Alignment.centerLeft,
                                  children: [TexteSurligne(q.reponse, r, style: Theme.of(context).textTheme.bodyMedium)],
                                ),
                            ],
                            if (raccourcis.isNotEmpty) ...[
                              const _Titre('Raccourcis'),
                              for (final k in raccourcis)
                                ListTile(
                                  leading: _Touche(k.touches, r),
                                  title: TexteSurligne(k.action, r),
                                  subtitle: k.ordinateurSeulement
                                      ? Text(desktop ? 'Ordinateur uniquement' : 'Disponible sur l\'app ordinateur')
                                      : null,
                                ),
                            ],
                            if (confidentialiteVisible || contactVisible) const _Titre('Nous joindre'),
                            if (confidentialiteVisible)
                              ListTile(
                                leading: const Icon(Icons.privacy_tip_outlined),
                                title: TexteSurligne('Politique de confidentialité', r),
                                subtitle: const Text('Données collectées, durées de conservation, vos droits'),
                                trailing: const Icon(Icons.open_in_new, size: 18),
                                onTap: () => _ouvrirConfidentialite(context),
                              ),
                            if (contactVisible)
                              ListTile(
                                leading: const Icon(Icons.mail_outline),
                                title: TexteSurligne('Contacter le support', r),
                                subtitle: Text(emailSupport ??
                                    '[Adresse de contact à compléter] — le formulaire de contact arrive bientôt'),
                                onTap: emailSupport == null
                                    ? null
                                    : () => launchUrl(Uri(scheme: 'mailto', path: emailSupport)),
                              ),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// L'URL de la politique est publiée par le serveur (GET /conditions/actuelles, type POLITIQUE_CONFIDENTIALITE).
  Future<void> _ouvrirConfidentialite(BuildContext context) async {
    try {
      final conditions = await context.noyau.compte.conditionsActuelles();
      final politique = conditions.cast<Map<String, dynamic>>().where((c) => c['type'] == 'POLITIQUE_CONFIDENTIALITE');
      if (politique.isEmpty) throw StateError('absente');
      final ok = await launchUrl(Uri.parse(politique.first['urlTexte'] as String));
      if (!ok && context.mounted) afficherMessage(context, 'Impossible d\'ouvrir la page. Réessayez plus tard.');
    } catch (_) {
      if (context.mounted) {
        afficherMessage(context, 'La politique de confidentialité n\'est pas disponible pour le moment. Vérifiez votre connexion.');
      }
    }
  }
}

class _Titre extends StatelessWidget {
  const _Titre(this.texte);
  final String texte;

  @override
  Widget build(BuildContext context) => Semantics(
        header: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Lulu.md, Lulu.lg, Lulu.md, Lulu.sm),
          child: Text(texte, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
        ),
      );
}

/// Touches d'un raccourci, façon touche de clavier.
class _Touche extends StatelessWidget {
  const _Touche(this.touches, this.recherche);
  final String touches;
  final String recherche;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 96),
      padding: const EdgeInsets.symmetric(horizontal: Lulu.sm, vertical: Lulu.xs),
      decoration: BoxDecoration(
        color: s.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(Lulu.rSm),
        border: Border.all(color: s.outlineVariant),
      ),
      child: TexteSurligne(touches, recherche, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600)),
    );
  }
}

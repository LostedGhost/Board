import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../noyau/api/client_api.dart';
import '../../ui/commun.dart';
import '../../ui/theme.dart';

// --- Mot de passe : règles partagées (inscription, réinitialisation, réglages) -----------------

/// Règles du mot de passe, affichées en direct et vérifiées par [validerMotDePasse].
final reglesMotDePasse = <({String libelle, bool Function(String) respectee})>[
  (libelle: '8 caractères minimum', respectee: (v) => v.length >= 8),
  (libelle: 'Au moins une majuscule', respectee: (v) => RegExp(r'[A-ZÀ-Ý]').hasMatch(v)),
  (libelle: 'Au moins un chiffre', respectee: (v) => RegExp(r'\d').hasMatch(v)),
];

/// Renvoie le premier problème du mot de passe, ou null s'il est valide.
String? validerMotDePasse(String? v) {
  for (final r in reglesMotDePasse) {
    if (!r.respectee(v ?? '')) return r.libelle;
  }
  return null;
}

final expressionEmail = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Police à chasse fixe : 'monospace' existe sur Android/Linux, les replis couvrent Windows et Apple.
const styleMono = TextStyle(
  fontFamily: 'monospace',
  fontFamilyFallback: ['Consolas', 'Menlo', 'SF Mono', 'Courier New', 'Courier'],
);

// --- Erreurs : placées sous le champ concerné ---------------------------------------------------

/// Répartit une erreur d'API sur les champs d'un formulaire.
/// [parChamp] : nom du champ dans le contrat → clé locale ; [parCode] : code d'erreur → clé locale.
/// Renvoie une table vide si l'erreur ne concerne aucun champ (à afficher alors en message général).
Map<String, String> erreursDeChamps(
  Object e, {
  Map<String, String> parChamp = const {},
  Map<String, String> parCode = const {},
}) {
  if (e is! ErreurApi) return const {};
  final sortie = <String, String>{};
  for (final c in e.champs ?? const []) {
    if (c is! Map) continue;
    final cle = parChamp[c['champ']];
    if (cle == null) continue;
    sortie[cle] = switch (c['raison']) {
      'deja_utilise' => 'Cette adresse est déjà utilisée. Connectez-vous plutôt.',
      'trop_court' => '8 caractères minimum',
      _ => messageErreur(e),
    };
  }
  final cleCode = parCode[e.code];
  if (cleCode != null) sortie.putIfAbsent(cleCode, () => messageErreur(e));
  return sortie;
}

// --- Mise en page ---------------------------------------------------------------------------

class LogoLuluBoard extends StatelessWidget {
  const LogoLuluBoard({super.key, this.taille = 36});

  final double taille;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'LuluBoard',
        excludeSemantics: true,
        child: Text(
          'LuluBoard',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: Lulu.policeMarque,
            fontSize: taille,
            height: 1.1,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );
}

class BadgeChiffrement extends StatelessWidget {
  const BadgeChiffrement({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final couleur = t.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.lock_outline, size: 16, color: couleur),
        const SizedBox(width: Lulu.xs),
        Text('Chiffré de bout en bout', style: t.textTheme.bodySmall?.copyWith(color: couleur)),
      ],
    );
  }
}

/// Cadre commun des écrans de compte : centré, 440 px max, logo, titre, rassurance.
class CadreAuth extends StatelessWidget {
  const CadreAuth({
    super.key,
    required this.titre,
    required this.enfants,
    this.sousTitre,
    this.actions,
    this.peutRevenir = true,
  });

  final String titre;
  final String? sousTitre;
  final List<Widget> enfants;
  final List<Widget>? actions;
  final bool peutRevenir;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: peutRevenir, actions: actions, shape: const Border()),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: Lulu.lg, vertical: Lulu.md),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const LogoLuluBoard(),
                  const SizedBox(height: Lulu.lg),
                  Semantics(
                    header: true,
                    child: Text(titre, style: t.textTheme.headlineSmall, textAlign: TextAlign.center),
                  ),
                  if (sousTitre != null) ...[
                    const SizedBox(height: Lulu.sm),
                    Text(
                      sousTitre!,
                      style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: Lulu.lg),
                  ...enfants,
                  const SizedBox(height: Lulu.xl),
                  const BadgeChiffrement(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bouton principal : désactivé avec indicateur pendant l'appel.
class BoutonPrincipal extends StatelessWidget {
  const BoutonPrincipal({super.key, required this.libelle, required this.onPressed, this.enCours = false});

  final String libelle;
  final VoidCallback? onPressed;
  final bool enCours;

  @override
  Widget build(BuildContext context) => Semantics(
        label: enCours ? '$libelle, en cours' : null,
        child: FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: enCours ? null : onPressed,
          child: enCours
              ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(libelle),
        ),
      );
}

/// Message d'erreur hors champ (ex. sous une case à cocher), annoncé par les lecteurs d'écran.
class TexteErreur extends StatelessWidget {
  const TexteErreur(this.texte, {super.key});

  final String texte;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.only(top: Lulu.xs),
        child: Text(texte, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.error)),
      ),
    );
  }
}

// --- Champs ----------------------------------------------------------------------------------

/// Champ mot de passe avec bouton afficher/masquer.
class ChampMotDePasse extends StatefulWidget {
  const ChampMotDePasse({
    super.key,
    required this.controleur,
    this.libelle = 'Mot de passe',
    this.nouveau = false,
    this.focus,
    this.erreur,
    this.action = TextInputAction.done,
    this.onSubmitted,
    this.onChanged,
    this.autofocus = false,
  });

  final TextEditingController controleur;
  final String libelle;

  /// Création d'un mot de passe : suggestion du gestionnaire de mots de passe (newPassword).
  final bool nouveau;
  final FocusNode? focus;
  final String? erreur;
  final TextInputAction action;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final bool autofocus;

  @override
  State<ChampMotDePasse> createState() => _ChampMotDePasseState();
}

class _ChampMotDePasseState extends State<ChampMotDePasse> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) => TextField(
        controller: widget.controleur,
        focusNode: widget.focus,
        autofocus: widget.autofocus,
        obscureText: !_visible,
        enableSuggestions: false,
        autocorrect: false,
        keyboardType: TextInputType.visiblePassword,
        autofillHints: [widget.nouveau ? AutofillHints.newPassword : AutofillHints.password],
        textInputAction: widget.action,
        onSubmitted: widget.onSubmitted,
        onChanged: widget.onChanged,
        decoration: InputDecoration(
          labelText: widget.libelle,
          errorText: widget.erreur,
          errorMaxLines: 3,
          suffixIcon: IconButton(
            tooltip: _visible ? 'Masquer le mot de passe' : 'Afficher le mot de passe',
            icon: Icon(_visible ? Icons.visibility_off_outlined : Icons.visibility_outlined),
            onPressed: () => setState(() => _visible = !_visible),
          ),
        ),
      );
}

/// Règles et force du mot de passe, mises à jour à chaque frappe.
class ReglesMotDePasse extends StatelessWidget {
  const ReglesMotDePasse({super.key, required this.motDePasse});

  final String motDePasse;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final respectees = reglesMotDePasse.where((r) => r.respectee(motDePasse)).length;
    final valide = validerMotDePasse(motDePasse) == null;
    final solide = valide && motDePasse.length >= 12;
    final (niveau, couleur, valeur) = motDePasse.isEmpty
        ? ('', cs.outline, 0.0)
        : solide
            ? ('Solide', cs.primary, 1.0)
            : valide
                ? ('Correct — 12 caractères ou plus le rendent plus solide', cs.primary, 0.75)
                : ('Trop faible', cs.error, (respectees / reglesMotDePasse.length) * 0.6);
    return Padding(
      padding: const EdgeInsets.only(top: Lulu.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            label: motDePasse.isEmpty ? null : 'Force du mot de passe : $niveau',
            excludeSemantics: true,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Lulu.rSm),
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: valeur),
                duration: Lulu.normal,
                builder: (_, v, _) => LinearProgressIndicator(
                  value: v,
                  minHeight: 4,
                  color: couleur,
                  backgroundColor: cs.outlineVariant,
                ),
              ),
            ),
          ),
          if (niveau.isNotEmpty) ...[
            const SizedBox(height: Lulu.xs),
            ExcludeSemantics(child: Text(niveau, style: t.textTheme.bodySmall?.copyWith(color: couleur))),
          ],
          const SizedBox(height: Lulu.xs),
          for (final r in reglesMotDePasse)
            Builder(builder: (context) {
              final ok = r.respectee(motDePasse);
              return Semantics(
                label: '${r.libelle} : ${ok ? 'respecté' : 'non respecté'}',
                excludeSemantics: true,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Icon(ok ? Icons.check_circle : Icons.radio_button_unchecked,
                          size: 16, color: ok ? cs.primary : cs.onSurfaceVariant),
                      const SizedBox(width: Lulu.sm),
                      Text(r.libelle,
                          style: t.textTheme.bodySmall?.copyWith(color: ok ? cs.onSurface : cs.onSurfaceVariant)),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

/// Code à 6 chiffres : champ unique grand format, chiffres seulement, [onComplet] dès le 6e chiffre.
class ChampCode extends StatelessWidget {
  const ChampCode({
    super.key,
    required this.controleur,
    required this.onComplet,
    this.focus,
    this.erreur,
    this.autofocus = false,
    this.libelle = 'Code à 6 chiffres',
    this.actif = true,
  });

  final TextEditingController controleur;
  final ValueChanged<String> onComplet;
  final FocusNode? focus;
  final String? erreur;
  final bool autofocus;
  final String libelle;
  final bool actif;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controleur,
        focusNode: focus,
        autofocus: autofocus,
        enabled: actif,
        keyboardType: TextInputType.number,
        autofillHints: const [AutofillHints.oneTimeCode],
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
        maxLength: 6,
        textAlign: TextAlign.center,
        textInputAction: TextInputAction.done,
        style: styleMono.copyWith(fontSize: 32, letterSpacing: 12, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          labelText: libelle,
          hintText: '000000',
          counterText: '',
          errorText: erreur,
          errorMaxLines: 3,
        ),
        onChanged: (v) {
          if (v.length == 6) onComplet(v);
        },
        onSubmitted: onComplet,
      );
}

/// « Renvoyer le code » avec décompte, pour éviter les envois répétés (et les refus 429).
class BoutonRenvoyerCode extends StatefulWidget {
  const BoutonRenvoyerCode({super.key, required this.renvoyer, this.delai = 60, this.demarrerDecompte = true});

  /// Renvoie true si l'envoi a réussi (le décompte repart alors).
  final Future<bool> Function() renvoyer;
  final int delai;
  final bool demarrerDecompte;

  @override
  State<BoutonRenvoyerCode> createState() => _BoutonRenvoyerCodeState();
}

class _BoutonRenvoyerCodeState extends State<BoutonRenvoyerCode> {
  Timer? _minuterie;
  int _restant = 0;
  bool _envoi = false;

  @override
  void initState() {
    super.initState();
    if (widget.demarrerDecompte) _demarrer();
  }

  void _demarrer() {
    _minuterie?.cancel();
    setState(() => _restant = widget.delai);
    _minuterie = Timer.periodic(const Duration(seconds: 1), (m) {
      if (!mounted) return m.cancel();
      setState(() => _restant--);
      if (_restant <= 0) m.cancel();
    });
  }

  @override
  void dispose() {
    _minuterie?.cancel();
    super.dispose();
  }

  Future<void> _appuyer() async {
    setState(() => _envoi = true);
    final ok = await widget.renvoyer();
    if (!mounted) return;
    setState(() => _envoi = false);
    if (ok) _demarrer();
  }

  @override
  Widget build(BuildContext context) {
    final attente = _restant > 0;
    final m = _restant ~/ 60, s = (_restant % 60).toString().padLeft(2, '0');
    return TextButton.icon(
      onPressed: attente || _envoi ? null : _appuyer,
      icon: _envoi
          ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.refresh, size: 18),
      label: Text(attente ? 'Renvoyer le code dans $m:$s' : 'Renvoyer le code'),
    );
  }
}

// --- Clé de récupération --------------------------------------------------------------------

/// Clé de récupération : lisible par lecteur d'écran (groupe par groupe, caractère par caractère),
/// sélectionnable, copiable et téléchargeable en .txt.
class AffichageCleRecuperation extends StatelessWidget {
  const AffichageCleRecuperation({super.key, required this.cle});

  final String cle;

  List<String> get _groupes => cle.split('-').where((g) => g.isNotEmpty).toList();

  String get _libelleSemantique {
    final g = _groupes;
    final parties = [
      for (var i = 0; i < g.length; i++) 'groupe ${i + 1} : ${g[i].split('').join(' ')}',
    ];
    return 'Clé de récupération, ${g.length} groupes de caractères. ${parties.join('. ')}.';
  }

  Future<void> _copier(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: cle));
    if (context.mounted) afficherMessage(context, 'Clé copiée — collez-la dans votre gestionnaire de mots de passe');
  }

  Future<void> _telecharger(BuildContext context) async {
    final date = DateTime.now();
    final jour = '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    final contenu = 'LuluBoard — clé de récupération\r\n'
        'Créée le $jour\r\n\r\n'
        '$cle\r\n\r\n'
        'Vos données sont chiffrées de bout en bout. Si vous oubliez votre mot de passe ET perdez tous vos '
        'appareils, seule cette clé permet de les retrouver.\r\n'
        'Rangez ce fichier hors de cet appareil (gestionnaire de mots de passe, clé USB, papier) '
        'et ne le communiquez à personne : LuluBoard ne vous la demandera jamais.\r\n';
    try {
      final chemin = await FilePicker.saveFile(
        fileName: 'luluboard-cle-recuperation.txt',
        bytes: Uint8List.fromList(utf8.encode(contenu)),
        mimeType: 'text/plain',
        dialogTitle: 'Enregistrer la clé de récupération',
      );
      if (!context.mounted) return;
      if (kIsWeb || (chemin != null && chemin.scheme != 'file')) {
        afficherMessage(context, 'Fichier téléchargé — rangez-le hors de cet appareil, puis cochez la case ci-dessous.');
      } else if (chemin != null) {
        afficherMessage(context,
            'Clé enregistrée dans ${chemin.toFilePath()} — rangez ce fichier hors de cet appareil, puis cochez la case ci-dessous.');
      }
    } catch (_) {
      if (context.mounted) afficherMessage(context, 'Enregistrement impossible. Copiez la clé à la place.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: Lulu.md, vertical: Lulu.lg),
          decoration: BoxDecoration(
            color: t.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(Lulu.rLg),
            border: Border.all(color: t.colorScheme.outlineVariant),
          ),
          child: Semantics(
            label: _libelleSemantique,
            excludeSemantics: true,
            child: SelectableText(
              _groupes.join('  '),
              textAlign: TextAlign.center,
              style: styleMono.copyWith(fontSize: 20, height: 1.8, letterSpacing: 1.5, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: Lulu.sm),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: Lulu.sm,
          runSpacing: Lulu.sm,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copier'),
              onPressed: () => _copier(context),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.download, size: 18),
              label: const Text('Télécharger en .txt'),
              onPressed: () => _telecharger(context),
            ),
          ],
        ),
      ],
    );
  }
}

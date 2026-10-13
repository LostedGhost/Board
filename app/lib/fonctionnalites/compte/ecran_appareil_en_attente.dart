import 'dart:async';

import 'package:flutter/material.dart';

import '../../noyau/api/client_api.dart';
import '../../noyau/noyau.dart';
import '../../ui/commun.dart';
import '../../ui/theme.dart';
import 'composants_auth.dart';

/// I11 : un nouvel appareil se déverrouille depuis un appareil déjà connecté (code à recopier),
/// ou avec la clé de récupération.
class EcranAppareilEnAttente extends StatefulWidget {
  const EcranAppareilEnAttente({super.key});

  @override
  State<EcranAppareilEnAttente> createState() => _EcranAppareilEnAttenteState();
}

class _EcranAppareilEnAttenteState extends State<EcranAppareilEnAttente> {
  String? _code;
  DateTime? _expire;
  Timer? _interrogation;
  Timer? _decompte;
  Duration _restant = Duration.zero;
  bool _interrogationEnCours = false;
  bool _demande = false;

  final _cle = TextEditingController();
  bool _parCle = false;
  bool _deverrouillage = false;
  String? _erreurCle;

  bool get _codeExpire => _expire != null && _restant <= Duration.zero;

  @override
  void dispose() {
    _arreter();
    _cle.dispose();
    super.dispose();
  }

  void _arreter() {
    _interrogation?.cancel();
    _decompte?.cancel();
    _interrogation = null;
    _decompte = null;
  }

  void _majDecompte() {
    final e = _expire;
    if (e == null) return;
    final r = e.difference(DateTime.now());
    setState(() => _restant = r.isNegative ? Duration.zero : r);
    if (r <= Duration.zero) _arreter();
  }

  Future<void> _demander() async {
    if (_demande) return;
    setState(() => _demande = true);
    final noyau = context.noyau;
    final d = await executer(context, noyau.compte.demanderDeverrouillage);
    if (!mounted) return;
    setState(() => _demande = false);
    if (d == null) return;
    _arreter();
    setState(() {
      _code = d['codeAffiche'] as String;
      _expire = DateTime.tryParse(d['expireLe'] as String? ?? '')?.toLocal();
    });
    _majDecompte();
    _decompte = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) _majDecompte();
    });
    _interrogation = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (_interrogationEnCours) return;
      _interrogationEnCours = true;
      try {
        if (await noyau.compte.verifierDeverrouillage()) _arreter();
      } catch (_) {
        // Erreur passagère : on réessaie au prochain tour.
      } finally {
        _interrogationEnCours = false;
      }
    });
  }

  void _annuler() {
    _arreter();
    setState(() {
      _code = null;
      _expire = null;
    });
  }

  Future<void> _deverrouillerParCle() async {
    if (_deverrouillage) return;
    if (_cle.text.trim().isEmpty) {
      setState(() => _erreurCle = 'Saisissez votre clé de récupération');
      return;
    }
    setState(() {
      _deverrouillage = true;
      _erreurCle = null;
    });
    try {
      await context.noyau.compte.deverrouillerParRecuperation(_cle.text);
      if (mounted) afficherMessage(context, 'Appareil déverrouillé.');
    } on ErreurApi catch (e) {
      if (!mounted) return;
      if (e.code == 'cle_recuperation_incorrecte') {
        setState(() => _erreurCle = 'Clé incorrecte. Vérifiez chaque groupe (les tirets et espaces sont facultatifs).');
      } else {
        afficherMessage(context, messageErreur(e));
      }
    } catch (e) {
      if (mounted) setState(() => _erreurCle = 'Clé illisible. Vérifiez qu\'elle est complète.');
    } finally {
      if (mounted) setState(() => _deverrouillage = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final noyau = context.noyau;
    final t = Theme.of(context);
    return CadreAuth(
      titre: 'Déverrouiller cet appareil',
      sousTitre: 'Vos données sont chiffrées de bout en bout. Pour les lire ici, cet appareil doit recevoir '
          'votre clé de façon sécurisée.',
      peutRevenir: false,
      actions: [TextButton(onPressed: noyau.compte.deconnecter, child: const Text('Se déconnecter'))],
      enfants: _parCle ? _modeCle(t) : _modeAppareil(t),
    );
  }

  List<Widget> _modeAppareil(ThemeData t) {
    final code = _code;
    return [
      Semantics(header: true, child: Text('Depuis un appareil déjà connecté', style: t.textTheme.titleMedium)),
      const SizedBox(height: Lulu.md),
      if (code == null) ...[
        Text(
          'Un code à 6 chiffres va s\'afficher ici. Vous le recopierez sur un appareil où vous êtes déjà connecté '
          '(3 appareils maximum par compte).',
          style: t.textTheme.bodyMedium,
        ),
        const SizedBox(height: Lulu.md),
        BoutonPrincipal(libelle: 'Afficher un code', enCours: _demande, onPressed: _demander),
      ] else ...[
        _CodeAffiche(code: code, expire: _codeExpire),
        const SizedBox(height: Lulu.sm),
        if (_expire != null)
          Semantics(
            liveRegion: _codeExpire,
            child: Text(
              _codeExpire
                  ? 'Ce code a expiré.'
                  : 'Expire dans ${_restant.inMinutes}:${(_restant.inSeconds % 60).toString().padLeft(2, '0')}',
              textAlign: TextAlign.center,
              style: t.textTheme.bodySmall?.copyWith(
                color: _codeExpire ? t.colorScheme.error : t.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        const SizedBox(height: Lulu.lg),
        if (_codeExpire)
          BoutonPrincipal(libelle: 'Afficher un nouveau code', enCours: _demande, onPressed: _demander)
        else ...[
          const _Etapes(),
          const SizedBox(height: Lulu.lg),
          ClipRRect(
            borderRadius: BorderRadius.circular(Lulu.rSm),
            child: const LinearProgressIndicator(minHeight: 4),
          ),
          const SizedBox(height: Lulu.sm),
          Semantics(
            liveRegion: true,
            child: Text(
              'En attente de l\'approbation… Cet écran se déverrouille tout seul.',
              textAlign: TextAlign.center,
              style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: Lulu.md),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: Lulu.sm,
            runSpacing: Lulu.sm,
            children: [
              OutlinedButton(onPressed: _annuler, child: const Text('Annuler')),
              TextButton(onPressed: _demande ? null : _demander, child: const Text('Nouveau code')),
            ],
          ),
        ],
      ],
      const SizedBox(height: Lulu.lg),
      const Divider(),
      const SizedBox(height: Lulu.sm),
      TextButton.icon(
        icon: const Icon(Icons.key, size: 18),
        onPressed: () {
          _annuler();
          setState(() => _parCle = true);
        },
        label: const Text('Aucun autre appareil ? Utiliser ma clé de récupération'),
      ),
    ];
  }

  List<Widget> _modeCle(ThemeData t) => [
        Semantics(header: true, child: Text('Avec votre clé de récupération', style: t.textTheme.titleMedium)),
        const SizedBox(height: Lulu.sm),
        Text(
          'C\'est la clé affichée à la création de votre compte (groupes de 4 caractères).',
          style: t.textTheme.bodyMedium,
        ),
        const SizedBox(height: Lulu.md),
        TextField(
          controller: _cle,
          autofocus: true,
          minLines: 2,
          maxLines: 3,
          autocorrect: false,
          enableSuggestions: false,
          textCapitalization: TextCapitalization.characters,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: 'Clé de récupération',
            hintText: 'XXXX-XXXX-XXXX-…',
            errorText: _erreurCle,
            errorMaxLines: 3,
          ),
          style: styleMono.copyWith(fontSize: 16, letterSpacing: 1),
          onChanged: (_) {
            if (_erreurCle != null) setState(() => _erreurCle = null);
          },
          onSubmitted: (_) => _deverrouillerParCle(),
        ),
        const SizedBox(height: Lulu.md),
        BoutonPrincipal(libelle: 'Déverrouiller', enCours: _deverrouillage, onPressed: _deverrouillerParCle),
        const SizedBox(height: Lulu.sm),
        TextButton(
          onPressed: _deverrouillage ? null : () => setState(() => _parCle = false),
          child: const Text('Utiliser un autre appareil'),
        ),
      ];
}

/// Code en très grand, groupé « 123 456 », lu chiffre par chiffre.
class _CodeAffiche extends StatelessWidget {
  const _CodeAffiche({required this.code, required this.expire});

  final String code;
  final bool expire;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final groupe = code.length == 6 ? '${code.substring(0, 3)} ${code.substring(3)}' : code;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: Lulu.lg, horizontal: Lulu.md),
      decoration: BoxDecoration(
        color: t.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(Lulu.rLg),
        border: Border.all(color: expire ? t.colorScheme.error : t.colorScheme.outlineVariant),
      ),
      child: Semantics(
        label: '${expire ? 'Code expiré' : 'Code'} : ${code.split('').join(' ')}',
        excludeSemantics: true,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            groupe,
            textAlign: TextAlign.center,
            style: styleMono.copyWith(
              fontSize: 56,
              fontWeight: FontWeight.w700,
              letterSpacing: 6,
              color: expire ? t.colorScheme.onSurfaceVariant : t.colorScheme.onSurface,
              decoration: expire ? TextDecoration.lineThrough : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _Etapes extends StatelessWidget {
  const _Etapes();

  static const _textes = [
    'Sur un appareil déjà connecté : Réglages › Appareils › Approuver.',
    'Saisissez le code ci-dessus sur cet appareil-là.',
    'Revenez ici : l\'accès s\'ouvre en quelques secondes.',
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < _textes.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: Lulu.sm),
            child: Semantics(
              label: 'Étape ${i + 1} : ${_textes[i]}',
              excludeSemantics: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: t.colorScheme.primary.withValues(alpha: 0.18),
                    child: Text('${i + 1}',
                        style: t.textTheme.labelMedium?.copyWith(color: t.colorScheme.primary, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: Lulu.sm + Lulu.xs),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(_textes[i], style: t.textTheme.bodyMedium),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

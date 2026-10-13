import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../noyau/api/client_api.dart';
import '../../noyau/noyau.dart';
import '../../ui/commun.dart';
import '../../ui/theme.dart';
import 'composants_auth.dart';

export 'composants_auth.dart' show validerMotDePasse;

void ouvrirInscription(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EcranInscription()));

void ouvrirConnexion(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EcranConnexion()));

void ouvrirRegenerationCle(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EcranRegenerationCle()));

/// Erreurs liées à un code saisi (incorrect, expiré, trop d'essais) : affichées sous le champ du code.
bool _erreurDeCode(Object e) =>
    e is ErreurApi && (e.statut == 410 || e.statut == 422 || e.code.startsWith('code_'));

// --- Inscription (A1) ----------------------------------------------------------------------

class EcranInscription extends StatefulWidget {
  const EcranInscription({super.key});

  @override
  State<EcranInscription> createState() => _EcranInscriptionState();
}

class _EcranInscriptionState extends State<EcranInscription> {
  final _emailCtrl = TextEditingController();
  final _nomCtrl = TextEditingController();
  final _mdpCtrl = TextEditingController();
  final _focusNom = FocusNode();
  final _focusEmail = FocusNode();
  final _focusMdp = FocusNode();
  bool _accepte = false;
  bool _envoi = false;
  Map<String, String> _erreurs = {};
  List<dynamic> _conditions = [];

  @override
  void initState() {
    super.initState();
    context.noyau.compte.conditionsActuelles().then((c) {
      if (mounted) setState(() => _conditions = c);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    for (final c in [_emailCtrl, _nomCtrl, _mdpCtrl]) {
      c.dispose();
    }
    for (final f in [_focusNom, _focusEmail, _focusMdp]) {
      f.dispose();
    }
    super.dispose();
  }

  void _effacerErreur(String champ) {
    if (_erreurs.containsKey(champ)) setState(() => _erreurs = {..._erreurs}..remove(champ));
  }

  Future<void> _valider() async {
    if (_envoi) return;
    final erreurs = <String, String>{
      if (_nomCtrl.text.trim().isEmpty) 'nom': 'Indiquez un nom',
      if (!expressionEmail.hasMatch(_emailCtrl.text.trim())) 'email': 'Adresse e-mail invalide',
      'mdp': ?validerMotDePasse(_mdpCtrl.text),
      if (!_accepte) 'conditions': 'Acceptez les conditions pour créer votre compte.',
    };
    setState(() => _erreurs = erreurs);
    if (erreurs.isNotEmpty) {
      if (erreurs.containsKey('nom')) {
        _focusNom.requestFocus();
      } else if (erreurs.containsKey('email')) {
        _focusEmail.requestFocus();
      } else if (erreurs.containsKey('mdp')) {
        _focusMdp.requestFocus();
      }
      return;
    }
    setState(() => _envoi = true);
    final noyau = context.noyau;
    try {
      await noyau.compte.inscrire(
        _emailCtrl.text.trim(),
        _nomCtrl.text.trim(),
        _mdpCtrl.text,
        [for (final c in _conditions) c['id'] as String],
      );
      TextInput.finishAutofillContext();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => EcranCodeVerification(email: _emailCtrl.text.trim())),
      );
    } catch (e) {
      if (!mounted) return;
      final parChamp = erreursDeChamps(
        e,
        parChamp: const {'email': 'email', 'nomAffichage': 'nom', 'motDePasse': 'mdp'},
        parCode: const {'email_deja_utilise': 'email'},
      );
      if (parChamp.isEmpty) {
        afficherMessage(context, messageErreur(e));
      } else {
        setState(() => _erreurs = parChamp);
      }
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) => CadreAuth(
        titre: 'Créer un compte',
        sousTitre: 'Synchronisez vos notes, presse-papiers et fichiers sur 3 appareils.',
        enfants: [
          AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _nomCtrl,
                  focusNode: _focusNom,
                  autofocus: true,
                  decoration: InputDecoration(labelText: 'Nom d\'affichage', errorText: _erreurs['nom']),
                  autofillHints: const [AutofillHints.name],
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => _effacerErreur('nom'),
                  onSubmitted: (_) => _focusEmail.requestFocus(),
                ),
                const SizedBox(height: Lulu.md),
                TextField(
                  controller: _emailCtrl,
                  focusNode: _focusEmail,
                  decoration: InputDecoration(
                    labelText: 'Adresse e-mail',
                    errorText: _erreurs['email'],
                    errorMaxLines: 3,
                  ),
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => _effacerErreur('email'),
                  onSubmitted: (_) => _focusMdp.requestFocus(),
                ),
                if (_erreurs['email']?.contains('Connectez-vous') ?? false)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () =>
                          Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const EcranConnexion())),
                      child: const Text('Se connecter avec cette adresse'),
                    ),
                  ),
                const SizedBox(height: Lulu.md),
                ChampMotDePasse(
                  controleur: _mdpCtrl,
                  focus: _focusMdp,
                  nouveau: true,
                  erreur: _erreurs['mdp'],
                  onChanged: (_) => setState(() => _erreurs = {..._erreurs}..remove('mdp')),
                  onSubmitted: (_) => _valider(),
                ),
                ReglesMotDePasse(motDePasse: _mdpCtrl.text),
              ],
            ),
          ),
          const SizedBox(height: Lulu.md),
          CheckboxListTile(
            value: _accepte,
            onChanged: (v) => setState(() {
              _accepte = v ?? false;
              _erreurs = {..._erreurs}..remove('conditions');
            }),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: const Text('J\'accepte les conditions d\'utilisation et la politique de confidentialité'),
            subtitle: _conditions.isEmpty
                ? null
                : Wrap(
                    spacing: Lulu.sm,
                    children: [
                      for (final c in _conditions)
                        TextButton(
                          onPressed: () => launchUrl(Uri.parse(c['urlTexte'] as String)),
                          child: Text(c['type'] == 'CONDITIONS_UTILISATION' ? 'Lire les conditions' : 'Lire la politique'),
                        ),
                    ],
                  ),
          ),
          if (_erreurs['conditions'] case final e?) TexteErreur(e),
          const SizedBox(height: Lulu.md),
          BoutonPrincipal(libelle: 'Créer mon compte', enCours: _envoi, onPressed: _valider),
          const SizedBox(height: Lulu.sm),
          TextButton(
            onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const EcranConnexion())),
            child: const Text('J\'ai déjà un compte'),
          ),
        ],
      );
}

// --- Code à 6 chiffres + clé de récupération (A1) --------------------------------------------

class EcranCodeVerification extends StatefulWidget {
  const EcranCodeVerification({super.key, required this.email});

  final String email;

  @override
  State<EcranCodeVerification> createState() => _EcranCodeVerificationState();
}

class _EcranCodeVerificationState extends State<EcranCodeVerification> {
  final _code = TextEditingController();
  final _focusCode = FocusNode();
  bool _envoi = false;
  bool _conserver = true;
  String? _erreur;

  @override
  void dispose() {
    _code.dispose();
    _focusCode.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    if (_envoi) return;
    if (!RegExp(r'^\d{6}$').hasMatch(_code.text.trim())) {
      setState(() => _erreur = 'Le code contient 6 chiffres.');
      _focusCode.requestFocus();
      return;
    }
    setState(() {
      _envoi = true;
      _erreur = null;
    });
    final noyau = context.noyau;
    try {
      final r = await noyau.compte.verifierInscription(widget.email, _code.text.trim(), noyau.descriptionAppareil,
          conserverDonneesLocales: _conserver);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => EcranCleRecuperation(cle: r.cleRecuperationAffichee, obligatoire: true)),
      );
    } catch (e) {
      if (!mounted) return;
      if (_erreurDeCode(e)) {
        setState(() => _erreur = messageErreur(e));
        // Le code reste sélectionné : la frappe suivante le remplace.
        _code.selection = TextSelection(baseOffset: 0, extentOffset: _code.text.length);
        _focusCode.requestFocus();
      } else {
        afficherMessage(context, messageErreur(e));
      }
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  Future<bool> _renvoyer() async {
    final ok = await executer(context, () async {
      await context.noyau.compte.renvoyerCode(widget.email);
      return true;
    }, succes: 'Nouveau code envoyé à ${widget.email}. Pensez à vérifier vos courriers indésirables.');
    if (ok == true && mounted) {
      _code.clear();
      setState(() => _erreur = null);
      _focusCode.requestFocus();
    }
    return ok == true;
  }

  @override
  Widget build(BuildContext context) => CadreAuth(
        titre: 'Vérifiez votre e-mail',
        sousTitre: 'Saisissez le code à 6 chiffres envoyé à ${widget.email}. Il est valable 15 minutes.',
        enfants: [
          ChampCode(
            controleur: _code,
            focus: _focusCode,
            autofocus: true,
            erreur: _erreur,
            actif: !_envoi,
            onComplet: (_) => _valider(),
          ),
          const SizedBox(height: Lulu.sm),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _conserver,
            onChanged: (v) => setState(() => _conserver = v),
            title: const Text('Conserver les données déjà créées sur cet appareil'),
            subtitle: const Text('Elles seront chiffrées puis synchronisées avec votre compte.'),
          ),
          const SizedBox(height: Lulu.md),
          BoutonPrincipal(libelle: 'Valider', enCours: _envoi, onPressed: _valider),
          const SizedBox(height: Lulu.sm),
          Center(child: BoutonRenvoyerCode(renvoyer: _renvoyer)),
        ],
      );
}

/// Affiche la clé de récupération UNE fois et exige la confirmation de sa sauvegarde (A1, I15).
/// [obligatoire] : comptes e-mail et régénération ; sinon (Google) la sauvegarde peut être reportée.
class EcranCleRecuperation extends StatefulWidget {
  const EcranCleRecuperation({super.key, required this.cle, this.obligatoire = false});

  final String cle;
  final bool obligatoire;

  @override
  State<EcranCleRecuperation> createState() => _EcranCleRecuperationState();
}

class _EcranCleRecuperationState extends State<EcranCleRecuperation> {
  bool _note = false;
  bool _envoi = false;

  Future<void> _terminer() async {
    setState(() => _envoi = true);
    final messager = ScaffoldMessenger.of(context);
    final ok = await executer(context, () async {
      await context.noyau.compte.confirmerCleRecuperation();
      return true;
    });
    if (!mounted) return;
    setState(() => _envoi = false);
    if (ok == true) {
      Navigator.of(context).popUntil((r) => r.isFirst);
      messager
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Clé sauvegardée. Votre compte est prêt et vos données sont synchronisées.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return PopScope(
      canPop: !widget.obligatoire,
      onPopInvokedWithResult: (aQuitte, _) {
        if (!aQuitte) afficherMessage(context, 'Sauvegardez votre clé et cochez la case avant de continuer.');
      },
      child: CadreAuth(
        titre: 'Votre clé de récupération',
        peutRevenir: !widget.obligatoire,
        enfants: [
          Text(
            'Vos données sont chiffrées de bout en bout : personne, pas même LuluBoard, ne peut les lire. '
            'Si vous oubliez votre mot de passe ET perdez tous vos appareils, seule cette clé permet de les retrouver.',
            style: t.textTheme.bodyMedium,
          ),
          const SizedBox(height: Lulu.sm),
          Text(
            'Elle ne sera plus jamais affichée. Rangez-la dans votre gestionnaire de mots de passe ou sur papier.',
            style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: Lulu.lg),
          AffichageCleRecuperation(cle: widget.cle),
          const SizedBox(height: Lulu.lg),
          CheckboxListTile(
            value: _note,
            onChanged: _envoi ? null : (v) => setState(() => _note = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: const Text('J\'ai sauvegardé ma clé de récupération en lieu sûr'),
          ),
          const SizedBox(height: Lulu.sm),
          BoutonPrincipal(libelle: 'Terminer', enCours: _envoi, onPressed: _note ? _terminer : null),
          if (!widget.obligatoire) ...[
            const SizedBox(height: Lulu.sm),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                afficherMessage(context, 'Pensez à sauvegarder votre clé : Réglages › Sécurité.');
              },
              child: const Text('Plus tard'),
            ),
          ],
        ],
      ),
    );
  }
}

// --- Connexion (A2) ------------------------------------------------------------------------

class EcranConnexion extends StatefulWidget {
  const EcranConnexion({super.key});

  @override
  State<EcranConnexion> createState() => _EcranConnexionState();
}

class _EcranConnexionState extends State<EcranConnexion> {
  final _emailCtrl = TextEditingController();
  final _mdpCtrl = TextEditingController();
  final _focusEmail = FocusNode();
  final _focusMdp = FocusNode();
  bool _envoi = false;
  Map<String, String> _erreurs = {};

  @override
  void dispose() {
    _emailCtrl.dispose();
    _mdpCtrl.dispose();
    _focusEmail.dispose();
    _focusMdp.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    if (_envoi) return;
    final erreurs = <String, String>{
      if (!expressionEmail.hasMatch(_emailCtrl.text.trim())) 'email': 'Adresse e-mail invalide',
      if (_mdpCtrl.text.isEmpty) 'mdp': 'Indiquez votre mot de passe',
    };
    setState(() => _erreurs = erreurs);
    if (erreurs.isNotEmpty) {
      (erreurs.containsKey('email') ? _focusEmail : _focusMdp).requestFocus();
      return;
    }
    setState(() => _envoi = true);
    final noyau = context.noyau;
    try {
      await noyau.compte.connecter(_emailCtrl.text.trim(), _mdpCtrl.text, noyau.descriptionAppareil);
      TextInput.finishAutofillContext();
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on ErreurApi catch (e) {
      if (!mounted) return;
      if (e.code == 'email_non_verifie') {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => EcranCodeVerification(email: _emailCtrl.text.trim())),
        );
        return;
      }
      final parChamp = erreursDeChamps(
        e,
        parChamp: const {'email': 'email', 'motDePasse': 'mdp'},
        parCode: const {'identifiants_incorrects': 'mdp'},
      );
      if (parChamp.isEmpty) {
        afficherMessage(context, messageErreur(e));
      } else {
        setState(() => _erreurs = parChamp);
        _focusMdp.requestFocus();
        _mdpCtrl.selection = TextSelection(baseOffset: 0, extentOffset: _mdpCtrl.text.length);
      }
    } catch (e) {
      if (mounted) afficherMessage(context, messageErreur(e));
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) => CadreAuth(
        titre: 'Se connecter',
        sousTitre: 'Retrouvez vos données sur cet appareil.',
        enfants: [
          AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _emailCtrl,
                  focusNode: _focusEmail,
                  autofocus: true,
                  decoration: InputDecoration(labelText: 'Adresse e-mail', errorText: _erreurs['email']),
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  autofillHints: const [AutofillHints.email, AutofillHints.username],
                  textInputAction: TextInputAction.next,
                  onChanged: (_) {
                    if (_erreurs.isNotEmpty) setState(() => _erreurs = {});
                  },
                  onSubmitted: (_) => _focusMdp.requestFocus(),
                ),
                const SizedBox(height: Lulu.md),
                ChampMotDePasse(
                  controleur: _mdpCtrl,
                  focus: _focusMdp,
                  erreur: _erreurs['mdp'],
                  onChanged: (_) {
                    if (_erreurs.containsKey('mdp')) setState(() => _erreurs = {..._erreurs}..remove('mdp'));
                  },
                  onSubmitted: (_) => _valider(),
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => EcranMotDePasseOublie(email: _emailCtrl.text.trim())),
              ),
              child: const Text('Mot de passe oublié ?'),
            ),
          ),
          const SizedBox(height: Lulu.sm),
          BoutonPrincipal(libelle: 'Se connecter', enCours: _envoi, onPressed: _valider),
          const SizedBox(height: Lulu.sm),
          TextButton(
            onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const EcranInscription())),
            child: const Text('Créer un compte'),
          ),
        ],
      );
}

// --- Mot de passe oublié (A3) ----------------------------------------------------------------

class EcranMotDePasseOublie extends StatefulWidget {
  const EcranMotDePasseOublie({super.key, this.email = ''});

  /// Adresse déjà saisie sur l'écran de connexion, reprise pour éviter de la retaper.
  final String email;

  @override
  State<EcranMotDePasseOublie> createState() => _EcranMotDePasseOublieState();
}

class _EcranMotDePasseOublieState extends State<EcranMotDePasseOublie> {
  late final _email = TextEditingController(text: widget.email);
  final _code = TextEditingController();
  final _mdp = TextEditingController();
  final _focusCode = FocusNode();
  final _focusMdp = FocusNode();
  bool _codeEnvoye = false;
  bool _envoi = false;
  Map<String, String> _erreurs = {};

  @override
  void dispose() {
    for (final c in [_email, _code, _mdp]) {
      c.dispose();
    }
    _focusCode.dispose();
    _focusMdp.dispose();
    super.dispose();
  }

  /// Appel inchangé : demande d'un code de réinitialisation.
  Future<void> _demanderCode() => context.noyau.api.post('/auth/mot-de-passe/oubli', {'email': _email.text.trim()});

  Future<void> _envoyerCode() async {
    if (_envoi) return;
    if (!expressionEmail.hasMatch(_email.text.trim())) {
      setState(() => _erreurs = {'email': 'Adresse e-mail invalide'});
      return;
    }
    setState(() {
      _envoi = true;
      _erreurs = {};
    });
    final ok = await executer(context, () async {
      await _demanderCode();
      return true;
    });
    if (!mounted) return;
    setState(() {
      _envoi = false;
      if (ok == true) _codeEnvoye = true;
    });
    if (ok == true) _focusCode.requestFocus();
  }

  Future<bool> _renvoyer() async {
    final ok = await executer(context, () async {
      await _demanderCode();
      return true;
    }, succes: 'Nouveau code envoyé à ${_email.text.trim()}.');
    if (ok == true && mounted) {
      _code.clear();
      setState(() => _erreurs = {..._erreurs}..remove('code'));
      _focusCode.requestFocus();
    }
    return ok == true;
  }

  Future<void> _changer() async {
    if (_envoi) return;
    final erreurs = <String, String>{
      if (!RegExp(r'^\d{6}$').hasMatch(_code.text.trim())) 'code': 'Le code contient 6 chiffres.',
      'mdp': ?validerMotDePasse(_mdp.text),
    };
    setState(() => _erreurs = erreurs);
    if (erreurs.isNotEmpty) {
      (erreurs.containsKey('code') ? _focusCode : _focusMdp).requestFocus();
      return;
    }
    setState(() => _envoi = true);
    final api = context.noyau.api;
    try {
      await api.post('/auth/mot-de-passe/reinitialiser',
          {'email': _email.text.trim(), 'code': _code.text.trim(), 'nouveauMotDePasse': _mdp.text});
      TextInput.finishAutofillContext();
      if (!mounted) return;
      afficherMessage(context, 'Mot de passe changé. Connectez-vous avec le nouveau.');
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      var parChamp = erreursDeChamps(e, parChamp: const {'code': 'code', 'nouveauMotDePasse': 'mdp', 'email': 'email'});
      if (parChamp.isEmpty && _erreurDeCode(e)) parChamp = {'code': messageErreur(e)};
      if (parChamp.isEmpty) {
        afficherMessage(context, messageErreur(e));
      } else {
        setState(() => _erreurs = parChamp);
        if (parChamp.containsKey('code')) _focusCode.requestFocus();
      }
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) => CadreAuth(
        titre: 'Mot de passe oublié',
        sousTitre: _codeEnvoye
            ? 'Code envoyé à ${_email.text.trim()}. Saisissez-le puis choisissez un nouveau mot de passe.'
            : 'Vous allez recevoir un code par e-mail.',
        enfants: [
          if (!_codeEnvoye) ...[
            Text(
              'Vos données restent chiffrées : vous les retrouverez avec votre clé de récupération '
              'ou depuis un autre appareil déjà connecté.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: Lulu.lg),
            TextField(
              controller: _email,
              autofocus: true,
              decoration: InputDecoration(labelText: 'Adresse e-mail', errorText: _erreurs['email']),
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.send,
              onChanged: (_) {
                if (_erreurs.isNotEmpty) setState(() => _erreurs = {});
              },
              onSubmitted: (_) => _envoyerCode(),
            ),
            const SizedBox(height: Lulu.md),
            BoutonPrincipal(libelle: 'Recevoir un code', enCours: _envoi, onPressed: _envoyerCode),
          ] else
            AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ChampCode(
                    controleur: _code,
                    focus: _focusCode,
                    libelle: 'Code reçu par e-mail',
                    erreur: _erreurs['code'],
                    onComplet: (_) {
                      setState(() => _erreurs = {..._erreurs}..remove('code'));
                      _focusMdp.requestFocus();
                    },
                  ),
                  const SizedBox(height: Lulu.md),
                  ChampMotDePasse(
                    controleur: _mdp,
                    focus: _focusMdp,
                    libelle: 'Nouveau mot de passe',
                    nouveau: true,
                    erreur: _erreurs['mdp'],
                    onChanged: (_) => setState(() => _erreurs = {..._erreurs}..remove('mdp')),
                    onSubmitted: (_) => _changer(),
                  ),
                  ReglesMotDePasse(motDePasse: _mdp.text),
                  const SizedBox(height: Lulu.lg),
                  BoutonPrincipal(libelle: 'Changer le mot de passe', enCours: _envoi, onPressed: _changer),
                  const SizedBox(height: Lulu.sm),
                  Wrap(
                    alignment: WrapAlignment.center,
                    children: [
                      BoutonRenvoyerCode(renvoyer: _renvoyer),
                      TextButton(
                        onPressed: _envoi ? null : () => setState(() => _codeEnvoye = false),
                        child: const Text('Modifier l\'adresse'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      );
}

// --- Régénération de la clé de récupération (I15) --------------------------------------------

class EcranRegenerationCle extends StatefulWidget {
  const EcranRegenerationCle({super.key});

  @override
  State<EcranRegenerationCle> createState() => _EcranRegenerationCleState();
}

class _EcranRegenerationCleState extends State<EcranRegenerationCle> {
  final _mdp = TextEditingController();
  bool _compris = false;
  bool _envoi = false;
  String? _erreur;

  @override
  void dispose() {
    _mdp.dispose();
    super.dispose();
  }

  Future<void> _generer() async {
    if (_envoi || !_compris) return;
    if (_mdp.text.isEmpty) {
      setState(() => _erreur = 'Indiquez votre mot de passe actuel');
      return;
    }
    setState(() {
      _envoi = true;
      _erreur = null;
    });
    final compte = context.noyau.compte;
    try {
      final cle = await compte.regenererCleRecuperation(_mdp.text);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => EcranCleRecuperation(cle: cle, obligatoire: true)),
      );
    } catch (e) {
      if (!mounted) return;
      final parChamp = erreursDeChamps(
        e,
        parChamp: const {'motDePasse': 'mdp'},
        parCode: const {'identifiants_incorrects': 'mdp', 'mot_de_passe_incorrect': 'mdp'},
      );
      if (parChamp['mdp'] case final m?) {
        setState(() => _erreur = m);
      } else {
        afficherMessage(context, messageErreur(e));
      }
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) => CadreAuth(
        titre: 'Nouvelle clé de récupération',
        sousTitre: 'Une nouvelle clé va être créée ; l\'ancienne cessera immédiatement de fonctionner.',
        enfants: [
          ChampMotDePasse(
            controleur: _mdp,
            libelle: 'Mot de passe actuel',
            autofocus: true,
            erreur: _erreur,
            onChanged: (_) {
              if (_erreur != null) setState(() => _erreur = null);
            },
            onSubmitted: (_) => _generer(),
          ),
          const SizedBox(height: Lulu.md),
          CheckboxListTile(
            value: _compris,
            onChanged: _envoi ? null : (v) => setState(() => _compris = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: const Text('J\'ai compris : mon ancienne clé ne fonctionnera plus'),
          ),
          const SizedBox(height: Lulu.sm),
          BoutonPrincipal(libelle: 'Générer une nouvelle clé', enCours: _envoi, onPressed: _compris ? _generer : null),
        ],
      );
}

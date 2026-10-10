import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../noyau/api/client_api.dart';
import '../../noyau/noyau.dart';
import '../../ui/commun.dart';

void ouvrirInscription(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EcranInscription()));

void ouvrirConnexion(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EcranConnexion()));

void ouvrirRegenerationCle(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EcranRegenerationCle()));

final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

String? validerMotDePasse(String? v) {
  if (v == null || v.length < 8) return '8 caractères minimum';
  if (!RegExp(r'[A-ZÀ-Ý]').hasMatch(v)) return 'Au moins une majuscule';
  if (!RegExp(r'\d').hasMatch(v)) return 'Au moins un chiffre';
  return null;
}

class _CadreAuth extends StatelessWidget {
  const _CadreAuth({required this.titre, required this.enfants});

  final String titre;
  final List<Widget> enfants;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(titre)),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: enfants),
            ),
          ),
        ),
      );
}

// --- Inscription (A1) ----------------------------------------------------------------------

class EcranInscription extends StatefulWidget {
  const EcranInscription({super.key});

  @override
  State<EcranInscription> createState() => _EcranInscriptionState();
}

class _EcranInscriptionState extends State<EcranInscription> {
  final _form = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _nomCtrl = TextEditingController();
  final _mdpCtrl = TextEditingController();
  bool _accepte = false;
  bool _envoi = false;
  bool _mdpVisible = false;
  List<dynamic> _conditions = [];

  @override
  void initState() {
    super.initState();
    context.noyau.compte.conditionsActuelles().then((c) {
      if (mounted) setState(() => _conditions = c);
    }).catchError((_) {});
  }

  Future<void> _valider() async {
    if (!_form.currentState!.validate()) return;
    if (!_accepte) {
      afficherMessage(context, 'Acceptez les conditions d\'utilisation pour continuer.');
      return;
    }
    setState(() => _envoi = true);
    final ok = await executer(context, () async {
      await context.noyau.compte.inscrire(
        _emailCtrl.text.trim(),
        _nomCtrl.text.trim(),
        _mdpCtrl.text,
        [for (final c in _conditions) c['id'] as String],
      );
      return true;
    });
    if (!mounted) return;
    setState(() => _envoi = false);
    if (ok == true) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => EcranCodeVerification(email: _emailCtrl.text.trim())),
      );
    }
  }

  @override
  Widget build(BuildContext context) => _CadreAuth(
        titre: 'Créer un compte',
        enfants: [
          Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _nomCtrl,
                  decoration: const InputDecoration(labelText: 'Nom d\'affichage'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Indiquez un nom' : null,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailCtrl,
                  decoration: const InputDecoration(labelText: 'Adresse e-mail'),
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  validator: (v) => _email.hasMatch(v?.trim() ?? '') ? null : 'Adresse e-mail invalide',
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _mdpCtrl,
                  obscureText: !_mdpVisible,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: InputDecoration(
                    labelText: 'Mot de passe',
                    helperText: '8 caractères minimum, une majuscule et un chiffre',
                    suffixIcon: IconButton(
                      tooltip: _mdpVisible ? 'Masquer' : 'Afficher',
                      icon: Icon(_mdpVisible ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _mdpVisible = !_mdpVisible),
                    ),
                  ),
                  validator: validerMotDePasse,
                  onFieldSubmitted: (_) => _valider(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            value: _accepte,
            onChanged: (v) => setState(() => _accepte = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: const Text('J\'accepte les conditions d\'utilisation et la politique de confidentialité'),
            subtitle: _conditions.isEmpty
                ? null
                : Wrap(
                    spacing: 8,
                    children: [
                      for (final c in _conditions)
                        TextButton(
                          onPressed: () => launchUrl(Uri.parse(c['urlTexte'] as String)),
                          child: Text(c['type'] == 'CONDITIONS_UTILISATION' ? 'Lire les conditions' : 'Lire la politique'),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _envoi ? null : _valider,
            child: _envoi
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Créer mon compte'),
          ),
          const SizedBox(height: 8),
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
  bool _envoi = false;
  bool _conserver = true;

  Future<void> _valider() async {
    if (!RegExp(r'^\d{6}$').hasMatch(_code.text.trim())) {
      afficherMessage(context, 'Le code contient 6 chiffres.');
      return;
    }
    setState(() => _envoi = true);
    final noyau = context.noyau;
    final r = await executer(
      context,
      () => noyau.compte.verifierInscription(widget.email, _code.text.trim(), noyau.descriptionAppareil,
          conserverDonneesLocales: _conserver),
    );
    if (!mounted) return;
    setState(() => _envoi = false);
    if (r != null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => EcranCleRecuperation(cle: r.cleRecuperationAffichee, obligatoire: true)),
      );
    }
  }

  @override
  Widget build(BuildContext context) => _CadreAuth(
        titre: 'Vérifiez votre e-mail',
        enfants: [
          Text('Nous avons envoyé un code à 6 chiffres à ${widget.email}. Il est valable 15 minutes.'),
          const SizedBox(height: 16),
          TextField(
            controller: _code,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(fontSize: 24, letterSpacing: 8),
            textAlign: TextAlign.center,
            decoration: const InputDecoration(labelText: 'Code'),
            onSubmitted: (_) => _valider(),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _conserver,
            onChanged: (v) => setState(() => _conserver = v),
            title: const Text('Conserver les données déjà créées sur cet appareil'),
            subtitle: const Text('Elles seront chiffrées puis synchronisées avec votre compte.'),
          ),
          const SizedBox(height: 8),
          FilledButton(onPressed: _envoi ? null : _valider, child: const Text('Valider')),
          TextButton(
            onPressed: () => executer(context, () => context.noyau.compte.renvoyerCode(widget.email),
                succes: 'Un nouveau code vous a été envoyé.'),
            child: const Text('Renvoyer un code'),
          ),
        ],
      );
}

/// Affiche la clé de récupération UNE fois et exige la confirmation de sa sauvegarde (A1, I15).
class EcranCleRecuperation extends StatefulWidget {
  const EcranCleRecuperation({super.key, required this.cle, this.obligatoire = false});

  final String cle;
  final bool obligatoire;

  @override
  State<EcranCleRecuperation> createState() => _EcranCleRecuperationState();
}

class _EcranCleRecuperationState extends State<EcranCleRecuperation> {
  bool _note = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return PopScope(
      canPop: !widget.obligatoire,
      child: _CadreAuth(
        titre: 'Votre clé de récupération',
        enfants: [
          const Icon(Icons.key, size: 48),
          const SizedBox(height: 12),
          const Text(
            'Vos données sont chiffrées de bout en bout : personne, pas même LuluBoard, ne peut les lire. '
            'Si vous oubliez votre mot de passe ET perdez tous vos appareils, seule cette clé permet de les retrouver. '
            'Notez-la sur papier ou dans votre gestionnaire de mots de passe.',
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: t.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: SelectableText(widget.cle,
                textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'monospace', fontSize: 18, height: 1.6)),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.copy),
            label: const Text('Copier la clé'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: widget.cle));
              afficherMessage(context, 'Clé copiée. Collez-la dans un endroit sûr, puis effacez-la du presse-papier.');
            },
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            value: _note,
            onChanged: (v) => setState(() => _note = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: const Text('J\'ai sauvegardé ma clé de récupération en lieu sûr'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: !_note
                ? null
                : () async {
                    final ok = await executer(context, () async {
                      await context.noyau.compte.confirmerCleRecuperation();
                      return true;
                    });
                    if (ok == true && context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
                  },
            child: const Text('Terminer'),
          ),
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
  bool _envoi = false;

  Future<void> _valider() async {
    setState(() => _envoi = true);
    final noyau = context.noyau;
    try {
      await noyau.compte.connecter(_emailCtrl.text.trim(), _mdpCtrl.text, noyau.descriptionAppareil);
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on ErreurApi catch (e) {
      if (!mounted) return;
      if (e.code == 'email_non_verifie') {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => EcranCodeVerification(email: _emailCtrl.text.trim())),
        );
      } else {
        afficherMessage(context, messageErreur(e));
      }
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) => _CadreAuth(
        titre: 'Se connecter',
        enfants: [
          TextField(
            controller: _emailCtrl,
            decoration: const InputDecoration(labelText: 'Adresse e-mail'),
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _mdpCtrl,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            decoration: const InputDecoration(labelText: 'Mot de passe'),
            onSubmitted: (_) => _valider(),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _envoi ? null : _valider, child: const Text('Se connecter')),
          TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EcranMotDePasseOublie())),
            child: const Text('Mot de passe oublié ?'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const EcranInscription())),
            child: const Text('Créer un compte'),
          ),
        ],
      );
}

// --- Mot de passe oublié (A3) ----------------------------------------------------------------

class EcranMotDePasseOublie extends StatefulWidget {
  const EcranMotDePasseOublie({super.key});

  @override
  State<EcranMotDePasseOublie> createState() => _EcranMotDePasseOublieState();
}

class _EcranMotDePasseOublieState extends State<EcranMotDePasseOublie> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _mdp = TextEditingController();
  bool _codeEnvoye = false;

  @override
  Widget build(BuildContext context) {
    final api = context.noyau.api;
    return _CadreAuth(
      titre: 'Mot de passe oublié',
      enfants: [
        const Text(
          'Vous allez recevoir un code par e-mail. Important : vos données restent chiffrées. '
          'Vous les retrouverez avec votre clé de récupération ou depuis un autre appareil déjà connecté.',
        ),
        const SizedBox(height: 16),
        TextField(controller: _email, decoration: const InputDecoration(labelText: 'Adresse e-mail')),
        const SizedBox(height: 12),
        if (!_codeEnvoye)
          FilledButton(
            onPressed: () async {
              final ok = await executer(context, () async {
                await api.post('/auth/mot-de-passe/oubli', {'email': _email.text.trim()});
                return true;
              });
              if (ok == true) setState(() => _codeEnvoye = true);
            },
            child: const Text('Recevoir un code'),
          )
        else ...[
          TextField(
            controller: _code,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: const InputDecoration(labelText: 'Code reçu par e-mail'),
          ),
          TextField(
            controller: _mdp,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Nouveau mot de passe', helperText: '8 caractères, une majuscule, un chiffre'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () async {
              final erreur = validerMotDePasse(_mdp.text);
              if (erreur != null) return afficherMessage(context, erreur);
              final ok = await executer(context, () async {
                await api.post('/auth/mot-de-passe/reinitialiser',
                    {'email': _email.text.trim(), 'code': _code.text.trim(), 'nouveauMotDePasse': _mdp.text});
                return true;
              }, succes: 'Mot de passe changé. Connectez-vous.');
              if (ok == true && context.mounted) Navigator.of(context).pop();
            },
            child: const Text('Changer le mot de passe'),
          ),
        ],
      ],
    );
  }
}

// --- Régénération de la clé de récupération (I15) --------------------------------------------

class EcranRegenerationCle extends StatefulWidget {
  const EcranRegenerationCle({super.key});

  @override
  State<EcranRegenerationCle> createState() => _EcranRegenerationCleState();
}

class _EcranRegenerationCleState extends State<EcranRegenerationCle> {
  final _mdp = TextEditingController();

  @override
  Widget build(BuildContext context) => _CadreAuth(
        titre: 'Nouvelle clé de récupération',
        enfants: [
          const Text('Une nouvelle clé va être créée ; l\'ancienne cessera immédiatement de fonctionner.'),
          const SizedBox(height: 16),
          TextField(controller: _mdp, obscureText: true, decoration: const InputDecoration(labelText: 'Mot de passe actuel')),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () async {
              final cle = await executer(context, () => context.noyau.compte.regenererCleRecuperation(_mdp.text));
              if (cle != null && context.mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => EcranCleRecuperation(cle: cle, obligatoire: true)),
                );
              }
            },
            child: const Text('Générer'),
          ),
        ],
      );
}

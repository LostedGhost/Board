import 'dart:async';

import 'package:flutter/material.dart';

import '../../noyau/noyau.dart';
import '../../ui/commun.dart';

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
  final _cle = TextEditingController();
  bool _parCle = false;

  @override
  void dispose() {
    _interrogation?.cancel();
    super.dispose();
  }

  Future<void> _demander() async {
    final noyau = context.noyau;
    final d = await executer(context, noyau.compte.demanderDeverrouillage);
    if (d == null || !mounted) return;
    setState(() {
      _code = d['codeAffiche'] as String;
      _expire = DateTime.parse(d['expireLe'] as String).toLocal();
    });
    _interrogation?.cancel();
    _interrogation = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (await noyau.compte.verifierDeverrouillage()) _interrogation?.cancel();
    });
  }

  @override
  Widget build(BuildContext context) {
    final noyau = context.noyau;
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Déverrouiller cet appareil'),
        actions: [TextButton(onPressed: noyau.compte.deconnecter, child: const Text('Se déconnecter'))],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.phonelink_lock, size: 56),
                const SizedBox(height: 12),
                const Text(
                  'Vos données sont chiffrées de bout en bout. Pour les lire sur ce nouvel appareil, '
                  'il faut lui transmettre votre clé, de façon sécurisée.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                if (!_parCle) ...[
                  Text('Depuis un appareil déjà connecté', style: t.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (_code == null)
                    FilledButton(onPressed: _demander, child: const Text('Afficher un code'))
                  else ...[
                    const Text('Sur votre autre appareil, ouvrez Réglages › Appareils et saisissez ce code :'),
                    const SizedBox(height: 12),
                    SelectableText(_code!,
                        textAlign: TextAlign.center,
                        style: t.textTheme.displaySmall?.copyWith(letterSpacing: 10, fontFamily: 'monospace')),
                    Text('Valable jusqu\'à ${_expire!.hour.toString().padLeft(2, '0')}:${_expire!.minute.toString().padLeft(2, '0')}',
                        textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    const LinearProgressIndicator(),
                    const SizedBox(height: 4),
                    const Text('En attente de l\'approbation…', textAlign: TextAlign.center),
                    TextButton(onPressed: _demander, child: const Text('Nouveau code')),
                  ],
                  const SizedBox(height: 24),
                  TextButton(onPressed: () => setState(() => _parCle = true), child: const Text('Utiliser ma clé de récupération')),
                ] else ...[
                  Text('Avec votre clé de récupération', style: t.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _cle,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Clé (XXXX-XXXX-…)'),
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => executer(context, () => noyau.compte.deverrouillerParRecuperation(_cle.text),
                        succes: 'Appareil déverrouillé.'),
                    child: const Text('Déverrouiller'),
                  ),
                  TextButton(onPressed: () => setState(() => _parCle = false), child: const Text('Utiliser un autre appareil')),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

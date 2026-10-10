import 'package:flutter/material.dart';

import '../noyau/depot.dart';
import '../noyau/noyau.dart';
import '../noyau/stockage/base_locale.dart';
import 'commun.dart';

/// H9 : capture rapide universelle (raccourci Ctrl+Alt+N, zone de notification, bouton +).
class CaptureRapide {
  static final demandes = ValueNotifier<int>(0);

  static void demander() => demandes.value++;

  static Future<void> ouvrir(BuildContext context) =>
      showDialog<void>(context: context, builder: (_) => const _DialogueCapture());
}

class _DialogueCapture extends StatefulWidget {
  const _DialogueCapture();

  @override
  State<_DialogueCapture> createState() => _DialogueCaptureState();
}

class _DialogueCaptureState extends State<_DialogueCapture> {
  final _texte = TextEditingController();
  String _type = TypeEl.postIt;

  Future<void> _enregistrer() async {
    final texte = _texte.text.trim();
    if (texte.isEmpty) return;
    final noyau = context.noyau;
    final depot = noyau.depot;
    switch (_type) {
      case TypeEl.postIt:
        final tableaux = await noyau.base.tous(Entite.tableau);
        final tableau = tableaux.isNotEmpty ? tableaux.first['id']! as String : await depot.creerTableau('Mon tableau', 0);
        await depot.creer(TypeEl.postIt, {
          'contenu': texte,
          'couleurFond': '#FFE066',
          'x': 40.0,
          'y': 40.0,
          'largeur': 240.0,
          'hauteur': 200.0,
          'ordreEmpilement': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        }, parentId: tableau);
      case TypeEl.tache:
        final listes = (await noyau.base.tous(Entite.element)).where((e) => e['type'] == TypeEl.liste).toList();
        final liste = listes.isNotEmpty ? listes.first['id']! as String : await depot.creer(TypeEl.liste, {'titre': 'À faire'});
        await depot.creer(TypeEl.tache, {'titre': texte, 'faite': false, 'echeance': null, 'priorite': 'NORMALE', 'ordre': 0},
            parentId: liste);
      case TypeEl.snippet:
        await depot.creer(TypeEl.snippet, {'titre': texte.split('\n').first, 'contenu': texte, 'langage': null});
      default:
        await depot.ajouterPressePapier(texte);
    }
    if (mounted) {
      Navigator.pop(context);
      afficherMessage(context, '${TypeEl.libelles[_type]} enregistré.');
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Capture rapide'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: TypeEl.postIt, label: Text('Post-it'), icon: Icon(Icons.sticky_note_2_outlined)),
                  ButtonSegment(value: TypeEl.tache, label: Text('Tâche'), icon: Icon(Icons.check_box_outlined)),
                  ButtonSegment(value: TypeEl.snippet, label: Text('Snippet'), icon: Icon(Icons.code)),
                ],
                selected: {_type},
                onSelectionChanged: (s) => setState(() => _type = s.first),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _texte,
                autofocus: true,
                minLines: 3,
                maxLines: 8,
                decoration: const InputDecoration(hintText: 'Votre idée…'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          FilledButton(onPressed: _enregistrer, child: const Text('Enregistrer')),
        ],
      );
}

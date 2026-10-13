import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../noyau/depot.dart';
import '../noyau/noyau.dart';
import '../noyau/stockage/base_locale.dart';
import 'commun.dart';
import 'theme.dart';

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
  bool _enCours = false;

  static const _destinations = {
    TypeEl.postIt: 'Ajouté à votre premier tableau de post-it.',
    TypeEl.tache: 'Ajoutée à votre première liste de tâches.',
    TypeEl.snippet: 'La première ligne devient le titre du snippet.',
  };

  @override
  void dispose() {
    _texte.dispose();
    super.dispose();
  }

  Future<void> _enregistrer() async {
    final texte = _texte.text.trim();
    if (texte.isEmpty || _enCours) return;
    setState(() => _enCours = true);
    final noyau = context.noyau;
    final depot = noyau.depot;
    try {
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
        afficherMessage(context, _type == TypeEl.tache ? 'Tâche enregistrée.' : '${TypeEl.libelles[_type]} enregistré.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _enCours = false);
        afficherMessage(context, 'Enregistrement impossible. Réessayez.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _enregistrer,
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): _enregistrer,
        const SingleActivator(LogicalKeyboardKey.numpadEnter, control: true): _enregistrer,
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.maybePop(context),
      },
      child: AlertDialog(
        title: const Text('Capture rapide'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                label: "Type d'élément à créer",
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: TypeEl.postIt, label: Text('Post-it'), icon: Icon(Icons.sticky_note_2_outlined), tooltip: 'Créer un post-it'),
                    ButtonSegment(value: TypeEl.tache, label: Text('Tâche'), icon: Icon(Icons.check_box_outlined), tooltip: 'Créer une tâche'),
                    ButtonSegment(value: TypeEl.snippet, label: Text('Snippet'), icon: Icon(Icons.code), tooltip: 'Créer un snippet de code'),
                  ],
                  selected: {_type},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() => _type = s.first),
                ),
              ),
              const SizedBox(height: Lulu.sm),
              Text(_destinations[_type] ?? '', style: t.textTheme.bodySmall),
              const SizedBox(height: Lulu.md),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _texte,
                builder: (context, v, _) => TextField(
                  controller: _texte,
                  autofocus: true,
                  minLines: 3,
                  maxLines: 8,
                  keyboardType: TextInputType.multiline,
                  style: _type == TypeEl.snippet ? const TextStyle(fontFamily: 'monospace') : null,
                  decoration: InputDecoration(
                    hintText: switch (_type) {
                      TypeEl.tache => "Ce qu'il faut faire…",
                      TypeEl.snippet => 'Collez ou tapez votre code…',
                      _ => 'Votre idée…',
                    },
                  ),
                ),
              ),
              const SizedBox(height: Lulu.sm),
              Text('Ctrl+Entrée pour enregistrer · Échap pour fermer', style: t.textTheme.bodySmall),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _texte,
            builder: (context, v, _) => Tooltip(
              message: 'Ctrl+Entrée',
              child: FilledButton(
                onPressed: v.text.trim().isEmpty || _enCours ? null : _enregistrer,
                child: Text(_enCours ? 'Enregistrement…' : 'Enregistrer'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

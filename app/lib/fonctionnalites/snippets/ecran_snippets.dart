import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../noyau/depot.dart';
import '../../noyau/noyau.dart';
import '../../ui/commun.dart';
import '../commun/actions_element.dart';

/// F1 : snippets (titre, contenu, langage), copiés en un clic.
class EcranSnippets extends StatelessWidget {
  const EcranSnippets({super.key});

  @override
  Widget build(BuildContext context) {
    final depot = context.noyau.depot;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => ouvrirEditeurSnippet(context, null),
        icon: const Icon(Icons.add),
        label: const Text('Snippet'),
      ),
      body: StreamBuilder<List<Enr>>(
        stream: depot.elements(TypeEl.snippet),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final snippets = snap.data!..sort((a, b) => (b['modifieLe'] as String? ?? '').compareTo(a['modifieLe'] as String? ?? ''));
          if (snippets.isEmpty) {
            return EtatVide(
              icone: Icons.code,
              titre: 'Aucun snippet',
              texte: 'Gardez ici vos bouts de code, modèles de messages ou adresses à recopier souvent.',
              action: FilledButton(onPressed: () => ouvrirEditeurSnippet(context, null), child: const Text('Créer un snippet')),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 420, mainAxisExtent: 200, crossAxisSpacing: 12, mainAxisSpacing: 12),
            itemCount: snippets.length,
            itemBuilder: (context, i) {
              final s = snippets[i];
              final d = (s['donnees'] as Map?) ?? {};
              return Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => ouvrirEditeurSnippet(context, s),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text((d['titre'] ?? 'Sans titre').toString(), style: Theme.of(context).textTheme.titleMedium, overflow: TextOverflow.ellipsis)),
                            if (d['langage'] != null) Chip(label: Text(d['langage'].toString()), visualDensity: VisualDensity.compact),
                            IconButton(
                              tooltip: 'Copier',
                              icon: const Icon(Icons.copy),
                              onPressed: () async {
                                await Clipboard.setData(ClipboardData(text: (d['contenu'] ?? '').toString()));
                                if (context.mounted) afficherMessage(context, 'Snippet copié.');
                              },
                            ),
                            MenuElement(element: s),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Expanded(
                          child: Text((d['contenu'] ?? '').toString(),
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 12), overflow: TextOverflow.fade),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

Future<void> ouvrirEditeurSnippet(BuildContext context, Enr? snippet) async {
  final d = (snippet?['donnees'] as Map?) ?? {};
  final titre = TextEditingController(text: (d['titre'] ?? '').toString());
  final langage = TextEditingController(text: (d['langage'] ?? '').toString());
  final contenu = TextEditingController(text: (d['contenu'] ?? '').toString());
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(snippet == null ? 'Nouveau snippet' : 'Modifier le snippet'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: titre, decoration: const InputDecoration(labelText: 'Titre'), autofocus: true),
            const SizedBox(height: 8),
            TextField(controller: langage, decoration: const InputDecoration(labelText: 'Langage (facultatif)', hintText: 'dart, sql, texte…')),
            const SizedBox(height: 8),
            SizedBox(
              height: 260,
              child: TextField(
                controller: contenu,
                expands: true,
                maxLines: null,
                style: const TextStyle(fontFamily: 'monospace'),
                decoration: const InputDecoration(labelText: 'Contenu', alignLabelWithHint: true),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Enregistrer')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final donnees = {
    'titre': titre.text.trim().isEmpty ? 'Sans titre' : titre.text.trim(),
    'langage': langage.text.trim().isEmpty ? null : langage.text.trim(),
    'contenu': contenu.text,
  };
  final depot = context.noyau.depot;
  if (snippet == null) {
    await depot.creer(TypeEl.snippet, donnees);
  } else {
    await depot.modifierDonnees(snippet['id']! as String, donnees);
  }
}

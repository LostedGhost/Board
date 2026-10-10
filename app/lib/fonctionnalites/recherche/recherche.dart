import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../noyau/depot.dart';
import '../../noyau/noyau.dart';
import '../../ui/commun.dart';
import '../commun/actions_element.dart';

/// G2 / H8 : une seule recherche sur tout le Board, faite sur l'appareil (données chiffrées côté serveur).
Future<void> ouvrirRecherche(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _Recherche());

class _Recherche extends StatefulWidget {
  const _Recherche();

  @override
  State<_Recherche> createState() => _RechercheState();
}

class _RechercheState extends State<_Recherche> {
  final _q = TextEditingController();

  static const _icones = {
    TypeEl.pressePapier: Icons.content_paste,
    TypeEl.postIt: Icons.sticky_note_2,
    TypeEl.snippet: Icons.code,
    TypeEl.liste: Icons.list_alt,
    TypeEl.tache: Icons.check_box_outlined,
    TypeEl.fichier: Icons.insert_drive_file_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final depot = context.noyau.depot;
    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 560),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _q,
                autofocus: true,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Rechercher dans tout le Board…'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            Expanded(
              child: StreamBuilder<List<Enr>>(
                stream: depot.tousLesElements(),
                builder: (context, snap) {
                  final q = _q.text.trim().toLowerCase();
                  final tous = snap.data ?? [];
                  final resultats = q.isEmpty
                      ? (tous.where((e) => e['epingleAccesRapide'] == true).toList())
                      : tous.where((e) => Depot.texteDe(e).toLowerCase().contains(q)).take(100).toList();
                  if (resultats.isEmpty) {
                    return Center(
                      child: Text(q.isEmpty ? 'Tapez pour chercher. Les éléments épinglés en accès rapide apparaissent ici.' : 'Aucun résultat.',
                          textAlign: TextAlign.center),
                    );
                  }
                  return ListView(
                    children: [
                      if (q.isEmpty) const ListTile(dense: true, title: Text('ACCÈS RAPIDE')),
                      for (final e in resultats)
                        ListTile(
                          leading: Icon(_icones[e['type']] ?? Icons.notes),
                          title: Text(Depot.texteDe(e).split('\n').first, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('${TypeEl.libelles[e['type']] ?? ''} · ${dateCourte(e['modifieLe'] as String?)}'),
                          onTap: () async {
                            await Clipboard.setData(ClipboardData(text: Depot.texteDe(e)));
                            if (context.mounted) afficherMessage(context, 'Copié.');
                          },
                          trailing: MenuElement(element: e),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

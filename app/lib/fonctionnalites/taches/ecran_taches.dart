import 'package:flutter/material.dart';

import '../../noyau/depot.dart';
import '../../noyau/noyau.dart';
import '../../ui/commun.dart';
import '../commun/actions_element.dart';

/// F2 : listes de tâches, sous-tâches sans limite de profondeur, échéance, priorité.
class EcranTaches extends StatefulWidget {
  const EcranTaches({super.key});

  @override
  State<EcranTaches> createState() => _EcranTachesState();
}

class _EcranTachesState extends State<EcranTaches> {
  String? _liste;

  @override
  Widget build(BuildContext context) {
    final depot = context.noyau.depot;
    final large = MediaQuery.sizeOf(context).width >= 900;
    return StreamBuilder<List<Enr>>(
      stream: depot.elements(TypeEl.liste),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final listes = snap.data!..sort((a, b) => (a['creeLe'] as String? ?? '').compareTo(b['creeLe'] as String? ?? ''));
        if (listes.isEmpty) {
          return EtatVide(
            icone: Icons.checklist,
            titre: 'Aucune liste',
            texte: 'Créez une liste pour suivre vos tâches, avec sous-tâches, échéances et rappels.',
            action: FilledButton(onPressed: () => _nouvelleListe(context), child: const Text('Créer une liste')),
          );
        }
        final courante = listes.firstWhere((l) => l['id'] == _liste, orElse: () => listes.first);
        final menuListes = Column(
          children: [
            Expanded(
              child: ListView(
                children: [
                  for (final l in listes)
                    ListTile(
                      selected: l['id'] == courante['id'],
                      leading: const Icon(Icons.list_alt),
                      title: Text(((l['donnees'] as Map)['titre'] ?? 'Sans titre').toString()),
                      onTap: () => setState(() => _liste = l['id'] as String),
                      trailing: l['id'] == courante['id'] ? MenuElement(element: l) : null,
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: OutlinedButton.icon(onPressed: () => _nouvelleListe(context), icon: const Icon(Icons.add), label: const Text('Nouvelle liste')),
            ),
          ],
        );
        final contenu = _Liste(liste: courante);
        if (large) {
          return Row(children: [SizedBox(width: 260, child: menuListes), const VerticalDivider(width: 1), Expanded(child: contenu)]);
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: DropdownButtonFormField<String>(
                initialValue: courante['id'] as String,
                decoration: const InputDecoration(labelText: 'Liste', isDense: true),
                items: [
                  for (final l in listes)
                    DropdownMenuItem(value: l['id'] as String, child: Text(((l['donnees'] as Map)['titre'] ?? '').toString())),
                ],
                onChanged: (v) => setState(() => _liste = v),
              ),
            ),
            Expanded(child: contenu),
          ],
        );
      },
    );
  }

  Future<void> _nouvelleListe(BuildContext context) async {
    final titre = await demanderTexte(context, 'Nouvelle liste', libelle: 'Titre');
    if (titre == null || titre.isEmpty || !context.mounted) return;
    final id = await context.noyau.depot.creer(TypeEl.liste, {'titre': titre});
    setState(() => _liste = id);
  }
}

class _Liste extends StatelessWidget {
  const _Liste({required this.liste});

  final Enr liste;

  @override
  Widget build(BuildContext context) {
    final depot = context.noyau.depot;
    return StreamBuilder<List<Enr>>(
      stream: depot.elements(TypeEl.tache),
      builder: (context, snap) {
        final toutes = snap.data ?? [];
        final parParent = <String, List<Enr>>{};
        for (final t in toutes) {
          parParent.putIfAbsent(t['parentId'] as String? ?? '', () => []).add(t);
        }
        for (final l in parParent.values) {
          l.sort((a, b) {
            final fa = (a['donnees'] as Map)['faite'] == true ? 1 : 0, fb = (b['donnees'] as Map)['faite'] == true ? 1 : 0;
            if (fa != fb) return fa - fb;
            return ((a['donnees'] as Map)['ordre'] as num? ?? 0).compareTo((b['donnees'] as Map)['ordre'] as num? ?? 0);
          });
        }
        final racines = parParent[liste['id']] ?? [];
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _ChampNouvelleTache(parentId: liste['id']! as String),
            const SizedBox(height: 8),
            if (racines.isEmpty)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Aucune tâche. Ajoutez-en une ci-dessus.'))),
            for (final t in racines) _Tache(tache: t, enfants: parParent, profondeur: 0),
          ],
        );
      },
    );
  }
}

class _ChampNouvelleTache extends StatefulWidget {
  const _ChampNouvelleTache({required this.parentId, this.compact = false});

  final String parentId;
  final bool compact;

  @override
  State<_ChampNouvelleTache> createState() => _ChampNouvelleTacheState();
}

class _ChampNouvelleTacheState extends State<_ChampNouvelleTache> {
  final _ctrl = TextEditingController();

  Future<void> _ajouter() async {
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;
    _ctrl.clear();
    await context.noyau.depot.creer(TypeEl.tache,
        {'titre': t, 'faite': false, 'echeance': null, 'priorite': 'NORMALE', 'ordre': DateTime.now().millisecondsSinceEpoch},
        parentId: widget.parentId);
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _ctrl,
        autofocus: widget.compact,
        decoration: InputDecoration(
          hintText: widget.compact ? 'Nouvelle sous-tâche' : 'Ajouter une tâche',
          prefixIcon: const Icon(Icons.add),
          isDense: true,
        ),
        onSubmitted: (_) => _ajouter(),
      );
}

class _Tache extends StatefulWidget {
  const _Tache({required this.tache, required this.enfants, required this.profondeur});

  final Enr tache;
  final Map<String, List<Enr>> enfants;
  final int profondeur;

  @override
  State<_Tache> createState() => _TacheState();
}

class _TacheState extends State<_Tache> {
  bool _ajoutSousTache = false;

  static const _couleursPriorite = {'HAUTE': Colors.red, 'NORMALE': Colors.blueGrey, 'BASSE': Colors.green};

  @override
  Widget build(BuildContext context) {
    final depot = context.noyau.depot;
    final d = (widget.tache['donnees'] as Map?) ?? {};
    final id = widget.tache['id']! as String;
    final faite = d['faite'] == true;
    final echeance = DateTime.tryParse(d['echeance'] as String? ?? '');
    final enRetard = echeance != null && !faite && echeance.isBefore(DateTime.now());
    final sousTaches = widget.enfants[id] ?? [];
    return Padding(
      padding: EdgeInsets.only(left: 20.0 * widget.profondeur.clamp(0, 8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.only(left: 4),
            leading: Checkbox(value: faite, onChanged: (v) => depot.modifierDonnees(id, {'faite': v ?? false})),
            title: Text(
              (d['titre'] ?? '').toString(),
              style: TextStyle(decoration: faite ? TextDecoration.lineThrough : null, color: faite ? Theme.of(context).disabledColor : null),
            ),
            subtitle: echeance == null
                ? null
                : Text('Échéance : ${dateCourte(echeance.toUtc().toIso8601String())}',
                    style: TextStyle(color: enRetard ? Theme.of(context).colorScheme.error : null)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Tooltip(
                  message: 'Priorité ${(d['priorite'] ?? 'NORMALE').toString().toLowerCase()} (cliquer pour changer)',
                  child: InkWell(
                    onTap: () {
                      const ordre = ['BASSE', 'NORMALE', 'HAUTE'];
                      final i = ordre.indexOf((d['priorite'] ?? 'NORMALE') as String);
                      depot.modifierDonnees(id, {'priorite': ordre[(i + 1) % 3]});
                    },
                    child: Icon(Icons.flag, color: _couleursPriorite[d['priorite']] ?? Colors.blueGrey, size: 20),
                  ),
                ),
                IconButton(
                  tooltip: 'Échéance',
                  icon: const Icon(Icons.event, size: 20),
                  onPressed: () async {
                    final date = await showDatePicker(
                      context: context,
                      firstDate: DateTime.now().subtract(const Duration(days: 365)),
                      lastDate: DateTime.now().add(const Duration(days: 3650)),
                      initialDate: echeance ?? DateTime.now(),
                    );
                    await depot.modifierDonnees(id, {'echeance': date?.toUtc().toIso8601String()});
                  },
                ),
                IconButton(
                  tooltip: 'Ajouter une sous-tâche',
                  icon: const Icon(Icons.subdirectory_arrow_right, size: 20),
                  onPressed: () => setState(() => _ajoutSousTache = !_ajoutSousTache),
                ),
                MenuElement(element: widget.tache),
              ],
            ),
            onLongPress: () async {
              final t = await demanderTexte(context, 'Modifier la tâche', initial: (d['titre'] ?? '').toString(), libelle: 'Titre');
              if (t != null && t.isNotEmpty) await depot.modifierDonnees(id, {'titre': t});
            },
          ),
          if (_ajoutSousTache)
            Padding(
              padding: const EdgeInsets.only(left: 48, right: 8, bottom: 6),
              child: _ChampNouvelleTache(parentId: id, compact: true),
            ),
          for (final s in sousTaches) _Tache(tache: s, enfants: widget.enfants, profondeur: widget.profondeur + 1),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../noyau/noyau.dart';
import '../../ui/commun.dart';

const _recurrences = {null: 'Une seule fois', 'QUOTIDIENNE': 'Tous les jours', 'HEBDOMADAIRE': 'Toutes les semaines', 'MENSUELLE': 'Tous les mois', 'ANNUELLE': 'Tous les ans'};
const _jours = ['LUNDI', 'MARDI', 'MERCREDI', 'JEUDI', 'VENDREDI', 'SAMEDI', 'DIMANCHE'];

/// F3 / H2 : rappels (plusieurs par élément), récurrents ou non, dans le fuseau de l'appareil.
Future<void> ouvrirDialogueRappel(BuildContext context, String elementId) =>
    showDialog<void>(context: context, builder: (_) => _DialogueRappel(elementId));

class _DialogueRappel extends StatefulWidget {
  const _DialogueRappel(this.elementId);

  final String elementId;

  @override
  State<_DialogueRappel> createState() => _DialogueRappelState();
}

class _DialogueRappelState extends State<_DialogueRappel> {
  DateTime _date = DateTime.now().add(const Duration(hours: 1));
  String? _recurrence;
  final _joursChoisis = <String>{};

  @override
  Widget build(BuildContext context) {
    final depot = context.noyau.depot;
    return AlertDialog(
      title: const Text('Rappels'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StreamBuilder(
              stream: depot.rappelsDe(widget.elementId),
              builder: (context, snap) {
                final rappels = snap.data ?? [];
                if (rappels.isEmpty) return const Text('Aucun rappel pour l\'instant.');
                return Column(
                  children: [
                    for (final r in rappels)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(r['actif'] == true ? Icons.alarm : Icons.alarm_off),
                        title: Text(dateCourte(r['prochaineEcheance'] as String?)),
                        subtitle: Text(resumeRappel(
                          DateTime.tryParse(r['prochaineEcheance'] as String? ?? '')?.toLocal() ?? DateTime.now(),
                          r['recurrence'] as String?,
                          ((r['joursSemaine'] as List?) ?? const []).cast<String>(),
                        )),
                        trailing: IconButton(
                          tooltip: 'Supprimer ce rappel',
                          icon: const Icon(Icons.close),
                          onPressed: () => depot.supprimerRappel(r['id']! as String),
                        ),
                      ),
                  ],
                );
              },
            ),
            const Divider(),
            Text('Nouveau rappel', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.event),
                    label: Text('${_date.day}/${_date.month}/${_date.year}'),
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        firstDate: DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day),
                        lastDate: DateTime.now().add(const Duration(days: 3650)),
                        initialDate: _date,
                      );
                      if (d != null) setState(() => _date = DateTime(d.year, d.month, d.day, _date.hour, _date.minute));
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.schedule),
                    label: Text('${_date.hour.toString().padLeft(2, '0')}:${_date.minute.toString().padLeft(2, '0')}'),
                    onPressed: () async {
                      final h = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_date));
                      if (h != null) setState(() => _date = DateTime(_date.year, _date.month, _date.day, h.hour, h.minute));
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String?>(
              initialValue: _recurrence,
              decoration: const InputDecoration(labelText: 'Répétition'),
              items: [for (final e in _recurrences.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() => _recurrence = v),
            ),
            const SizedBox(height: 8),
            Text(resumeRappel(_date, _recurrence, _joursChoisis), style: Theme.of(context).textTheme.bodyMedium),
            if (!_date.isAfter(DateTime.now()))
              Text('Cette date est passée : choisissez une date et une heure à venir.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            if (_recurrence == 'HEBDOMADAIRE')
              Wrap(
                spacing: 4,
                children: [
                  for (final j in _jours)
                    FilterChip(
                      label: Text(j.substring(0, 3)),
                      selected: _joursChoisis.contains(j),
                      onSelected: (s) => setState(() => s ? _joursChoisis.add(j) : _joursChoisis.remove(j)),
                    ),
                ],
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer')),
        FilledButton(
          onPressed: !_date.isAfter(DateTime.now()) ? null : () async {
            await depot.creerRappel(widget.elementId, _date,
                recurrence: _recurrence, jours: _joursChoisis.toList(), fuseau: _fuseauLocal());
            if (context.mounted) afficherMessage(context, 'Rappel ajouté.');
          },
          child: const Text('Ajouter'),
        ),
      ],
    );
  }
}

/// Fuseau IANA de l'appareil (approché par le décalage si le nom n'est pas disponible).
String _fuseauLocal() {
  final nom = DateTime.now().timeZoneName;
  if (nom.contains('/')) return nom;
  final h = DateTime.now().timeZoneOffset.inHours;
  if (h == 0) return 'UTC';
  // Les zones « Etc/GMT » ont un signe inversé par convention POSIX.
  return 'Etc/GMT${h > 0 ? '-' : '+'}${h.abs()}';
}

const _nomsJours = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
const _mois = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'];

/// Résumé lisible : « Tous les lundis à 09:00 », « Le 14 octobre 2026 à 18:30 »…
String resumeRappel(DateTime d, String? recurrence, Iterable<String> jours) {
  final h = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  switch (recurrence) {
    case 'QUOTIDIENNE':
      return 'Tous les jours à $h';
    case 'HEBDOMADAIRE':
      final noms = [for (var i = 0; i < 7; i++) if (jours.contains(_jours[i])) '${_nomsJours[i]}s'];
      if (noms.isEmpty) noms.add('${_nomsJours[d.weekday - 1]}s');
      final liste = noms.length == 1 ? noms.first : '${noms.sublist(0, noms.length - 1).join(', ')} et ${noms.last}';
      return 'Tous les $liste à $h';
    case 'MENSUELLE':
      return 'Tous les mois, le ${d.day == 1 ? '1er' : d.day}, à $h';
    case 'ANNUELLE':
      return 'Tous les ans, le ${d.day == 1 ? '1er' : d.day} ${_mois[d.month - 1]}, à $h';
    default:
      return 'Le ${_nomsJours[d.weekday - 1]} ${d.day} ${_mois[d.month - 1]} ${d.year} à $h';
  }
}

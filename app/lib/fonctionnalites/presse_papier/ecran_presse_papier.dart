import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../noyau/depot.dart';
import '../../noyau/noyau.dart';
import '../../plateformes/desktop.dart';
import '../../ui/commun.dart';
import '../commun/actions_element.dart';

/// B1-B4 : historique du presse-papier.
class EcranPressePapier extends StatefulWidget {
  const EcranPressePapier({super.key});

  @override
  State<EcranPressePapier> createState() => _EcranPressePapierState();
}

class _EcranPressePapierState extends State<EcranPressePapier> {
  final _recherche = TextEditingController();
  String? _filtre; // null = tous, sinon TEXTE / LIEN / IMAGE
  bool _pause = false;

  @override
  void initState() {
    super.initState();
    context.noyau.base.lireMeta<bool>('capture_pause').then((v) {
      if (mounted) setState(() => _pause = v ?? false);
    });
  }

  Future<void> _coller() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    if (d?.text == null || d!.text!.isEmpty) {
      afficherMessage(context, 'Le presse-papier est vide ou ne contient pas de texte.');
      return;
    }
    await context.noyau.depot.ajouterPressePapier(d.text!);
  }

  Future<void> _ajouterManuellement() async {
    final texte = await demanderTexte(context, 'Ajouter au presse-papier', libelle: 'Texte ou lien');
    if (texte != null && texte.isNotEmpty && mounted) await context.noyau.depot.ajouterPressePapier(texte);
  }

  @override
  Widget build(BuildContext context) {
    final depot = context.noyau.depot;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 280,
                child: TextField(
                  controller: _recherche,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Filtrer l\'historique', isDense: true),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              for (final (v, l) in [(null, 'Tout'), ('TEXTE', 'Textes'), ('LIEN', 'Liens'), ('IMAGE', 'Images')])
                ChoiceChip(label: Text(l), selected: _filtre == v, onSelected: (_) => setState(() => _filtre = v)),
              FilledButton.tonalIcon(onPressed: _coller, icon: const Icon(Icons.content_paste_go), label: const Text('Coller')),
              OutlinedButton.icon(onPressed: _ajouterManuellement, icon: const Icon(Icons.add), label: const Text('Ajouter')),
              if (IntegrationDesktop.captureDisponible)
                FilterChip(
                  avatar: Icon(_pause ? Icons.pause_circle : Icons.fiber_manual_record, size: 18),
                  label: Text(_pause ? 'Capture en pause' : 'Capture automatique'),
                  selected: !_pause,
                  onSelected: (actif) async {
                    await IntegrationDesktop.definirPause(!actif);
                    setState(() => _pause = !actif);
                  },
                ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Enr>>(
            stream: depot.elements(TypeEl.pressePapier),
            builder: (context, snap) {
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final q = _recherche.text.toLowerCase();
              final entrees = snap.data!
                  .where((e) => _filtre == null || e['typeContenu'] == _filtre)
                  .where((e) => q.isEmpty || Depot.texteDe(e).toLowerCase().contains(q))
                  .toList()
                ..sort((a, b) {
                  final ea = (a['epingle'] == true) ? 1 : 0, eb = (b['epingle'] == true) ? 1 : 0;
                  if (ea != eb) return eb - ea; // épinglées en tête
                  return (b['creeLe'] as String? ?? b['modifieLe'] as String? ?? '')
                      .compareTo(a['creeLe'] as String? ?? a['modifieLe'] as String? ?? '');
                });
              if (entrees.isEmpty) {
                return EtatVide(
                  icone: Icons.content_paste,
                  titre: q.isEmpty ? 'Votre historique est vide' : 'Aucun résultat',
                  texte: IntegrationDesktop.captureDisponible
                      ? 'Copiez du texte n\'importe où : il apparaîtra ici automatiquement. Raccourci : Ctrl+Alt+B.'
                      : 'Collez un texte ou un lien pour le garder et le retrouver sur tous vos appareils.',
                  action: q.isEmpty ? FilledButton.icon(onPressed: _coller, icon: const Icon(Icons.content_paste_go), label: const Text('Coller maintenant')) : null,
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: entrees.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, i) => _CarteEntree(entrees[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CarteEntree extends StatelessWidget {
  const _CarteEntree(this.e);

  final Enr e;

  @override
  Widget build(BuildContext context) {
    final d = (e['donnees'] as Map?) ?? {};
    final image = e['typeContenu'] == 'IMAGE' && d['image'] != null;
    final lien = e['typeContenu'] == 'LIEN';
    final depot = context.noyau.depot;
    return Card(
      child: ListTile(
        leading: Icon(image ? Icons.image_outlined : (lien ? Icons.link : Icons.notes)),
        title: image
            ? Align(alignment: Alignment.centerLeft, child: Image.memory(base64Decode(d['image'] as String), height: 120))
            : Text(Depot.texteDe(e), maxLines: 4, overflow: TextOverflow.ellipsis),
        subtitle: Text(dateCourte(e['creeLe'] as String? ?? e['modifieLe'] as String?)),
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: Depot.texteDe(e)));
          if (context.mounted) afficherMessage(context, 'Copié dans le presse-papier.');
        },
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (lien)
              IconButton(
                tooltip: 'Ouvrir le lien',
                icon: const Icon(Icons.open_in_new),
                onPressed: () => launchUrl(Uri.parse(Depot.texteDe(e).trim())),
              ),
            IconButton(
              tooltip: e['epingle'] == true ? 'Désépingler' : 'Épingler (jamais purgé)',
              icon: Icon(e['epingle'] == true ? Icons.push_pin : Icons.push_pin_outlined),
              onPressed: () => depot.modifierChamps(e['id']! as String, {'epingle': e['epingle'] != true}),
            ),
            MenuElement(element: e),
          ],
        ),
      ),
    );
  }
}

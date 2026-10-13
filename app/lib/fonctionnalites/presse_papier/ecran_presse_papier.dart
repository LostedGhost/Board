import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../noyau/depot.dart';
import '../../noyau/noyau.dart';
import '../../plateformes/desktop.dart';
import '../../ui/commun.dart';
import '../../ui/recherche_locale.dart';
import '../../ui/theme.dart';
import '../commun/actions_element.dart';

/// B1-B4 : historique du presse-papier.
class EcranPressePapier extends StatefulWidget {
  const EcranPressePapier({super.key});

  @override
  State<EcranPressePapier> createState() => _EcranPressePapierState();
}

class _EcranPressePapierState extends State<EcranPressePapier> {
  final _recherche = TextEditingController();
  final _focusRecherche = FocusNode(debugLabel: 'filtre presse-papier');
  String? _filtre; // null = tous, sinon TEXTE / LIEN / IMAGE
  bool _pause = false;

  @override
  void initState() {
    super.initState();
    context.noyau.base.lireMeta<bool>('capture_pause').then((v) {
      if (mounted) setState(() => _pause = v ?? false);
    });
  }

  @override
  void dispose() {
    _recherche.dispose();
    _focusRecherche.dispose();
    super.dispose();
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

  void _viderFiltre() {
    _recherche.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final depot = context.noyau.depot;
    return RaccourciFiltre(
      focusNode: _focusRecherche,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Lulu.md, Lulu.md, Lulu.md, Lulu.xs),
            child: Wrap(
              spacing: Lulu.sm,
              runSpacing: Lulu.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 300,
                  child: ChampRecherche(
                    controller: _recherche,
                    focusNode: _focusRecherche,
                    indice: 'Filtrer l\'historique (Ctrl+F)',
                    padding: EdgeInsets.zero,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                for (final (v, l) in [(null, 'Tout'), ('TEXTE', 'Textes'), ('LIEN', 'Liens'), ('IMAGE', 'Images')])
                  ChoiceChip(label: Text(l), selected: _filtre == v, onSelected: (_) => setState(() => _filtre = v)),
                FilledButton.tonalIcon(onPressed: _coller, icon: const Icon(Icons.content_paste_go), label: const Text('Coller')),
                OutlinedButton.icon(onPressed: _ajouterManuellement, icon: const Icon(Icons.add), label: const Text('Ajouter')),
                if (IntegrationDesktop.captureDisponible)
                  Tooltip(
                    message: _pause ? 'Reprendre la capture automatique' : 'Mettre la capture automatique en pause',
                    child: FilterChip(
                      avatar: Icon(_pause ? Icons.pause_circle : Icons.fiber_manual_record, size: 18),
                      label: Text(_pause ? 'Capture en pause' : 'Capture automatique'),
                      selected: !_pause,
                      onSelected: (actif) async {
                        await IntegrationDesktop.definirPause(!actif);
                        setState(() => _pause = !actif);
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Enr>>(
              stream: depot.elements(TypeEl.pressePapier),
              builder: (context, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final tout = snap.data!;
                if (tout.isEmpty) return _etatVide();
                final q = _recherche.text.trim();
                final entrees = tout
                    .where((e) => _filtre == null || e['typeContenu'] == _filtre)
                    .where((e) => concorde(Depot.texteDe(e), q))
                    .toList()
                  ..sort((a, b) {
                    final ea = (a['epingle'] == true) ? 1 : 0, eb = (b['epingle'] == true) ? 1 : 0;
                    if (ea != eb) return eb - ea; // épinglées en tête
                    return _date(b).compareTo(_date(a));
                  });
                if (entrees.isEmpty) {
                  if (q.isNotEmpty) return AucunResultat(recherche: q, onVider: _viderFiltre);
                  return EtatVide(
                    icone: Icons.filter_alt_off_outlined,
                    titre: 'Rien dans cette catégorie',
                    texte: 'Aucune entrée de ce type dans votre historique.',
                    action: OutlinedButton.icon(
                      onPressed: () => setState(() => _filtre = null),
                      icon: const Icon(Icons.clear_all),
                      label: const Text('Tout afficher'),
                    ),
                  );
                }
                final lignes = _grouper(entrees);
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(Lulu.md, Lulu.sm, Lulu.md, Lulu.lg),
                  itemCount: lignes.length,
                  itemBuilder: (context, i) {
                    final l = lignes[i];
                    if (l is String) return _EnTeteGroupe(l, premier: i == 0);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: Lulu.sm),
                      child: _CarteEntree(l as Enr, recherche: q),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _etatVide() => EtatVide(
        icone: Icons.content_paste,
        titre: 'Votre historique est vide',
        texte: IntegrationDesktop.captureDisponible
            ? 'Copiez du texte n\'importe où : il apparaîtra ici automatiquement. Raccourci : Ctrl+Alt+B.'
            : 'Collez un texte ou un lien pour le garder et le retrouver sur tous vos appareils.',
        action: FilledButton.icon(onPressed: _coller, icon: const Icon(Icons.content_paste_go), label: const Text('Coller maintenant')),
      );
}

String _date(Enr e) => e['creeLe'] as String? ?? e['modifieLe'] as String? ?? '';

/// Liste à plat : en-têtes de groupe (String) suivis de leurs entrées (Enr).
/// Les épinglées forment un groupe à part, en tête ; le reste est regroupé par jour.
List<Object> _grouper(List<Enr> entrees) {
  final lignes = <Object>[];
  String? courant;
  for (final e in entrees) {
    final groupe = e['epingle'] == true ? 'Épinglées' : _libelleJour(_date(e));
    if (groupe != courant) {
      lignes.add(groupe);
      courant = groupe;
    }
    lignes.add(e);
  }
  return lignes;
}

String _libelleJour(String iso) {
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return 'Date inconnue';
  final maintenant = DateTime.now();
  final jour = DateTime(d.year, d.month, d.day);
  final ecart = DateTime(maintenant.year, maintenant.month, maintenant.day).difference(jour).inDays;
  if (ecart == 0) return 'Aujourd\'hui';
  if (ecart == 1) return 'Hier';
  final libelle = DateFormat(d.year == maintenant.year ? 'EEEE d MMMM' : 'EEEE d MMMM y', 'fr').format(d);
  return libelle.isEmpty ? libelle : libelle[0].toUpperCase() + libelle.substring(1);
}

class _EnTeteGroupe extends StatelessWidget {
  const _EnTeteGroupe(this.libelle, {required this.premier});

  final String libelle;
  final bool premier;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(top: premier ? 0 : Lulu.md, bottom: Lulu.sm, left: Lulu.xs),
      child: Semantics(
        header: true,
        child: Row(
          children: [
            if (libelle == 'Épinglées') ...[
              Icon(Icons.push_pin, size: 14, color: t.colorScheme.primary),
              const SizedBox(width: Lulu.xs),
            ],
            Text(libelle, style: t.textTheme.labelLarge?.copyWith(color: t.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _CarteEntree extends StatefulWidget {
  const _CarteEntree(this.e, {required this.recherche});

  final Enr e;
  final String recherche;

  @override
  State<_CarteEntree> createState() => _CarteEntreeState();
}

class _CarteEntreeState extends State<_CarteEntree> {
  bool _copie = false;
  Timer? _minuteur;

  @override
  void dispose() {
    _minuteur?.cancel();
    super.dispose();
  }

  Future<void> _copier() async {
    await Clipboard.setData(ClipboardData(text: Depot.texteDe(widget.e)));
    if (!mounted) return;
    setState(() => _copie = true);
    _minuteur?.cancel();
    _minuteur = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copie = false);
    });
    afficherMessage(context, 'Copié dans le presse-papier.');
  }

  Future<void> _ouvrirLien() async {
    final uri = Uri.tryParse(Depot.texteDe(widget.e).trim());
    final ok = uri != null && await launchUrl(uri);
    if (!ok && mounted) afficherMessage(context, 'Impossible d\'ouvrir ce lien.');
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.e;
    final t = Theme.of(context);
    final d = (e['donnees'] as Map?) ?? {};
    final image = e['typeContenu'] == 'IMAGE' && d['image'] != null;
    final lien = e['typeContenu'] == 'LIEN';
    final epingle = e['epingle'] == true;
    final depot = context.noyau.depot;
    final (icone, type) = image ? (Icons.image_outlined, 'Image') : (lien ? (Icons.link, 'Lien') : (Icons.notes, 'Texte'));

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _copier,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Lulu.md, Lulu.sm, Lulu.xs, Lulu.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: Lulu.sm + 2),
                child: Tooltip(message: type, child: Icon(icone, size: 20, color: lien ? t.colorScheme.primary : t.colorScheme.onSurfaceVariant)),
              ),
              const SizedBox(width: Lulu.md),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Lulu.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (image)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(Lulu.rMd),
                          child: Image.memory(base64Decode(d['image'] as String), height: 120, semanticLabel: 'Image copiée'),
                        )
                      else
                        TexteSurligne(
                          Depot.texteDe(e),
                          widget.recherche,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: lien ? TextStyle(color: t.colorScheme.primary) : null,
                        ),
                      const SizedBox(height: Lulu.xs),
                      Text(
                        dateCourte(_date(e)),
                        style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: _copie ? 'Copié' : 'Copier',
                icon: AnimatedSwitcher(
                  duration: Lulu.rapide,
                  child: _copie
                      ? Icon(Icons.check, key: const ValueKey('ok'), color: t.colorScheme.primary)
                      : const Icon(Icons.copy, key: ValueKey('copier')),
                ),
                onPressed: _copier,
              ),
              if (lien)
                IconButton(tooltip: 'Ouvrir le lien', icon: const Icon(Icons.open_in_new), onPressed: _ouvrirLien),
              IconButton(
                tooltip: epingle ? 'Désépingler' : 'Épingler (jamais purgé)',
                isSelected: epingle,
                icon: Icon(epingle ? Icons.push_pin : Icons.push_pin_outlined, color: epingle ? t.colorScheme.primary : null),
                onPressed: () => depot.modifierChamps(e['id']! as String, {'epingle': !epingle}),
              ),
              IconButton(
                tooltip: 'Supprimer',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => executerAction(context, e, 'supprimer'),
              ),
              MenuElement(element: e),
            ],
          ),
        ),
      ),
    );
  }
}

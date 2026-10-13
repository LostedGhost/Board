import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../noyau/depot.dart';
import '../../noyau/noyau.dart';
import '../../ui/commun.dart';
import '../../ui/glisser.dart';
import '../../ui/recherche_locale.dart';
import '../../ui/theme.dart';
import '../commun/actions_element.dart';

/// Police à chasse fixe : pas de police embarquée, on s'appuie sur celles du système.
const _mono = TextStyle(fontFamily: 'monospace', fontFamilyFallback: ['Consolas', 'Menlo', 'Courier New'], fontSize: 12.5, height: 1.45);

Map _donnees(Enr s) => (s['donnees'] as Map?) ?? {};

String? _langage(Enr s) {
  final l = _donnees(s)['langage']?.toString().trim();
  return (l == null || l.isEmpty) ? null : l;
}

List<String> _etiquettes(Enr s) {
  final e = _donnees(s)['etiquettes'] ?? s['etiquettes'];
  return e is List ? [for (final x in e) x.toString()] : const [];
}

bool _snippetConcorde(Enr s, String q) {
  if (q.isEmpty) return true;
  final d = _donnees(s);
  return concorde(d['titre']?.toString(), q) ||
      concorde(d['contenu']?.toString(), q) ||
      concorde(_langage(s), q) ||
      _etiquettes(s).any((e) => concorde(e, q));
}

/// F1 : snippets (titre, contenu, langage), copiés en un clic.
class EcranSnippets extends StatefulWidget {
  const EcranSnippets({super.key});

  @override
  State<EcranSnippets> createState() => _EcranSnippetsState();
}

class _EcranSnippetsState extends State<EcranSnippets> {
  final _recherche = TextEditingController();
  final _focusRecherche = FocusNode(debugLabel: 'filtre snippets');
  String? _langageChoisi;

  @override
  void dispose() {
    _recherche.dispose();
    _focusRecherche.dispose();
    super.dispose();
  }

  void _viderFiltre() {
    _recherche.clear();
    setState(() => _langageChoisi = null);
  }

  @override
  Widget build(BuildContext context) {
    final depot = context.noyau.depot;
    return RaccourciFiltre(
      focusNode: _focusRecherche,
      child: Scaffold(
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => ouvrirEditeurSnippet(context, null),
          icon: const Icon(Icons.add),
          label: const Text('Snippet'),
        ),
        body: StreamBuilder<List<Enr>>(
          stream: depot.elements(TypeEl.snippet),
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final tous = [...snap.data!]..sort((a, b) => (b['modifieLe'] as String? ?? '').compareTo(a['modifieLe'] as String? ?? ''));
            if (tous.isEmpty) {
              return EtatVide(
                icone: Icons.code,
                titre: 'Aucun snippet',
                texte: 'Gardez ici vos bouts de code, modèles de messages ou adresses à recopier souvent.',
                action: FilledButton(onPressed: () => ouvrirEditeurSnippet(context, null), child: const Text('Créer un snippet')),
              );
            }
            final langages = {for (final s in tous) ?_langage(s)}.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
            final langageActif = langages.contains(_langageChoisi) ? _langageChoisi : null;
            final q = _recherche.text.trim();
            final snippets = tous.where((s) => (langageActif == null || _langage(s) == langageActif) && _snippetConcorde(s, q)).toList();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                          indice: 'Titre, contenu, langage… (Ctrl+F)',
                          padding: EdgeInsets.zero,
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      if (langages.length > 1) ...[
                        ChoiceChip(label: const Text('Tous'), selected: langageActif == null, onSelected: (_) => setState(() => _langageChoisi = null)),
                        for (final l in langages)
                          ChoiceChip(label: Text(l), selected: langageActif == l, onSelected: (_) => setState(() => _langageChoisi = l)),
                      ],
                    ],
                  ),
                ),
                const AstuceGlisser(padding: EdgeInsets.fromLTRB(Lulu.md, Lulu.xs, Lulu.md, 0)),
                Expanded(
                  child: snippets.isEmpty
                      ? AucunResultat(recherche: q.isEmpty ? (langageActif ?? '') : q, onVider: _viderFiltre)
                      : GridView.builder(
                          padding: const EdgeInsets.fromLTRB(Lulu.md, Lulu.sm, Lulu.md, 88),
                          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 440,
                            mainAxisExtent: 232,
                            crossAxisSpacing: Lulu.md,
                            mainAxisSpacing: Lulu.md,
                          ),
                          itemCount: snippets.length,
                          itemBuilder: (context, i) =>
                              Glissable(element: snippets[i], child: _CarteSnippet(snippets[i], recherche: q)),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CarteSnippet extends StatefulWidget {
  const _CarteSnippet(this.s, {required this.recherche});

  final Enr s;
  final String recherche;

  @override
  State<_CarteSnippet> createState() => _CarteSnippetState();
}

class _CarteSnippetState extends State<_CarteSnippet> {
  bool _copie = false;
  Timer? _minuteur;

  @override
  void dispose() {
    _minuteur?.cancel();
    super.dispose();
  }

  Future<void> _copier() async {
    await Clipboard.setData(ClipboardData(text: (_donnees(widget.s)['contenu'] ?? '').toString()));
    if (!mounted) return;
    setState(() => _copie = true);
    _minuteur?.cancel();
    _minuteur = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copie = false);
    });
    afficherMessage(context, 'Snippet copié.');
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final q = widget.recherche;
    final t = Theme.of(context);
    final c = t.colorScheme;
    final d = _donnees(s);
    final langage = _langage(s);
    final etiquettes = _etiquettes(s);
    final titre = (d['titre'] ?? 'Sans titre').toString();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => ouvrirEditeurSnippet(context, s),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Lulu.md, Lulu.sm, Lulu.xs, Lulu.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: TexteSurligne(titre, q, style: t.textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  if (langage != null) ...[
                    const SizedBox(width: Lulu.sm),
                    _Pastille(langage, recherche: q, accent: true),
                  ],
                  const SizedBox(width: Lulu.xs),
                  TextButton.icon(
                    onPressed: _copier,
                    style: TextButton.styleFrom(minimumSize: const Size(40, 40)),
                    icon: Icon(_copie ? Icons.check : Icons.copy, size: 18),
                    label: Text(_copie ? 'Copié' : 'Copier'),
                  ),
                  MenuElement(element: s),
                ],
              ),
              if (etiquettes.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: Lulu.sm, right: Lulu.md),
                  child: Wrap(
                    spacing: Lulu.xs,
                    runSpacing: Lulu.xs,
                    children: [for (final e in etiquettes) _Pastille(e, recherche: q)],
                  ),
                ),
              const SizedBox(height: Lulu.xs),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: Lulu.md - Lulu.xs),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(Lulu.md - Lulu.xs),
                    decoration: BoxDecoration(
                      color: c.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(Lulu.rMd),
                      border: Border.all(color: c.outlineVariant),
                    ),
                    child: TexteSurligne(
                      (d['contenu'] ?? '').toString(),
                      q,
                      style: _mono.copyWith(color: c.onSurface),
                      overflow: TextOverflow.fade,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Petite pastille (langage, étiquette) avec surlignage de la recherche.
class _Pastille extends StatelessWidget {
  const _Pastille(this.texte, {required this.recherche, this.accent = false});

  final String texte;
  final String recherche;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Lulu.sm, vertical: 2),
      decoration: BoxDecoration(
        color: accent ? c.primary.withValues(alpha: 0.12) : c.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(Lulu.rSm),
        border: Border.all(color: accent ? c.primary.withValues(alpha: 0.35) : c.outlineVariant),
      ),
      child: TexteSurligne(
        texte,
        recherche,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: _mono.copyWith(fontSize: 11.5, height: 1.2, color: accent ? c.primary : c.onSurfaceVariant),
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
            const SizedBox(height: Lulu.sm),
            TextField(controller: langage, decoration: const InputDecoration(labelText: 'Langage (facultatif)', hintText: 'dart, sql, texte…')),
            const SizedBox(height: Lulu.sm),
            SizedBox(
              height: 260,
              child: TextField(
                controller: contenu,
                expands: true,
                maxLines: null,
                style: _mono.copyWith(fontSize: 13),
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

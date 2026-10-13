import '../../noyau/api/client_api.dart';
import '../../noyau/stockage/base_locale.dart';

/// UC-I30 : annonce publiée par l'administrateur (contrat 2.11, AnnonceDTO).
class Annonce {
  const Annonce({required this.id, required this.messageFr, required this.messageEn, this.finLe});

  factory Annonce.depuisJson(Map<String, dynamic> j) => Annonce(
        id: j['id'].toString(),
        messageFr: (j['messageFr'] ?? '').toString(),
        messageEn: (j['messageEn'] ?? '').toString(),
        finLe: DateTime.tryParse((j['finLe'] ?? '').toString()),
      );

  final String id;
  final String messageFr;
  final String messageEn;
  final DateTime? finLe;

  /// Le contrat ne porte pas de niveau : une annonce de maintenance est affichée en avertissement,
  /// les autres (nouveautés) en information.
  bool get estAvertissement {
    final m = messageFr.toLowerCase();
    return m.contains('maintenance') || m.contains('interruption') || m.contains('indisponib') || m.contains('panne');
  }
}

/// Récupère les annonces actives (GET /annonces/actives) et mémorise localement celles masquées.
class ServiceAnnonces {
  ServiceAnnonces(this.api, this.base);

  final ClientApi api;
  final BaseLocale base;

  static const _cleMasquees = 'annonces_masquees';

  /// Annonces actives non masquées. Ne lève jamais : en cas d'échec (hors ligne, serveur), liste vide.
  Future<List<Annonce>> visibles() async {
    try {
      final reponse = await api.get('/annonces/actives');
      if (reponse is! List) return const [];
      final masquees = await _masquees();
      return [
        for (final j in reponse)
          if (j is Map<String, dynamic>) Annonce.depuisJson(j),
      ].where((a) => a.messageFr.trim().isNotEmpty && !masquees.contains(a.id)).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Mémorise l'annonce comme masquée sur cet appareil.
  Future<void> masquer(String id) async {
    final masquees = await _masquees();
    if (masquees.add(id)) await base.ecrireMeta(_cleMasquees, masquees.toList());
  }

  Future<Set<String>> _masquees() async {
    try {
      final v = await base.lireMeta<Object>(_cleMasquees);
      return v is List ? v.map((e) => e.toString()).toSet() : <String>{};
    } catch (_) {
      return <String>{};
    }
  }
}

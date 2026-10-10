import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../api/client_api.dart';
import '../config.dart';
import '../crypto/base64url.dart';
import '../crypto/chiffrement.dart';
import '../session/service_compte.dart';
import '../stockage/base_locale.dart';

enum EtatSynchro { inactif, enCours, aJour, horsLigne, erreur }

/// Synchronisation hors ligne (contrat 2.5, ADR-005), côté app.
/// - Pousse les entités « sales » en les chiffrant au dernier moment.
/// - Tire les changements depuis la dernière version connue et les déchiffre.
/// - La dernière modification gagne ; le serveur archive les versions de post-it.
class MoteurSynchro extends ChangeNotifier {
  MoteurSynchro(this.api, this.crypto, this.base, this.compte) {
    compte.addListener(_surChangementSession);
  }

  final ClientApi api;
  final Chiffrement crypto;
  final BaseLocale base;
  final ServiceCompte compte;

  EtatSynchro etat = EtatSynchro.inactif;
  int enAttente = 0;
  String? derniereErreur;

  /// Événements temps réel reçus (envois, demandes de déverrouillage, conflits...).
  final evenements = StreamController<Map<String, dynamic>>.broadcast();

  Timer? _minuterieDifferee;
  Timer? _minuteriePeriodique;
  WebSocketChannel? _ws;
  StreamSubscription<dynamic>? _abonnementWs;
  int _delaiReconnexion = 2;
  bool _enCours = false;
  bool _relancer = false;

  bool get _actif => compte.etat.mode == ModeSession.actif && compte.cleMaitre != null;

  void _surChangementSession() {
    if (_actif) {
      _demarrer();
    } else {
      _arreter();
    }
  }

  void _demarrer() {
    _minuteriePeriodique ??= Timer.periodic(const Duration(seconds: 60), (_) => synchroniser());
    _connecterWs();
    unawaited(synchroniser());
  }

  void _arreter() {
    _minuteriePeriodique?.cancel();
    _minuteriePeriodique = null;
    _abonnementWs?.cancel();
    _ws?.sink.close();
    _ws = null;
    _changer(EtatSynchro.inactif);
  }

  void _changer(EtatSynchro e, [String? erreur]) {
    etat = e;
    derniereErreur = erreur;
    notifyListeners();
  }

  /// À appeler après chaque modification locale : synchro différée de 1,5 s (regroupe les frappes).
  void signalerModification() {
    if (!_actif) return;
    _minuterieDifferee?.cancel();
    _minuterieDifferee = Timer(const Duration(milliseconds: 1500), () => synchroniser());
  }

  Future<void> synchroniser() async {
    if (!_actif) return;
    if (_enCours) {
      _relancer = true;
      return;
    }
    _enCours = true;
    _changer(EtatSynchro.enCours);
    try {
      do {
        _relancer = false;
        await _pousser();
        await _tirer();
      } while (_relancer);
      enAttente = (await base.aEnvoyer()).length;
      _changer(EtatSynchro.aJour);
    } on ErreurApi catch (e) {
      enAttente = (await base.aEnvoyer()).length;
      _changer(e.horsLigne ? EtatSynchro.horsLigne : EtatSynchro.erreur, e.message);
    } catch (e) {
      _changer(EtatSynchro.erreur, e.toString());
    } finally {
      _enCours = false;
    }
  }

  // --- Envoi ---------------------------------------------------------------------------------

  Uint8List get _maitre => compte.cleMaitre!;

  /// Clé d'un élément ; une tâche utilise celle de sa liste (docs/07, §1).
  Future<Uint8List?> cleDe(Map<String, Object?> element) async {
    var courant = element;
    for (var i = 0; i < 60; i++) {
      if (courant['type'] != 'TACHE') {
        final cle = courant['cle'] as String?;
        return cle == null ? null : decoderB64(cle);
      }
      final parent = courant['parentId'] as String?;
      if (parent == null) return null;
      final p = await base.lire(Entite.element, parent);
      if (p == null) return null;
      courant = p;
    }
    return null;
  }

  Future<Map<String, dynamic>?> _versChangement(Entite e, Map<String, Object?> r) async {
    final id = r['id']! as String;
    final changement = <String, dynamic>{'entite': e.nom, 'id': id, 'modifieLe': r['modifieLe']};
    if (r['supprimeLe'] != null) {
      changement['supprimeLe'] = r['supprimeLe'];
      return changement;
    }
    final donnees = Map<String, dynamic>.from((r['donnees'] as Map?) ?? {});
    switch (e) {
      case Entite.element:
        if (r['type'] == 'FICHIER' && r['version'] == null) return null; // créé uniquement par /fichiers
        Uint8List? cle;
        String? cleEnveloppee;
        if (r['type'] == 'TACHE') {
          cle = await cleDe(r);
          if (cle == null) return null; // liste pas encore connue : on réessaiera
        } else {
          final existante = r['cle'] as String?;
          cle = existante != null ? decoderB64(existante) : crypto.aleatoire(32);
          if (existante == null) await base.fusionner(e, id, {'cle': encoderB64(cle)});
          cleEnveloppee = encoderB64(crypto.envelopperCleElement(_maitre, id, cle));
        }
        changement['donnees'] = {
          'type': r['type'],
          'parentId': r['parentId'],
          'elementSourceId': r['elementSourceId'],
          'epingleAccesRapide': r['epingleAccesRapide'] ?? false,
          'epingle': r['epingle'] ?? false,
          'typeContenu': r['typeContenu'],
          'archive': r['archive'] ?? false,
          if (cleEnveloppee != null) 'cleElementEnveloppee': cleEnveloppee,
          'contenuChiffre': encoderB64(crypto.aeadJson(cle, donnees, 'el:$id')),
        };
      case Entite.tableau:
        changement['donnees'] = {'contenuChiffre': encoderB64(crypto.aeadJson(_maitre, donnees, 'tb:$id'))};
      case Entite.etiquette:
        changement['donnees'] = {'contenuChiffre': encoderB64(crypto.aeadJson(_maitre, donnees, 'et:$id'))};
      case Entite.elementEtiquette:
        changement['donnees'] = {'elementId': r['elementId'], 'etiquetteId': r['etiquetteId']};
      case Entite.rappel:
        changement['donnees'] = {
          'elementId': r['elementId'],
          'prochaineEcheance': r['prochaineEcheance'],
          'recurrence': r['recurrence'],
          'joursSemaine': r['joursSemaine'] ?? <String>[],
          'fuseauHoraire': r['fuseauHoraire'] ?? 'UTC',
          'actif': r['actif'] ?? true,
        };
      case Entite.versionPostIt:
        return null; // créées par le serveur (D20)
    }
    return changement;
  }

  Future<void> _pousser() async {
    final sales = await base.aEnvoyer();
    // Listes, tableaux et étiquettes d'abord : leurs enfants en dépendent.
    int rang((Entite, Map<String, Object?>) x) {
      final (e, r) = x;
      if (e != Entite.element) return 0;
      return r['type'] == 'LISTE_TACHES' ? 1 : (r['type'] == 'TACHE' ? 3 : 2);
    }

    sales.sort((a, b) => rang(a).compareTo(rang(b)));
    var lot = <Map<String, dynamic>>[];
    var taille = 0;
    for (final (e, r) in sales) {
      final ch = await _versChangement(e, r);
      if (ch == null) continue;
      final t = jsonEncode(ch).length;
      if (lot.isNotEmpty && (lot.length >= 100 || taille + t > 8 * 1024 * 1024)) {
        await _envoyerLot(lot);
        lot = [];
        taille = 0;
      }
      lot.add(ch);
      taille += t;
    }
    if (lot.isNotEmpty) await _envoyerLot(lot);
  }

  Future<void> _envoyerLot(List<Map<String, dynamic>> lot) async {
    final r = await api.post('/synchro/envoyer', {'changements': lot}) as Map<String, dynamic>;
    for (final res in (r['resultats'] as List).cast<Map<String, dynamic>>()) {
      final e = Entite.depuis(res['entite'] as String);
      final id = res['id'] as String;
      final local = await base.lire(e, id);
      // Modifié de nouveau pendant l'envoi : on le garde « sale ».
      final envoye = lot.firstWhere((c) => c['id'] == id);
      if (local != null && local['modifieLe'] != envoye['modifieLe']) continue;
      await base.marquerPropre(e, id, version: res['versionServeur'] as int?);
      if (res['statut'] == 'ecrase_par_plus_recent') {
        // Une version plus récente existe ailleurs : on la retélécharge.
        final depuis = await base.lireMeta<int>('synchro_depuis') ?? 0;
        final v = (res['versionServeur'] as int? ?? 1) - 1;
        if (v < depuis) await base.ecrireMeta('synchro_depuis', v < 0 ? 0 : v);
      }
    }
  }

  // --- Réception -----------------------------------------------------------------------------

  Future<void> _tirer() async {
    var depuis = await base.lireMeta<int>('synchro_depuis') ?? 0;
    final enAttenteDeCle = <Map<String, dynamic>>[];
    while (true) {
      final r = await api.get('/synchro/changements', {'depuis': '$depuis', 'limite': '500'}) as Map<String, dynamic>;
      for (final ch in (r['changements'] as List).cast<Map<String, dynamic>>()) {
        if (!await _appliquer(ch)) enAttenteDeCle.add(ch);
      }
      depuis = r['versionCourante'] as int;
      await base.ecrireMeta('synchro_depuis', depuis);
      if (r['encore'] != true) break;
    }
    for (final ch in enAttenteDeCle) {
      await _appliquer(ch); // ex. tâche arrivée avant sa liste
    }
  }

  /// Applique un changement distant. Renvoie false si la clé nécessaire n'est pas encore connue.
  Future<bool> _appliquer(Map<String, dynamic> ch) async {
    final e = Entite.depuis(ch['entite'] as String);
    final id = ch['id'] as String;
    final local = await base.lire(e, id);
    if (local != null && local['sale'] == true && ch['supprimeLe'] == null) {
      final lm = DateTime.parse(local['modifieLe']! as String);
      final dm = DateTime.parse(ch['modifieLe'] as String);
      if (lm.isAfter(dm)) return true; // notre version locale est plus récente : elle sera envoyée
    }
    final d = Map<String, dynamic>.from(ch['donnees'] as Map);
    final rec = <String, Object?>{
      'id': id,
      'modifieLe': ch['modifieLe'],
      'supprimeLe': ch['supprimeLe'],
      'version': ch['version'],
    };
    if (ch['supprimeLe'] != null) {
      await base.enregistrerDistant(e, {...?local, ...rec, 'donnees': <String, Object?>{}});
      return true;
    }
    try {
      switch (e) {
        case Entite.element:
          rec.addAll({
            'type': d['type'],
            'parentId': d['parentId'],
            'elementSourceId': d['elementSourceId'],
            'epingleAccesRapide': d['epingleAccesRapide'],
            'epingle': d['epingle'],
            'typeContenu': d['typeContenu'],
            'archive': d['archive'],
          });
          Uint8List? cle;
          if (d['type'] == 'TACHE') {
            cle = await cleDe(rec);
            if (cle == null) return false;
          } else if (d['cleElementEnveloppee'] != null) {
            cle = crypto.ouvrirCleElement(_maitre, id, decoderB64(d['cleElementEnveloppee'] as String));
            rec['cle'] = encoderB64(cle);
          }
          rec['donnees'] = cle != null && d['contenuChiffre'] != null
              ? crypto.ouvrirJson(cle, decoderB64(d['contenuChiffre'] as String), 'el:$id')
              : <String, Object?>{};
        case Entite.tableau:
        case Entite.etiquette:
          final ad = e == Entite.tableau ? 'tb:$id' : 'et:$id';
          rec['donnees'] = crypto.ouvrirJson(_maitre, decoderB64(d['contenuChiffre'] as String), ad);
        case Entite.elementEtiquette:
          rec.addAll({'elementId': d['elementId'], 'etiquetteId': d['etiquetteId']});
        case Entite.rappel:
          rec.addAll({
            'elementId': d['elementId'],
            'prochaineEcheance': d['prochaineEcheance'],
            'recurrence': d['recurrence'],
            'joursSemaine': d['joursSemaine'],
            'fuseauHoraire': d['fuseauHoraire'],
            'actif': d['actif'],
          });
        case Entite.versionPostIt:
          final postIt = await base.lire(Entite.element, d['postItId'] as String);
          final cle = postIt == null ? null : await cleDe(postIt);
          if (cle == null) return false;
          rec.addAll({
            'postItId': d['postItId'],
            'creeLe': d['creeLe'],
            'donnees': crypto.ouvrirJson(cle, decoderB64(d['contenuChiffre'] as String), 'el:${d['postItId']}'),
          });
      }
    } on FormatException {
      return true; // format inconnu (version future) : ignoré sans bloquer la synchro
    }
    await base.enregistrerDistant(e, rec);
    return true;
  }

  // --- WebSocket (contrat 2.6) ---------------------------------------------------------------

  void _connecterWs() {
    if (_ws != null || !_actif) return;
    try {
      final ws = WebSocketChannel.connect(Uri.parse(Config.wsUrl));
      _ws = ws;
      ws.sink.add(jsonEncode({'type': 'auth', 'jeton': api.jeton}));
      _abonnementWs = ws.stream.listen(
        (message) {
          final ev = jsonDecode(message as String) as Map<String, dynamic>;
          if (ev['type'] == 'pret') _delaiReconnexion = 2;
          if (ev['type'] == 'changements') signalerModification();
          if (ev['type'] == 'appareil_revoque' && ev['appareilId'] == compte.etat.appareil?['id']) {
            unawaited(compte.appareilRevoque());
          }
          evenements.add(ev);
        },
        onDone: _reconnecter,
        onError: (_) => _reconnecter(),
        cancelOnError: true,
      );
    } catch (_) {
      _reconnecter();
    }
  }

  void _reconnecter() {
    _abonnementWs?.cancel();
    _ws = null;
    if (!_actif) return;
    Timer(Duration(seconds: _delaiReconnexion), _connecterWs);
    _delaiReconnexion = (_delaiReconnexion * 2).clamp(2, 60);
  }

  @override
  void dispose() {
    _arreter();
    compte.removeListener(_surChangementSession);
    super.dispose();
  }
}

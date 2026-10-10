import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../config.dart';

/// Erreur au format commun du contrat : `{ "erreur": { "code", "message", ... } }`.
/// L'app se fie à [code], jamais à [message].
class ErreurApi implements Exception {
  ErreurApi(this.statut, this.code, this.message, {this.details, this.champs});

  final int statut;
  final String code;
  final String message;
  final Map<String, dynamic>? details;
  final List<dynamic>? champs;

  bool get horsLigne => code == 'hors_ligne';

  @override
  String toString() => message;
}

/// Client HTTP du contrat d'API v1 (docs/05-contrat-api.md).
class ClientApi {
  ClientApi({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;
  String? jeton;

  /// Appelé quand le serveur répond 401 : la session n'est plus valide.
  void Function()? surSessionInvalide;

  Map<String, String> _entetes({bool json = true}) => {
        if (json) 'Content-Type': 'application/json',
        'Accept': 'application/json',
        'X-App-Version': Config.versionApp,
        if (jeton != null) 'Authorization': 'Bearer $jeton',
      };

  Uri _uri(String chemin, [Map<String, String>? params]) =>
      Uri.parse('${Config.apiBase}$chemin').replace(queryParameters: params);

  Future<dynamic> _envoyer(Future<http.Response> Function() requete) async {
    http.Response r;
    try {
      r = await requete().timeout(const Duration(seconds: 60));
    } on TimeoutException {
      throw ErreurApi(0, 'hors_ligne', 'Le serveur ne répond pas.');
    } catch (_) {
      throw ErreurApi(0, 'hors_ligne', 'Pas de connexion au serveur.');
    }
    if (r.statusCode >= 200 && r.statusCode < 300) {
      if (r.body.isEmpty) return null;
      return jsonDecode(utf8.decode(r.bodyBytes));
    }
    Map<String, dynamic> erreur = {};
    try {
      erreur = (jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>)['erreur'] as Map<String, dynamic>;
    } catch (_) {}
    final code = erreur['code'] as String? ?? 'service_indisponible';
    if (r.statusCode == 401 && (code == 'non_authentifie' || code == 'session_expiree')) {
      surSessionInvalide?.call();
    }
    throw ErreurApi(
      r.statusCode,
      code,
      erreur['message'] as String? ?? 'Erreur ${r.statusCode}',
      details: erreur['details'] as Map<String, dynamic>?,
      champs: erreur['champs'] as List<dynamic>?,
    );
  }

  Future<dynamic> get(String chemin, [Map<String, String>? params]) =>
      _envoyer(() => _http.get(_uri(chemin, params), headers: _entetes()));

  Future<dynamic> post(String chemin, [Object? corps]) =>
      _envoyer(() => _http.post(_uri(chemin), headers: _entetes(), body: corps == null ? null : jsonEncode(corps)));

  Future<dynamic> put(String chemin, Object corps) =>
      _envoyer(() => _http.put(_uri(chemin), headers: _entetes(), body: jsonEncode(corps)));

  Future<dynamic> patch(String chemin, Object corps) =>
      _envoyer(() => _http.patch(_uri(chemin), headers: _entetes(), body: jsonEncode(corps)));

  Future<dynamic> delete(String chemin, [Object? corps]) =>
      _envoyer(() => _http.delete(_uri(chemin), headers: _entetes(), body: corps == null ? null : jsonEncode(corps)));

  /// Envoi multipart d'un fichier déjà chiffré (contrat 2.7).
  Future<dynamic> televerser(Map<String, dynamic> metadonnees, Uint8List octets,
      {void Function(int envoyes, int total)? progression}) async {
    final requete = http.MultipartRequest('POST', _uri('/fichiers'))
      ..headers.addAll(_entetes(json: false))
      ..fields['metadonnees'] = jsonEncode(metadonnees)
      ..files.add(http.MultipartFile.fromBytes('fichier', octets, filename: '${metadonnees['id']}.bin'));
    return _envoyer(() async => http.Response.fromStream(await _http.send(requete)));
  }

  /// Téléchargement brut (octets chiffrés) : fichiers et liens publics.
  Future<Uint8List> telecharger(String urlOuChemin) async {
    final uri = urlOuChemin.startsWith('http') ? Uri.parse(urlOuChemin) : Uri.parse('${Config.apiUrl}$urlOuChemin');
    final r = await _http.get(uri, headers: urlOuChemin.startsWith(Config.apiUrl) || !urlOuChemin.startsWith('http') ? _entetes(json: false) : {});
    if (r.statusCode != 200 && r.statusCode != 206) {
      throw ErreurApi(r.statusCode, 'telechargement_impossible', 'Téléchargement impossible (${r.statusCode}).');
    }
    return r.bodyBytes;
  }
}

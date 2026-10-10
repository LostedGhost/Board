import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../crypto/base64url.dart';

/// Secrets de l'appareil, dans le stockage sécurisé du système (D41) :
/// trousseau Windows/macOS/iOS, Keystore Android, stockage chiffré du navigateur.
class Coffre {
  Coffre([FlutterSecureStorage? stockage]) : _s = stockage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _s;

  static const _jeton = 'jeton';
  static const _appareilId = 'appareil_id';
  static const _publique = 'appareil_publique';
  static const _privee = 'appareil_privee';
  static const _maitre = 'cle_maitre';

  Future<String?> get jeton => _s.read(key: _jeton);
  Future<void> ecrireJeton(String? v) => v == null ? _s.delete(key: _jeton) : _s.write(key: _jeton, value: v);

  Future<String?> get appareilId => _s.read(key: _appareilId);
  Future<void> ecrireAppareilId(String v) => _s.write(key: _appareilId, value: v);

  Future<({Uint8List publique, Uint8List privee})?> get paireAppareil async {
    final pub = await _s.read(key: _publique), priv = await _s.read(key: _privee);
    if (pub == null || priv == null) return null;
    return (publique: decoderB64(pub), privee: decoderB64(priv));
  }

  Future<void> ecrirePaireAppareil(Uint8List publique, Uint8List privee) async {
    await _s.write(key: _publique, value: encoderB64(publique));
    await _s.write(key: _privee, value: encoderB64(privee));
  }

  Future<Uint8List?> get cleMaitre async {
    final v = await _s.read(key: _maitre);
    return v == null ? null : decoderB64(v);
  }

  Future<void> ecrireCleMaitre(Uint8List? v) =>
      v == null ? _s.delete(key: _maitre) : _s.write(key: _maitre, value: encoderB64(v));

  /// Déconnexion ou révocation : plus aucune clé ni session sur cet appareil.
  Future<void> toutEffacer() => _s.deleteAll();
}

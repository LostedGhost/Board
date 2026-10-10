import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:sodium/sodium_sumo.dart';

import 'base64url.dart';

/// Format de chiffrement v1 (docs/07-format-chiffrement.md).
/// Même logique, mêmes octets que l'implémentation de référence `backend/e2e/crypto.py`.
class Chiffrement {
  Chiffrement(this.sodium);

  final SodiumSumo sodium;

  static const _version = 1;
  static const tailleBlocFichier = 64 * 1024;

  static Future<Chiffrement> initialiser() async => Chiffrement(await SodiumSumoInit.init());

  Uint8List aleatoire(int n) => sodium.randombytes.buf(n);

  // --- AEAD XChaCha20-Poly1305 avec données associées (§2) ---------------------------------

  Uint8List aead(Uint8List cle, Uint8List clair, String ad) {
    final aead = sodium.crypto.aeadXChaCha20Poly1305IETF;
    final nonce = aleatoire(aead.nonceBytes);
    final k = sodium.secureCopy(cle);
    try {
      final corps = aead.encrypt(message: clair, nonce: nonce, key: k, additionalData: utf8.encode(ad));
      return Uint8List.fromList([_version, ...nonce, ...corps]);
    } finally {
      k.dispose();
    }
  }

  Uint8List ouvrir(Uint8List cle, Uint8List chiffre, String ad) {
    if (chiffre.isEmpty || chiffre[0] != _version) {
      throw const FormatException('Version de format inconnue');
    }
    final aead = sodium.crypto.aeadXChaCha20Poly1305IETF;
    final n = aead.nonceBytes;
    final k = sodium.secureCopy(cle);
    try {
      return aead.decrypt(
        cipherText: chiffre.sublist(1 + n),
        nonce: chiffre.sublist(1, 1 + n),
        key: k,
        additionalData: utf8.encode(ad),
      );
    } finally {
      k.dispose();
    }
  }

  Uint8List aeadJson(Uint8List cle, Map<String, dynamic> donnees, String ad) =>
      aead(cle, Uint8List.fromList(utf8.encode(jsonEncode(donnees))), ad);

  Map<String, dynamic> ouvrirJson(Uint8List cle, Uint8List chiffre, String ad) =>
      jsonDecode(utf8.decode(ouvrir(cle, chiffre, ad))) as Map<String, dynamic>;

  // --- Clés d'appareil et enveloppes (§3) ---------------------------------------------------

  ({Uint8List publique, Uint8List privee}) paireAppareil() {
    final paire = sodium.crypto.box.keyPair();
    try {
      return (publique: paire.publicKey, privee: paire.secretKey.extractBytes());
    } finally {
      paire.secretKey.dispose();
    }
  }

  Uint8List scellerPour(Uint8List clePublique, Uint8List cleMaitre) =>
      sodium.crypto.box.seal(message: cleMaitre, publicKey: clePublique);

  Uint8List desceller(Uint8List enveloppe, Uint8List publique, Uint8List privee) {
    final k = sodium.secureCopy(privee);
    try {
      return sodium.crypto.box.sealOpen(cipherText: enveloppe, publicKey: publique, secretKey: k);
    } finally {
      k.dispose();
    }
  }

  // --- Clé de vérification Ed25519 dérivée de la clé maître (§1) ------------------------------

  KeyPair _paireVerification(Uint8List cleMaitre) {
    final k = sodium.secureCopy(cleMaitre);
    try {
      final graine = sodium.crypto.genericHash(
        message: Uint8List.fromList(utf8.encode('luluboard-verification-v1')),
        outLen: 32,
        key: k,
      );
      final g = sodium.secureCopy(graine);
      try {
        return sodium.crypto.sign.seedKeyPair(g);
      } finally {
        g.dispose();
      }
    } finally {
      k.dispose();
    }
  }

  Uint8List clePubliqueVerification(Uint8List cleMaitre) {
    final paire = _paireVerification(cleMaitre);
    paire.secretKey.dispose();
    return paire.publicKey;
  }

  Uint8List signerDefi(Uint8List cleMaitre, Uint8List defi) {
    final paire = _paireVerification(cleMaitre);
    try {
      return sodium.crypto.sign.detached(message: defi, secretKey: paire.secretKey);
    } finally {
      paire.secretKey.dispose();
    }
  }

  // --- Clé de récupération --------------------------------------------------------------------

  Uint8List enveloppeRecuperation(Uint8List cleRecup, Uint8List cleMaitre) => aead(cleRecup, cleMaitre, 'recup:v1');

  Uint8List ouvrirRecuperation(Uint8List cleRecup, Uint8List enveloppe) => ouvrir(cleRecup, enveloppe, 'recup:v1');

  // --- Éléments (§2, §4) ----------------------------------------------------------------------

  Uint8List envelopperCleElement(Uint8List cleMaitre, String id, Uint8List cleElement) =>
      aead(cleMaitre, cleElement, 'cle:$id');

  Uint8List ouvrirCleElement(Uint8List cleMaitre, String id, Uint8List enveloppee) =>
      ouvrir(cleMaitre, enveloppee, 'cle:$id');

  // --- Liens protégés par mot de passe (§6) -----------------------------------------------------

  /// Renvoie (clé du lien, vérificateur envoyé au serveur). Coûteux : Argon2id, 64 Mo.
  ({Uint8List cleLien, Uint8List verificateur}) deriverLien(String motDePasse, Uint8List sel) {
    final pw = sodium.crypto.pwhash;
    final s = pw(
      outLen: 64,
      password: Int8List.fromList(utf8.encode(motDePasse)),
      salt: sel,
      opsLimit: pw.opsLimitInteractive,
      memLimit: pw.memLimitInteractive,
      alg: CryptoPwhashAlgorithm.argon2id13,
    );
    try {
      final octets = s.extractBytes();
      return (cleLien: octets.sublist(0, 32), verificateur: octets.sublist(32, 64));
    } finally {
      s.dispose();
    }
  }

  // --- Fichiers : secretstream par blocs de 64 Kio (§5) ---------------------------------------

  Future<Uint8List> chiffrerFichier(Uint8List cleElement, Uint8List clair) async {
    final k = sodium.secureCopy(cleElement);
    try {
      final sortie = BytesBuilder(copy: false);
      await for (final bloc in sodium.crypto.secretStream.pushChunked(
        messageStream: Stream.value(clair),
        key: k,
        chunkSize: tailleBlocFichier,
      )) {
        sortie.add(bloc);
      }
      return sortie.takeBytes();
    } finally {
      k.dispose();
    }
  }

  Future<Uint8List> dechiffrerFichier(Uint8List cleElement, Uint8List chiffre) async {
    final k = sodium.secureCopy(cleElement);
    try {
      final sortie = BytesBuilder(copy: false);
      await for (final bloc in sodium.crypto.secretStream.pullChunked(
        cipherStream: Stream.value(chiffre),
        key: k,
        chunkSize: tailleBlocFichier, // taille du clair : la bibliothèque ajoute elle-même les 17 octets d'authentification
      )) {
        sortie.add(bloc);
      }
      return sortie.takeBytes();
    } finally {
      k.dispose();
    }
  }

  String b64(Uint8List o) => encoderB64(o);
  Uint8List deb64(String t) => decoderB64(t);
}

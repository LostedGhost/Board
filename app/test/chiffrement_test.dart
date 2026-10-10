import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:luluboard/noyau/crypto/base64url.dart';
import 'package:luluboard/noyau/crypto/chiffrement.dart';

/// Compatibilité octet pour octet avec l'implémentation de référence Python (backend/e2e/crypto.py),
/// elle-même validée de bout en bout contre le serveur (docs/08).
void main() {
  late Chiffrement c;
  late Map<String, dynamic> v;

  setUpAll(() async {
    c = await Chiffrement.initialiser();
    v = jsonDecode(File('test/vecteurs_crypto.json').readAsStringSync()) as Map<String, dynamic>;
  });

  test('clé de vérification Ed25519 dérivée identique', () {
    expect(encoderB64(c.clePubliqueVerification(decoderB64(v['cleMaitre'] as String))), v['clePubliqueVerification']);
  });

  test('signature du défi identique (Ed25519 déterministe)', () {
    final sig = c.signerDefi(decoderB64(v['cleMaitre'] as String), decoderB64(v['defi'] as String));
    expect(encoderB64(sig), v['signatureDefi']);
  });

  test('ouverture de l\'enveloppe de récupération produite par Python', () {
    final maitre = c.ouvrirRecuperation(decoderB64(v['cleRecup'] as String), decoderB64(v['enveloppeRecuperation'] as String));
    expect(encoderB64(maitre), v['cleMaitre']);
  });

  test('desceller l\'enveloppe d\'appareil (crypto_box_seal) produite par Python', () {
    final maitre = c.desceller(
      decoderB64(v['enveloppeAppareil'] as String),
      decoderB64(v['appareilPublique'] as String),
      decoderB64(v['appareilPrivee'] as String),
    );
    expect(encoderB64(maitre), v['cleMaitre']);
  });

  test('clé d\'élément et contenu JSON déchiffrés', () {
    final id = v['idElement'] as String;
    final cle = c.ouvrirCleElement(decoderB64(v['cleMaitre'] as String), id, decoderB64(v['cleElementEnveloppee'] as String));
    expect(encoderB64(cle), v['cleElement']);
    expect(c.ouvrirJson(cle, decoderB64(v['contenuChiffre'] as String), 'el:$id'), v['contenuClair']);
  });

  test('les données associées empêchent de déplacer un contenu vers un autre élément', () {
    final cle = decoderB64(v['cleElement'] as String);
    expect(() => c.ouvrir(cle, decoderB64(v['contenuChiffre'] as String), 'el:autre-id'), throwsA(anything));
  });

  test('aller-retour Dart → Dart et tableau chiffré par Python', () {
    final maitre = decoderB64(v['cleMaitre'] as String);
    final t = v['tableau'] as Map<String, dynamic>;
    expect(c.ouvrirJson(maitre, decoderB64(t['chiffre'] as String), 'tb:${t['id']}'), {'nom': 'Perso'});
    final chiffre = c.aeadJson(maitre, {'a': 1}, 'tb:x');
    expect(c.ouvrirJson(maitre, chiffre, 'tb:x'), {'a': 1});
  });

  test('dérivation Argon2id du lien protégé identique', () {
    final l = v['lien'] as Map<String, dynamic>;
    final d = c.deriverLien(l['motDePasse'] as String, decoderB64(l['sel'] as String));
    expect(encoderB64(d.cleLien), l['cleLien']);
    expect(encoderB64(d.verificateur), l['verificateur']);
  });

  test('fichier secretstream (blocs de 64 Kio) chiffré par Python, déchiffré par Dart, et inversement', () async {
    final cle = decoderB64(v['cleElement'] as String);
    final clair = await c.dechiffrerFichier(cle, decoderB64(v['fichierChiffre'] as String));
    expect(encoderB64(clair), v['fichierClair']);
    final rechiffre = await c.chiffrerFichier(cle, clair);
    expect(rechiffre.length, decoderB64(v['fichierChiffre'] as String).length);
    expect(encoderB64(await c.dechiffrerFichier(cle, rechiffre)), v['fichierClair']);
  });

  test('clé de récupération en base32 Crockford : aller-retour et tolérance de saisie', () {
    final cle = decoderB64(v['cleRecup'] as String);
    final texte = Base32Crockford.encoder(cle);
    expect(texte.split('-').length, 13);
    expect(encoderB64(Base32Crockford.decoder(texte.toLowerCase().replaceAll('-', ' '))), v['cleRecup']);
  });
}

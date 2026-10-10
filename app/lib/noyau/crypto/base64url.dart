import 'dart:convert';
import 'dart:typed_data';

/// base64url sans remplissage (contrat, section 1).
String encoderB64(List<int> octets) => base64Url.encode(octets).replaceAll('=', '');

Uint8List decoderB64(String texte) {
  final reste = texte.length % 4;
  return base64Url.decode(reste == 0 ? texte : texte + '=' * (4 - reste));
}

/// Clé de récupération affichée en base32 Crockford, par groupes de 4 (docs/07, §1).
class Base32Crockford {
  static const _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  static String encoder(Uint8List octets) {
    final sortie = StringBuffer();
    var tampon = 0, bits = 0;
    for (final o in octets) {
      tampon = (tampon << 8) | o;
      bits += 8;
      while (bits >= 5) {
        sortie.write(_alphabet[(tampon >> (bits - 5)) & 31]);
        bits -= 5;
      }
    }
    if (bits > 0) sortie.write(_alphabet[(tampon << (5 - bits)) & 31]);
    final brut = sortie.toString();
    final groupes = <String>[];
    for (var i = 0; i < brut.length; i += 4) {
      groupes.add(brut.substring(i, i + 4 > brut.length ? brut.length : i + 4));
    }
    return groupes.join('-');
  }

  /// Tolère minuscules, espaces, tirets et les confusions classiques (O→0, I/L→1).
  static Uint8List decoder(String texte, {int longueur = 32}) {
    final propre = texte
        .toUpperCase()
        .replaceAll(RegExp(r'[\s-]'), '')
        .replaceAll('O', '0')
        .replaceAll(RegExp('[IL]'), '1');
    final sortie = <int>[];
    var tampon = 0, bits = 0;
    for (final c in propre.split('')) {
      final v = _alphabet.indexOf(c);
      if (v < 0) throw const FormatException('Caractère invalide dans la clé');
      tampon = (tampon << 5) | v;
      bits += 5;
      if (bits >= 8) {
        sortie.add((tampon >> (bits - 8)) & 255);
        bits -= 8;
      }
    }
    if (sortie.length < longueur) throw const FormatException('Clé incomplète');
    return Uint8List.fromList(sortie.sublist(0, longueur));
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:luluboard/noyau/depot.dart';
import 'package:luluboard/ui/mentions.dart';

void main() {
  group('analyserMentions', () {
    test('titre et identifiant', () {
      const t = 'Voir [[Courses|abc-123]] puis [[Idée]].';
      expect(analyserMentions(t), [
        const Mention('Courses', 'abc-123', 5, 24),
        const Mention('Idée', null, 30, 38),
      ]);
    });

    test('espaces retirés, syntaxes invalides ignorées', () {
      expect(analyserMentions('[[  Projet X  |  id1 ]]').single, const Mention('Projet X', 'id1', 0, 23));
      expect(analyserMentions('[[]] [[|id]] [[a\nb]] [lien](x) [[non fermé'), isEmpty);
    });

    test('segmenter alterne texte et mentions', () {
      final s = segmenter('A [[B|1]] C');
      expect(s.map((e) => e.mention?.titre ?? e.texte).toList(), ['A ', 'B', ' C']);
      expect(segmenter('sans mention').single.texte, 'sans mention');
    });

    test('texteSansMentions', () {
      expect(texteSansMentions('Lire [[Livre|x]] et [[Film]]'), 'Lire Livre et Film');
    });
  });

  group('formatage', () {
    test('le titre est nettoyé des caractères de la syntaxe', () {
      expect(formaterMention('Plan [v2] | final\nsuite', 'id9'), '[[Plan v2 final suite|id9]]');
      expect(formaterMention('  ', 'id'), '[[Sans titre|id]]');
      final m = analyserMentions(formaterMention('a|b]c', 'z')).single;
      expect((m.titre, m.id), ('a b c', 'z'));
    });
  });

  group('saisie et insertion', () {
    test('requeteEnCours détecte [[ avant le curseur', () {
      expect(requeteEnCours('Voir [[cou', 10), const RequeteMention(5, 'cou'));
      expect(requeteEnCours('[[', 2), const RequeteMention(0, ''));
      expect(requeteEnCours('Voir [[a|b]] fin', 16), isNull);
      expect(requeteEnCours('[[a\nb', 5), isNull);
      expect(requeteEnCours('pas de mention', 5), isNull);
      expect(requeteEnCours('x', 9), isNull);
    });

    test('insererMention remplace la saisie et place le curseur après', () {
      const texte = 'Voir [[cou suite';
      final r = requeteEnCours(texte, 10)!;
      final res = insererMention(texte, 10, r, 'Courses', 'id1');
      expect(res.texte, 'Voir [[Courses|id1]] suite');
      expect(res.curseur, 'Voir [[Courses|id1]]'.length);
    });

    test('insererMention absorbe les ]] déjà tapés', () {
      const texte = '[[co]]';
      final res = insererMention(texte, 4, requeteEnCours(texte, 4)!, 'Code', 'z');
      expect(res.texte, '[[Code|z]]');
    });
  });

  group('Markdown', () {
    test('mentions converties en liens internes, code laissé intact', () {
      const md = 'Voir [[Note *1*|a b]]\n`[[code|x]]` et [[T|y]]\n```\n[[bloc|z]]\n```';
      expect(markdownAvecMentions(md),
          'Voir [Note \\*1\\*](lulu-mention:a%20b)\n`[[code|x]]` et [T](lulu-mention:y)\n```\n[[bloc|z]]\n```');
      expect(markdownAvecMentions('[[Seul]]'), '[Seul](lulu-mention:)');
    });
  });

  group('titreElement', () {
    Enr el(String type, Map<String, Object?> d) => {'id': '1', 'type': type, 'donnees': d};

    test('première ligne utile, sans balisage Markdown', () {
      expect(titreElement(el(TypeEl.postIt, {'contenu': '\n# **Réunion** du [[Lundi|x]]\nsuite'})), 'Réunion du Lundi');
      expect(titreElement(el(TypeEl.tache, {'titre': '- [ ] Acheter'})), 'Acheter');
      expect(titreElement(el(TypeEl.snippet, {'titre': 'Tri', 'contenu': 'code'})), 'Tri');
      expect(titreElement(el(TypeEl.fichier, {'nom': 'plan.pdf'})), 'plan.pdf');
      expect(titreElement(el(TypeEl.pressePapier, {'image': 'b64'})), 'Image');
      expect(titreElement(el(TypeEl.postIt, {'contenu': ''})), 'Sans titre');
    });
  });
}

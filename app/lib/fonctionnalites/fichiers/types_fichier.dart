import 'package:flutter/material.dart';

/// Taille maximale d'un fichier (E1).
const tailleMaxFichier = 100 * 1024 * 1024;

/// Extension en minuscules, sans le point (chaîne vide si absente).
String extensionDe(String nom) {
  final i = nom.lastIndexOf('.');
  return i <= 0 || i == nom.length - 1 ? '' : nom.substring(i + 1).toLowerCase();
}

/// Taille lisible : « 512 o », « 12,4 Ko », « 3,2 Mo », « 1,1 Go ».
String tailleLisible(num octets) {
  String fmt(double v) => (v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1)).replaceAll('.', ',');
  if (octets < 1024) return '${octets.toInt()} o';
  if (octets < 1024 * 1024) return '${fmt(octets / 1024)} Ko';
  if (octets < 1024 * 1024 * 1024) return '${fmt(octets / 1024 / 1024)} Mo';
  return '${fmt(octets / 1024 / 1024 / 1024)} Go';
}

/// Famille d'un fichier d'après son extension : icône et libellé (lecteurs d'écran, infobulles).
({IconData icone, String libelle}) familleDe(String nom) {
  final ext = extensionDe(nom);
  for (final (exts, icone, libelle) in _familles) {
    if (exts.contains(ext)) return (icone: icone, libelle: libelle);
  }
  return (icone: Icons.insert_drive_file_outlined, libelle: ext.isEmpty ? 'Fichier' : 'Fichier ${ext.toUpperCase()}');
}

const _familles = <(Set<String>, IconData, String)>[
  ({'pdf'}, Icons.picture_as_pdf_outlined, 'Document PDF'),
  ({'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'svg', 'heic', 'tif', 'tiff', 'ico'}, Icons.image_outlined, 'Image'),
  ({'mp4', 'mov', 'avi', 'mkv', 'webm', 'm4v', 'wmv'}, Icons.movie_outlined, 'Vidéo'),
  ({'mp3', 'wav', 'ogg', 'flac', 'm4a', 'aac', 'opus'}, Icons.audio_file_outlined, 'Audio'),
  ({'zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz'}, Icons.folder_zip_outlined, 'Archive'),
  ({'doc', 'docx', 'odt', 'rtf', 'pages'}, Icons.description_outlined, 'Document texte'),
  ({'xls', 'xlsx', 'ods', 'csv', 'numbers'}, Icons.table_chart_outlined, 'Tableur'),
  ({'ppt', 'pptx', 'odp', 'key'}, Icons.slideshow_outlined, 'Présentation'),
  ({'txt', 'md', 'log'}, Icons.article_outlined, 'Texte'),
  (
    {'dart', 'js', 'ts', 'py', 'java', 'kt', 'c', 'cpp', 'h', 'cs', 'go', 'rs', 'rb', 'php', 'html', 'css', 'json', 'xml', 'yaml', 'yml', 'sh', 'sql'},
    Icons.code,
    'Code source',
  ),
  ({'exe', 'msi', 'apk', 'dmg', 'deb', 'appimage', 'ipa'}, Icons.install_desktop_outlined, 'Installateur'),
];

/// Type MIME indicatif (métadonnée chiffrée ; LuluBoard n'ouvre jamais le fichier).
String mimeDe(String nom) =>
    const {
      'pdf': 'application/pdf',
      'png': 'image/png',
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'gif': 'image/gif',
      'webp': 'image/webp',
      'txt': 'text/plain',
      'csv': 'text/csv',
      'json': 'application/json',
      'zip': 'application/zip',
      'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'mp4': 'video/mp4',
      'mp3': 'audio/mpeg',
    }[extensionDe(nom)] ??
    'application/octet-stream';

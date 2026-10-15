/// Configuration de l'app, fournie à la compilation :
/// `flutter run --dart-define=API_URL=https://api.exemple.com`.
class Config {
  static const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://127.0.0.1:8000');
  static const versionApp = '0.1.0';

  static String get apiBase => '$apiUrl/api/v1';

  static String get wsUrl => '${apiUrl.replaceFirst('http', 'ws')}/api/v1/ws';

  /// Site public qui héberge la page de consultation des liens (public/l/), distinct de l'API.
  static const siteUrl = String.fromEnvironment('SITE_URL', defaultValue: 'http://127.0.0.1:5191');

  /// Lien public : `/l/?t=<jeton>` fonctionne sur tout hébergeur statique, sans règle de réécriture.
  /// La clé reste dans le fragment `#`, jamais envoyé au serveur.
  static String lienPublic(String jeton, {String? fragment}) =>
      '$siteUrl/l/?t=$jeton${fragment != null ? '#$fragment' : ''}';
}

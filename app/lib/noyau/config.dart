/// Configuration de l'app, fournie à la compilation :
/// `flutter run --dart-define=API_URL=https://api.exemple.com`.
class Config {
  static const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://127.0.0.1:8000');
  static const versionApp = '0.1.0';

  static String get apiBase => '$apiUrl/api/v1';

  static String get wsUrl => '${apiUrl.replaceFirst('http', 'ws')}/api/v1/ws';

  /// Domaine des liens publics : la page /l/{jeton} est servie par le backend.
  static String lienPublic(String jeton, {String? fragment}) =>
      '$apiUrl/l/$jeton${fragment != null ? '#$fragment' : ''}';
}

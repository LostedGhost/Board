import '../noyau/noyau.dart';

/// Web : pas d'intégration système (capture du presse-papier impossible dans un navigateur, B2).
class IntegrationDesktop {
  static Future<void> initialiser(Noyau noyau) async {}
  static Future<void> notifier(String titre, String texte) async {}
  static Future<void> basculerPremierPlan(bool actif) async {}
  static bool get captureDisponible => false;
  static Future<void> definirPause(bool pause) async {}
  static Future<void> definirDemarrageAuto(bool actif) async {}
  static Future<void> ouvrirDossier(String chemin) async {}
}

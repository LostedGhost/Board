import 'package:sembast_web/sembast_web.dart';

/// Base locale dans IndexedDB (navigateur).
Future<Database> ouvrirBase(String nom) => databaseFactoryWeb.openDatabase(nom);

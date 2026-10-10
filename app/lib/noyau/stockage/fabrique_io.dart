import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';

/// Base locale sur disque (desktop et mobile).
Future<Database> ouvrirBase(String nom) async {
  final dossier = await getApplicationSupportDirectory();
  return databaseFactoryIo.openDatabase(p.join(dossier.path, '$nom.db'));
}

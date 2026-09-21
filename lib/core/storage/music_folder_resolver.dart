import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Résout le dossier de bibliothèque locale — équivalent pratique de
/// "/Music/AppFolder/" (voir AppConstants). Un chemin absolu littéral comme
/// `/storage/emulated/0/Music/AppFolder` n'est plus inscriptible sans la
/// permission sensible MANAGE_EXTERNAL_STORAGE depuis le stockage cloisonné
/// d'Android 10+ (testé sur émulateur — écriture refusée). On utilise donc le
/// stockage externe propre à l'app, inscriptible sans permission
/// supplémentaire, avec la même arborescence `Music/AppFolder`.
class MusicFolderResolver {
  static Directory? _cached;

  static Future<Directory> resolve() async {
    final Directory? cached = _cached;
    if (cached != null) return cached;

    final Directory base = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
    final Directory folder = Directory(p.join(base.path, 'Music', 'AppFolder'));
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }

    _cached = folder;
    return folder;
  }
}

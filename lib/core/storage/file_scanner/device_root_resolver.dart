import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Résout la racine de stockage partagée de l'appareil (ex.
/// `/storage/emulated/0`), à ne pas confondre avec [MusicFolderResolver] qui
/// lui reste cantonné au dossier privé de l'app. Nécessaire pour le scan
/// plein-appareil du premier lancement (Étape 8) : `path_provider` n'expose
/// pas directement cette racine partagée, seulement des dossiers propres à
/// l'app (`.../Android/data/<package>/files`), donc on la dérive en retirant
/// ce suffixe.
class DeviceRootResolver {
  static Future<Directory?> resolve() async {
    final Directory? appScoped = await getExternalStorageDirectory();
    if (appScoped == null) return null;

    final String path = appScoped.path.replaceAll('\\', '/');
    final int androidIndex = path.indexOf('/Android/');
    if (androidIndex == -1) return null;

    final Directory root = Directory(path.substring(0, androidIndex));
    return await root.exists() ? root : null;
  }
}

import 'dart:async';
import 'dart:io';

/// Résultat d'un scan : fichiers audio candidats, et fichiers reconnus mais
/// non exploitables (ex. téléchargements incomplets) — cette seconde liste
/// existe pour que l'appelant puisse *signaler* ces fichiers à l'utilisateur
/// au lieu de les faire disparaître sans trace ("blocage silencieux").
class FileScanResult {
  const FileScanResult({required this.audioFiles, required this.incompleteDownloads});

  final List<File> audioFiles;
  final List<File> incompleteDownloads;
}

/// Parcourt le stockage de l'appareil et exclut : dossiers de messagerie/notes
/// vocales, et extensions typiques de clips vocaux (.opus/.amr/.wav). Le filtre
/// de durée < 30s s'applique en aval, une fois les métadonnées du fichier lues
/// (voir LibraryScanService), car il nécessite un décodage.
class FileScanner {
  FileScanner({Set<String>? extensions}) : _supportedExtensions = extensions ?? _defaultExtensions;

  static const Set<String> _defaultExtensions = {'.mp3', '.m4a', '.flac', '.aac', '.ogg'};
  static const Set<String> _excludedDirNames = {
    'WhatsApp',
    'Telegram',
    'Voice Recorder',
    'Android/media',
    'Android/data',
  };
  static const Set<String> _excludedExtensions = {'.opus', '.amr', '.wav'};

  // Stub JSON laissé par un gestionnaire de téléchargement YouTube->audio
  // quand le téléchargement n'a pas abouti (contenu observé : un JSON avec
  // une URL googlevideo.com temporaire, pas de piste audio réelle). Détecté
  // par extension plutôt que par contenu : ouvrir chaque fichier pour en
  // sniffer les octets serait coûteux sur un scan plein-appareil, alors que
  // cette extension est un signal fiable à elle seule.
  static const String _incompleteDownloadExtension = '.giga';

  final Set<String> _supportedExtensions;

  /// Scan récursif tolérant aux erreurs : un sous-dossier illisible (permission
  /// refusée sur le dossier privé d'une autre app, point de montage retiré en
  /// cours de scan, etc. — attendu sur un scan plein-appareil, Étape 8) est
  /// ignoré plutôt que d'interrompre tout le scan.
  Future<FileScanResult> scan(Directory root) async {
    final List<File> audioFiles = [];
    final List<File> incompleteDownloads = [];
    final Completer<void> done = Completer<void>();
    late final StreamSubscription<FileSystemEntity> subscription;

    subscription = root.list(recursive: true, followLinks: false).listen(
      (entity) {
        if (entity is! File) return;
        final String path = entity.path.replaceAll('\\', '/');
        if (_excludedDirNames.any((dir) => path.contains('/$dir/'))) return;

        if (_hasExtension(path, _incompleteDownloadExtension)) {
          incompleteDownloads.add(entity);
          return;
        }
        if (_isCandidate(path)) audioFiles.add(entity);
      },
      onError: (Object _) {}, // sous-arbre illisible : ignoré, le scan continue.
      onDone: () => done.complete(),
      cancelOnError: false,
    );

    await done.future;
    await subscription.cancel();
    return FileScanResult(audioFiles: audioFiles, incompleteDownloads: incompleteDownloads);
  }

  bool _isCandidate(String normalizedPath) {
    final String ext = _extensionOf(normalizedPath);
    if (ext.isEmpty) return false;
    if (_excludedExtensions.contains(ext)) return false;
    return _supportedExtensions.contains(ext);
  }

  bool _hasExtension(String normalizedPath, String extension) => _extensionOf(normalizedPath) == extension;

  String _extensionOf(String normalizedPath) {
    final int dotIndex = normalizedPath.lastIndexOf('.');
    if (dotIndex == -1) return '';
    return normalizedPath.substring(dotIndex).toLowerCase();
  }
}

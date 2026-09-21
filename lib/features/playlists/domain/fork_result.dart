import '../../../core/playlist_manifest/manifest_track_ref.dart';
import '../../../core/storage/database/app_database.dart';

/// Résultat d'un fork ou d'une acceptation de mise à jour : la playlist
/// locale résultante, et les entrées de manifeste qui n'ont trouvé aucune
/// correspondance dans la bibliothèque locale (voir MissingTrackDialog).
class ForkResult {
  const ForkResult({required this.playlist, required this.missingTracks});

  final Playlist playlist;
  final List<ManifestTrackRef> missingTracks;
}

import '../../../core/identity/track_key.dart';
import '../../../core/networking/metadata_api_client/metadata_api_client.dart';
import '../../../core/networking/metadata_api_client/online_track_result.dart';
import '../../../core/storage/database/app_database.dart';

/// Mode B : morceaux publics (non téléchargés) correspondant aux tags/mood de
/// la playlist cible, en excluant ce qui est déjà présent en local (même
/// clé que celle générée au scan, voir core/identity/track_key.dart).
class GlobalSuggestionsEngine {
  GlobalSuggestionsEngine(this._db, this._metadataApiClient);

  final AppDatabase _db;
  final MetadataApiClient _metadataApiClient;

  Future<List<OnlineTrackResult>> suggestTracks({required String playlistId, int limit = 20}) async {
    final Playlist? playlist =
        await (_db.select(_db.playlists)..where((p) => p.id.equals(playlistId))).getSingleOrNull();
    if (playlist == null || playlist.tags.isEmpty) return const [];

    final Set<String> localTrackIds = (await _db.select(_db.tracks).get()).map((t) => t.id).toSet();

    final List<OnlineTrackResult> collected = [];
    for (final tag in playlist.tags) {
      collected.addAll(await _metadataApiClient.search(tag, limit: limit));
    }

    final Map<String, OnlineTrackResult> deduped = {
      for (final result in collected) '${result.artist.toLowerCase()}_${result.title.toLowerCase()}': result,
    };

    return deduped.values.where((result) {
      final String candidateId = buildSanitizedKey(title: result.title, album: result.album, primaryArtist: result.artist);
      return !localTrackIds.contains(candidateId);
    }).take(limit).toList();
  }
}

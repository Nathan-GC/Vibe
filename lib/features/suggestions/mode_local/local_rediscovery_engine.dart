import '../../../core/storage/database/app_database.dart';

/// Mode A : morceaux locaux présents dans /Music/AppFolder/ non assignés à la
/// playlist cible, classés par nombre de tags en commun avec `playlists.tags`.
/// Sans tags cibles, retourne simplement les morceaux non assignés (aucun tri
/// de pertinence possible).
class LocalRediscoveryEngine {
  LocalRediscoveryEngine(this._db);

  final AppDatabase _db;

  Future<List<Track>> suggestTracks({required String playlistId, int limit = 20}) async {
    final Playlist? playlist =
        await (_db.select(_db.playlists)..where((p) => p.id.equals(playlistId))).getSingleOrNull();
    if (playlist == null) return const [];

    final Set<String> targetTags = playlist.tags.map((t) => t.toLowerCase()).toSet();

    final assignedRows = await (_db.selectOnly(_db.playlistTracks)
          ..addColumns([_db.playlistTracks.trackId])
          ..where(_db.playlistTracks.playlistId.equals(playlistId)))
        .get();
    final Set<String> assignedIds = assignedRows.map((row) => row.read(_db.playlistTracks.trackId)!).toSet();

    final List<Track> allTracks = await _db.select(_db.tracks).get();
    final List<Track> candidates = allTracks.where((t) => !assignedIds.contains(t.id)).toList();

    int overlapScore(Track track) => track.tags.where((tag) => targetTags.contains(tag.toLowerCase())).length;

    if (targetTags.isNotEmpty) {
      candidates.retainWhere((t) => overlapScore(t) > 0);
      candidates.sort((a, b) => overlapScore(b).compareTo(overlapScore(a)));
    }

    return candidates.take(limit).toList();
  }
}

import 'package:drift/drift.dart';

import '../../../core/storage/database/app_database.dart';
import '../domain/artist_filter.dart';
import '../domain/artist_sort.dart';
import 'artist_repository.dart';

class DriftArtistRepository implements ArtistRepository {
  DriftArtistRepository(this._db);

  final AppDatabase _db;

  @override
  Stream<List<Track>> watchArtistTracks(
    String artistName, {
    ArtistFilter filter = ArtistFilter.all,
    ArtistSort sort = ArtistSort.chronological,
  }) {
    final query = _db.select(_db.tracks).join([
      innerJoin(_db.trackArtists, _db.trackArtists.trackId.equalsExp(_db.tracks.id)),
    ])
      ..where(_db.trackArtists.artistName.equals(artistName));

    return query.watch().map((rows) {
      final List<Track> tracks = rows.map((row) => row.readTable(_db.tracks)).toList();
      return _sort(_filterTracks(tracks, filter), sort);
    });
  }

  List<Track> _filterTracks(List<Track> tracks, ArtistFilter filter) {
    switch (filter) {
      case ArtistFilter.all:
        return tracks;
      case ArtistFilter.albums:
        return tracks.where((t) => t.album.trim().isNotEmpty).toList();
      case ArtistFilter.singlesEps:
        return tracks.where((t) => t.album.trim().isEmpty).toList();
      case ArtistFilter.collaborations:
        return tracks.where((t) => t.artists.length > 1).toList();
    }
  }

  List<Track> _sort(List<Track> tracks, ArtistSort sort) {
    final List<Track> sorted = [...tracks];
    switch (sort) {
      case ArtistSort.chronological:
        sorted.sort((a, b) => b.releaseYear.compareTo(a.releaseYear));
      case ArtistSort.popularity:
        sorted.sort((a, b) => b.playCount.compareTo(a.playCount));
      case ArtistSort.alphabetical:
        sorted.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    }
    return sorted;
  }

  @override
  Future<List<String>> fetchAllArtistNames() async {
    final query = _db.selectOnly(_db.trackArtists, distinct: true)..addColumns([_db.trackArtists.artistName]);
    final List<TypedResult> rows = await query.get();
    final List<String> names = rows.map((row) => row.read(_db.trackArtists.artistName)!).toList();
    names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names;
  }
}

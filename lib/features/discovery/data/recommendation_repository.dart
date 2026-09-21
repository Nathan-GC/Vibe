import 'package:drift/drift.dart';

import '../../../core/networking/metadata_api_client/metadata_api_client.dart';
import '../../../core/storage/database/app_database.dart';
import '../domain/keyword_stats.dart';
import '../domain/search_result.dart';

/// Moteur de recommandation local (Étape 4) : peuple les blocs de suggestions
/// de l'onglet Recherche à partir des mots-clés déjà en base (genre/mood/
/// époque issus de l'enrichissement iTunes, Étape 2). Ne joue AUCUN rôle dans
/// le choix de la Vibe — celui-ci reste exclusivement manuel (Vibe
/// Customizer). Les mots-clés servent uniquement d'entrée à ce moteur.
class RecommendationRepository {
  RecommendationRepository(this._db, this._metadataApiClient);

  final AppDatabase _db;
  final MetadataApiClient _metadataApiClient;

  static const int _maxSuggestions = 8;

  /// Bloc "Suggestion d'artistes" (wireframe) — basé sur les mots-clés les
  /// plus récurrents de TOUTE la bibliothèque locale.
  Future<List<SearchResult>> suggestArtists({required bool useOnlineSource}) async {
    final List<Track> allTracks = await _db.select(_db.tracks).get();
    final List<String> topKeywords = KeywordStats.top(allTracks.map((t) => t.tags));
    if (topKeywords.isEmpty) return const [];

    if (!useOnlineSource) {
      final Map<String, int> scoreByArtist = {};
      for (final track in allTracks) {
        if (!track.tags.any(topKeywords.contains)) continue;
        for (final artist in track.artists) {
          scoreByArtist[artist] = (scoreByArtist[artist] ?? 0) + 1;
        }
      }
      final List<MapEntry<String, int>> ranked = scoreByArtist.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      return ranked.take(_maxSuggestions).map((e) => ArtistSearchResult(e.key)).toList();
    }

    // Banque de données : interroge iTunes avec les mots-clés dominants pour
    // suggérer des artistes qui n'existent pas déjà dans la bibliothèque locale.
    final Set<String> localArtists = {for (final track in allTracks) ...track.artists};
    final List<SearchResult> suggestions = [];
    final Set<String> seen = {};
    for (final keyword in topKeywords) {
      final results = await _metadataApiClient.search(keyword, limit: 10);
      for (final result in results) {
        if (localArtists.contains(result.artist) || !seen.add(result.artist)) continue;
        suggestions.add(ArtistSearchResult(result.artist));
        if (suggestions.length >= _maxSuggestions) return suggestions;
      }
    }
    return suggestions;
  }

  /// Bloc "Suggestion de titres" (wireframe) — basé sur les mots-clés les
  /// plus récurrents des morceaux déjà présents dans la playlist
  /// [playlistId] sélectionnée via le filtre "Playlist".
  Future<List<SearchResult>> suggestTracksForPlaylist(String playlistId, {required bool useOnlineSource}) async {
    final List<Track> playlistTracks = await _orderedTracks(playlistId);
    final List<String> topKeywords = KeywordStats.top(playlistTracks.map((t) => t.tags));
    if (topKeywords.isEmpty) return const [];

    if (!useOnlineSource) {
      final Set<String> alreadyInPlaylist = {for (final track in playlistTracks) track.id};
      final List<Track> allTracks = await _db.select(_db.tracks).get();
      final List<Track> matches = allTracks
          .where((track) => !alreadyInPlaylist.contains(track.id) && track.tags.any(topKeywords.contains))
          .toList();
      return matches.take(_maxSuggestions).map(TrackSearchResult.new).toList();
    }

    final List<SearchResult> suggestions = [];
    for (final keyword in topKeywords) {
      final results = await _metadataApiClient.search(keyword, limit: 10);
      for (final result in results) {
        suggestions.add(OnlineTrackSearchResult(result));
        if (suggestions.length >= _maxSuggestions) return suggestions;
      }
    }
    return suggestions;
  }

  Future<List<Track>> _orderedTracks(String playlistId) async {
    final query = _db.select(_db.playlistTracks).join([
      innerJoin(_db.tracks, _db.tracks.id.equalsExp(_db.playlistTracks.trackId)),
    ])
      ..where(_db.playlistTracks.playlistId.equals(playlistId));
    final rows = await query.get();
    return rows.map((row) => row.readTable(_db.tracks)).toList();
  }
}

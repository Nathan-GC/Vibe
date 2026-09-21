import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/networking/metadata_api_client/metadata_api_client.dart';
import '../../../core/storage/database/database_provider.dart';
import '../domain/search_result.dart';
import 'recommendation_repository.dart';

final Provider<RecommendationRepository> recommendationRepositoryProvider = Provider<RecommendationRepository>((ref) {
  return RecommendationRepository(ref.watch(appDatabaseProvider), MetadataApiClient());
});

/// Bascule "Local / Banque de données" du wireframe — partagée par les deux
/// blocs de suggestions. `false` = Local (fichiers déjà sur l'appareil),
/// `true` = Banque de données (requêtes iTunes).
class SuggestionSource extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
}

final NotifierProvider<SuggestionSource, bool> suggestionSourceProvider =
    NotifierProvider<SuggestionSource, bool>(SuggestionSource.new);

/// Playlist cible du bloc "Suggestion de titres", choisie via le filtre
/// "Playlist" du wireframe. `null` tant que l'utilisateur n'a rien choisi.
class SuggestionPlaylistId extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? playlistId) => state = playlistId;
}

final NotifierProvider<SuggestionPlaylistId, String?> suggestionPlaylistIdProvider =
    NotifierProvider<SuggestionPlaylistId, String?>(SuggestionPlaylistId.new);

final FutureProvider<List<SearchResult>> artistSuggestionsProvider = FutureProvider<List<SearchResult>>((ref) {
  final bool online = ref.watch(suggestionSourceProvider);
  return ref.watch(recommendationRepositoryProvider).suggestArtists(useOnlineSource: online);
});

final FutureProvider<List<SearchResult>> trackSuggestionsProvider = FutureProvider<List<SearchResult>>((ref) {
  final bool online = ref.watch(suggestionSourceProvider);
  final String? playlistId = ref.watch(suggestionPlaylistIdProvider);
  if (playlistId == null) return Future.value(const []);
  return ref.watch(recommendationRepositoryProvider).suggestTracksForPlaylist(playlistId, useOnlineSource: online);
});

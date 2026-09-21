import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/networking/metadata_api_client/metadata_api_client.dart';
import '../../../core/networking/metadata_api_client/online_track_result.dart';
import '../../../core/storage/database/app_database.dart';
import '../../../core/storage/database/database_provider.dart';
import '../mode_global/global_suggestions_engine.dart';
import '../mode_local/local_rediscovery_engine.dart';

export '../../playlists/data/playlist_providers.dart' show playlistByIdProvider, playlistTrackRepositoryProvider;

final Provider<LocalRediscoveryEngine> localRediscoveryEngineProvider = Provider<LocalRediscoveryEngine>((ref) {
  return LocalRediscoveryEngine(ref.watch(appDatabaseProvider));
});

final Provider<GlobalSuggestionsEngine> globalSuggestionsEngineProvider = Provider<GlobalSuggestionsEngine>((ref) {
  return GlobalSuggestionsEngine(ref.watch(appDatabaseProvider), MetadataApiClient());
});

final localSuggestionsProvider = FutureProvider.family<List<Track>, String>((ref, playlistId) {
  return ref.watch(localRediscoveryEngineProvider).suggestTracks(playlistId: playlistId);
});

final globalSuggestionsProvider = FutureProvider.family<List<OnlineTrackResult>, String>((ref, playlistId) {
  return ref.watch(globalSuggestionsEngineProvider).suggestTracks(playlistId: playlistId);
});

import '../../networking/metadata_api_client/online_track_result.dart';
import '../../networking/youtube/youtube_enricher_service.dart';
import 'track_enricher.dart';
import 'track_repository.dart';

/// Pendant YouTube de [TrackAutoEnricher] (Section 2) — même circuit-breaker
/// partagé ([TrackRepository.shouldAttemptEnrichment]/
/// [TrackRepository.recordEnrichmentOutcome], voir [EnrichmentStatus]) mais
/// sans le filtre de confiance strict d'iTunes ([TrackMatchConfidence]) : la
/// recherche YouTube en texte libre n'a pas d'équivalent structuré
/// Titre/Artiste à comparer, et ce module cible justement les morceaux
/// (remixes, bootlegs, sets DJ) qu'iTunes ne référence pas — le meilleur
/// résultat de recherche est retenu directement.
class YoutubeAutoEnricher implements TrackEnricher {
  YoutubeAutoEnricher({required YoutubeEnricherService youtubeEnricherService, required TrackRepository trackRepository})
      : _youtubeEnricherService = youtubeEnricherService,
        _trackRepository = trackRepository;

  final YoutubeEnricherService _youtubeEnricherService;
  final TrackRepository _trackRepository;

  @override
  Future<bool> enrichTrack({required String trackId, required String title, required List<String> artists}) async {
    if (!await _trackRepository.shouldAttemptEnrichment(trackId)) return false;

    final String artist = artists.isNotEmpty ? artists.first : '';

    List<OnlineTrackResult> results;
    try {
      results = await _youtubeEnricherService.search(artist: artist, title: title);
    } catch (_) {
      // Erreur réseau : ne consomme pas de tentative, comme pour l'iTunes
      // (voir TrackAutoEnricher.enrichTrack).
      return false;
    }

    final String? thumbnailUrl = results.isNotEmpty ? results.first.coverArtUrl : null;
    if (thumbnailUrl == null) {
      await _trackRepository.recordEnrichmentOutcome(trackId, success: false);
      return false;
    }

    final bool ok = await _trackRepository.enrichCoverArtFromYoutube(trackId, thumbnailUrl);
    await _trackRepository.recordEnrichmentOutcome(trackId, success: ok);
    return ok;
  }
}

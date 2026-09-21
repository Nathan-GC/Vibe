import '../../networking/metadata_api_client/metadata_api_client.dart';
import '../../networking/metadata_api_client/online_track_result.dart';
import '../../networking/metadata_api_client/track_match_confidence.dart';
import 'track_repository.dart';

/// Enrichissement iTunes partagé entre l'action manuelle de la Bibliothèque
/// (bouton "Enrichir") et l'enrichissement automatique de post-import (voir
/// LibraryScreen._importFiles, OnboardingScanController.start) — évite de
/// dupliquer la construction de requête et le filtre de confiance à chaque
/// appelant.
class TrackAutoEnricher {
  TrackAutoEnricher({required MetadataApiClient metadataApiClient, required TrackRepository trackRepository})
      : _metadataApiClient = metadataApiClient,
        _trackRepository = trackRepository;

  final MetadataApiClient _metadataApiClient;
  final TrackRepository _trackRepository;

  /// Nombre de résultats iTunes examinés par tentative : la recherche en
  /// texte libre n'a pas le filtre d'artiste exact de
  /// `searchByArtist`/`searchAlbumsByArtist`, donc la bonne correspondance
  /// n'est pas toujours en tête — on en regarde plusieurs et on ne retient
  /// que le premier qui passe [TrackMatchConfidence] plutôt que le premier
  /// tout court. Poussé à 10 (au lieu de 5) : la vitesse n'est pas la
  /// priorité, et plus de candidats donne à la fois plus de chances de
  /// trouver le bon et plus de matière au garde-fou anti-ambiguïté de
  /// [TrackMatchConfidence.pickBestMatch] (artiste local inconnu).
  static const int candidateLimit = 10;

  // Clause "feat./ft./featuring ..." en fin de titre — retirée seulement de
  // la *requête* envoyée à iTunes, jamais du titre stocké/affiché (voir
  // [_searchTitleFor]). Vérifié empiriquement : une requête du type "VALD
  // PANDEMONIUM RELOADED feat. VLADIMIR CAUCHEMAR & TODI3FOR" ne trouve rien,
  // alors que "VALD PANDEMONIUM RELOADED" seul trouve le morceau.
  static final RegExp _trailingFeatureClauseForQuery = RegExp(
    r'[\(\[]?\s*\b(?:feat\.?|ft\.?|featuring)\b.*$',
    caseSensitive: false,
  );

  /// Cherche la meilleure correspondance iTunes pour ([title], [artists]) et
  /// enrichit pochette HD / genre / époque en base. Non destructif dans ce
  /// cas (voir [TrackRepository.enrichFromOnlineMetadata]) : sûr à relancer.
  ///
  /// Si la recherche Artiste+Titre ne trouve rien de fiable, retente une
  /// seconde fois avec les deux inversés avant d'abandonner — certains noms
  /// de fichiers inversent Titre et Artiste (ex. "Halo - Beyoncé.mp3", où
  /// "Halo" est en réalité le titre et "Beyoncé" l'artiste, vérifié
  /// empiriquement sur de vrais fichiers, structurellement indiscernable
  /// d'un nom bien ordonné). Si CETTE tentative trouve une correspondance
  /// fiable, c'est une confirmation externe assez forte pour corriger
  /// Titre/Artiste stockés plutôt que seulement enrichir la pochette — voir
  /// [TrackRepository.correctReversedTitleArtist] — contrairement à la
  /// tentative primaire, qui elle ne touche jamais Titre/Artiste. Dans le pire
  /// cas où l'ordre inversé ne trouve rien de fiable non plus, rien n'est
  /// appliqué.
  Future<bool> enrichTrack({required String trackId, required String title, required List<String> artists}) async {
    final String artist = artists.isNotEmpty ? artists.first : '';

    final OnlineTrackResult? primaryMatch = await _search(localTitle: title, localArtists: artists, queryArtist: artist, queryTitle: title);
    if (primaryMatch != null) {
      return _trackRepository.enrichFromOnlineMetadata(trackId, primaryMatch);
    }

    final bool hasBothFields = artist.isNotEmpty && artist != 'Unknown' && title.isNotEmpty;
    if (!hasBothFields) return false;

    final OnlineTrackResult? swappedMatch =
        await _search(localTitle: artist, localArtists: [title], queryArtist: title, queryTitle: artist);
    if (swappedMatch == null) return false;

    return _trackRepository.correctReversedTitleArtist(trackId, swappedMatch);
  }

  Future<OnlineTrackResult?> _search({
    required String localTitle,
    required List<String> localArtists,
    required String queryArtist,
    required String queryTitle,
  }) async {
    final String query = [
      if (queryArtist.isNotEmpty && queryArtist != 'Unknown') queryArtist,
      _searchTitleFor(queryTitle),
    ].join(' ').trim();
    if (query.isEmpty) return null;

    try {
      final List<OnlineTrackResult> results = await _metadataApiClient.search(query, limit: candidateLimit);
      return TrackMatchConfidence.pickBestMatch(localTitle: localTitle, localArtists: localArtists, candidates: results);
    } catch (_) {
      return null;
    }
  }

  static String _searchTitleFor(String title) => title.replaceFirst(_trailingFeatureClauseForQuery, '').trim();
}

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../metadata_api_client/online_track_result.dart';

/// Recherche YouTube (Section 2) — sans clé API ni quota Google Cloud
/// (youtube_explode_dart parse la page de résultats publique), source
/// alternative à iTunes pour les remixes/bootlegs/sets DJ/vidéos converties
/// qui n'existent tout simplement pas sur iTunes. Contrairement à
/// [MetadataApiClient], ne fournit qu'un titre/nom de chaîne/miniature —
/// jamais d'Album/Genre/Année structurés, ces champs restant `null` sur
/// [OnlineTrackResult] pour cette source.
class YoutubeEnricherService {
  YoutubeEnricherService({YoutubeExplode? client}) : _client = client ?? YoutubeExplode();

  final YoutubeExplode _client;

  static const int resultLimit = 5;

  // Tags parasites de titres YouTube, retirés avant la recherche ET avant
  // affichage — jamais du contenu réel de titre (ex. un vrai titre "(Slowed)"
  // sans "+ Reverb" reste intact).
  static final RegExp _noiseTags = RegExp(
    r'[\(\[]\s*(?:'
    r'official\s+(?:video|music\s+video|audio|lyric\s+video)|'
    r'clip\s+officiel|'
    r'lyrics?(?:\s+video)?|paroles?|audio|hd|4k|'
    r'prod\.?\s*by\s*[^\)\]]*|'
    r'slowed\s*\+\s*reverb'
    r')\s*[\)\]]',
    caseSensitive: false,
  );

  static String cleanTitle(String rawTitle) =>
      rawTitle.replaceAll(_noiseTags, '').replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Recherche les [resultLimit] meilleurs résultats vidéo pour
  /// "[artist] [title nettoyé]" — jamais d'exception avalée ici (voir
  /// [YoutubeAutoEnricher.enrichTrack] pour la distinction erreur réseau vs
  /// aucun résultat, comme pour [MetadataApiClient]).
  Future<List<OnlineTrackResult>> search({required String artist, required String title}) async {
    final String query = [
      if (artist.isNotEmpty && artist != 'Unknown') artist,
      cleanTitle(title),
    ].join(' ').trim();
    if (query.isEmpty) return const [];

    final VideoSearchList results = await _client.search.search(query);
    return results.take(resultLimit).map((video) {
      return OnlineTrackResult(artist: video.author, title: cleanTitle(video.title), coverArtUrl: _bestThumbnail(video.thumbnails));
    }).toList();
  }

  // `maxResUrl`/`standardResUrl` ne sont pas toujours générées par YouTube
  // (vidéos anciennes ou en basse résolution) — repli en cascade vers la
  // meilleure résolution réellement disponible plutôt que de renvoyer une URL
  // qui n'existe pas.
  String? _bestThumbnail(ThumbnailSet thumbnails) {
    // `lowResUrl` en dernier repli : vérifié empiriquement, les résultats de
    // recherche (contrairement à une fiche vidéo complète) ne renseignent
    // parfois que celui-ci — sans lui, un morceau pourtant trouvé restait
    // sans pochette alors qu'une miniature existait bel et bien.
    for (final String url in [
      thumbnails.maxResUrl,
      thumbnails.standardResUrl,
      thumbnails.highResUrl,
      thumbnails.mediumResUrl,
      thumbnails.lowResUrl,
    ]) {
      if (url.isNotEmpty) return url;
    }
    return null;
  }

  void dispose() => _client.close();
}

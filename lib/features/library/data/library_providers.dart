import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/networking/metadata_api_client/metadata_api_client.dart';
import '../../../core/networking/youtube/youtube_enricher_service.dart';
import '../../../core/storage/database/app_database.dart';
import '../../../core/storage/database/database_provider.dart';
import '../../../core/storage/database/duplicate_detector_service.dart';
import '../../../core/storage/database/duplicate_track_group.dart';
import '../../../core/storage/database/library_category.dart';
import '../../../core/storage/database/track_auto_enricher.dart';
import '../../../core/storage/database/track_repository.dart';
import '../../../core/storage/database/youtube_auto_enricher.dart';
import '../../../core/storage/scanner/library_scan_service.dart';
import '../../../core/storage/storage_manager/storage_manager_service.dart';

final Provider<LibraryScanService> libraryScanServiceProvider = Provider<LibraryScanService>((ref) {
  return LibraryScanService();
});

final Provider<MetadataApiClient> metadataApiClientProvider = Provider<MetadataApiClient>((ref) {
  return MetadataApiClient();
});

/// Partagé entre l'enrichissement manuel (Bibliothèque) et l'enrichissement
/// automatique de post-import (onboarding, import manuel) — voir
/// [TrackAutoEnricher].
final Provider<TrackAutoEnricher> trackAutoEnricherProvider = Provider<TrackAutoEnricher>((ref) {
  return TrackAutoEnricher(
    metadataApiClient: ref.watch(metadataApiClientProvider),
    trackRepository: ref.watch(trackRepositoryProvider),
  );
});

final Provider<StorageManagerService> storageManagerServiceProvider = Provider<StorageManagerService>((ref) {
  return StorageManagerService();
});

final Provider<YoutubeEnricherService> youtubeEnricherServiceProvider = Provider<YoutubeEnricherService>((ref) {
  final service = YoutubeEnricherService();
  ref.onDispose(service.dispose);
  return service;
});

/// Pendant YouTube de [trackAutoEnricherProvider] (Section 2) — voir
/// [YoutubeAutoEnricher].
final Provider<YoutubeAutoEnricher> youtubeAutoEnricherProvider = Provider<YoutubeAutoEnricher>((ref) {
  return YoutubeAutoEnricher(
    youtubeEnricherService: ref.watch(youtubeEnricherServiceProvider),
    trackRepository: ref.watch(trackRepositoryProvider),
  );
});

/// Morceaux déjà en base, les plus récents en premier.
final StreamProvider<List<Track>> libraryTracksProvider = StreamProvider<List<Track>>((ref) {
  final AppDatabase db = ref.watch(appDatabaseProvider);
  return (db.select(db.tracks)..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).watch();
});

/// Cible des passes automatiques d'"Enrichir tout" : catégorie "À enrichir"
/// (voir [libraryCategoryOf]) hors `needsManualReview` (tentatives épuisées,
/// ne repasse plus dans la file automatique — voir [EnrichmentStatus],
/// [TrackRepository.shouldAttemptEnrichment]). Un morceau "À renommer" n'y
/// entre jamais : son Titre/Artiste doivent d'abord être confirmés ; un
/// morceau "Renommé et enrichi" non plus, y compris s'il y a été placé à la
/// main (Changer de catégorie).
bool trackNeedsEnrichment(Track track) =>
    libraryCategoryOf(track) == LibraryCategory.toEnrich &&
    track.enrichmentStatus != EnrichmentStatus.needsManualReview;

/// Sous-catégories de provenance, affichées sous leur catégorie principale
/// ([category]) une fois celle-ci sélectionnée. Filtrent sur le statut exact
/// posé par [TrackRepository.recordEnrichmentOutcome]/[TrackRepository.
/// updateMetadata], donc sur QUI/COMMENT un morceau a été enrichi.
/// [autoFailed] (tentatives automatiques épuisées) est la seule rangée sous
/// "À enrichir".
enum EnrichmentProvenanceFilter { youtubeManual, itunesManual, fullyManual, youtubeAuto, itunesAuto, autoFailed }

extension EnrichmentProvenanceFilterStyle on EnrichmentProvenanceFilter {
  String get label => switch (this) {
        EnrichmentProvenanceFilter.youtubeManual => 'Enrichi par YouTube manuel',
        EnrichmentProvenanceFilter.itunesManual => 'Enrichi par iTunes manuel',
        EnrichmentProvenanceFilter.fullyManual => 'Enrichi totalement manuellement',
        EnrichmentProvenanceFilter.youtubeAuto => 'Enrichi par YouTube auto',
        EnrichmentProvenanceFilter.itunesAuto => 'Enrichi par iTunes auto',
        EnrichmentProvenanceFilter.autoFailed => 'Échec auto, à enrichir manuellement',
      };

  EnrichmentStatus get matchingStatus => switch (this) {
        EnrichmentProvenanceFilter.youtubeManual => EnrichmentStatus.enrichedManualYoutube,
        EnrichmentProvenanceFilter.itunesManual => EnrichmentStatus.enrichedManualItunes,
        EnrichmentProvenanceFilter.fullyManual => EnrichmentStatus.enrichedManualEdit,
        EnrichmentProvenanceFilter.youtubeAuto => EnrichmentStatus.enrichedAutoYoutube,
        EnrichmentProvenanceFilter.itunesAuto => EnrichmentStatus.enrichedAutoItunes,
        EnrichmentProvenanceFilter.autoFailed => EnrichmentStatus.needsManualReview,
      };

  LibraryCategory get category =>
      this == EnrichmentProvenanceFilter.autoFailed ? LibraryCategory.toEnrich : LibraryCategory.done;
}

/// Filtre de la Bibliothèque : une catégorie principale au plus (sélection
/// exclusive) et, dans celle-ci, zéro, une ou plusieurs sous-catégories de
/// provenance (OU logique entre elles, voir [filterLibraryTracks]).
class LibraryFilterState {
  const LibraryFilterState({this.category, this.provenances = const {}});

  final LibraryCategory? category;
  final Set<EnrichmentProvenanceFilter> provenances;

  bool get isActive => category != null || provenances.isNotEmpty;
}

class LibraryFilterController extends Notifier<LibraryFilterState> {
  @override
  LibraryFilterState build() => const LibraryFilterState();

  /// Changer de catégorie efface les sous-catégories : elles n'ont de sens
  /// que sous leur propre catégorie.
  void toggleCategory(LibraryCategory category) {
    state = LibraryFilterState(category: state.category == category ? null : category);
  }

  void toggleProvenance(EnrichmentProvenanceFilter filter) {
    final Set<EnrichmentProvenanceFilter> next = {...state.provenances};
    if (!next.remove(filter)) next.add(filter);
    state = LibraryFilterState(category: filter.category, provenances: next);
  }

  void clear() => state = const LibraryFilterState();
}

final NotifierProvider<LibraryFilterController, LibraryFilterState> libraryFilterProvider =
    NotifierProvider<LibraryFilterController, LibraryFilterState>(LibraryFilterController.new);

List<Track> filterLibraryTracks(List<Track> tracks, LibraryFilterState filter) {
  if (!filter.isActive) return tracks;
  final Set<EnrichmentStatus> allowedStatuses = filter.provenances.map((f) => f.matchingStatus).toSet();
  return tracks
      .where((t) => filter.category == null || libraryCategoryOf(t) == filter.category)
      .where((t) => allowedStatuses.isEmpty || allowedStatuses.contains(t.enrichmentStatus))
      .toList();
}

/// Morceaux strictement en double (Titre + Artiste identiques) — alerte
/// visible dans la Bibliothèque tant que la liste n'est pas vide, voir
/// [DuplicateDetectorService].
final StreamProvider<List<DuplicateTrackGroup>> duplicateTrackGroupsProvider =
    StreamProvider<List<DuplicateTrackGroup>>((ref) {
  final AppDatabase db = ref.watch(appDatabaseProvider);
  return DuplicateDetectorService(db).watchDuplicates();
});

/// 3 tris disponibles sur la Bibliothèque (Feuille de route pt.5) — appliqué
/// côté client sur la liste déjà chargée plutôt qu'en base : la bibliothèque
/// reste de taille modeste (import manuel + scan device), et ça évite de
/// dupliquer la requête Drift `orderBy` de [libraryTracksProvider] par tri.
enum LibrarySort { dateAdded, titleAz, artistAz }

extension LibrarySortLabel on LibrarySort {
  String get label => switch (this) {
        LibrarySort.dateAdded => "Date d'ajout",
        LibrarySort.titleAz => 'Titre (A-Z)',
        LibrarySort.artistAz => 'Artiste (A-Z)',
      };
}

class LibrarySortController extends Notifier<LibrarySort> {
  @override
  LibrarySort build() => LibrarySort.dateAdded;

  void setSort(LibrarySort sort) => state = sort;
}

final NotifierProvider<LibrarySortController, LibrarySort> librarySortProvider =
    NotifierProvider<LibrarySortController, LibrarySort>(LibrarySortController.new);

/// [tracks] est déjà triée par date d'ajout décroissante par
/// [libraryTracksProvider] — seuls `titleAz`/`artistAz` retrient réellement.
List<Track> sortLibraryTracks(List<Track> tracks, LibrarySort sort) {
  if (sort == LibrarySort.dateAdded) return tracks;

  final List<Track> sorted = [...tracks];
  sorted.sort((a, b) {
    switch (sort) {
      case LibrarySort.titleAz:
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      case LibrarySort.artistAz:
        final String artistA = a.artists.isNotEmpty ? a.artists.first.toLowerCase() : '';
        final String artistB = b.artists.isNotEmpty ? b.artists.first.toLowerCase() : '';
        final int artistCompare = artistA.compareTo(artistB);
        return artistCompare != 0 ? artistCompare : a.title.toLowerCase().compareTo(b.title.toLowerCase());
      case LibrarySort.dateAdded:
        return 0;
    }
  });
  return sorted;
}

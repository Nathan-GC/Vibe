import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/networking/metadata_api_client/metadata_api_client.dart';
import '../../../core/networking/youtube/youtube_enricher_service.dart';
import '../../../core/storage/database/app_database.dart';
import '../../../core/storage/database/database_provider.dart';
import '../../../core/storage/database/duplicate_detector_service.dart';
import '../../../core/storage/database/duplicate_track_group.dart';
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

/// Morceaux insérés avec repli nom-de-fichier ambigu (Étape 8, badge "À
/// vérifier") — tags ID3 absents et FilenameSanitizer pas assez confiant pour
/// distinguer Artiste/Titre. Toujours lisibles immédiatement (voir
/// LibraryScanService), juste signalés pour une correction manuelle.
final StreamProvider<List<Track>> needsReviewTracksProvider = StreamProvider<List<Track>>((ref) {
  final AppDatabase db = ref.watch(appDatabaseProvider);
  return (db.select(db.tracks)
        ..where((t) => t.requiresUserReview.equals(true))
        ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
      .watch();
});

/// Bascule de la puce de filtre "À vérifier" dans la Bibliothèque (Étape 8).
class LibraryReviewFilter extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
}

final NotifierProvider<LibraryReviewFilter, bool> libraryReviewFilterProvider =
    NotifierProvider<LibraryReviewFilter, bool>(LibraryReviewFilter.new);

/// Puce de filtre "À enrichir" dans la Bibliothèque (Feuille de route pt.4) —
/// isole les morceaux dont l'enrichissement (pochette/genres) a échoué ou
/// n'a jamais été tenté, pour un enrichissement manuel rapide. Pas de colonne
/// dédiée en base : un morceau "à enrichir" est simplement un morceau qui n'a
/// ni pochette ni mots-clés, le même critère que la cible de
/// `_enrichLibrary` — voir [tracksNeedingEnrichment].
class LibraryEnrichmentFilter extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
}

final NotifierProvider<LibraryEnrichmentFilter, bool> libraryEnrichmentFilterProvider =
    NotifierProvider<LibraryEnrichmentFilter, bool>(LibraryEnrichmentFilter.new);

/// Un morceau `needsManualReview` (tentatives épuisées) ou `requiresReview`
/// (nom de fichier trop ambigu) reste sans pochette/mots-clés mais ne doit
/// plus être proposé aux passes automatiques d'"Enrichir tout" — voir
/// [EnrichmentStatus], [TrackRepository.shouldAttemptEnrichment].
bool trackNeedsEnrichment(Track track) =>
    (track.coverArtPath.isEmpty || track.tags.isEmpty) &&
    track.enrichmentStatus != EnrichmentStatus.needsManualReview &&
    track.enrichmentStatus != EnrichmentStatus.requiresReview;

/// Critères de filtrage multi-provenance de la Bibliothèque (Section 1) —
/// distinct de [LibraryEnrichmentFilter] (heuristique pochette/mots-clés
/// manquants, cible des passes auto) : ceux-ci filtrent sur le statut exact
/// posé par [TrackRepository.recordEnrichmentOutcome]/[TrackRepository.
/// updateMetadata], donc sur QUI/COMMENT un morceau a été enrichi plutôt que
/// sur ce qu'il lui manque.
enum EnrichmentProvenanceFilter { manualTotal, manualItunes, manualYoutube, autoItunes, autoYoutube, needsManualReview }

extension EnrichmentProvenanceFilterStyle on EnrichmentProvenanceFilter {
  String get label => switch (this) {
        EnrichmentProvenanceFilter.manualTotal => 'Manuel (total)',
        EnrichmentProvenanceFilter.manualItunes => 'Manuel iTunes',
        EnrichmentProvenanceFilter.manualYoutube => 'Manuel YouTube',
        EnrichmentProvenanceFilter.autoItunes => 'Auto iTunes',
        EnrichmentProvenanceFilter.autoYoutube => 'Auto YouTube',
        EnrichmentProvenanceFilter.needsManualReview => 'À enrichir manuellement',
      };

  /// Statuts [EnrichmentStatus] correspondant à ce critère — [manualTotal]
  /// regroupe les trois variantes manuelles (édition libre + suggestion
  /// iTunes/YouTube validée).
  Set<EnrichmentStatus> get matchingStatuses => switch (this) {
        EnrichmentProvenanceFilter.manualTotal => const {
            EnrichmentStatus.enrichedManualEdit,
            EnrichmentStatus.enrichedManualItunes,
            EnrichmentStatus.enrichedManualYoutube,
          },
        EnrichmentProvenanceFilter.manualItunes => const {EnrichmentStatus.enrichedManualItunes},
        EnrichmentProvenanceFilter.manualYoutube => const {EnrichmentStatus.enrichedManualYoutube},
        EnrichmentProvenanceFilter.autoItunes => const {EnrichmentStatus.enrichedAutoItunes},
        EnrichmentProvenanceFilter.autoYoutube => const {EnrichmentStatus.enrichedAutoYoutube},
        EnrichmentProvenanceFilter.needsManualReview => const {EnrichmentStatus.needsManualReview},
      };
}

/// Sélection multiple de puces de provenance (Section 1) — plusieurs critères
/// actifs à la fois s'unissent (OU logique, voir [filterTracksByProvenance])
/// plutôt que de se remplacer, contrairement aux filtres "À vérifier"/"À
/// enrichir" (mutuellement exclusifs par priorité, voir LibraryScreen.build).
class LibraryProvenanceFilter extends Notifier<Set<EnrichmentProvenanceFilter>> {
  @override
  Set<EnrichmentProvenanceFilter> build() => const {};

  void toggle(EnrichmentProvenanceFilter filter) {
    final Set<EnrichmentProvenanceFilter> next = {...state};
    if (!next.remove(filter)) next.add(filter);
    state = next;
  }

  void clear() => state = const {};
}

final NotifierProvider<LibraryProvenanceFilter, Set<EnrichmentProvenanceFilter>> libraryProvenanceFilterProvider =
    NotifierProvider<LibraryProvenanceFilter, Set<EnrichmentProvenanceFilter>>(LibraryProvenanceFilter.new);

/// Morceaux dont le statut correspond à au moins un des [filters] actifs.
List<Track> filterTracksByProvenance(List<Track> tracks, Set<EnrichmentProvenanceFilter> filters) {
  if (filters.isEmpty) return tracks;
  final Set<EnrichmentStatus> allowedStatuses = filters.expand((f) => f.matchingStatuses).toSet();
  return tracks.where((t) => allowedStatuses.contains(t.enrichmentStatus)).toList();
}

/// Morceaux strictement en double (Titre + Artiste identiques) — alerte
/// visible dans la Bibliothèque tant que la liste n'est pas vide, voir
/// [DuplicateDetectorService].
final StreamProvider<List<DuplicateTrackGroup>> duplicateTrackGroupsProvider =
    StreamProvider<List<DuplicateTrackGroup>>((ref) {
  final AppDatabase db = ref.watch(appDatabaseProvider);
  return DuplicateDetectorService(db).watchDuplicates();
});

/// Dérivé synchrone de [libraryTracksProvider] plutôt qu'un `StreamProvider`
/// séparé : se recalcule à chaque nouvelle émission de la bibliothèque sans
/// dupliquer l'abonnement Drift.
final Provider<List<Track>> tracksNeedingEnrichmentProvider = Provider<List<Track>>((ref) {
  final List<Track> tracks = ref.watch(libraryTracksProvider).value ?? const [];
  return tracks.where(trackNeedsEnrichment).toList();
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

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/networking/metadata_api_client/metadata_api_client.dart';
import '../../../core/storage/database/app_database.dart';
import '../../../core/storage/database/database_provider.dart';
import '../../../core/storage/database/duplicate_detector_service.dart';
import '../../../core/storage/database/duplicate_track_group.dart';
import '../../../core/storage/database/track_auto_enricher.dart';
import '../../../core/storage/database/track_repository.dart';
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

bool trackNeedsEnrichment(Track track) => track.coverArtPath.isEmpty || track.tags.isEmpty;

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

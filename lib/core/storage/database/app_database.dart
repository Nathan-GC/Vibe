import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../../theme/vibe_engine/vibe_engine.dart';

part 'app_database.g.dart';

/// Sérialise les colonnes `json text array` (artists, tags, bg_colors) en JSON.
class StringListConverter extends TypeConverter<List<String>, String> {
  const StringListConverter();

  @override
  List<String> fromSql(String fromDb) {
    if (fromDb.isEmpty) return const [];
    return (jsonDecode(fromDb) as List<dynamic>).cast<String>();
  }

  @override
  String toSql(List<String> value) => jsonEncode(value);
}

/// Mappe `playlists.vibe_style` ('minimal' | 'neon' | 'glassmorphism' | 'retro' | 'organic' | 'oled').
class VibePresetConverter extends TypeConverter<VibePreset, String> {
  const VibePresetConverter();

  @override
  VibePreset fromSql(String fromDb) {
    return VibePreset.values.firstWhere((preset) => preset.name == fromDb, orElse: () => VibePreset.minimal);
  }

  @override
  String toSql(VibePreset value) => value.name;
}

/// Mappe `playlists.custom_effect` — voir [VibeCustomEffect].
class VibeCustomEffectConverter extends TypeConverter<VibeCustomEffect, String> {
  const VibeCustomEffectConverter();

  @override
  VibeCustomEffect fromSql(String fromDb) {
    return VibeCustomEffect.values.firstWhere((effect) => effect.name == fromDb, orElse: () => VibeCustomEffect.fluid);
  }

  @override
  String toSql(VibeCustomEffect value) => value.name;
}

/// Statut du circuit-breaker d'enrichissement automatique ET provenance de
/// l'enrichissement (Section 1 — voir `Tracks.enrichmentStatus`,
/// `TrackAutoEnricher`, `YoutubeAutoEnricher`, `TrackRepository.
/// shouldAttemptEnrichment`/`recordEnrichmentOutcome`/`updateMetadata`) :
///  - [pending] : éligible aux prochaines tentatives auto (post-import,
///    "Enrichir tout").
///  - [enrichedAutoItunes] / [enrichedAutoYoutube] : enrichi automatiquement
///    avec confiance par la source indiquée, plus besoin de retenter.
///  - [enrichedManualEdit] : Titre/Artiste/Album saisis à la main dans
///    l'éditeur, sans passer par une suggestion réseau.
///  - [enrichedManualItunes] / [enrichedManualYoutube] : suggestion de
///    l'onglet réseau correspondant validée telle quelle dans l'éditeur.
///  - [needsManualReview] : `maxEnrichmentAttempts` tentatives auto épuisées
///    sans correspondance fiable — ne repasse plus jamais dans la file
///    automatique et s'affiche sous "À enrichir manuellement" (jusqu'à une
///    correction manuelle, voir `TrackRepository.updateMetadata`, qui
///    réinitialise ce statut).
///  - [requiresReview] : titre/artiste trop ambigus dès le nom de fichier
///    (`requiresUserReview`) pour même tenter une requête API — évite de
///    gaspiller des appels réseau sur un morceau qu'une confirmation humaine
///    va de toute façon changer.
enum EnrichmentStatus {
  pending,
  enrichedAutoItunes,
  enrichedAutoYoutube,
  enrichedManualEdit,
  enrichedManualItunes,
  enrichedManualYoutube,
  needsManualReview,
  requiresReview,
}

class EnrichmentStatusConverter extends TypeConverter<EnrichmentStatus, String> {
  const EnrichmentStatusConverter();

  @override
  EnrichmentStatus fromSql(String fromDb) {
    return EnrichmentStatus.values.firstWhere((status) => status.name == fromDb, orElse: () => EnrichmentStatus.pending);
  }

  @override
  String toSql(EnrichmentStatus value) => value.name;
}

/// `id` = sanitized key (title_slug + album_slug + primary_artist_slug), voir
/// core/identity/track_key.dart. `artists` conserve tous les featurings en
/// tableau JSON, jamais aplatis en string ("Daft Punk feat. Justice" interdit).
class Tracks extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get album => text()();
  IntColumn get releaseYear => integer().withDefault(const Constant(0))();
  TextColumn get artists => text().map(const StringListConverter())();
  IntColumn get durationSeconds => integer()();
  IntColumn get bpm => integer().withDefault(const Constant(120))();
  IntColumn get trimStartMs => integer().withDefault(const Constant(0))();
  IntColumn get trimEndMs => integer().withDefault(const Constant(0))();
  TextColumn get filePath => text().unique()();
  TextColumn get coverArtPath => text().withDefault(const Constant(''))();
  TextColumn get tags => text().map(const StringListConverter()).withDefault(const Constant('[]'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  // true quand l'extraction ID3 a échoué et que le repli sur le nom de fichier
  // (FilenameSanitizer) est resté ambigu — voir LibraryScanService (Étape 2).
  BoolColumn get requiresUserReview => boolean().withDefault(const Constant(false))();
  // Nombre de lectures locales, utilisé par le tri "Popularité" (Étape 3).
  IntColumn get playCount => integer().withDefault(const Constant(0))();
  // Dernière lecture, affichée dans la vue de purge des orphelins (Étape 7).
  DateTimeColumn get lastPlayedAt => dateTime().nullable()();
  // Empreinte de fichier pour le scan incrémental (import zero-click, Étape 8) :
  // `lastModifiedEpochMs` (mtime du fichier au dernier scan) permet un test de
  // changement quasi instantané (pas de lecture du contenu) ; `fileHash`
  // (SHA-256, calculé seulement quand mtime/taille diffèrent) confirme qu'un
  // contenu a réellement changé avant de relancer extraction ID3 + trim.
  IntColumn get lastModifiedEpochMs => integer().withDefault(const Constant(0))();
  TextColumn get fileHash => text().nullable()();
  // Numéro de piste/disque officiel (iTunes `trackNumber`/`discNumber`) —
  // alimenté par l'enrichissement (Étape "audit iTunes"), 0 si inconnu.
  // Permet de trier les morceaux d'un album dans leur ordre officiel plutôt
  // que par ordre d'ajout à la bibliothèque (voir AlbumGroup).
  IntColumn get trackNumber => integer().withDefault(const Constant(0))();
  IntColumn get discNumber => integer().withDefault(const Constant(0))();
  IntColumn get trackCount => integer().withDefault(const Constant(0))();
  // Circuit-breaker de l'enrichissement automatique — voir [EnrichmentStatus].
  // Un morceau nouvellement scanné démarre à `requiresReview` s'il est déjà
  // `requiresUserReview` (nom de fichier ambigu), sinon `pending`.
  IntColumn get enrichmentAttempts => integer().withDefault(const Constant(0))();
  TextColumn get enrichmentStatus =>
      text().map(const EnrichmentStatusConverter()).withDefault(const Constant('pending'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Index dérivé de `tracks.artists` : une ligne par artiste crédité sur un morceau.
/// Permet de retrouver tous les morceaux d'un artiste (y compris en featuring)
/// sans dupliquer le fichier physique ni scanner le JSON à chaque requête.
/// Tenu à jour par TrackRepository.upsertTrack à chaque insert/update de track.
@TableIndex(name: 'idx_track_artists_artist_name', columns: {#artistName})
class TrackArtists extends Table {
  TextColumn get trackId => text().references(Tracks, #id)();
  TextColumn get artistName => text()();
  IntColumn get position => integer()();

  @override
  Set<Column> get primaryKey => {trackId, artistName};
}

/// `original_creator` n'est renseigné que pour les playlists forkées (voir Étape 6),
/// auquel cas l'UI affiche "Inspired by @original_creator".
class Playlists extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get originalCreator => text().nullable()();
  // `manifest.id` du JSON importé au moment du fork — distinct de `id` (qui,
  // lui, inclut un suffixe `-fork-<timestamp>` unique par copie locale). Sert
  // à reconnaître qu'un JSON réimporté est une mise à jour d'une playlist déjà
  // forkée ici plutôt que de créer un doublon (voir PlaylistManifestService).
  TextColumn get sourceManifestId => text().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get tags => text().map(const StringListConverter()).withDefault(const Constant('[]'))();
  TextColumn get vibeStyle =>
      text().map(const VibePresetConverter()).withDefault(const Constant('minimal'))();
  // Pour `vibeStyle == VibePreset.custom` : couleurs choisies dans le Vibe
  // Creator (format hex ARGB, ex. "FFFF00E5"), voir PlaylistVibeResolver.
  TextColumn get bgColors => text().map(const StringListConverter()).withDefault(const Constant('[]'))();
  // Image de fond importée via image_picker pour la Vibe personnalisée
  // (chemin local sous Music/AppFolder/vibe_backgrounds/) — vide si non définie.
  TextColumn get customBackgroundImagePath => text().withDefault(const Constant(''))();
  // Couleur d'accentuation choisie explicitement dans le Vibe Creator (format
  // hex ARGB) — distincte des couleurs de `bgColors` (dégradé de fond). Vide :
  // repli sur la dernière couleur du dégradé (comportement historique).
  TextColumn get customAccentColor => text().withDefault(const Constant(''))();
  // Pochette personnalisée (Design System — carte PlaylistCard), distincte de
  // `customBackgroundImagePath` (fond plein écran du Player, Vibe Creator) :
  // chemin local sous Music/AppFolder/playlist_covers/, vide si non définie
  // — auquel cas l'UI compose un visuel 2x2 des 4 premières pochettes de la
  // playlist (voir PlaylistCoverImage), ou un repli générique Vibe si vide.
  TextColumn get coverImagePath => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  // Effet de fond du Vibe Creator (Section 4.2) pour `vibeStyle == custom`
  // uniquement — voir [VibeCustomEffect]. Sans effet pour les autres presets.
  TextColumn get customEffect =>
      text().map(const VibeCustomEffectConverter()).withDefault(const Constant('fluid'))();
  // Vidéo de fond personnalisée (Section 4.3, `vibeStyle == custom`) —
  // chemin local sous Music/AppFolder/vibe_backgrounds/, vide si non définie.
  // Remplace entièrement le rendu shader/dégradé/image du Master Player
  // quand renseignée (voir MasterPlayerScreen) : mutuellement exclusive avec
  // `customEffect`/`customBackgroundImagePath`, jamais superposée.
  TextColumn get customBackgroundVideoPath => text().withDefault(const Constant(''))();
  // Pochette masquable dans le Player (Section 3, `VibePreset.custom`/
  // `newOled`/`neon`/`retro` uniquement — voir VibeCustomizerScreen) : par
  // défaut visible (`true`) pour tout le reste, jamais exposé ailleurs.
  BoolColumn get showCoverImage => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

/// `is_pending_placement` : true tant qu'un morceau ajouté (import, fork, suggestion)
/// n'a pas encore été positionné manuellement dans l'éditeur drag-and-drop (Étape 5).
@DataClassName('PlaylistTrack')
class PlaylistTracks extends Table {
  TextColumn get playlistId => text().references(Playlists, #id)();
  TextColumn get trackId => text().references(Tracks, #id)();
  IntColumn get position => integer()();
  BoolColumn get isPendingPlacement => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {playlistId, trackId};
}

@DriftDatabase(tables: [Tracks, Playlists, PlaylistTracks, TrackArtists])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 11;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) => m.createAll(),
        onUpgrade: (Migrator m, int from, int to) async {
          if (from < 2) {
            await m.addColumn(playlists, playlists.sourceManifestId);
          }
          if (from < 3) {
            await m.addColumn(tracks, tracks.lastModifiedEpochMs);
            await m.addColumn(tracks, tracks.fileHash);
          }
          if (from < 4) {
            await m.addColumn(playlists, playlists.customBackgroundImagePath);
          }
          if (from < 5) {
            await m.addColumn(playlists, playlists.customAccentColor);
          }
          if (from < 6) {
            await m.addColumn(tracks, tracks.trackNumber);
            await m.addColumn(tracks, tracks.discNumber);
            await m.addColumn(tracks, tracks.trackCount);
          }
          if (from < 7) {
            await m.addColumn(playlists, playlists.coverImagePath);
          }
          if (from < 8) {
            await m.addColumn(tracks, tracks.enrichmentAttempts);
            await m.addColumn(tracks, tracks.enrichmentStatus);
            // Les morceaux déjà en base avant cette version n'ont jamais eu de
            // statut : les tracks encore "à vérifier" démarrent directement en
            // `requiresReview` (comme un nouveau scan) pour ne pas gaspiller de
            // requêtes API dessus tant qu'un humain n'a pas confirmé
            // Titre/Artiste.
            await (update(tracks)..where((t) => t.requiresUserReview.equals(true))).write(
              const TracksCompanion(enrichmentStatus: Value(EnrichmentStatus.requiresReview)),
            );
          }
          if (from < 9) {
            await m.addColumn(playlists, playlists.customEffect);
            await m.addColumn(playlists, playlists.customBackgroundVideoPath);
          }
          if (from < 10) {
            // Éclatement de [EnrichmentStatus] (Section 1) : les anciennes
            // valeurs texte 'success'/'failedPermanently' n'existent plus
            // côté Dart (EnrichmentStatusConverter.fromSql retomberait
            // silencieusement sur `pending`, perdant tout historique
            // d'enrichissement) — remappées en SQL brut vers leurs
            // équivalents le plus proche avant que l'app ne relise ces
            // lignes : la provenance exacte (iTunes vs YouTube) d'un ancien
            // `success` n'est pas connue, iTunes (source par défaut) sert de
            // repli raisonnable.
            await customStatement(
              "UPDATE tracks SET enrichment_status = 'enrichedAutoItunes' WHERE enrichment_status = 'success'",
            );
            await customStatement(
              "UPDATE tracks SET enrichment_status = 'needsManualReview' WHERE enrichment_status = 'failedPermanently'",
            );
          }
          if (from < 11) {
            await m.addColumn(playlists, playlists.showCoverImage);
          }
        },
      );

  static QueryExecutor _openConnection() => driftDatabase(name: 'playlist_app');
}

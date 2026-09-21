import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playlist_app/core/storage/database/app_database.dart';
import 'package:playlist_app/core/storage/database/track_repository.dart';
import 'package:playlist_app/core/storage/scanner/scanned_track.dart';

void main() {
  late AppDatabase db;
  late TrackRepository repository;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = TrackRepository(db);
  });

  tearDown(() => db.close());

  ScannedTrack scannedTrack({
    required String id,
    required List<String> artists,
  }) {
    return ScannedTrack(
      id: id,
      title: 'Some Title',
      album: '',
      primaryArtist: artists.isNotEmpty ? artists.first : '',
      artists: artists,
      filePath: '/music/$id.mp3',
      durationMs: 180000,
      requiresUserReview: false,
      trimStartMs: 0,
      trimEndMs: 0,
    );
  }

  test(
    'deduplicates a repeated artist name instead of crashing on the track_artists unique constraint',
    () async {
      // Cas réel : "Hunter X Hunter - Ending 2...mp3" — le séparateur
      // multi-artiste du sanitizer traite le "X" du titre comme un
      // featuring et produit artists: ["Hunter", "Hunter"], ce qui plantait
      // tout le scan (SqliteException 1555, UNIQUE constraint failed) avant
      // la déduplication dans upsertTrack.
      final scanned = scannedTrack(id: 't1', artists: ['Hunter', 'Hunter']);

      await repository.upsertTrack(scanned);

      final track = await repository.findById('t1');
      expect(track!.artists, ['Hunter']);

      final artistRows = await (db.select(db.trackArtists)..where((t) => t.trackId.equals('t1'))).get();
      expect(artistRows.map((r) => r.artistName).toList(), ['Hunter']);
    },
  );

  test('keeps distinct artists in order when there is no duplicate', () async {
    final scanned = scannedTrack(id: 't1', artists: ['Daft Punk', 'Pharrell Williams']);

    await repository.upsertTrack(scanned);

    final track = await repository.findById('t1');
    expect(track!.artists, ['Daft Punk', 'Pharrell Williams']);

    final artistRows = await (db.select(db.trackArtists)..where((t) => t.trackId.equals('t1'))).get();
    expect(artistRows.map((r) => r.artistName).toList(), ['Daft Punk', 'Pharrell Williams']);
  });

  test('re-scanning the same file (upsert) does not duplicate track_artists rows', () async {
    final scanned = scannedTrack(id: 't1', artists: ['Daft Punk']);

    await repository.upsertTrack(scanned);
    await repository.upsertTrack(scanned);

    final artistRows = await (db.select(db.trackArtists)..where((t) => t.trackId.equals('t1'))).get();
    expect(artistRows.length, 1);
  });
}

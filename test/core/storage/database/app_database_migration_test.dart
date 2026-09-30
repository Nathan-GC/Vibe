import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playlist_app/core/storage/database/app_database.dart';
import 'package:playlist_app/core/theme/vibe_engine/vibe_engine.dart';

void main() {
  late Directory dir;
  late File dbFile;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('vibe_migration_test');
    dbFile = File('${dir.path}/app.sqlite');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('upgrading from v12 keeps what users saw and remaps the retired forced-done status', () async {
    // Base "v12" : schéma identique pour ces tables, données héritées écrites
    // en SQL brut (valeur d'enum retirée), puis user_version ramené à 12.
    final AppDatabase legacy = AppDatabase.forTesting(NativeDatabase(dbFile));
    await legacy.into(legacy.tracks).insert(TracksCompanion.insert(
        id: 't1', title: 'Forced', album: '', artists: const ['A'], durationSeconds: 180, filePath: '/m/t1.mp3'));
    await legacy.customStatement("UPDATE tracks SET enrichment_status = 'markedEnrichedManually' WHERE id = 't1'");
    await legacy.into(legacy.playlists).insert(PlaylistsCompanion.insert(
        id: 'space', title: 'Space', vibeStyle: const Value(VibePreset.oled), showCoverImage: const Value(false)));
    await legacy.into(legacy.playlists).insert(PlaylistsCompanion.insert(
        id: 'retro', title: 'Retro', vibeStyle: const Value(VibePreset.retro), showCoverImage: const Value(false)));
    await legacy.customStatement('PRAGMA user_version = 12');
    await legacy.close();

    final AppDatabase upgraded = AppDatabase.forTesting(NativeDatabase(dbFile));
    addTearDown(upgraded.close);

    final Track track = await upgraded.select(upgraded.tracks).getSingle();
    expect(track.enrichmentStatus, EnrichmentStatus.enrichedManualEdit,
        reason: 'v14 : Enrichi totalement manuellement');

    Future<bool> showCover(String id) => (upgraded.select(upgraded.playlists)..where((p) => p.id.equals(id)))
        .getSingle()
        .then((playlist) => playlist.showCoverImage);
    expect(await showCover('space'), isTrue, reason: 'v13 : pochette toujours affichée avant la mise à jour');
    expect(await showCover('retro'), isFalse, reason: 'v13 : choix explicite conservé là où le bouton existait');

    final int version =
        await upgraded.customSelect('PRAGMA user_version').getSingle().then((row) => row.read<int>('user_version'));
    expect(version, upgraded.schemaVersion);
  });
}

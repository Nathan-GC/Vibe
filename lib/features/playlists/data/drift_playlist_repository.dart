import 'package:drift/drift.dart';
import 'package:flutter/material.dart';

import '../../../core/storage/database/app_database.dart';
import '../../../core/theme/vibe_engine/playlist_vibe_resolver.dart';
import '../../../core/theme/vibe_engine/vibe_engine.dart';
import '../domain/playlist_editor_entry.dart';
import 'playlist_repository.dart';

class DriftPlaylistRepository implements PlaylistRepository {
  DriftPlaylistRepository(this._db);

  final AppDatabase _db;

  @override
  Stream<List<Playlist>> watchAll() => _db.select(_db.playlists).watch();

  @override
  Stream<Playlist?> watchPlaylist(String playlistId) {
    return (_db.select(_db.playlists)..where((p) => p.id.equals(playlistId))).watchSingleOrNull();
  }

  @override
  Future<Playlist?> findBySourceManifestId(String manifestId) {
    return (_db.select(_db.playlists)..where((p) => p.sourceManifestId.equals(manifestId))).getSingleOrNull();
  }

  @override
  Future<Playlist> createEmpty({required String title, required VibePreset vibeStyle}) async {
    final String id = 'local-${DateTime.now().millisecondsSinceEpoch}';
    await _db.into(_db.playlists).insert(
          PlaylistsCompanion.insert(id: id, title: title, vibeStyle: Value(vibeStyle)),
        );
    return (_db.select(_db.playlists)..where((p) => p.id.equals(id))).getSingle();
  }

  @override
  Future<Playlist> ensureLikedPlaylist() async {
    final Playlist? existing =
        await (_db.select(_db.playlists)..where((p) => p.id.equals(kLikedPlaylistId))).getSingleOrNull();
    if (existing != null) return existing;

    await _db.into(_db.playlists).insert(
          PlaylistsCompanion.insert(
            id: kLikedPlaylistId,
            title: 'Titres likés',
            vibeStyle: const Value(VibePreset.retro),
          ),
        );
    return (_db.select(_db.playlists)..where((p) => p.id.equals(kLikedPlaylistId))).getSingle();
  }

  @override
  Stream<List<PlaylistEditorEntry>> watchEditorEntries(String playlistId) {
    final query = _db.select(_db.playlistTracks).join([
      innerJoin(_db.tracks, _db.tracks.id.equalsExp(_db.playlistTracks.trackId)),
    ])
      ..where(_db.playlistTracks.playlistId.equals(playlistId))
      ..orderBy([OrderingTerm.asc(_db.playlistTracks.position)]);

    return query.watch().map((rows) {
      return rows.map((row) {
        final PlaylistTrack playlistTrack = row.readTable(_db.playlistTracks);
        return PlaylistEditorEntry(
          track: row.readTable(_db.tracks),
          isPendingPlacement: playlistTrack.isPendingPlacement,
          position: playlistTrack.position,
        );
      }).toList();
    });
  }

  @override
  Future<List<Track>> fetchOrderedTracks(String playlistId) async {
    final entries = await watchEditorEntries(playlistId).first;
    return entries.map((e) => e.track).toList();
  }

  @override
  Future<void> commitOrder(String playlistId, List<String> orderedTrackIds) {
    return _db.transaction(() async {
      await (_db.delete(_db.playlistTracks)..where((t) => t.playlistId.equals(playlistId))).go();

      if (orderedTrackIds.isNotEmpty) {
        await _db.batch((batch) {
          batch.insertAll(_db.playlistTracks, [
            for (int i = 0; i < orderedTrackIds.length; i++)
              PlaylistTracksCompanion.insert(
                playlistId: playlistId,
                trackId: orderedTrackIds[i],
                position: i,
                isPendingPlacement: const Value(false),
              ),
          ]);
        });
      }

      await _bumpVersion(playlistId);
    });
  }

  @override
  Future<void> updateVibeStyle(String playlistId, VibePreset vibeStyle) {
    return (_db.update(_db.playlists)..where((p) => p.id.equals(playlistId)))
        .write(PlaylistsCompanion(vibeStyle: Value(vibeStyle)));
  }

  @override
  Future<void> updateCustomVibe(
    String playlistId, {
    required List<Color> colors,
    required Color accentColor,
    required String backgroundImagePath,
    required VibeCustomEffect effect,
    required String backgroundVideoPath,
  }) {
    return (_db.update(_db.playlists)..where((p) => p.id.equals(playlistId))).write(
      PlaylistsCompanion(
        vibeStyle: const Value(VibePreset.custom),
        bgColors: Value(colors.map(colorToHex).toList()),
        customAccentColor: Value(colorToHex(accentColor)),
        customBackgroundImagePath: Value(backgroundImagePath),
        customEffect: Value(effect),
        customBackgroundVideoPath: Value(backgroundVideoPath),
      ),
    );
  }

  @override
  Future<void> incrementVersion(String playlistId) => _bumpVersion(playlistId);

  @override
  Future<void> updateCoverImagePath(String playlistId, String path) {
    return (_db.update(_db.playlists)..where((p) => p.id.equals(playlistId)))
        .write(PlaylistsCompanion(coverImagePath: Value(path)));
  }

  @override
  Future<void> updateShowCoverImage(String playlistId, bool showCoverImage) {
    return (_db.update(_db.playlists)..where((p) => p.id.equals(playlistId)))
        .write(PlaylistsCompanion(showCoverImage: Value(showCoverImage)));
  }

  @override
  Future<void> renamePlaylist(String playlistId, String title) {
    return (_db.update(_db.playlists)..where((p) => p.id.equals(playlistId)))
        .write(PlaylistsCompanion(title: Value(title)));
  }

  @override
  Future<void> deletePlaylist(String playlistId) {
    return _db.transaction(() async {
      await (_db.delete(_db.playlistTracks)..where((t) => t.playlistId.equals(playlistId))).go();
      await (_db.delete(_db.playlists)..where((p) => p.id.equals(playlistId))).go();
    });
  }

  Future<void> _bumpVersion(String playlistId) async {
    final Playlist current = await (_db.select(_db.playlists)..where((p) => p.id.equals(playlistId))).getSingle();
    await (_db.update(_db.playlists)..where((p) => p.id.equals(playlistId)))
        .write(PlaylistsCompanion(version: Value(current.version + 1)));
  }
}

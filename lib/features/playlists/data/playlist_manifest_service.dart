import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/playlist_manifest/manifest_track_ref.dart';
import '../../../core/playlist_manifest/playlist_manifest.dart';
import '../../../core/storage/database/app_database.dart';
import '../../../core/theme/vibe_engine/vibe_engine.dart';
import '../../diff/domain/diff_result.dart';
import '../domain/fork_result.dart';

/// Export/fork/diff de playlists via le manifeste JSON commun (Étape 6).
class PlaylistManifestService {
  PlaylistManifestService(this._db);

  final AppDatabase _db;

  Future<PlaylistManifest> buildManifest(String playlistId, {String? creatorHandle}) async {
    final Playlist playlist = await (_db.select(_db.playlists)..where((p) => p.id.equals(playlistId))).getSingle();
    final List<ManifestTrackRef> tracks = (await _orderedTracks(playlistId)).map(_toManifestRef).toList();

    return PlaylistManifest(
      id: playlist.id,
      title: playlist.title,
      description: playlist.description,
      version: playlist.version,
      tags: playlist.tags,
      vibeStyle: playlist.vibeStyle.name,
      creatorHandle: creatorHandle,
      originalCreator: playlist.originalCreator,
      tracks: tracks,
    );
  }

  /// Écrit le manifeste dans le dossier documents de l'app (`exports/`) et
  /// retourne le fichier créé.
  Future<File> exportManifestToFile(String playlistId, {String? creatorHandle}) async {
    final PlaylistManifest manifest = await buildManifest(playlistId, creatorHandle: creatorHandle);
    final Directory documentsDir = await getApplicationDocumentsDirectory();
    final String safeName = manifest.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final File file = File(p.join(documentsDir.path, 'exports', '$safeName.json'));
    await file.parent.create(recursive: true);
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(manifest.toJson()));
    return file;
  }

  /// Crée une nouvelle playlist locale éditable à partir d'un manifeste
  /// importé, taguée "Inspired by @OriginalCreator" (`playlists.original_creator`).
  Future<ForkResult> forkFromManifest(PlaylistManifest manifest) async {
    final String newId = '${manifest.id}-fork-${DateTime.now().millisecondsSinceEpoch}';
    final String? attribution = manifest.creatorHandle ?? manifest.originalCreator;
    final (resolvedIds, missing) = await _resolveAgainstLocalLibrary(manifest.tracks);

    await _db.transaction(() async {
      await _db.into(_db.playlists).insert(
            PlaylistsCompanion.insert(
              id: newId,
              title: manifest.title,
              description: Value(manifest.description),
              originalCreator: Value(attribution),
              sourceManifestId: Value(manifest.id),
              version: Value(manifest.version),
              tags: Value(manifest.tags),
              vibeStyle: Value(_parseVibe(manifest.vibeStyle)),
            ),
          );
      await _insertPlaylistTracks(newId, resolvedIds);
    });

    final Playlist created = await (_db.select(_db.playlists)..where((p) => p.id.equals(newId))).getSingle();
    return ForkResult(playlist: created, missingTracks: missing);
  }

  Future<DiffResult> computeDiff(String playlistId, PlaylistManifest incoming) async {
    final Playlist local = await (_db.select(_db.playlists)..where((p) => p.id.equals(playlistId))).getSingle();
    final List<Track> localTracks = await _orderedTracks(playlistId);

    final Map<String, ManifestTrackRef> localByKey = {for (final t in localTracks) t.id: _toManifestRef(t)};
    final Map<String, ManifestTrackRef> incomingByKey = {for (final t in incoming.tracks) t.sanitizedKey: t};

    return DiffResult(
      localVersion: local.version,
      incomingVersion: incoming.version,
      added: [for (final e in incomingByKey.entries) if (!localByKey.containsKey(e.key)) e.value],
      removed: [for (final e in localByKey.entries) if (!incomingByKey.containsKey(e.key)) e.value],
    );
  }

  /// "Accept Update" : aligne `playlist_tracks` sur le manifeste entrant et
  /// met à jour `version` localement.
  Future<ForkResult> acceptUpdate(String playlistId, PlaylistManifest incoming) async {
    final (resolvedIds, missing) = await _resolveAgainstLocalLibrary(incoming.tracks);

    await _db.transaction(() async {
      await (_db.delete(_db.playlistTracks)..where((t) => t.playlistId.equals(playlistId))).go();
      await _insertPlaylistTracks(playlistId, resolvedIds);
      await (_db.update(_db.playlists)..where((p) => p.id.equals(playlistId)))
          .write(PlaylistsCompanion(version: Value(incoming.version)));
    });

    final Playlist updated = await (_db.select(_db.playlists)..where((p) => p.id.equals(playlistId))).getSingle();
    return ForkResult(playlist: updated, missingTracks: missing);
  }

  Future<List<Track>> _orderedTracks(String playlistId) async {
    final query = _db.select(_db.playlistTracks).join([
      innerJoin(_db.tracks, _db.tracks.id.equalsExp(_db.playlistTracks.trackId)),
    ])
      ..where(_db.playlistTracks.playlistId.equals(playlistId))
      ..orderBy([OrderingTerm.asc(_db.playlistTracks.position)]);

    final rows = await query.get();
    return rows.map((row) => row.readTable(_db.tracks)).toList();
  }

  Future<(List<String>, List<ManifestTrackRef>)> _resolveAgainstLocalLibrary(List<ManifestTrackRef> refs) async {
    final Set<String> localIds = (await _db.select(_db.tracks).get()).map((t) => t.id).toSet();
    final List<String> resolved = [];
    final List<ManifestTrackRef> missing = [];

    for (final ref in refs) {
      if (localIds.contains(ref.sanitizedKey)) {
        resolved.add(ref.sanitizedKey);
      } else {
        missing.add(ref);
      }
    }
    return (resolved, missing);
  }

  Future<void> _insertPlaylistTracks(String playlistId, List<String> orderedTrackIds) async {
    if (orderedTrackIds.isEmpty) return;
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

  ManifestTrackRef _toManifestRef(Track track) => ManifestTrackRef(
        title: track.title,
        artist: track.artists.isNotEmpty ? track.artists.first : 'Unknown',
        album: track.album.isEmpty ? null : track.album,
      );

  VibePreset _parseVibe(String raw) => VibePreset.values.firstWhere((v) => v.name == raw, orElse: () => VibePreset.minimal);
}

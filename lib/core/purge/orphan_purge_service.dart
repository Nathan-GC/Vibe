import 'dart:io';

import '../storage/database/app_database.dart';

/// Suppression **définitive** (fichier physique + lignes `tracks`/`track_artists`)
/// des morceaux sélectionnés dans la vue de nettoyage (Étape 7).
class OrphanPurgeService {
  OrphanPurgeService(this._db);

  final AppDatabase _db;

  Future<void> deleteTracks(List<Track> tracks) async {
    if (tracks.isEmpty) return;

    for (final track in tracks) {
      final File file = File(track.filePath);
      if (await file.exists()) await file.delete();
    }

    final List<String> ids = tracks.map((t) => t.id).toList();
    await _db.transaction(() async {
      await (_db.delete(_db.trackArtists)..where((t) => t.trackId.isIn(ids))).go();
      await (_db.delete(_db.tracks)..where((t) => t.id.isIn(ids))).go();
    });
  }
}

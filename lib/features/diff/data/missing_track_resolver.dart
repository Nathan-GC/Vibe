import 'dart:io';

import '../../../core/storage/database/app_database.dart';
import '../../../core/storage/database/track_repository.dart';
import '../../../core/storage/scanner/library_scan_service.dart';
import '../../../core/storage/scanner/scanned_track.dart';
import '../../../core/storage/storage_manager/imported_audio_file.dart';
import '../../../core/storage/storage_manager/storage_manager_service.dart';

/// Résout une entrée de manifeste manquante (Étape 6.4) en important un
/// fichier choisi par l'utilisateur : copie vers /Music/AppFolder/ (Disk
/// Guard, Étape 1), passage par le pipeline de scan/sanitization (Étape 2),
/// puis insertion en base (Étape 3).
class MissingTrackResolver {
  MissingTrackResolver(this._storageManager, this._scanService, this._trackRepository);

  final StorageManagerService _storageManager;
  final LibraryScanService _scanService;
  final TrackRepository _trackRepository;

  Future<Track?> importFromDevice(File pickedFile) async {
    final ImportedAudioFile imported = await _storageManager.importAudioFile(pickedFile);
    final ScannedTrack? scanned = await _scanService.processImportedFile(imported);
    if (scanned == null) return null;

    await _trackRepository.upsertTrack(scanned);
    return _trackRepository.findById(scanned.id);
  }
}

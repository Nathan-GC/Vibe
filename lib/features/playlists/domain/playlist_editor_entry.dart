import '../../../core/storage/database/app_database.dart';

/// Une ligne de l'éditeur de playlist : le morceau, sa position, et si elle
/// est encore "en attente de placement" (ajoutée mais jamais réordonnée
/// manuellement) — affichée avec un contour ambre tant que non commitée.
class PlaylistEditorEntry {
  const PlaylistEditorEntry({required this.track, required this.isPendingPlacement, required this.position});

  final Track track;
  final bool isPendingPlacement;
  final int position;
}

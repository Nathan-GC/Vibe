import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../features/library/data/library_providers.dart';
import '../../../features/library/presentation/metadata_editor_modal.dart';
import '../../../features/playlists/data/playlist_providers.dart';
import '../../storage/database/app_database.dart';
import '../../storage/database/track_repository.dart';
import 'add_to_playlist_sheet.dart';

/// Actions rapides sur un morceau via appui long — utilisé de façon
/// cohérente dans Recherche, Bibliothèque et l'éditeur de playlist plutôt
/// que de dupliquer des menus différents par écran.
class TrackActionsSheet extends ConsumerWidget {
  const TrackActionsSheet({super.key, required this.track, this.currentPlaylistId, this.onChanged});

  final Track track;
  /// Playlist depuis laquelle ce morceau est affiché — active l'action
  /// "Retirer de cette playlist" quand renseignée (éditeur de playlist).
  final String? currentPlaylistId;
  /// Appelé une fois qu'une action a réellement terminé sa modification en
  /// base — pas au moment où cette feuille se ferme, qui la précède souvent
  /// (ex. "Modifier les métadonnées" ferme la feuille puis ouvre un dialogue
  /// séparé ; attendre uniquement `show()` déclenchait donc une resynchro
  /// prématurée chez l'appelant, avant même la sauvegarde). Optionnel : les
  /// écrans purement réactifs (Recherche, Bibliothèque) n'en ont pas besoin.
  final VoidCallback? onChanged;

  static Future<void> show(
    BuildContext context,
    Track track, {
    String? currentPlaylistId,
    VoidCallback? onChanged,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => TrackActionsSheet(track: track, currentPlaylistId: currentPlaylistId, onChanged: onChanged),
    );
  }

  /// Ouvre l'éditeur complet (Titre/Artiste/Album/Année/Genre/Pochette,
  /// recherche API ou saisie manuelle) — remplace l'ancien dialogue minimal
  /// Titre/Artiste : un seul point d'entrée pour renommer ou (ré-)enrichir un
  /// morceau, accessible à tout moment depuis Recherche/Bibliothèque/éditeur
  /// de playlist (partout où `TrackActionsSheet` est utilisé).
  Future<void> _editMetadata(BuildContext context) async {
    Navigator.of(context).pop();
    await showDialog<void>(context: context, builder: (context) => MetadataEditorModal(track: track));
    onChanged?.call();
  }

  /// Même précaution que [_editMetadata] : `ImagePicker().pickImage` est un aller-
  /// retour utilisateur potentiellement long (choix dans la galerie), donc le
  /// `ref` de la feuille déjà démontée ne doit plus servir après cet `await`.
  Future<void> _editCoverArt(BuildContext context, WidgetRef ref) async {
    final storageManager = ref.read(storageManagerServiceProvider);
    final TrackRepository trackRepository = ref.read(trackRepositoryProvider);
    Navigator.of(context).pop();
    final XFile? picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (picked == null) return;

    final File imported = await storageManager.importTrackCoverImage(File(picked.path), track.id);
    await trackRepository.updateCoverArtPath(track.id, imported.path);
    onChanged?.call();
  }

  Future<void> _addToPlaylist(BuildContext context) async {
    Navigator.of(context).pop();
    if (context.mounted) await AddToPlaylistSheet.show(context, track.id);
    onChanged?.call();
  }

  Future<void> _removeFromCurrentPlaylist(BuildContext context, WidgetRef ref) async {
    final playlistTrackRepository = ref.read(playlistTrackRepositoryProvider);
    Navigator.of(context).pop();
    final String? playlistId = currentPlaylistId;
    if (playlistId == null) return;
    await playlistTrackRepository.removeTrack(playlistId, track.id);
    onChanged?.call();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Modifier les métadonnées'),
            onTap: () => _editMetadata(context),
          ),
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: const Text('Éditer la pochette'),
            onTap: () => _editCoverArt(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.playlist_add),
            title: const Text('Ajouter à une playlist'),
            onTap: () => _addToPlaylist(context),
          ),
          if (currentPlaylistId != null)
            ListTile(
              leading: const Icon(Icons.playlist_remove),
              title: const Text('Retirer de cette playlist'),
              onTap: () => _removeFromCurrentPlaylist(context, ref),
            ),
        ],
      ),
    );
  }
}

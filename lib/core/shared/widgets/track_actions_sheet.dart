import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../features/library/data/library_providers.dart';
import '../../../features/library/presentation/metadata_editor_modal.dart';
import '../../../features/playlists/data/playlist_providers.dart';
import '../../audio_engine/preview_player_controller.dart';
import '../../purge/purge_providers.dart';
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

  /// Section 6.1 — extrait audio du fichier LOCAL (contrairement aux 20-30s
  /// en ligne de [OnlineTrackCard], qui restent le seul autre appelant de
  /// [PreviewPlayerController.togglePreview]) : reste ouvert (pas de `pop`)
  /// pour laisser basculer lecture/arrêt sans rouvrir la feuille, et démarre
  /// après le silence de tête déjà détecté (`trimStartMs`, voir
  /// SilenceTrimmerService) plutôt qu'au tout début du fichier.
  Future<void> _togglePreview(WidgetRef ref) {
    return ref
        .read(previewPlayerControllerProvider.notifier)
        .togglePreview(track.filePath, startAt: Duration(milliseconds: track.trimStartMs));
  }

  /// Suppression **définitive** du fichier audio de l'appareil (Section 6.1)
  /// — mêmes garanties que la vue de nettoyage des orphelins
  /// (OrphanPurgeService : fichier physique + lignes `tracks`/`track_artists`).
  /// Irréversible, donc confirmé avant d'agir, comme la suppression de
  /// playlist (PersonalSpaceScreen._delete).
  Future<void> _deleteAudioFile(BuildContext context, WidgetRef ref) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer ce fichier ?'),
        content: Text('"${track.title}" sera définitivement supprimé de l\'appareil. Cette action est irréversible.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (confirmed != true) return;

    // Un extrait de ce morceau en cours de lecture tiendrait sinon un handle
    // ouvert sur le fichier qu'on s'apprête à effacer.
    if (ref.read(previewPlayerControllerProvider) == track.filePath) {
      await ref.read(previewPlayerControllerProvider.notifier).stop();
    }

    try {
      await ref.read(orphanPurgeServiceProvider).deleteTracks([track]);
    } catch (_) {
      // Un morceau indexé par le scan plein-appareil (jamais copié dans le
      // dossier privé de l'app, contrairement à un import manuel) peut être
      // protégé par le stockage cloisonné d'Android : l'app peut le lire
      // mais pas le supprimer directement — vérifié empiriquement (le fichier
      // reste intact). Feedback explicite plutôt que de laisser la feuille
      // bloquée sans aucun retour.
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Suppression impossible : fichier protégé par le système.')),
        );
      }
      return;
    }

    if (context.mounted) Navigator.of(context).pop();
    onChanged?.call();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String? activePreviewPath = ref.watch(previewPlayerControllerProvider);
    final bool isPreviewingThis = activePreviewPath == track.filePath;

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
          ListTile(
            leading: Icon(isPreviewingThis ? Icons.stop_circle_outlined : Icons.play_circle_outline),
            title: Text(isPreviewingThis ? 'Arrêter l\'extrait' : 'Écouter un extrait'),
            onTap: () => _togglePreview(ref),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
            title: const Text('Supprimer le fichier de l\'appareil', style: TextStyle(color: Colors.redAccent)),
            onTap: () => _deleteAudioFile(context, ref),
          ),
        ],
      ),
    );
  }
}

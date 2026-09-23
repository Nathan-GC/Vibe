import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../features/playlists/data/playlist_providers.dart';
import '../../../features/playlists/domain/playlist_editor_entry.dart';
import '../../audio_engine/player_controller.dart';
import '../../storage/database/app_database.dart';
import '../../theme/design_system/app_spacing.dart';
import '../../theme/design_system/vibe_design_system.dart';
import 'playlist_cover_image.dart';

/// Lecture immédiate d'une playlist depuis sa pochette (Section 3.3) —
/// factorisé ici pour rester identique au bouton "Lire" dédié de Mon Espace
/// (voir PersonalSpaceScreen._PlaylistTile) : ne fait rien si la playlist est
/// vide plutôt que de naviguer vers un Lecteur sans rien à jouer.
Future<void> playPlaylistAndNavigate(BuildContext context, WidgetRef ref, Playlist playlist) async {
  final List<Track> tracks = await ref.read(playlistRepositoryProvider).fetchOrderedTracks(playlist.id);
  if (tracks.isEmpty) return;
  await ref.read(playerControllerProvider.notifier).playPlaylist(playlist.id, tracks);
  if (context.mounted) context.go('/player');
}

/// Carte verticale d'une playlist (Design System, charte Spotify) : pochette
/// carrée en haut, titre en gras et sous-titre gris en dessous. Utilisée
/// aussi bien dans les carrousels horizontaux (Mon espace, Découverte) qu'en
/// grille.
///
/// Convention de gestes commune à toute l'app (playlists, artistes,
/// morceaux) :
///  - appui simple = action principale, IMMÉDIATE (lecture depuis une
///    pochette, ouverture depuis un titre) — jamais conditionnée à un appui
///    long préalable ;
///  - appui long = vue détaillée/actions secondaires (éditeur de playlist,
///    fiche artiste, feuille d'actions d'un morceau), jamais une lecture.
/// Exception : les listes réordonnables (file d'attente, éditeur de
/// playlist) où l'appui long reste réservé au glisser-déposer.
class PlaylistCard extends StatelessWidget {
  const PlaylistCard(
      {super.key, required this.playlist, this.onTap, this.onImageTap, this.onLongPress, this.width = 152});

  final Playlist playlist;
  final VoidCallback? onTap;
  // Appui long (voir convention ci-dessus) : vue détaillée, sur toute la
  // carte pochette comprise.
  final VoidCallback? onLongPress;
  // Section 3.3 : appui sur la pochette = lecture immédiate, distinct du
  // reste de la carte (titre/sous-titre) qui garde [onTap] (édition). Retombe
  // sur [onTap] si non fourni, pour rester compatible avec un appelant qui ne
  // distinguerait pas les deux zones.
  final VoidCallback? onImageTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: InkWell(
        borderRadius: const BorderRadius.all(Radius.circular(AppRadii.card)),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: InkWell(
                borderRadius: const BorderRadius.all(Radius.circular(AppRadii.card)),
                onTap: onImageTap ?? onTap,
                onLongPress: onLongPress,
                child: PlaylistCoverImage(playlist: playlist),
              ),
            ),
            const SizedBox(height: AppSpacing.s),
            Text(
              playlist.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 2),
            _PlaylistSubtitle(playlist: playlist),
          ],
        ),
      ),
    );
  }
}

class _PlaylistSubtitle extends ConsumerWidget {
  const _PlaylistSubtitle({required this.playlist});

  final Playlist playlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<PlaylistEditorEntry>> entries = ref.watch(playlistEditorEntriesProvider(playlist.id));
    final int count = entries.value?.length ?? 0;
    final String by = playlist.originalCreator == null ? 'Toi' : '@${playlist.originalCreator}';

    return Text(
      'Par $by • $count morceau${count > 1 ? 'x' : ''}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}

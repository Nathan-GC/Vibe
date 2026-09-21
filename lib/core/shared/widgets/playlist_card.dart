import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/playlists/data/playlist_providers.dart';
import '../../../features/playlists/domain/playlist_editor_entry.dart';
import '../../storage/database/app_database.dart';
import '../../theme/design_system/app_spacing.dart';
import '../../theme/design_system/vibe_design_system.dart';
import 'playlist_cover_image.dart';

/// Carte verticale d'une playlist (Design System, charte Spotify) : pochette
/// carrée en haut, titre en gras et sous-titre gris en dessous. Utilisée
/// aussi bien dans les carrousels horizontaux (Mon espace, Découverte) qu'en
/// grille.
class PlaylistCard extends StatelessWidget {
  const PlaylistCard({super.key, required this.playlist, this.onTap, this.width = 152});

  final Playlist playlist;
  final VoidCallback? onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: InkWell(
        borderRadius: const BorderRadius.all(Radius.circular(AppRadii.card)),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(aspectRatio: 1, child: PlaylistCoverImage(playlist: playlist)),
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/database/app_database.dart';
import '../../../core/theme/vibe_engine/vibe_engine.dart';
import '../../playlists/data/playlist_providers.dart';
import '../data/recommendation_providers.dart';

/// Filtre "Playlist" du wireframe : choisit la playlist cible du bloc
/// "Suggestion de titres".
class PlaylistFilterSheet extends ConsumerWidget {
  const PlaylistFilterSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => const PlaylistFilterSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Playlist>> playlists = ref.watch(playlistsProvider);
    final String? selected = ref.watch(suggestionPlaylistIdProvider);

    return SafeArea(
      child: playlists.when(
        data: (data) {
          if (data.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Aucune playlist — crée-en une depuis "Mon espace".'),
            );
          }
          return ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Text('Playlist cible des suggestions', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              ...data.map(
                (playlist) => ListTile(
                  leading: CircleAvatar(backgroundColor: playlist.vibeStyle.accentColor, radius: 10),
                  title: Text(playlist.title),
                  trailing: playlist.id == selected ? const Icon(Icons.check) : null,
                  onTap: () {
                    ref.read(suggestionPlaylistIdProvider.notifier).select(playlist.id);
                    Navigator.of(context).pop();
                  },
                ),
              ),
            ],
          );
        },
        loading: () => const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (error, _) => Padding(padding: const EdgeInsets.all(24), child: Text('Erreur : $error')),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/playlist_manifest/manifest_track_ref.dart';
import '../../../core/shared/widgets/online_track_card.dart';
import '../../../core/shared/widgets/skeleton_loader.dart';
import '../../../core/storage/database/app_database.dart';
import '../../diff/presentation/missing_track_dialog.dart';
import 'suggestions_providers.dart';

/// Moteur "To Complete [Playlist]" (Étape 4) : bascule entre Mode A
/// (bibliothèque locale, insertion instantanée) et Mode B (suggestions
/// externes avec preview, ajout nécessitant un téléchargement ultérieur).
class CompletePlaylistScreen extends ConsumerStatefulWidget {
  const CompletePlaylistScreen({super.key, required this.playlistId});

  final String playlistId;

  @override
  ConsumerState<CompletePlaylistScreen> createState() => _CompletePlaylistScreenState();
}

class _CompletePlaylistScreenState extends ConsumerState<CompletePlaylistScreen> {
  bool _globalMode = false;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<Playlist?> playlist = ref.watch(playlistByIdProvider(widget.playlistId));

    return Scaffold(
      appBar: AppBar(
        title: playlist.when(
          data: (p) => Text('Pour compléter "${p?.title ?? ''}"'),
          loading: () => const Text('Pour compléter...'),
          error: (_, __) => const Text('Pour compléter...'),
        ),
      ),
      body: Column(
        children: [
          SwitchListTile(
            title: Text(_globalMode ? 'Suggestions en ligne' : 'Dans ma bibliothèque'),
            subtitle: Text(
              _globalMode
                  ? 'Morceaux non téléchargés correspondant aux tags de la playlist'
                  : 'Morceaux locaux oubliés, non assignés à cette playlist',
            ),
            value: _globalMode,
            onChanged: (value) => setState(() => _globalMode = value),
          ),
          const Divider(height: 1),
          Expanded(
            child: _globalMode
                ? _GlobalSuggestionsList(playlistId: widget.playlistId)
                : _LocalSuggestionsList(playlistId: widget.playlistId),
          ),
        ],
      ),
    );
  }
}

class _LocalSuggestionsList extends ConsumerWidget {
  const _LocalSuggestionsList({required this.playlistId});

  final String playlistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Track>> tracks = ref.watch(localSuggestionsProvider(playlistId));

    return tracks.when(
      data: (data) {
        if (data.isEmpty) return const Center(child: Text('Rien à rediscover pour le moment.'));
        return ListView.builder(
          itemCount: data.length,
          itemBuilder: (context, index) {
            final Track track = data[index];
            return ListTile(
              leading: const Icon(Icons.folder_zip_outlined),
              title: Text(track.title),
              subtitle: Text(track.artists.join(', ')),
              trailing: IconButton(
                icon: const Icon(Icons.add_circle_outline),
                tooltip: 'Ajouter (instantané)',
                onPressed: () async {
                  await ref.read(playlistTrackRepositoryProvider).addTrack(playlistId, track.id);
                  ref.invalidate(localSuggestionsProvider(playlistId));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('"${track.title}" ajouté')));
                  }
                },
              ),
            );
          },
        );
      },
      loading: () => ListView(children: List.generate(6, (_) => const SkeletonLoader())),
      error: (error, _) => Center(child: Text('Erreur : $error')),
    );
  }
}

class _GlobalSuggestionsList extends ConsumerWidget {
  const _GlobalSuggestionsList({required this.playlistId});

  final String playlistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(globalSuggestionsProvider(playlistId));

    return tracks.when(
      data: (data) {
        if (data.isEmpty) return const Center(child: Text('Aucune suggestion en ligne pour cette playlist.'));
        return ListView.builder(
          itemCount: data.length,
          itemBuilder: (context, index) {
            final track = data[index];
            return OnlineTrackCard(
              track: track,
              // L'API de métadonnées ne fournit qu'un extrait 30s, jamais le
              // fichier complet : on redirige vers l'assistant "morceau
              // manquant" (Étape 6.4) pour que l'utilisateur fournisse le MP3
              // depuis son propre stockage plutôt que de prétendre l'ajouter.
              onAdd: () => showDialog<void>(
                context: context,
                builder: (context) => MissingTrackDialog(
                  missingTrack: ManifestTrackRef(title: track.title, artist: track.artist, album: track.album),
                  playlistId: playlistId,
                ),
              ),
            );
          },
        );
      },
      loading: () => ListView(children: List.generate(6, (_) => const SkeletonLoader())),
      error: (error, _) => Center(child: Text('Erreur : $error')),
    );
  }
}

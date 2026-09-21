import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/database/app_database.dart';
import '../../../core/storage/database/duplicate_track_group.dart';
import '../data/library_providers.dart';
import 'metadata_editor_modal.dart';

/// Alerte "doublons stricts" (même Titre + même Artiste) — pour chaque
/// groupe, ouvre l'éditeur de métadonnées sur l'un des deux afin de le
/// renommer ou le ré-enrichir manuellement plutôt que de laisser deux fiches
/// concurrentes dans la bibliothèque.
class DuplicateTracksScreen extends ConsumerWidget {
  const DuplicateTracksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<DuplicateTrackGroup>> groups = ref.watch(duplicateTrackGroupsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Doublons détectés')),
      body: groups.when(
        data: (data) {
          if (data.isEmpty) return const Center(child: Text('Aucun doublon — chaque morceau est unique.'));
          return ListView.builder(
            itemCount: data.length,
            itemBuilder: (context, index) => _DuplicateGroupCard(group: data[index]),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Erreur : $error')),
      ),
    );
  }
}

class _DuplicateGroupCard extends StatelessWidget {
  const _DuplicateGroupCard({required this.group});

  final DuplicateTrackGroup group;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber_outlined, color: Colors.amber, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${group.title} — ${group.artist}',
                    style: Theme.of(context).textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${group.tracks.length} exemplaires identiques — renomme ou ré-enrichis l\'un des deux.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Divider(height: 20),
            for (final track in group.tracks) _DuplicateTrackRow(track: track),
          ],
        ),
      ),
    );
  }
}

class _DuplicateTrackRow extends StatelessWidget {
  const _DuplicateTrackRow({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: const Icon(Icons.music_note_outlined),
      title: Text(track.album.isEmpty ? '(album inconnu)' : track.album, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(track.filePath, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: TextButton(
        onPressed: () => showDialog<void>(context: context, builder: (context) => MetadataEditorModal(track: track)),
        child: const Text('Modifier'),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/database/app_database.dart';
import '../data/playlist_providers.dart';

/// Édition des mots-clés de style d'une playlist (Étape 4) — purement
/// descriptif pour l'utilisateur, voir PlaylistRepository.updateTags.
class PlaylistKeywordsDialog extends ConsumerStatefulWidget {
  const PlaylistKeywordsDialog({super.key, required this.playlist});

  final Playlist playlist;

  @override
  ConsumerState<PlaylistKeywordsDialog> createState() => _PlaylistKeywordsDialogState();
}

class _PlaylistKeywordsDialogState extends ConsumerState<PlaylistKeywordsDialog> {
  late List<String> _tags = List.of(widget.playlist.tags);
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _addTag() {
    final String value = _controller.text.trim();
    if (value.isEmpty || _tags.contains(value)) return;
    setState(() {
      _tags = [..._tags, value];
      _controller.clear();
    });
    ref.read(playlistRepositoryProvider).updateTags(widget.playlist.id, _tags);
  }

  void _removeTag(String tag) {
    setState(() => _tags = _tags.where((t) => t != tag).toList());
    ref.read(playlistRepositoryProvider).updateTags(widget.playlist.id, _tags);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Mots-clés — ${widget.playlist.title}'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_tags.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('Aucun mot-clé pour le moment.'),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _tags
                    .map((tag) => InputChip(label: Text(tag), onDeleted: () => _removeTag(tag)))
                    .toList(),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Ajouter un mot-clé (ex. chill, road trip...)',
                suffixIcon: IconButton(icon: const Icon(Icons.add), onPressed: _addTag),
              ),
              onSubmitted: (_) => _addTag(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Fermer')),
      ],
    );
  }
}

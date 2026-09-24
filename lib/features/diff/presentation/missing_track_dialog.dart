import 'dart:io';

import 'package:drift/drift.dart' hide Column;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/playlist_manifest/manifest_track_ref.dart';
import '../../../core/storage/database/app_database.dart';
import '../../../core/storage/database/database_provider.dart';
import '../../playlists/data/playlist_providers.dart';
import '../data/diff_providers.dart';

/// Assistant d'import de morceau manquant (Étape 6.4) : choisir un MP3 depuis
/// le stockage, ou chercher une correspondance déjà présente dans la
/// bibliothèque locale.
class MissingTrackDialog extends ConsumerStatefulWidget {
  const MissingTrackDialog({super.key, required this.missingTrack, required this.playlistId});

  final ManifestTrackRef missingTrack;
  final String playlistId;

  @override
  ConsumerState<MissingTrackDialog> createState() => _MissingTrackDialogState();
}

class _MissingTrackDialogState extends ConsumerState<MissingTrackDialog> {
  List<Track> _localMatches = const [];
  bool _searching = false;
  bool _importing = false;

  Future<void> _searchLocally() async {
    setState(() => _searching = true);
    final AppDatabase db = ref.read(appDatabaseProvider);
    final String pattern = '%${widget.missingTrack.title}%';
    final List<Track> matches = await (db.select(db.tracks)..where((t) => t.title.like(pattern))).get();
    if (!mounted) return;
    setState(() {
      _localMatches = matches;
      _searching = false;
    });
  }

  Future<void> _pickFile() async {
    final PlatformFile? picked = await FilePicker.pickFile(type: FileType.audio);
    final String? path = picked?.path;
    if (path == null) return;

    setState(() => _importing = true);
    final Track? imported = await ref.read(missingTrackResolverProvider).importFromDevice(File(path));
    if (!mounted) return;
    setState(() => _importing = false);

    if (imported != null) {
      await _link(imported.id);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fichier trop court ou illisible.')));
    }
  }

  Future<void> _link(String trackId) async {
    await ref.read(playlistTrackRepositoryProvider).addTrack(widget.playlistId, trackId);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Morceau manquant : ${widget.missingTrack.title}'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                [widget.missingTrack.artist, if (widget.missingTrack.album != null) widget.missingTrack.album]
                    .join(' · '),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: _importing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.folder_open),
                label: const Text('Choisir un fichier MP3'),
                onPressed: _importing ? null : _pickFile,
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.search),
                label: const Text('Chercher dans ma bibliothèque'),
                onPressed: _searching ? null : _searchLocally,
              ),
              if (_searching) const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()),
              ..._localMatches.map(
                (track) => ListTile(
                  title: Text(track.title),
                  subtitle: Text(track.artists.join(', ')),
                  onTap: () => _link(track.id),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Ignorer'))],
    );
  }
}

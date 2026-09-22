import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/database/track_repository.dart';
import '../../discovery/data/artist_providers.dart';
import '../../discovery/domain/top_artist_playlist.dart';

/// Fusion Manuelle (Section 4, Réglages > "Fusion & renommage d'artistes") :
/// liste tous les artistes locaux, sélection multiple par appui long.
///  - >= 2 sélectionnés : "Fusionner" (choix du nom cible parmi la sélection
///    ou nom personnalisé).
///  - exactement 1 sélectionné : "Renommer" (simple saisie du nouveau nom).
/// Les deux passent par [TrackRepository.renameOrMergeArtists].
class ManualArtistFusionScreen extends ConsumerStatefulWidget {
  const ManualArtistFusionScreen({super.key});

  @override
  ConsumerState<ManualArtistFusionScreen> createState() => _ManualArtistFusionScreenState();
}

class _ManualArtistFusionScreenState extends ConsumerState<ManualArtistFusionScreen> {
  final Set<String> _selected = {};
  bool _busy = false;

  void _toggle(String artistName) {
    setState(() {
      if (!_selected.remove(artistName)) _selected.add(artistName);
    });
  }

  Future<void> _rename() async {
    final String current = _selected.single;
    final String? newName = await _promptForName(initial: current, title: 'Renommer "$current"');
    if (newName == null || newName.trim().isEmpty) return;
    await _apply([current], newName.trim());
  }

  Future<void> _merge() async {
    final String? targetName = await _pickMergeTargetName();
    if (targetName == null || targetName.trim().isEmpty) return;
    await _apply(_selected.toList(), targetName.trim());
  }

  Future<void> _apply(List<String> sources, String target) async {
    setState(() => _busy = true);
    await ref.read(trackRepositoryProvider).renameOrMergeArtists(sources, target);
    ref.invalidate(allArtistsWithTrackCountProvider);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _selected.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('"$target" appliqué à ${sources.length} artiste(s).')),
    );
  }

  Future<String?> _promptForName({required String initial, required String title}) {
    final TextEditingController controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: 'Nom')),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.of(context).pop(controller.text), child: const Text('Valider')),
        ],
      ),
    );
  }

  /// Choix du nom cible parmi la sélection, ou saisie d'un nom personnalisé
  /// (ex. fusionner "Artist & A" + "Artist & B" en "Artist") — les deux
  /// options s'excluent mutuellement : taper dans le champ personnalisé
  /// désélectionne la radio, et inversement.
  Future<String?> _pickMergeTargetName() {
    final List<String> choices = _selected.toList()..sort();
    final TextEditingController customController = TextEditingController();
    String? selectedChoice = choices.first;

    return showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Fusionner vers...'),
            content: SingleChildScrollView(
              child: RadioGroup<String>(
                groupValue: selectedChoice,
                onChanged: (value) => setDialogState(() {
                  selectedChoice = value;
                  customController.clear();
                }),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final choice in choices) RadioListTile<String>(title: Text(choice), value: choice),
                    const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider()),
                    TextField(
                      controller: customController,
                      decoration: const InputDecoration(labelText: 'Nom personnalisé'),
                      onChanged: (value) => setDialogState(() {
                        if (value.trim().isNotEmpty) selectedChoice = null;
                      }),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(
                  customController.text.trim().isNotEmpty ? customController.text.trim() : selectedChoice,
                ),
                child: const Text('Fusionner'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<TopArtistPlaylist>> artists = ref.watch(allArtistsWithTrackCountProvider);
    final int selectedCount = _selected.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(selectedCount == 0 ? 'Fusion manuelle' : '$selectedCount sélectionné(s)'),
        actions: [
          if (selectedCount == 1)
            TextButton(onPressed: _busy ? null : _rename, child: const Text('Renommer')),
          if (selectedCount >= 2)
            TextButton(onPressed: _busy ? null : _merge, child: const Text('Fusionner')),
        ],
      ),
      body: artists.when(
        data: (data) {
          if (data.isEmpty) return const Center(child: Text('Aucun artiste.'));
          return ListView.builder(
            itemCount: data.length,
            itemBuilder: (context, index) {
              final TopArtistPlaylist artist = data[index];
              final bool selected = _selected.contains(artist.artistName);
              return ListTile(
                selected: selected,
                leading: CircleAvatar(child: Icon(selected ? Icons.check : Icons.person_outline)),
                title: Text(artist.artistName),
                subtitle: Text('${artist.trackCount} morceau${artist.trackCount > 1 ? 'x' : ''}'),
                onLongPress: () => _toggle(artist.artistName),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Erreur : $error')),
      ),
    );
  }
}

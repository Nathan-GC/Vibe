import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/shared/widgets/playlist_cover_image.dart';
import '../../../../core/shared/widgets/track_actions_sheet.dart';
import '../../../../core/storage/database/app_database.dart';
import '../../../../core/theme/design_system/app_spacing.dart';
import '../../../library/data/library_providers.dart';
import '../../data/playlist_providers.dart';
import '../../domain/playlist_editor_entry.dart';
import 'add_by_artist_sheet.dart';

/// Éditeur drag-and-drop d'une playlist (Étape 5). Le réordonnancement ne
/// touche que l'état local ; "Enregistrer" commit en base : purge
/// `is_pending_placement` (retire les contours ambre), persiste les
/// `position`, incrémente `version`.
class PlaylistEditorScreen extends ConsumerStatefulWidget {
  const PlaylistEditorScreen({super.key, required this.playlistId});

  final String playlistId;

  @override
  ConsumerState<PlaylistEditorScreen> createState() => _PlaylistEditorScreenState();
}

class _PlaylistEditorScreenState extends ConsumerState<PlaylistEditorScreen> {
  List<PlaylistEditorEntry>? _localOrder;
  bool _saving = false;

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      final List<PlaylistEditorEntry> list = [..._localOrder!];
      final PlaylistEditorEntry item = list.removeAt(oldIndex);
      list.insert(newIndex, item);
      _localOrder = list;
    });
  }

  /// `_localOrder` n'est peuplé qu'une fois (voir le commentaire sur
  /// `entries.whenData` plus bas) — une action venue de TrackActionsSheet
  /// (retrait de la playlist) ou d'AddByArtistSheet (ajout en masse) ne s'y
  /// refléterait donc jamais sans une resynchronisation explicite après coup.
  ///
  /// Récupère directement un instantané frais via le repository (`.first` sur
  /// son Stream) plutôt que de vider `_localOrder` et compter sur
  /// `entries.whenData` / `ref.watch(playlistEditorEntriesProvider(...))`
  /// pour le repeupler tout seul au prochain rebuild : bug réel reproduit —
  /// après "Ajouter par artiste", les morceaux étaient bien écrits en base
  /// (confirmé par le Snackbar et une requête SQL directe) mais l'écran
  /// continuait d'afficher l'ancienne liste indéfiniment, y compris après
  /// avoir simplement vidé `_localOrder` et même après `ref.invalidate` sur
  /// ce provider — la ré-émission du flux Drift retriggée par l'invalidation
  /// n'arrivait, pour une raison qui reste à élucider dans le comportement de
  /// ce `StreamProvider`, jamais à déclencher un nouveau `entries.whenData`.
  /// Aller chercher explicitement la donnée fraîche et l'assigner directement
  /// élimine toute dépendance à ce timing.
  Future<void> _refreshLocalOrder() async {
    final List<PlaylistEditorEntry> fresh =
        await ref.read(playlistRepositoryProvider).watchEditorEntries(widget.playlistId).first;
    if (!mounted) return;
    setState(() => _localOrder = fresh);
  }

  Future<void> _openTrackActions(Track track) async {
    // `onChanged` (pas seulement l'attente de `show()`) : une action comme
    // "Modifier les métadonnées" ferme cette feuille avant même d'ouvrir son
    // propre dialogue de saisie, donc attendre uniquement `show()` déclenchait
    // la resynchro trop tôt — le titre affiché restait périmé jusqu'à quitter
    // puis rouvrir l'écran. Voir le commentaire de `TrackActionsSheet.onChanged`.
    await TrackActionsSheet.show(
      context,
      track,
      currentPlaylistId: widget.playlistId,
      onChanged: _refreshLocalOrder,
    );
    if (mounted) await _refreshLocalOrder();
  }

  Future<void> _openAddByArtist() async {
    await AddByArtistSheet.show(context, widget.playlistId);
    if (mounted) await _refreshLocalOrder();
  }

  /// Pochette personnalisée (Design System) — distincte du fond du Vibe
  /// Creator (`/vibe`) : cette image alimente uniquement PlaylistCard, pas le
  /// fond plein écran du Player.
  Future<void> _pickCoverImage() async {
    final XFile? picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (picked == null || !mounted) return;

    final File imported =
        await ref.read(storageManagerServiceProvider).importPlaylistCoverImage(File(picked.path), widget.playlistId);
    await ref.read(playlistRepositoryProvider).updateCoverImagePath(widget.playlistId, imported.path);
  }

  Future<void> _commit() async {
    if (_localOrder == null) return;
    setState(() => _saving = true);

    final List<String> orderedIds = _localOrder!.map((e) => e.track.id).toList();
    await ref.read(playlistRepositoryProvider).commitOrder(widget.playlistId, orderedIds);

    if (!mounted) return;
    setState(() {
      _saving = false;
      _localOrder = null; // reprend le flux à jour : plus de pending, version incrémentée.
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Playlist enregistrée')));
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<PlaylistEditorEntry>> entries = ref.watch(playlistEditorEntriesProvider(widget.playlistId));
    final AsyncValue<Playlist?> playlist = ref.watch(playlistByIdProvider(widget.playlistId));
    // Doit s'exécuter avant la construction du Scaffold ci-dessous : `appBar`
    // lit `_localOrder` pour (dés)activer le bouton Enregistrer, et Dart
    // évalue les arguments nommés d'un même appel dans l'ordre du code —
    // peupler `_localOrder` à l'intérieur de `body:` (plus bas dans l'appel)
    // arrivait donc une évaluation trop tard : le tout premier frame où les
    // données arrivaient rendait le bouton désactivé, sans jamais se
    // rafraîchir ensuite puisque cette affectation ne passe pas par setState.
    entries.whenData((data) => _localOrder ??= data);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Éditeur'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_outlined),
            tooltip: 'Ajouter par artiste',
            onPressed: _openAddByArtist,
          ),
          IconButton(
            icon: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_outlined),
            onPressed: (_localOrder == null || _saving) ? null : _commit,
          ),
        ],
      ),
      body: Column(
        children: [
          if (playlist.value != null) _CoverHeader(playlist: playlist.value!, onPickImage: _pickCoverImage),
          Expanded(
            child: entries.when(
              data: (data) {
                final List<PlaylistEditorEntry> list = _localOrder!;
                if (list.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        'Playlist vide — utilise "Ajouter par artiste" en haut de l\'écran pour lui ajouter des morceaux.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                return ReorderableListView.builder(
                  // Poignée de drag explicite (voir _EditorTile) plutôt que le
                  // comportement par défaut (glisser-déposer déclenché par un
                  // appui long sur toute la tuile) : cette tuile a déjà son
                  // propre `onLongPress` (ouvre TrackActionsSheet), et les deux
                  // gestes en appui long entraient en conflit dans l'arène de
                  // gestes — bug réel reproduit : le drag ne démarrait jamais
                  // de façon fiable. Isoler le drag sur l'icône dédiée lève
                  // l'ambiguïté.
                  buildDefaultDragHandles: false,
                  itemCount: list.length,
                  onReorderItem: _reorder,
                  itemBuilder: (context, index) => _EditorTile(
                    key: ValueKey(list[index].track.id),
                    index: index,
                    entry: list[index],
                    onLongPress: () => _openTrackActions(list[index].track),
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text('Erreur : $error')),
            ),
          ),
        ],
      ),
    );
  }
}

/// Aperçu de la pochette personnalisée en tête de l'éditeur, avec le bouton
/// "Changer l'image" demandé par la charte graphique — distinct du Vibe
/// Creator (`/vibe`, fond plein écran du Player).
class _CoverHeader extends StatelessWidget {
  const _CoverHeader({required this.playlist, required this.onPickImage});

  final Playlist playlist;
  final VoidCallback onPickImage;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.m),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            height: 88,
            child: PlaylistCoverImage(playlist: playlist),
          ),
          const SizedBox(width: AppSpacing.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(playlist.title, style: Theme.of(context).textTheme.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: AppSpacing.s),
                OutlinedButton.icon(
                  icon: const Icon(Icons.image_outlined, size: 18),
                  label: const Text('Changer l\'image'),
                  onPressed: onPickImage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EditorTile extends StatelessWidget {
  const _EditorTile({super.key, required this.index, required this.entry, required this.onLongPress});

  final int index;
  final PlaylistEditorEntry entry;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        border: entry.isPendingPlacement ? Border.all(color: Colors.amber, width: 2) : null,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        title: Text(entry.track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(entry.track.artists.join(', '), maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: ReorderableDragStartListener(index: index, child: const Icon(Icons.drag_handle)),
        onLongPress: onLongPress,
      ),
    );
  }
}

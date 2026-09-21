import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/storage/database/app_database.dart';
import '../../../../core/theme/vibe_engine/playlist_vibe_resolver.dart';
import '../../../../core/theme/vibe_engine/vibe_engine.dart';
import '../../../../core/theme/vibe_engine/vibe_haptic_service.dart';
import '../../../library/data/library_providers.dart';
import '../../data/playlist_providers.dart';

/// Vibe Engine (Étape 5) : sélection du preset visuel (Layer B) d'une
/// playlist — dégradé de fond du Player et couleur des contrôles (Tab 2).
/// Inclut le Vibe Creator : palette de couleurs et image de fond sur mesure
/// (`VibePreset.custom`).
class VibeCustomizerScreen extends ConsumerWidget {
  const VibeCustomizerScreen({super.key, required this.playlistId});

  final String playlistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Playlist?> playlist = ref.watch(playlistByIdProvider(playlistId));

    return Scaffold(
      appBar: AppBar(title: const Text('Vibe')),
      body: playlist.when(
        data: (data) {
          if (data == null) return const SizedBox.shrink();
          final VibePreset current = data.vibeStyle;
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              ...VibePreset.values.where((preset) => preset != VibePreset.custom).map((preset) {
                final bool isSelected = preset == current;
                return Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: isSelected ? BorderSide(color: preset.accentColor, width: 2) : BorderSide.none,
                  ),
                  child: ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: preset.gradientColors),
                        shape: BoxShape.circle,
                      ),
                    ),
                    title: Text(preset.label),
                    trailing: isSelected ? Icon(Icons.check, color: preset.accentColor) : null,
                    onTap: () {
                      VibeHapticService.triggerForPreset(preset, VibeInteraction.vibeSelect);
                      ref.read(playlistRepositoryProvider).updateVibeStyle(playlistId, preset);
                    },
                  ),
                );
              }),
              const Divider(height: 32),
              _CustomVibeEditor(playlistId: playlistId, playlist: data),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Erreur : $error')),
      ),
    );
  }
}

/// Section "Personnaliser" : jusqu'à 2 couleurs de dégradé au choix, plus une
/// image de fond importée depuis la galerie (`image_picker`). Enregistrer
/// bascule la playlist sur `VibePreset.custom`.
class _CustomVibeEditor extends ConsumerStatefulWidget {
  const _CustomVibeEditor({required this.playlistId, required this.playlist});

  final String playlistId;
  final Playlist playlist;

  @override
  ConsumerState<_CustomVibeEditor> createState() => _CustomVibeEditorState();
}

class _CustomVibeEditorState extends ConsumerState<_CustomVibeEditor> {
  static const List<Color> _swatchChoices = [
    Color(0xFFFF3D68),
    Color(0xFFFF8A00),
    Color(0xFFFFE14D),
    Color(0xFF6FCF97),
    Color(0xFF219653),
    Color(0xFF00F0FF),
    Color(0xFF2F80ED),
    Color(0xFF9B51E0),
    Color(0xFFFF00E5),
    Color(0xFFFFFFFF),
  ];

  late List<Color> _selectedColors;
  late Color _selectedAccentColor;
  String? _pendingImagePath;
  bool _clearImage = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final VibeVisual current = widget.playlist.resolvedVibe;
    _selectedColors = widget.playlist.vibeStyle == VibePreset.custom
        ? List.of(current.gradientColors)
        : [_swatchChoices[0], _swatchChoices[5]];
    _selectedAccentColor = current.accentColor;
  }

  void _toggleColor(Color color) {
    setState(() {
      if (_selectedColors.contains(color)) {
        if (_selectedColors.length > 1) _selectedColors.remove(color);
      } else if (_selectedColors.length < 2) {
        _selectedColors.add(color);
      } else {
        _selectedColors = [_selectedColors.last, color];
      }
    });
  }

  Future<void> _pickImage() async {
    final XFile? picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (picked == null) return;
    setState(() {
      _pendingImagePath = picked.path;
      _clearImage = false;
    });
  }

  Future<void> _save() async {
    VibeHapticService.triggerForPreset(VibePreset.custom, VibeInteraction.vibeSelect);
    setState(() => _isSaving = true);
    try {
      String backgroundImagePath = widget.playlist.customBackgroundImagePath;
      if (_clearImage) {
        backgroundImagePath = '';
      } else if (_pendingImagePath != null) {
        final File imported = await ref
            .read(storageManagerServiceProvider)
            .importVibeBackgroundImage(File(_pendingImagePath!), widget.playlistId);
        backgroundImagePath = imported.path;
      }

      await ref.read(playlistRepositoryProvider).updateCustomVibe(
            widget.playlistId,
            colors: _selectedColors,
            accentColor: _selectedAccentColor,
            backgroundImagePath: backgroundImagePath,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vibe personnalisée appliquée')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool hasExistingImage =
        !_clearImage && _pendingImagePath == null && widget.playlist.customBackgroundImagePath.isNotEmpty;
    final bool isCustomActive = widget.playlist.vibeStyle == VibePreset.custom;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isCustomActive ? BorderSide(color: _selectedAccentColor, width: 2) : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Personnaliser', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (isCustomActive) const Icon(Icons.check_circle, size: 20),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: LinearGradient(colors: _selectedColors),
                image: hasExistingImage || _pendingImagePath != null
                    ? DecorationImage(
                        image: _pendingImagePath != null
                            ? FileImage(File(_pendingImagePath!))
                            : FileImage(File(widget.playlist.customBackgroundImagePath)) as ImageProvider,
                        fit: BoxFit.cover,
                        opacity: 0.85,
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            Text('Couleurs du dégradé (2 max)', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _swatchChoices.map((color) {
                final bool selected = _selectedColors.contains(color);
                return GestureDetector(
                  onTap: () => _toggleColor(color),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? Theme.of(context).colorScheme.onSurface : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: selected
                        ? Icon(Icons.check, size: 16, color: color.computeLuminance() > 0.5 ? Colors.black : Colors.white)
                        : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            Text('Couleur d\'accentuation (boutons, contrôles)', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _swatchChoices.map((color) {
                final bool selected = color == _selectedAccentColor;
                return GestureDetector(
                  onTap: () => setState(() => _selectedAccentColor = color),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? Theme.of(context).colorScheme.onSurface : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: selected
                        ? Icon(Icons.check, size: 16, color: color.computeLuminance() > 0.5 ? Colors.black : Colors.white)
                        : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.image_outlined),
                  label: const Text('Image de fond'),
                ),
                if (hasExistingImage || _pendingImagePath != null) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Retirer l\'image',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() {
                      _pendingImagePath = null;
                      _clearImage = true;
                    }),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Appliquer la Vibe personnalisée'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

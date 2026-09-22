import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/storage/database/track_repository.dart';
import '../../../core/theme/design_system/app_spacing.dart';
import '../../../core/theme/global_theme/global_theme.dart';

/// Accessible depuis les 3 écrans principaux (Découverte, Lecteur, Espace).
/// Section "Apparence" (Design System) : mode clair/sombre/système et
/// couleur principale — voir global_theme.dart pour la persistance.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeMode themeMode = ref.watch(globalThemeModeProvider);
    final Color accentColor = ref.watch(userAccentColorProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Paramètres')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.m),
        children: [
          const _SectionTitle('Apparence'),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.m),
            child: Text('Thème'),
          ),
          const SizedBox(height: AppSpacing.s),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
            child: Wrap(
              spacing: AppSpacing.s,
              children: ThemeMode.values.map((mode) {
                return ChoiceChip(
                  label: Text(_themeModeLabel(mode)),
                  avatar: Icon(_themeModeIcon(mode), size: 18),
                  selected: themeMode == mode,
                  onSelected: (_) => ref.read(globalThemeModeProvider.notifier).setThemeMode(mode),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: AppSpacing.l),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.m),
            child: Text('Couleur principale'),
          ),
          const SizedBox(height: AppSpacing.s),
          SizedBox(
            height: 56,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
              scrollDirection: Axis.horizontal,
              itemCount: kAccentColorChoices.length,
              separatorBuilder: (context, index) => const SizedBox(width: AppSpacing.s),
              itemBuilder: (context, index) {
                final Color color = kAccentColorChoices[index];
                final bool selected = color.toARGB32() == accentColor.toARGB32();
                return GestureDetector(
                  onTap: () => ref.read(userAccentColorProvider.notifier).setAccentColor(color),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? Theme.of(context).colorScheme.onSurface : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: selected
                        ? Icon(Icons.check, color: color.computeLuminance() > 0.5 ? Colors.black : Colors.white)
                        : null,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.l),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.s),
          const _SectionTitle('Maintenance'),
          ListTile(
            leading: const Icon(Icons.people_outline),
            title: const Text('Fusion & renommage d\'artistes'),
            subtitle: const Text('Fusion automatique (doublons de casse) ou sélection manuelle'),
            onTap: () => _openArtistFusionDialog(context, ref),
          ),
          const Divider(height: 1),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('À propos'),
            subtitle: Text('Playlist App — lecteur local-first'),
          ),
        ],
      ),
    );
  }

  /// Bouton "Fusion & renommage d'artistes" (Section 4) — choix entre
  /// l'algorithme existant de fusion des doublons de casse
  /// ([TrackRepository.mergeDuplicateCaseArtists], déjà accessible depuis la
  /// Bibliothèque) et la sélection manuelle ([ManualArtistFusionScreen]).
  Future<void> _openArtistFusionDialog(BuildContext context, WidgetRef ref) async {
    final bool? manual = await showDialog<bool>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Fusion & renommage d\'artistes'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(false),
            child: const ListTile(
              leading: Icon(Icons.auto_fix_high_outlined),
              title: Text('Fusion automatique'),
              subtitle: Text('Regroupe les variantes de casse du même artiste'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(true),
            child: const ListTile(
              leading: Icon(Icons.checklist_outlined),
              title: Text('Fusion manuelle'),
              subtitle: Text('Sélectionner les artistes à fusionner ou renommer'),
            ),
          ),
        ],
      ),
    );
    if (manual == null) return;

    if (manual) {
      if (context.mounted) context.push('/settings/artist-fusion');
      return;
    }

    final int mergedGroups = await ref.read(trackRepositoryProvider).mergeDuplicateCaseArtists();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mergedGroups == 0 ? 'Aucun doublon de casse trouvé.' : '$mergedGroups artiste(s) fusionné(s).'),
      ),
    );
  }

  String _themeModeLabel(ThemeMode mode) => switch (mode) {
        ThemeMode.system => 'Système',
        ThemeMode.light => 'Clair',
        ThemeMode.dark => 'Sombre',
      };

  IconData _themeModeIcon(ThemeMode mode) => switch (mode) {
        ThemeMode.system => Icons.brightness_auto_outlined,
        ThemeMode.light => Icons.light_mode_outlined,
        ThemeMode.dark => Icons.dark_mode_outlined,
      };
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.m, 0, AppSpacing.m, AppSpacing.s),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/shared/widgets/add_to_playlist_sheet.dart';
import '../../../core/shared/widgets/online_track_card.dart';
import '../../../core/shared/widgets/playlist_card.dart';
import '../../../core/shared/widgets/skeleton_loader.dart';
import '../../../core/shared/widgets/track_actions_sheet.dart';
import '../../../core/storage/database/app_database.dart';
import '../../../core/theme/design_system/app_spacing.dart';
import '../../../core/theme/vibe_engine/active_vibe_provider.dart';
import '../../../core/theme/vibe_engine/vibe_engine.dart';
import '../../playlists/data/playlist_providers.dart';
import '../data/autocomplete_providers.dart';
import '../data/recommendation_providers.dart';
import '../data/search_providers.dart';
import '../domain/autocomplete_suggestion.dart';
import '../domain/search_result.dart';
import 'playlist_filter_sheet.dart';

/// Délai de debounce avant d'interroger l'autocomplétion — évite une requête
/// iTunes à chaque frappe.
const Duration _autocompleteDebounce = Duration(milliseconds: 300);

/// Tab 1 : recherche unifiée (locale d'abord, repli API publique si aucun
/// résultat local), autocomplétion dynamique pendant la frappe, ingestion de
/// liens Spotify, imports JSON, et — quand la recherche est vide — le tableau
/// de bord de suggestions (Étape 4) : artistes/titres recommandés localement
/// à partir des mots-clés déjà en base, sans aucune incidence sur la Vibe
/// (choix exclusivement manuel).
class DiscoveryScreen extends ConsumerStatefulWidget {
  const DiscoveryScreen({super.key});

  @override
  ConsumerState<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends ConsumerState<DiscoveryScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounceTimer;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    ref.read(liveQueryProvider.notifier).set(value);
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_autocompleteDebounce, () {
      ref.read(debouncedAutocompleteQueryProvider.notifier).set(value);
    });
  }

  /// Valide la recherche et referme l'autocomplétion — [text] permet à une
  /// suggestion tapée de remplir le champ puis soumettre en un seul geste.
  void _submit([String? text]) {
    final String value = text ?? _controller.text;
    if (text != null) {
      _controller.text = text;
      _controller.selection = TextSelection.collapsed(offset: text.length);
    }
    _debounceTimer?.cancel();
    ref.read(liveQueryProvider.notifier).set('');
    ref.read(debouncedAutocompleteQueryProvider.notifier).set('');
    ref.read(searchQueryProvider.notifier).set(value);
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<SearchResult>> results = ref.watch(searchResultsProvider);
    final String activeQuery = ref.watch(searchQueryProvider);
    final String liveQuery = ref.watch(liveQueryProvider);
    final bool showAutocomplete = activeQuery.isEmpty && liveQuery.trim().length >= 2;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.settings_outlined),
          tooltip: 'Paramètres',
          onPressed: () => context.push('/settings'),
        ),
        title: TextField(
          controller: _controller,
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            hintText: 'Titre, artiste, playlist...',
            border: InputBorder.none,
            suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: () => _submit()),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Importer (Spotify / JSON)',
            onPressed: () => context.push('/discovery/import'),
          ),
        ],
      ),
      body: showAutocomplete
          ? _AutocompletePanel(onSelect: _submit)
          : activeQuery.isEmpty
              ? const _SuggestionsPanel()
              : results.when(
                  data: (data) => data.isEmpty
                      ? const Center(child: Text('Aucun résultat.'))
                      : ListView.builder(
                          itemCount: data.length,
                          itemBuilder: (context, index) => _ResultTile(result: data[index]),
                        ),
                  loading: () => ListView(children: List.generate(6, (_) => const SkeletonLoader())),
                  error: (error, _) => Center(child: Text('Erreur de recherche : $error')),
                ),
    );
  }
}

/// Menu déroulant d'autocomplétion (Google/Spotify-style) : matchs locaux
/// d'abord, puis en ligne, puis un repli "Rechercher '...'" — stylisé selon
/// la Vibe active (fond semi-translucide, icônes teintées à l'accent).
/// [onSelect] remplit le champ ET soumet ; pour un artiste, on navigue
/// directement vers son profil à la place (fiche existante, plus utile
/// qu'un simple remplissage de champ).
class _AutocompletePanel extends ConsumerWidget {
  const _AutocompletePanel({required this.onSelect});

  final void Function(String text) onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<AutocompleteSuggestion>> suggestions = ref.watch(autocompleteSuggestionsProvider);
    final VibeVisual vibe = ref.watch(activeVibeProvider);

    return Container(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
      child: suggestions.when(
        data: (data) {
          if (data.isEmpty) return const SizedBox.shrink();

          // Ordre d'affichage strict imposé par la charte de recherche :
          // Artistes en haut, Titres en bas — déjà l'ordre renvoyé par
          // AutocompleteRepository.suggest, ce regroupement ajoute juste les
          // en-têtes de section (le reste, ex. "Rechercher '...'", suit tel quel).
          final List<AutocompleteSuggestion> artists = data.where((s) => s.kind == SuggestionKind.artist).toList();
          final List<AutocompleteSuggestion> tracks = data.where((s) => s.kind == SuggestionKind.track).toList();
          final List<AutocompleteSuggestion> rest =
              data.where((s) => s.kind != SuggestionKind.artist && s.kind != SuggestionKind.track).toList();

          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 4),
            children: [
              if (artists.isNotEmpty) _AutocompleteSectionHeader('Artistes'),
              for (final suggestion in artists)
                _AutocompleteTile(suggestion: suggestion, accentColor: vibe.accentColor, onSelect: onSelect),
              if (tracks.isNotEmpty) _AutocompleteSectionHeader('Titres'),
              for (final suggestion in tracks)
                _AutocompleteTile(suggestion: suggestion, accentColor: vibe.accentColor, onSelect: onSelect),
              for (final suggestion in rest)
                _AutocompleteTile(suggestion: suggestion, accentColor: vibe.accentColor, onSelect: onSelect),
            ],
          );
        },
        loading: () => Padding(
          padding: const EdgeInsets.all(16),
          child: LinearProgressIndicator(color: vibe.accentColor),
        ),
        error: (error, _) => const SizedBox.shrink(),
      ),
    );
  }
}

class _AutocompleteSectionHeader extends StatelessWidget {
  const _AutocompleteSectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.6,
            ),
      ),
    );
  }
}

class _AutocompleteTile extends StatelessWidget {
  const _AutocompleteTile({required this.suggestion, required this.accentColor, required this.onSelect});

  final AutocompleteSuggestion suggestion;
  final Color accentColor;
  final void Function(String text) onSelect;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: suggestion.artworkUrl != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(
                suggestion.artworkUrl!,
                width: 40,
                height: 40,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Icon(_iconFor(suggestion.kind), color: accentColor),
              ),
            )
          : Icon(_iconFor(suggestion.kind), color: accentColor),
      title: Text(suggestion.label, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: suggestion.subtitle == null ? null : Text(suggestion.subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: suggestion.kind == SuggestionKind.artist ? const Icon(Icons.chevron_right, size: 18) : null,
      onTap: () {
        if (suggestion.kind == SuggestionKind.artist) {
          context.push('/discovery/artist/${suggestion.label}');
        } else {
          onSelect(suggestion.label);
        }
      },
    );
  }

  IconData _iconFor(SuggestionKind kind) => switch (kind) {
        SuggestionKind.track => Icons.music_note,
        SuggestionKind.artist => Icons.person_outline,
        SuggestionKind.album => Icons.album_outlined,
        SuggestionKind.query => Icons.search,
      };
}

/// Tableau de bord affiché quand la recherche est vide (wireframe) :
/// suggestions d'artistes (bibliothèque entière) et de titres (playlist
/// cible), plus les deux filtres "Playlist" et "Local / Banque de données".
class _SuggestionsPanel extends ConsumerWidget {
  const _SuggestionsPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<SearchResult>> artistSuggestions = ref.watch(artistSuggestionsProvider);
    final AsyncValue<List<SearchResult>> trackSuggestions = ref.watch(trackSuggestionsProvider);
    final String? selectedPlaylistId = ref.watch(suggestionPlaylistIdProvider);
    final bool useOnlineSource = ref.watch(suggestionSourceProvider);
    final AsyncValue<List<Playlist>> playlists = ref.watch(playlistsProvider);

    final AsyncValue<Playlist?> selectedPlaylist =
        selectedPlaylistId == null ? const AsyncValue.data(null) : ref.watch(playlistByIdProvider(selectedPlaylistId));

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [
        playlists.maybeWhen(
          data: (data) => data.isEmpty
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text('Tes playlists', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                      const SizedBox(height: AppSpacing.s),
                      SizedBox(
                        height: 208,
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          scrollDirection: Axis.horizontal,
                          itemCount: data.length,
                          separatorBuilder: (context, index) => const SizedBox(width: AppSpacing.m),
                          itemBuilder: (context, index) => PlaylistCard(
                            playlist: data[index],
                            onTap: () => context.push('/space/playlist/${data[index].id}/edit'),
                            onImageTap: () => playPlaylistAndNavigate(context, ref, data[index]),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
          orElse: () => const SizedBox.shrink(),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _SuggestionCard(
            title: "Suggestion d'artistes",
            subtitle: 'D\'après les mots-clés les plus récurrents de toute ta bibliothèque',
            child: artistSuggestions.when(
              data: (data) => data.isEmpty
                  ? const Text(
                      'Pas encore assez de mots-clés — enrichis ta bibliothèque depuis Mon espace > Bibliothèque.',
                    )
                  : SizedBox(
                      height: 96,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: data.length,
                        separatorBuilder: (context, index) => const SizedBox(width: AppSpacing.s),
                        itemBuilder: (context, index) => _ArtistSuggestionCard(result: data[index]),
                      ),
                    ),
              loading: () => const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: LinearProgressIndicator()),
              error: (error, _) => Text('Erreur : $error'),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _SuggestionCard(
            title: 'Suggestion de titres',
            subtitle: selectedPlaylist.value == null
                ? 'Choisis une playlist cible avec le filtre "Playlist" ci-dessous'
                : 'D\'après les mots-clés des morceaux de "${selectedPlaylist.value!.title}"',
            child: selectedPlaylistId == null
                ? const Text('Aucune playlist sélectionnée.')
                : trackSuggestions.when(
                    data: (data) => data.isEmpty
                        ? const Text('Aucune suggestion pour cette playlist.')
                        : Column(children: data.map((r) => _ResultTile(result: r)).toList()),
                    loading: () =>
                        const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: LinearProgressIndicator()),
                    error: (error, _) => Text('Erreur : $error'),
                  ),
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.queue_music),
                  label: Text(
                    selectedPlaylist.value?.title ?? 'Playlist',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onPressed: () => PlaylistFilterSheet.show(context),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: Icon(useOnlineSource ? Icons.cloud_outlined : Icons.smartphone_outlined),
                  label: Text(useOnlineSource ? 'Banque de données' : 'Local'),
                  onPressed: () => ref.read(suggestionSourceProvider.notifier).toggle(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Carte compacte d'un artiste suggéré (carrousel horizontal, Design System)
/// — avatar circulaire + nom, tap direct vers la fiche artiste.
class _ArtistSuggestionCard extends StatelessWidget {
  const _ArtistSuggestionCard({required this.result});

  final SearchResult result;

  @override
  Widget build(BuildContext context) {
    final String name = switch (result) {
      ArtistSearchResult(:final artistName) => artistName,
      TrackSearchResult(:final track) => track.artists.isNotEmpty ? track.artists.first : track.title,
      PlaylistSearchResult(:final playlist) => playlist.title,
      OnlineTrackSearchResult(:final track) => track.artist,
    };

    return SizedBox(
      width: 76,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/discovery/artist/$name'),
        child: Column(
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Icon(Icons.person_outline),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({required this.title, required this.subtitle, required this.child});

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.result});

  final SearchResult result;

  @override
  Widget build(BuildContext context) {
    return switch (result) {
      TrackSearchResult(:final track) => ListTile(
          leading: const Icon(Icons.music_note),
          title: Text(track.title),
          subtitle: Text(track.artists.join(', ')),
          trailing: IconButton(
            icon: const Icon(Icons.playlist_add),
            tooltip: 'Ajouter à une playlist',
            onPressed: () => AddToPlaylistSheet.show(context, track.id),
          ),
          onLongPress: () => TrackActionsSheet.show(context, track),
        ),
      PlaylistSearchResult(:final playlist) => ListTile(
          leading: const Icon(Icons.queue_music),
          title: Text(playlist.title),
        ),
      ArtistSearchResult(:final artistName) => ListTile(
          leading: const Icon(Icons.person_outline),
          title: Text(artistName),
          onTap: () => context.push('/discovery/artist/$artistName'),
        ),
      OnlineTrackSearchResult(:final track) => OnlineTrackCard(track: track),
    };
  }
}

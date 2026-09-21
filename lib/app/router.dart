import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/discovery/presentation/artist_profile_screen.dart';
import '../features/discovery/presentation/discovery_screen.dart';
import '../features/discovery/presentation/import_screen.dart';
import '../features/library/presentation/duplicate_tracks_screen.dart';
import '../features/library/presentation/library_screen.dart';
import '../features/library/presentation/orphan_cleanup_screen.dart';
import '../features/onboarding/presentation/onboarding_screen.dart';
import '../features/player/presentation/master_player_screen.dart';
import '../features/playlists/presentation/editor/playlist_editor_screen.dart';
import '../features/playlists/presentation/personal_space_screen.dart';
import '../features/playlists/presentation/vibe_customizer/vibe_customizer_screen.dart';
import '../features/settings/presentation/settings_screen.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/player',
  routes: [
    GoRoute(path: '/onboarding', builder: (context, state) => const OnboardingScreen()),
    GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) => _TabShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [GoRoute(path: '/discovery', builder: (context, state) => const DiscoveryScreen())],
        ),
        StatefulShellBranch(
          routes: [GoRoute(path: '/player', builder: (context, state) => const MasterPlayerScreen())],
        ),
        StatefulShellBranch(
          routes: [GoRoute(path: '/space', builder: (context, state) => const PersonalSpaceScreen())],
        ),
      ],
    ),
    GoRoute(
      path: '/discovery/artist/:artistName',
      builder: (context, state) => ArtistProfileScreen(artistName: state.pathParameters['artistName']!),
    ),
    GoRoute(path: '/discovery/import', builder: (context, state) => const ImportScreen()),
    GoRoute(
      path: '/space/playlist/:playlistId/edit',
      builder: (context, state) => PlaylistEditorScreen(playlistId: state.pathParameters['playlistId']!),
    ),
    GoRoute(
      path: '/space/playlist/:playlistId/vibe',
      builder: (context, state) => VibeCustomizerScreen(playlistId: state.pathParameters['playlistId']!),
    ),
    GoRoute(path: '/space/cleanup', builder: (context, state) => const OrphanCleanupScreen()),
    GoRoute(path: '/space/library', builder: (context, state) => const LibraryScreen()),
    GoRoute(path: '/space/library/duplicates', builder: (context, state) => const DuplicateTracksScreen()),
  ],
);

class _TabShell extends StatelessWidget {
  const _TabShell({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: navigationShell.goBranch,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: 'Découverte',
          ),
          NavigationDestination(
            icon: Icon(Icons.play_circle_outline),
            selectedIcon: Icon(Icons.play_circle),
            label: 'Lecteur',
          ),
          NavigationDestination(
            icon: Icon(Icons.library_music_outlined),
            selectedIcon: Icon(Icons.library_music),
            label: 'Espace',
          ),
        ],
      ),
    );
  }
}

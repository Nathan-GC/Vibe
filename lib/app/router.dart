import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/audio_engine/player_immersive_mode_provider.dart';
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
import '../features/settings/presentation/artist_fusion_screen.dart';
import '../features/settings/presentation/settings_screen.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/player',
  routes: [
    GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen()),
    GoRoute(
        path: '/settings', builder: (context, state) => const SettingsScreen()),
    GoRoute(
        path: '/settings/artist-fusion',
        builder: (context, state) => const ManualArtistFusionScreen()),
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          _TabShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
                path: '/discovery',
                builder: (context, state) => const DiscoveryScreen())
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
                path: '/player',
                builder: (context, state) => const MasterPlayerScreen())
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
                path: '/space',
                builder: (context, state) => const PersonalSpaceScreen())
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/discovery/artist/:artistName',
      builder: (context, state) =>
          ArtistProfileScreen(artistName: state.pathParameters['artistName']!),
    ),
    GoRoute(
        path: '/discovery/import',
        builder: (context, state) => const ImportScreen()),
    GoRoute(
      path: '/space/playlist/:playlistId/edit',
      builder: (context, state) =>
          PlaylistEditorScreen(playlistId: state.pathParameters['playlistId']!),
    ),
    GoRoute(
      path: '/space/playlist/:playlistId/vibe',
      builder: (context, state) =>
          VibeCustomizerScreen(playlistId: state.pathParameters['playlistId']!),
    ),
    GoRoute(
        path: '/space/cleanup',
        builder: (context, state) => const OrphanCleanupScreen()),
    GoRoute(
        path: '/space/library',
        builder: (context, state) => const LibraryScreen()),
    GoRoute(
        path: '/space/library/duplicates',
        builder: (context, state) => const DuplicateTracksScreen()),
  ],
);

/// Hiérarchie du bouton Retour Android au niveau de la coque de navigation
/// (Ergonomie & Navigation Android, 2.B) : les pages de détail/modales sont
/// des `GoRoute` sœurs poussées sur le Navigator racine au-dessus de ce Shell
/// (voir `/discovery/artist/:artistName`, `/space/playlist/:id/edit`, etc.),
/// donc le pop par défaut de Flutter les referme déjà avant que ce `PopScope`
/// ne soit jamais atteint (2.B.1). Ce qui reste à gérer ici : depuis
/// Découverte/Espace, Retour bascule vers l'onglet Lecteur plutôt que de
/// quitter l'app (2.B.2) ; depuis Lecteur, Retour réduit d'abord le mode
/// immersif du Master Player avant d'autoriser la sortie (2.B.3).
///
/// `canPop` reste TOUJOURS `false` ici, y compris à la racine de l'onglet
/// Lecteur où la sortie de l'app est censée être autorisée : `canPop: true`
/// délègue au pop par défaut de Flutter, qui — vérifié empiriquement sur
/// émulateur (Android "predictive back") — ne fait alors STRICTEMENT RIEN
/// puisqu'il n'y a plus rien à dépiler sur ce Navigator racine (l'app reste
/// bloquée au premier plan, un bouton Retour qui ne répond plus). Appeler
/// explicitement [SystemNavigator.pop] dans ce cas précis est la seule
/// façon fiable de vraiment quitter l'app.
/// Persistance des 3 onglets (Robustesse Système, Section 3) :
/// `StatefulShellRoute.indexedStack` (voir plus haut) construit déjà en
/// interne un `IndexedStack` sur les Navigators de chaque branche — les 3
/// onglets restent donc mounted en permanence, jamais détruits/reconstruits
/// à la bascule, `navigationShell` ci-dessous n'a donc pas besoin d'un
/// `IndexedStack` explicite supplémentaire. Le crash `_dependents.isEmpty`
/// observé en QA lors de bascules rapides d'onglets ne venait pas d'ici :
/// root-cause identifiée dans `MasterPlayerScreen` (voir `_pageViewKey`,
/// `master_player_screen.dart`) — le PageView Player/Queue était recréé à
/// chaque bascule du fond Vibe entre vidéo et fluide, pas par ce Shell.
class _TabShell extends ConsumerWidget {
  const _TabShell({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const int _playerTabIndex = 1;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool isImmersive = ref.watch(playerImmersiveModeProvider);
    final bool onPlayerTab = navigationShell.currentIndex == _playerTabIndex;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        if (!onPlayerTab) {
          navigationShell.goBranch(_playerTabIndex);
          return;
        }
        if (isImmersive) {
          ref.read(playerImmersiveModeProvider.notifier).set(false);
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
          return;
        }
        SystemNavigator.pop();
      },
      child: Scaffold(
        body: navigationShell,
        bottomNavigationBar: SafeArea(
          bottom: true,
          child: NavigationBar(
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
        ),
      ),
    );
  }
}

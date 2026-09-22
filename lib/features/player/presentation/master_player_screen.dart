import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/animation/tempo_sync/tempo_sync_controller.dart';
import '../../../core/audio_engine/player_controller.dart';
import '../../../core/audio_engine/player_immersive_mode_provider.dart';
import '../../../core/shared/widgets/add_to_playlist_sheet.dart';
import '../../../core/storage/database/app_database.dart';
import '../../../core/theme/vibe_engine/animated_vibe_theme.dart';
import '../../../core/theme/vibe_engine/playlist_vibe_resolver.dart';
import '../../../core/theme/vibe_engine/vibe_engine.dart';
import '../../../core/theme/vibe_engine/vibe_haptic_service.dart';
import '../../playlists/data/playlist_providers.dart';
import '../widgets/album_art_reactive.dart';
import '../widgets/fluid_background.dart';
import '../widgets/like_button.dart';
import '../widgets/progress_slider.dart';
import '../widgets/vibe_video_background.dart';
import 'queue_screen.dart';

/// Tab 2 : swipe horizontal Page 1 (Player) / Page 2 (Queue, voir queue_screen.dart).
class MasterPlayerScreen extends ConsumerStatefulWidget {
  const MasterPlayerScreen({super.key});

  @override
  ConsumerState<MasterPlayerScreen> createState() => _MasterPlayerScreenState();
}

class _MasterPlayerScreenState extends ConsumerState<MasterPlayerScreen>
    with SingleTickerProviderStateMixin {
  late final TempoSyncController _tempoController =
      TempoSyncController(vsync: this);

  // Clé stable pour le PageView (Player + Queue) : sans elle, chaque bascule
  // du fond entre `VibeVideoBackground` et `FluidBackground` (types de widget
  // différents) fait recréer tout le sous-arbre `child`, y compris ce
  // PageView et son état de scroll interne — Flutter détruit puis reconstruit
  // au lieu de réutiliser l'élément. Avec un `GlobalKey`, l'élément est
  // déplacé (réutilisé) sous le nouveau parent plutôt que détruit. Cause
  // racine probable du crash `_dependents.isEmpty` observé en QA (Tests
  // Robustesse Système, Section 3) lors de bascules rapides d'onglets : la
  // Vibe peut encore être en transition (800ms, voir AnimatedVibeTheme)
  // pendant qu'on quitte puis revient sur l'onglet Lecteur, et la
  // destruction/reconstruction du PageView en plein vol laissait des
  // `InheritedElement` internes (Scrollable/PrimaryScrollController) avec des
  // dépendants non nettoyés.
  final GlobalKey _pageViewKey = GlobalKey();

  @override
  void dispose() {
    _tempoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final PlayerSnapshot player = ref.watch(playerControllerProvider);
    final bool isPlaying = player.status == PlaybackStatus.playing;

    // Retour haptique synesthésique (Vibe Engine) sur changement de piste —
    // ici plutôt que dans PlayerController : le style dépend de la Vibe
    // active, une préoccupation d'UI, pas du moteur de lecture lui-même.
    ref.listen<PlayerSnapshot>(playerControllerProvider, (previous, next) {
      final String? previousId = previous?.currentTrack?.id;
      final String? nextId = next.currentTrack?.id;
      if (nextId != null && nextId != previousId) {
        VibeHapticService.trigger(context, VibeInteraction.trackChange);
      }
    });

    _tempoController.updateBpm((player.currentTrack?.bpm ?? 120).toDouble());
    isPlaying ? _tempoController.start() : _tempoController.stop();

    final String? playlistId = player.currentPlaylistId;
    final AsyncValue<Playlist?> playlist = playlistId == null
        ? const AsyncValue.data(null)
        : ref.watch(playlistByIdProvider(playlistId));
    final VibeVisual vibe = playlist.value?.resolvedVibe ??
        const VibeVisual(
            gradientColors: [Color(0xFFF5F5F5), Color(0xFFE0E0E0)],
            accentColor: Colors.black87);

    final Track? track = player.currentTrack;
    final String? playlistCoverImagePath = playlist.value?.coverImagePath;
    // Section 3.2 : même repli pochette->playlist que MasterPlayerScreen
    // utilise déjà pour AlbumArtReactive, réutilisé ici pour l'extraction de
    // palette (FluidBackground) — un morceau sans pochette dédiée profite
    // quand même des couleurs de la playlist plutôt que du dégradé statique.
    final String? effectiveCoverArtPath =
        (track?.coverArtPath.isNotEmpty ?? false)
            ? track!.coverArtPath
            : ((playlistCoverImagePath?.isNotEmpty ?? false)
                ? playlistCoverImagePath
                : null);

    return Scaffold(
      // Transitions fluides de Vibe (800ms, easeInOutCubic) : tout ce qui
      // dépend de la Vibe reçoit la valeur interpolée, jamais `vibe` brute —
      // voir AnimatedVibeTheme.
      body: AnimatedVibeTheme(
        vibe: vibe,
        builder: (context, animatedVibe, child) {
          // Section 4.1 : le fond (FluidBackground ou vidéo) englobe désormais
          // tout le PageView (Player + Queue) plutôt que la seule page 1 — la
          // Vibe reste donc visible et animée pendant le swipe vers la Queue
          // au lieu de disparaître derrière un fond vide.
          final Widget pageView = PageView(
            key: _pageViewKey,
            children: [
              _PlayerPage(
                tempoController: _tempoController,
                vibe: animatedVibe,
                player: player,
                playlistCoverImagePath: playlistCoverImagePath,
              ),
              const QueueScreen(),
            ],
          );

          // Section 4.3 : une vidéo de fond personnalisée remplace
          // entièrement le shader/dégradé/effet — jamais superposée.
          final String? videoPath = animatedVibe.customBackgroundVideoPath;
          if (videoPath != null) {
            return VibeVideoBackground(videoPath: videoPath, child: pageView);
          }

          return FluidBackground(
            tempoController: _tempoController,
            vibe: animatedVibe,
            coverArtPath: effectiveCoverArtPath,
            child: _VibeBackgroundImageLayer(
                backgroundImagePath: animatedVibe.backgroundImagePath,
                child: pageView),
          );
        },
      ),
    );
  }
}

/// Image de fond personnalisée (Vibe Creator, `VibePreset.custom`) posée
/// sous [child] en semi-transparence — extrait de l'ancien corps de
/// `_PlayerPage` pour s'appliquer à tout le PageView (voir Section 4.1)
/// plutôt qu'à sa seule page 1.
class _VibeBackgroundImageLayer extends StatelessWidget {
  const _VibeBackgroundImageLayer(
      {required this.backgroundImagePath, required this.child});

  final String? backgroundImagePath;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final String? path = backgroundImagePath;
    if (path == null) return child;
    return Stack(
      fit: StackFit.expand,
      children: [
        Opacity(
          opacity: 0.35,
          // `errorBuilder` : même garde que PlaylistCoverImage/AlbumArtReactive
          // — un chemin d'image de fond personnalisée supprimé/déplacé/corrompu
          // hors de l'app ne doit pas casser tout l'écran (bug réel reproduit :
          // `Image.file` sans errorBuilder fait planter le rendu du Viewport
          // parent avec "RenderViewport expected a child of type RenderSliver
          // but received a child of type RenderErrorBox").
          child: Image.file(
            File(path),
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
          ),
        ),
        child,
      ],
    );
  }
}

class _PlayerPage extends ConsumerStatefulWidget {
  const _PlayerPage(
      {required this.tempoController,
      required this.vibe,
      required this.player,
      this.playlistCoverImagePath});

  final TempoSyncController tempoController;
  final VibeVisual vibe;
  final PlayerSnapshot player;
  // Section 3.2 : pochette de repli quand le morceau en cours n'a pas de
  // pochette dédiée (`coverArtPath` vide) — celle de la playlist en cours de
  // lecture plutôt que l'icône générique d'AlbumArtReactive.
  final String? playlistCoverImagePath;

  @override
  ConsumerState<_PlayerPage> createState() => _PlayerPageState();
}

/// Mode Canvas immersif (Vibe Engine) : appui long sur la pochette, ou 15s
/// d'inactivité, masque les contrôles pour une écoute épurée façon
/// cadre/station — un tap n'importe où les ramène instantanément. L'état
/// vit dans [playerImmersiveModeProvider] (pas un simple `bool` local) pour
/// que la coque de navigation (`_TabShell`, router.dart) puisse le lire et
/// le forcer à `false` depuis le bouton Retour Android (Section 2.B).
class _PlayerPageState extends ConsumerState<_PlayerPage>
    with SingleTickerProviderStateMixin {
  static const Duration _inactivityDelay = Duration(seconds: 15);
  static const Duration _fadeDuration = Duration(milliseconds: 1500);

  Timer? _inactivityTimer;

  late final AnimationController _floatController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  )..repeat(reverse: true);
  late final Animation<double> _floatAnimation =
      CurvedAnimation(parent: _floatController, curve: Curves.easeInOut);

  @override
  void initState() {
    super.initState();
    _scheduleInactivity();
  }

  @override
  void didUpdateWidget(covariant _PlayerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Un morceau qui change repart sur une interface visible plutôt que de
    // rester immersif sur les infos d'un morceau différent.
    if (oldWidget.player.currentTrack?.id != widget.player.currentTrack?.id) {
      _exitImmersive();
    }
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    _floatController.dispose();
    super.dispose();
  }

  void _scheduleInactivity() {
    _inactivityTimer?.cancel();
    if (widget.player.currentTrack == null) return;
    _inactivityTimer = Timer(_inactivityDelay, _enterImmersive);
  }

  void _enterImmersive() {
    if (!mounted ||
        ref.read(playerImmersiveModeProvider) ||
        widget.player.currentTrack == null) {
      return;
    }
    ref.read(playerImmersiveModeProvider.notifier).set(true);
    // Ergonomie navigation Android (2.A) : masque aussi la barre système
    // (statut + navigation), pas seulement les contrôles in-app — restauré
    // dans le `ref.listen` du `build()` ci-dessous, seul point qui sait que
    // le mode immersif vient de se terminer, qu'il ait été quitté depuis
    // l'intérieur (tap) ou depuis l'extérieur (bouton Retour, `_TabShell`).
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _exitImmersive() {
    _inactivityTimer?.cancel();
    if (ref.read(playerImmersiveModeProvider) && mounted) {
      ref.read(playerImmersiveModeProvider.notifier).set(false);
    }
    _scheduleInactivity();
  }

  void _onAnyInteraction() {
    if (!ref.read(playerImmersiveModeProvider)) _scheduleInactivity();
  }

  @override
  Widget build(BuildContext context) {
    final bool immersive = ref.watch(playerImmersiveModeProvider);
    // Restaure la barre système (statut + navigation) dès que le mode
    // immersif se termine, qu'il ait été quitté depuis l'intérieur (tap,
    // voir _exitImmersive) ou depuis l'extérieur (bouton Retour Android,
    // voir _TabShell dans router.dart) — un seul point de restauration
    // plutôt que de dupliquer l'appel SystemChrome à chaque appelant.
    ref.listen<bool>(playerImmersiveModeProvider, (previous, next) {
      if (previous == true && next == false) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        _scheduleInactivity();
      }
    });

    final Track? track = widget.player.currentTrack;
    final bool isPlaying = widget.player.status == PlaybackStatus.playing;
    final VibeVisual vibe = widget.vibe;
    // Section 3.2 : repli sur la pochette de la playlist en cours quand le
    // morceau n'en a pas de dédiée — les deux champs partagent la même
    // convention "vide = absente" (voir Tracks.coverArtPath, Playlists.
    // coverImagePath), jamais `null` directement en base.
    final String? albumArtPath = (track?.coverArtPath.isNotEmpty ?? false)
        ? track!.coverArtPath
        : ((widget.playlistCoverImagePath?.isNotEmpty ?? false)
            ? widget.playlistCoverImagePath
            : null);

    final Widget albumArt = AnimatedBuilder(
      animation: _floatAnimation,
      builder: (context, child) {
        final double floatOffset =
            immersive ? (_floatAnimation.value - 0.5) * 16 : 0;
        return Transform.translate(
            offset: Offset(0, floatOffset), child: child);
      },
      child: AnimatedScale(
        scale: immersive ? 1.12 : 1.0,
        duration: _fadeDuration,
        curve: Curves.easeInOut,
        child: GestureDetector(
          onLongPress: _enterImmersive,
          child:
              AlbumArtReactive(imagePath: albumArtPath, isPlaying: isPlaying),
        ),
      ),
    );

    final Widget content = SafeArea(
      child: Listener(
        onPointerDown: (_) => _onAnyInteraction(),
        behavior: HitTestBehavior.translucent,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(24),
              // `ConstrainedBox(minHeight:)` + `SingleChildScrollView` plutôt
              // qu'un simple Column centré : sur un écran bas (petit téléphone,
              // barre de progression + actions ajoutées) le contenu peut
              // dépasser la hauteur disponible — il scrolle alors au lieu de
              // déborder, tout en restant centré quand il tient dans l'écran.
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    physics:
                        immersive ? const NeverScrollableScrollPhysics() : null,
                    child: ConstrainedBox(
                      constraints:
                          BoxConstraints(minHeight: constraints.maxHeight),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          albumArt,
                          const SizedBox(height: 24),
                          AnimatedOpacity(
                            opacity: immersive ? 0 : 1,
                            duration: _fadeDuration,
                            curve: Curves.easeInOut,
                            child: IgnorePointer(
                              ignoring: immersive,
                              child: Column(
                                children: [
                                  Text(
                                    track?.title ?? 'Aucune lecture',
                                    style:
                                        Theme.of(context).textTheme.titleLarge,
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    track?.artists.join(', ') ?? '',
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
                                  ),
                                  const SizedBox(height: 16),
                                  ProgressSlider(
                                    fallbackDuration:
                                        track?.effectivePlaybackDuration ??
                                            Duration.zero,
                                    color: vibe.accentColor,
                                  ),
                                  const SizedBox(height: 8),
                                  _PlaybackControls(
                                      vibe: vibe, isPlaying: isPlaying),
                                  const SizedBox(height: 8),
                                  if (track != null)
                                    _TrackActions(
                                        trackId: track.id, vibe: vibe),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: AnimatedOpacity(
                opacity: immersive ? 0 : 1,
                duration: _fadeDuration,
                curve: Curves.easeInOut,
                child: IgnorePointer(
                  ignoring: immersive,
                  child: _OverlayIconButton(
                    icon: Icons.settings_outlined,
                    color: vibe.accentColor,
                    tooltip: 'Paramètres',
                    onPressed: () => context.push('/settings'),
                  ),
                ),
              ),
            ),
            // Titre/artiste/année minimalistes du mode Canvas — seulement
            // visibles (et interactifs) en immersion.
            Positioned(
              left: 0,
              right: 0,
              bottom: 32,
              child: IgnorePointer(
                ignoring: !immersive,
                child: AnimatedOpacity(
                  opacity: immersive ? 1 : 0,
                  duration: _fadeDuration,
                  curve: Curves.easeInOut,
                  child: _ImmersiveCaption(
                      track: track, accentColor: vibe.accentColor),
                ),
              ),
            ),
            if (immersive)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _exitImmersive,
                ),
              ),
          ],
        ),
      ),
    );

    // FluidBackground/l'image de fond personnalisée sont posés au niveau de
    // MasterPlayerScreen (Section 4.1), pas ici : cette page ne fait plus que
    // son propre contenu, affiché par-dessus le fond partagé avec la Queue.
    return content;
  }
}

/// Titre/artiste/année en bas d'écran, seul repère laissé visible en mode
/// Canvas immersif.
class _ImmersiveCaption extends StatelessWidget {
  const _ImmersiveCaption({required this.track, required this.accentColor});

  final Track? track;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    if (track == null) return const SizedBox.shrink();

    final String subtitle = [
      track!.artists.join(', '),
      if (track!.releaseYear > 0) '${track!.releaseYear}',
    ].join(' · ');

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          track!.title,
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(color: accentColor, letterSpacing: 0.5),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: accentColor.withValues(alpha: 0.8)),
        ),
      ],
    );
  }
}

/// Bouton en overlay translucide : garde l'écran immersif lisible sur un
/// preset sombre (OLED) comme sur un dégradé clair (Minimal), sans AppBar.
class _OverlayIconButton extends StatelessWidget {
  const _OverlayIconButton(
      {required this.icon,
      required this.color,
      required this.tooltip,
      required this.onPressed});

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.25),
      shape: const CircleBorder(),
      child: IconButton(
          icon: Icon(icon, color: color),
          tooltip: tooltip,
          onPressed: onPressed),
    );
  }
}

class _PlaybackControls extends ConsumerWidget {
  const _PlaybackControls({required this.vibe, required this.isPlaying});

  final VibeVisual vibe;
  final bool isPlaying;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PlayerController controller =
        ref.read(playerControllerProvider.notifier);
    final PlayerRepeatMode repeatMode =
        ref.watch(playerControllerProvider.select((s) => s.repeatMode));

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _RepeatModeButton(
            mode: repeatMode,
            color: vibe.accentColor,
            onPressed: controller.cycleRepeatMode),
        IconButton(
          iconSize: 36,
          color: vibe.accentColor,
          icon: const Icon(Icons.skip_previous),
          onPressed: controller.previous,
        ),
        IconButton(
          iconSize: 64,
          color: vibe.accentColor,
          icon: Icon(
              isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled),
          onPressed: controller.togglePlayPause,
        ),
        IconButton(
          iconSize: 36,
          color: vibe.accentColor,
          icon: const Icon(Icons.skip_next),
          onPressed: controller.next,
        ),
        // Espace muet de la même largeur que le bouton de mode — garde les
        // boutons précédent/lecture/suivant centrés plutôt que décalés vers
        // la droite par le bouton de mode isolé à gauche.
        const SizedBox(width: 36),
      ],
    );
  }
}

/// Bouton unique cyclant les 3 modes de lecture (Feuille de route pt.2) :
/// ordre de la playlist -> aléatoire -> répétition du titre.
class _RepeatModeButton extends StatelessWidget {
  const _RepeatModeButton(
      {required this.mode, required this.color, required this.onPressed});

  final PlayerRepeatMode mode;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, String tooltip) = switch (mode) {
      PlayerRepeatMode.playlistOrder => (
          Icons.repeat,
          'Ordre de la playlist — appuyer pour activer l\'aléatoire'
        ),
      PlayerRepeatMode.shuffle => (
          Icons.shuffle,
          'Lecture aléatoire — appuyer pour répéter le titre'
        ),
      PlayerRepeatMode.repeatOne => (
          Icons.repeat_one,
          'Répétition du titre — appuyer pour revenir à l\'ordre normal'
        ),
    };
    // Mode "ordre de la playlist" = repli neutre, atténué ; les deux modes
    // actifs (aléatoire/répétition) restent pleinement colorés pour rester
    // visibles d'un coup d'œil.
    final bool isActiveMode = mode != PlayerRepeatMode.playlistOrder;

    return IconButton(
      iconSize: 22,
      color: isActiveMode ? color : color.withValues(alpha: 0.5),
      icon: Icon(icon),
      tooltip: tooltip,
      onPressed: onPressed,
    );
  }
}

/// "J'aime" + "Ajouter à une playlist" (Étape 3) — couleurs alignées sur la
/// Vibe active, comme le reste des contrôles.
class _TrackActions extends StatelessWidget {
  const _TrackActions({required this.trackId, required this.vibe});

  final String trackId;
  final VibeVisual vibe;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        LikeButton(trackId: trackId, color: vibe.accentColor),
        const SizedBox(width: 16),
        IconButton(
          iconSize: 28,
          icon: Icon(Icons.playlist_add, color: vibe.accentColor),
          tooltip: 'Ajouter à une playlist',
          onPressed: () => AddToPlaylistSheet.show(context, trackId),
        ),
      ],
    );
  }
}

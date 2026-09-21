import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio_engine/player_controller.dart';
import '../../storage/database/app_database.dart';
import '../../../features/playlists/data/playlist_providers.dart';
import '../global_theme/global_theme.dart';
import 'playlist_vibe_resolver.dart';
import 'vibe_engine.dart';

/// Vibe active de l'app ENTIÈRE (pas seulement le Player) : celle de la
/// playlist en cours de lecture, sinon un repli sur la couleur principale
/// choisie par l'utilisateur (Réglages — voir `userAccentColorProvider`),
/// jamais une teinte fixe qui écraserait silencieusement ce choix. Consommée
/// par `applyVibe` (global_theme.dart) pour reteinter le thème Material —
/// fond, cartes, barre de navigation — sur les 3 tabs. Le fond Fluid du
/// Player reste une couche additionnelle, plus élaborée, propre à cet écran.
final Provider<VibeVisual> activeVibeProvider = Provider<VibeVisual>((ref) {
  final Color userAccent = ref.watch(userAccentColorProvider);
  final VibeVisual defaultVibe = VibeVisual(
    gradientColors: [Color.alphaBlend(userAccent.withValues(alpha: 0.12), const Color(0xFFF5F5F5)), const Color(0xFFE0E0E0)],
    accentColor: userAccent,
  );

  final PlayerSnapshot player = ref.watch(playerControllerProvider);
  final String? playlistId = player.currentPlaylistId;
  if (playlistId == null) return defaultVibe;

  final AsyncValue<Playlist?> playlist = ref.watch(playlistByIdProvider(playlistId));
  return playlist.value?.resolvedVibe ?? defaultVibe;
});

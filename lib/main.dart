import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';
import 'core/audio_engine/playlist_audio_handler.dart';
import 'core/networking/dev_http_overrides.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kDebugMode) {
    HttpOverrides.global = DevHttpOverrides();
  }

  // Un seul conteneur, partagé entre le handler audio_service (créé ici, hors
  // de l'arbre de widgets) et le reste de l'app (voir UncontrolledProviderScope
  // ci-dessous) — le handler pilote ainsi le même PlayerController que l'UI,
  // sans second moteur `just_audio` ni duplication de la logique de Queue.
  final ProviderContainer container = ProviderContainer();

  await bootstrap();

  // Notification média persistante (lecture en fond, écran verrouillé) —
  // Attention, `notificationColor` est fixé une fois pour toutes ici : l'API
  // Android ne permet pas de la reteindre dynamiquement selon la Vibe active
  // en cours de lecture (voir PlaylistAudioHandler).
  await AudioService.init(
    builder: () => PlaylistAudioHandler(container),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.example.playlist_app.channel.audio',
      androidNotificationChannelName: 'Lecture audio',
      androidNotificationOngoing: true,
      notificationColor: Color(0xFF673AB7),
    ),
  );

  runApp(UncontrolledProviderScope(container: container, child: const PlaylistApp()));
}

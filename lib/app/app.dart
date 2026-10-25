import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/purge/purge_providers.dart';
import '../core/shared/onboarding_storage.dart';
import '../core/theme/global_theme/global_theme.dart';
import '../core/theme/vibe_engine/active_vibe_provider.dart' show defaultVibeFor;
import '../core/theme/vibe_engine/vibe_engine.dart';
import 'router.dart';

class PlaylistApp extends ConsumerStatefulWidget {
  const PlaylistApp({super.key});

  @override
  ConsumerState<PlaylistApp> createState() => _PlaylistAppState();
}

class _PlaylistAppState extends ConsumerState<PlaylistApp> {
  @override
  void initState() {
    super.initState();
    // Après la première frame (Activity Android attachée), les conditions
    // étant déjà acceptées (voir runLegalConsentGate dans main.dart).
    // Repli premier-plan de la purge mensuelle (Étape 7) : le tap sur la
    // notification navigue vers la vue de nettoyage via le routeur global.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Premier lancement : l'onboarding demande lui-même notifications et
      // audio, une seule fois (voir OnboardingScreen). Lancements suivants :
      // aucune nouvelle demande d'autorisation — un refus reste respecté —,
      // seul le tap sur la notification de nettoyage est câblé. La
      // vérification de purge, simple lecture de la base locale, est faite
      // dans les deux cas.
      if (await OnboardingStorage().isFirstLaunch()) {
        appRouter.go('/onboarding');
      } else {
        await ref.read(localNotificationServiceProvider).initialize(
              onNotificationTap: () => appRouter.go('/space/cleanup'),
            );
      }

      await ref.read(purgeCheckOnLaunchProvider.future);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeMode themeMode = ref.watch(globalThemeModeProvider);
    final Color userAccent = ref.watch(userAccentColorProvider);
    // Identité visuelle UNIQUE de l'app : mode clair/sombre + couleur principale
    // des Réglages, jamais la Vibe de la playlist en cours de lecture (celle-ci
    // ne teinte que le Lecteur et sa file d'attente, voir MasterPlayerScreen).
    final VibeVisual identity = defaultVibeFor(userAccent);

    return MaterialApp.router(
      title: 'Vibe',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: applyVibe(buildLightTheme(seedColor: userAccent), identity),
      darkTheme: applyVibe(buildDarkTheme(seedColor: userAccent), identity),
      // Transition fluide (800ms) lors d'un changement d'identité dans les
      // Réglages : `Theme.of(context)` ici est déjà résolu (clair/sombre) par
      // MaterialApp à partir de `theme`/`darkTheme` ci-dessus — `AnimatedTheme`
      // anime la BARRE DE NAVIGATION et le FOND DES CARTES vers cette cible au
      // lieu d'y sauter, pour tout l'arbre en dessous de `child`.
      builder: (context, child) => AnimatedTheme(
        data: Theme.of(context),
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeInOutCubic,
        child: child!,
      ),
      routerConfig: appRouter,
    );
  }
}

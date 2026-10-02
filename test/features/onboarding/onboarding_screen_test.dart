import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:playlist_app/core/storage/database/app_database.dart';
import 'package:playlist_app/core/storage/database/database_provider.dart';
import 'package:playlist_app/core/storage/database/track_repository.dart';
import 'package:playlist_app/core/storage/scanner/full_device_scan_service.dart';
import 'package:playlist_app/core/storage/scanner/scanned_track.dart';
import 'package:playlist_app/features/onboarding/data/onboarding_providers.dart';
import 'package:playlist_app/features/onboarding/presentation/onboarding_screen.dart';
import 'package:playlist_app/features/settings/data/auto_enrich_preference.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Journal partagé des demandes système et du scan, dans l'ordre d'appel.
final List<String> _log = [];

class _FakePermissions implements OnboardingPermissions {
  _FakePermissions({required this.audioGranted});

  final bool audioGranted;

  @override
  Future<void> requestNotifications({required void Function() onTap}) async => _log.add('notifications');

  @override
  Future<bool> requestAudio() async {
    _log.add('audio');
    return audioGranted;
  }
}

class _FakeScan implements FullDeviceScanService {
  /// Réglage d'enrichissement tel qu'enregistré au moment où le scan démarre.
  bool? enrichPreferenceAtScan;

  /// Si défini, le scan reste en cours d'indexation jusqu'à sa complétion.
  Completer<void>? hold;

  @override
  Future<List<ScannedTrack>> scan({
    required TrackRepository trackRepository,
    void Function(FullDeviceScanProgress progress)? onProgress,
  }) async {
    _log.add('scan');
    enrichPreferenceAtScan = await AutoEnrichPreference.isEnabled();
    onProgress?.call(const FullDeviceScanProgress(phase: FullDeviceScanPhase.indexing, processed: 1, total: 2));
    await hold?.future;
    return const [];
  }
}

void main() {
  late AppDatabase db;
  late _FakeScan scan;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _log.clear();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    scan = _FakeScan();
  });
  tearDown(() => db.close());

  /// Onboarding tel qu'ouvert après l'écran de consentement (voir
  /// runLegalConsentGate, testé à part) : il démarre seul à l'étape 2.
  Future<void> open(WidgetTester tester, {bool audioGranted = true}) async {
    final GoRouter router = GoRouter(
      initialLocation: '/onboarding',
      routes: [
        GoRoute(path: '/onboarding', builder: (context, state) => const OnboardingScreen()),
        GoRoute(path: '/player', builder: (context, state) => const Scaffold(body: Text('PLAYER'))),
      ],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        fullDeviceScanServiceProvider.overrideWithValue(scan),
        onboardingPermissionsProvider.overrideWithValue(_FakePermissions(audioGranted: audioGranted)),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
  }

  Future<SharedPreferences> prefs() => SharedPreferences.getInstance();

  Future<void> answer(WidgetTester tester, String button) async {
    await tester.tap(find.text(button));
    await tester.pumpAndSettle();
  }

  testWidgets('steps 2 then 3 are requested on opening, then the import question, nothing scanned yet', (
    tester,
  ) async {
    await open(tester);

    expect(_log, ['notifications', 'audio']);
    expect(find.textContaining('importer automatiquement tous les titres audio'), findsOneWidget);
    // Rien d'autre à l'écran sous la modale (ancien « B » parasite, début de
    // « Bienvenue » décalé à gauche).
    expect(find.textContaining('Bienvenue'), findsNothing);
  });

  testWidgets('step 4 "Refuser": no scan, onboarding done, later manual imports stay offline', (tester) async {
    await open(tester);

    await answer(tester, 'Refuser');

    expect(find.textContaining('renommer et enrichir'), findsNothing);
    expect(_log, isNot(contains('scan')));
    expect(find.text('PLAYER'), findsOneWidget);
    expect((await prefs()).getBool('onboarding.full_scan_completed'), isTrue);
    // Interrupteur Paramètres > Confidentialité basculé sur OFF.
    expect((await prefs()).getBool('privacy.auto_enrich_on_import'), isFalse);
  });

  testWidgets('steps 4 "Importer" + 5 "Non merci": choice saved before the scan, which then runs offline', (
    tester,
  ) async {
    await open(tester);

    await answer(tester, 'Importer');
    expect(_log, isNot(contains('scan')), reason: 'no scan before step 5 is answered');
    expect(find.textContaining('renommer et enrichir automatiquement'), findsOneWidget);

    await answer(tester, 'Non merci');

    expect(_log, ['notifications', 'audio', 'scan']);
    expect(scan.enrichPreferenceAtScan, isFalse);
    expect((await prefs()).getBool('privacy.auto_enrich_on_import'), isFalse);
    expect(find.text('PLAYER'), findsOneWidget);
    expect((await prefs()).getBool('onboarding.full_scan_completed'), isTrue);
  });

  testWidgets('step 5 "Activer" turns the Privacy switch on before the scan', (tester) async {
    await open(tester);

    await answer(tester, 'Importer');
    await answer(tester, 'Activer');

    expect(scan.enrichPreferenceAtScan, isTrue);
    expect((await prefs()).getBool('privacy.auto_enrich_on_import'), isTrue);
  });

  testWidgets('audio denied at step 3: no question, no scan, auto-enrichment OFF, import place named', (
    tester,
  ) async {
    await open(tester, audioGranted: false);

    expect(find.textContaining('importer automatiquement'), findsNothing);
    expect(_log, ['notifications', 'audio']);
    expect(find.text('PLAYER'), findsOneWidget);
    expect(find.textContaining('vous pourrez importer vos morceaux manuellement depuis Espace → Bibliothèque'),
        findsOneWidget);
    expect((await prefs()).getBool('onboarding.full_scan_completed'), isTrue);
    expect((await prefs()).getBool('privacy.auto_enrich_on_import'), isFalse);
  });

  testWidgets('scan progress addresses the user formally (vouvoiement)', (tester) async {
    scan.hold = Completer<void>();
    await open(tester);
    await answer(tester, 'Importer');
    await answer(tester, 'Non merci');

    expect(find.text('Indexation de votre bibliothèque...'), findsOneWidget);
    expect(find.textContaining(RegExp(r'\b(tu|ta|ton|tes)\b', caseSensitive: false)), findsNothing);

    scan.hold!.complete();
    await tester.pumpAndSettle();
  });
}

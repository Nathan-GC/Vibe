import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playlist_app/app/app.dart';
import 'package:playlist_app/core/purge/local_notification_service.dart';
import 'package:playlist_app/core/purge/purge_providers.dart';
import 'package:playlist_app/core/storage/cover_art/remote_cover_auto_trigger.dart';
import 'package:playlist_app/core/storage/metadata_extractor/embedded_cover_backfill.dart';
import 'package:playlist_app/features/library/data/library_rescan_providers.dart';
import 'package:playlist_app/features/library/data/library_rescan_service.dart';
import 'package:playlist_app/features/settings/presentation/legal_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeNotifications implements LocalNotificationService {
  int initializations = 0;

  @override
  Future<void> initialize({void Function()? onNotificationTap}) async => initializations++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCoverTrigger implements RemoteCoverAutoTrigger {
  int passes = 0;

  @override
  Future<int> runPass() async => ++passes;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCoverBackfill implements EmbeddedCoverBackfill {
  int runs = 0;

  @override
  Future<void> runOnce() async => runs++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRescan implements LibraryRescanService {
  int runs = 0;

  @override
  Future<void> runIfPending() async => runs++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('later launches never ask again for system permissions (a refusal at onboarding stands)', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'onboarding.full_scan_completed': true,
      'legal.accepted_version': LegalScreen.lastUpdated,
    });
    final List<String> permissionCalls = [];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/permissions/methods'),
      (call) async {
        permissionCalls.add(call.method);
        return call.method == 'requestPermissions' ? <int, int>{} : 0;
      },
    );
    final _FakeNotifications notifications = _FakeNotifications();
    final _FakeCoverTrigger coverTrigger = _FakeCoverTrigger();
    final _FakeCoverBackfill coverBackfill = _FakeCoverBackfill();
    final _FakeRescan rescan = _FakeRescan();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        localNotificationServiceProvider.overrideWithValue(notifications),
        purgeCheckOnLaunchProvider.overrideWith((ref) async {}),
        remoteCoverAutoTriggerProvider.overrideWithValue(coverTrigger),
        embeddedCoverBackfillProvider.overrideWithValue(coverBackfill),
        libraryRescanServiceProvider.overrideWithValue(rescan),
      ],
      child: const PlaylistApp(),
    ));
    await tester.pump(const Duration(seconds: 1));

    // Tap sur la notification de nettoyage toujours câblé, sans demande.
    expect(notifications.initializations, 1);
    // Rapatriement des pochettes en ligne : une passe au démarrage (le localiseur
    // relit lui-même onboarding terminé + interrupteur, voir son test).
    expect(coverTrigger.passes, 1);
    expect(coverBackfill.runs, 1);
    // Nouveau scan des métadonnées (la garde RGPD et le drapeau sont dans le service, testés à part).
    expect(rescan.runs, 1);
    expect(permissionCalls, isNot(contains('requestPermissions')));
  });
}

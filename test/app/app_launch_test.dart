import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playlist_app/app/app.dart';
import 'package:playlist_app/core/purge/local_notification_service.dart';
import 'package:playlist_app/core/purge/purge_providers.dart';
import 'package:playlist_app/features/settings/presentation/legal_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeNotifications implements LocalNotificationService {
  int initializations = 0;

  @override
  Future<void> initialize({void Function()? onNotificationTap}) async => initializations++;

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

    await tester.pumpWidget(ProviderScope(
      overrides: [
        localNotificationServiceProvider.overrideWithValue(notifications),
        purgeCheckOnLaunchProvider.overrideWith((ref) async {}),
      ],
      child: const PlaylistApp(),
    ));
    await tester.pump(const Duration(seconds: 1));

    // Tap sur la notification de nettoyage toujours câblé, sans demande.
    expect(notifications.initializations, 1);
    expect(permissionCalls, isNot(contains('requestPermissions')));
  });
}

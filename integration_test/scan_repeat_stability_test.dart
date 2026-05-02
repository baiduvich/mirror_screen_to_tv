import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mirror_screen_to_tv/main.dart' as app;
import 'package:mirror_screen_to_tv/services/device_discovery_service.dart';

// ignore: directives_ordering
import '../test/test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late List<String> capturedLogs;
  late DebugPrintCallback originalDebugPrint;

  setUp(() async {
    capturedLogs = [];
    originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) capturedLogs.add(message);
    };
    SharedPreferences.setMockInitialValues({'auto_scan': false});
    DeviceDiscoveryService.mockDevices = null;
  });

  tearDown(() {
    debugPrint = originalDebugPrint;
    DeviceDiscoveryService.mockDevices = null;
  });

  testWidgets('3 manual refresh taps all complete without crash', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Cast tab is already active (index 0)
    final refreshBtn = find.byKey(const Key('discover_button'));
    expect(refreshBtn, findsOneWidget);

    for (int i = 0; i < 3; i++) {
      // Tap refresh
      await tester.tap(refreshBtn);
      await tester.pump(const Duration(milliseconds: 50));

      // Wait for discovery_done to fire
      final done = await pumpUntilLogged(
        tester, capturedLogs, 'discovery_done', 'success',
        timeout: const Duration(seconds: 5),
      );
      expect(done, isTrue,
          reason: 'Scan $i must complete (discovery_done) within 5s');

      // After scan, the button should be enabled again (not null/disabled)
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      final btn = tester.widget<IconButton>(refreshBtn);
      expect(btn.onPressed, isNotNull,
          reason: 'discover_button must be re-enabled after scan $i');
    }

    // State assertion: discovery_done fired at least 3 times
    final doneCount = capturedLogs
        .where((l) => l.contains('[TEST_EVENT] discovery_done status=success'))
        .length;
    expect(doneCount, greaterThanOrEqualTo(3),
        reason: 'discovery_done must fire at least 3 times for 3 manual scans');

    // peer_item from mock device is visible
    expect(find.byKey(const Key('peer_item')), findsOneWidget);
  });
}

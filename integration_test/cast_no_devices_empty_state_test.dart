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
    // auto_scan=true so scan fires
    SharedPreferences.setMockInitialValues({'auto_scan': true});
    // Empty list → scan completes with 0 devices
    DeviceDiscoveryService.mockDevices = [];
  });

  tearDown(() {
    debugPrint = originalDebugPrint;
    DeviceDiscoveryService.mockDevices = null;
  });

  testWidgets('empty mock scan shows error_banner and no peer_item', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Wait for scan to finish
    final found = await pumpUntilLogged(
      tester, capturedLogs, 'discovery_done', 'success',
      timeout: const Duration(seconds: 5),
    );
    expect(found, isTrue,
        reason: 'discovery_done success must fire even with 0 devices');

    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    // State assertion: error_banner visible, peer_item absent
    expect(find.byKey(const Key('error_banner')), findsOneWidget,
        reason: 'error_banner must be shown when no devices found');
    expect(find.byKey(const Key('peer_item')), findsNothing,
        reason: 'No peer_item should exist in the empty state');

    // Log assertion: peer_count=0
    final hasZeroCount = capturedLogs
        .any((l) => l.contains('[TEST_EVENT] discovery_done status=success') &&
                    l.contains('peer_count=0'));
    expect(hasZeroCount, isTrue,
        reason: 'discovery_done must report peer_count=0');
  });
}

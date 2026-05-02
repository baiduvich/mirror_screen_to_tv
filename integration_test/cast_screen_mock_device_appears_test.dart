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
    // auto_scan=true → scan fires on Cast tab open
    SharedPreferences.setMockInitialValues({'auto_scan': true});
    // null → service returns default mock TV
    DeviceDiscoveryService.mockDevices = null;
  });

  tearDown(() {
    debugPrint = originalDebugPrint;
    DeviceDiscoveryService.mockDevices = null;
  });

  testWidgets('kTestMode scan returns mock device in peer list', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Cast tab is index 0, already shown on launch
    // Wait for discovery_done event
    final found = await pumpUntilLogged(
      tester, capturedLogs, 'discovery_done', 'success',
      timeout: const Duration(seconds: 5),
    );
    expect(found, isTrue,
        reason: 'discovery_done success event must fire within 5 seconds');

    // State assertion: peer_list with peer_item is visible
    final peerVisible = await pumpUntilFound(
      tester, find.byKey(const Key('peer_item')),
      timeout: const Duration(seconds: 3),
    );
    expect(peerVisible, isTrue,
        reason: 'peer_item card must be visible after mock scan');

    // Exactly 1 mock device
    expect(find.byKey(const Key('peer_item')), findsOneWidget,
        reason: 'Exactly one mock TV device should appear');

    // Connect button is present and tappable
    expect(find.byKey(const Key('connect_button')), findsOneWidget);

    // Log assertion: peer_count=1 in discovery_done
    final hasPeerCount = capturedLogs
        .any((l) => l.contains('[TEST_EVENT] discovery_done status=success') &&
                    l.contains('peer_count=1'));
    expect(hasPeerCount, isTrue,
        reason: 'discovery_done must report peer_count=1');
  });
}

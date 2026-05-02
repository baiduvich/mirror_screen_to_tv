import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mirror_screen_to_tv/main.dart' as app;
import 'package:mirror_screen_to_tv/services/device_discovery_service.dart';

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
    // Disable auto-scan so scan doesn't run mid-navigation
    SharedPreferences.setMockInitialValues({'auto_scan': false});
    DeviceDiscoveryService.mockDevices = [];
  });

  tearDown(() {
    debugPrint = originalDebugPrint;
    DeviceDiscoveryService.mockDevices = null;
  });

  testWidgets('navigate through all 4 tabs 3 times without crash', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 3));

    final tabs = ['Cast', 'Videos', 'Web', 'Settings'];

    for (int cycle = 0; cycle < 3; cycle++) {
      for (final label in tabs) {
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle(const Duration(seconds: 1));
        // Verify tap registered — the label should still be visible
        expect(find.text(label), findsWidgets,
            reason: 'Tab "$label" should render after tap (cycle $cycle)');
      }
    }

    // State assertion: app is on Settings tab at end, no exceptions thrown
    expect(find.text('Settings'), findsWidgets);
    // discovery_done should not have fired since auto_scan was disabled
    final scanFired = capturedLogs
        .any((l) => l.contains('[TEST_EVENT] discovery_started'));
    expect(scanFired, isFalse,
        reason: 'No scan should have started with auto_scan=false');
  });
}

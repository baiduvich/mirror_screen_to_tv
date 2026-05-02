import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mirror_screen_to_tv/core/theme.dart';
import 'package:mirror_screen_to_tv/screens/settings_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'auto_scan': true});
  });

  testWidgets('toggling auto-scan switch updates SharedPreferences', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: const SettingsScreen(),
      ),
    );

    // Wait for _loadSettings to complete
    await tester.pumpAndSettle(const Duration(seconds: 2));

    final switchKey = find.byKey(const Key('settings_auto_scan_switch'));
    expect(switchKey, findsOneWidget,
        reason: 'Auto-scan switch must be present before tapping');

    // Verify initial state is on
    final switchWidget = tester.widget<SwitchListTile>(switchKey);
    expect(switchWidget.value, isTrue, reason: 'Switch starts as ON from mock prefs');

    // Tap the switch to toggle off
    await tester.tap(switchKey);
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    // State assertion: SharedPreferences 'auto_scan' should now be false
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('auto_scan'), isFalse,
        reason: "SharedPreferences 'auto_scan' must be false after toggle");
  });
}

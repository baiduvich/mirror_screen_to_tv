import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mirror_screen_to_tv/core/theme.dart';
import 'package:mirror_screen_to_tv/screens/settings_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'auto_scan': true,
      'slideshow_interval': 5,
      'video_quality': 'High',
    });
  });

  testWidgets('SettingsScreen renders auto-scan switch', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: const SettingsScreen(),
      ),
    );

    // Let initState async work complete
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.byKey(const Key('settings_auto_scan_switch')), findsOneWidget,
        reason: 'Auto-scan SwitchListTile must be visible');

    expect(find.text('Auto-scan on open'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('SettingsScreen shows Rate App, Contact Us, Privacy Policy', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: const SettingsScreen(),
      ),
    );

    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.text('Rate App'), findsOneWidget);
    expect(find.text('Contact Us'), findsOneWidget);
    expect(find.text('Privacy Policy'), findsOneWidget);
  });
}

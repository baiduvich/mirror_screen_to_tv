import 'package:flutter/foundation.dart';

/// Compile-time flag. Set via: flutter run --dart-define=TEST_MODE=true
const bool kTestMode = bool.fromEnvironment('TEST_MODE', defaultValue: false);

/// Emit a structured test event. No-op in non-test builds.
///
/// Format: [TEST_EVENT] <name> status=<status> [key=value ...]
void logTestEvent(
  String name, {
  required String status,
  Map<String, Object?> extras = const {},
}) {
  if (!kTestMode) return;
  final extrasStr =
      extras.entries.map((e) => '${e.key}=${e.value}').join(' ');
  debugPrint('[TEST_EVENT] $name status=$status $extrasStr'.trim());
}

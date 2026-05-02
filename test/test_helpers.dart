import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pump until [finder] matches at least one widget, or [timeout] elapses.
/// Returns true if found, false on timeout.
Future<bool> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 10),
  Duration interval = const Duration(milliseconds: 100),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(interval);
    if (finder.evaluate().isNotEmpty) return true;
  }
  return false;
}

/// Pump until a [TEST_EVENT] log line appears in [logs].
Future<bool> pumpUntilLogged(
  WidgetTester tester,
  List<String> logs,
  String eventName,
  String status, {
  Duration timeout = const Duration(seconds: 10),
  Duration interval = const Duration(milliseconds: 100),
}) async {
  final marker = '[TEST_EVENT] $eventName status=$status';
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(interval);
    if (logs.any((line) => line.contains(marker))) return true;
  }
  return false;
}

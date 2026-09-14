import 'package:alpha_netscope/product/diagnostics.dart';
import 'package:alpha_netscope/product/support.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('onboarding explains permissions and completes', (tester) async {
    var completed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingScreen(onComplete: () async => completed = true),
      ),
    );

    expect(find.text('See your Wi-Fi clearly'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Permissions only when needed'), findsOneWidget);
    expect(find.textContaining('Nearby scans may require'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Private by design'), findsOneWidget);
    await tester.tap(find.text('Start monitoring'));
    await tester.pumpAndSettle();
    expect(completed, isTrue);
  });

  testWidgets('privacy policy documents local diagnostics', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PrivacyPolicyPage()));

    expect(find.text('Privacy policy'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Crash diagnostics'),
      220,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('Crash diagnostics'), findsOneWidget);
    expect(
      find.textContaining('Nothing is uploaded automatically'),
      findsOneWidget,
    );
  });

  test('diagnostic entries include actionable technical context', () {
    final entry = formatDiagnosticEntry(
      error: StateError('test failure'),
      stack: StackTrace.fromString('frame one'),
      source: 'automated test',
      timestamp: DateTime.utc(2026, 8, 11),
    );

    expect(entry, contains('2026-08-11T00:00:00.000Z'));
    expect(entry, contains('automated test'));
    expect(entry, contains('test failure'));
    expect(entry, contains('frame one'));
  });

  test('diagnostic log trimming cuts on an entry boundary', () {
    final entries = List.generate(
      40,
      (index) => formatDiagnosticEntry(
        error: StateError('failure $index ${'x' * 200}'),
        stack: StackTrace.fromString('frame $index'),
        source: 'test',
        timestamp: DateTime.utc(2026, 1, 1, 0, index),
      ),
    );
    final log = entries.join();
    final trimmed = trimDiagnosticLog(log, keepBytes: 2000);

    expect(trimmed.length, lessThan(log.length));
    expect(trimmed.trimLeft(), startsWith('--- Alpha NetScope diagnostic ---'));
    expect(trimmed, endsWith(entries.last));
    expect(trimmed, contains('failure 39'));
    expect(trimDiagnosticLog('short', keepBytes: 2000), 'short');
  });
}

import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'product/app.dart';
import 'product/diagnostics.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final diagnostics = DiagnosticsService();
  await diagnostics.initialize();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    unawaited(
      diagnostics.record(
        details.exception,
        details.stack ?? StackTrace.current,
        source: details.library ?? 'Flutter framework',
      ),
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(diagnostics.record(error, stack, source: 'Platform dispatcher'));
    return true;
  };
  ErrorWidget.builder = (details) => Material(
    color: const Color(0xfff2f0ec),
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'This screen encountered an error. A diagnostic report was saved on this device.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xff191719)),
        ),
      ),
    ),
  );
  runApp(AlphaNetScopeApp(diagnostics: diagnostics));
}

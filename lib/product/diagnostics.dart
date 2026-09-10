import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class DiagnosticsService extends ChangeNotifier {
  File? _file;

  Future<void> initialize() async {
    try {
      final base = await getApplicationDocumentsDirectory();
      final directory = Directory('${base.path}/diagnostics');
      await directory.create(recursive: true);
      _file = File('${directory.path}/alpha_netscope_crashes.log');
    } catch (_) {
      _file = null;
    }
  }

  Future<void> record(
    Object error,
    StackTrace stack, {
    required String source,
  }) async {
    final file = _file;
    if (file == null) return;
    try {
      final entry = formatDiagnosticEntry(
        error: error,
        stack: stack,
        source: source,
        timestamp: DateTime.now().toUtc(),
      );
      await file.writeAsString(entry, mode: FileMode.append, flush: true);
      if (await file.length() > 256 * 1024) {
        final text = await file.readAsString();
        await file.writeAsString(trimDiagnosticLog(text), flush: true);
      }
      notifyListeners();
    } catch (_) {
      // Writing the crash log should never crash the app itself.
    }
  }

  Future<bool> hasReports() async => await _file?.exists() ?? false;

  Future<String> readReports() async {
    final file = _file;
    if (file == null || !await file.exists()) return '';
    return file.readAsString();
  }

  Future<File?> reportFile() async {
    final file = _file;
    return file != null && await file.exists() ? file : null;
  }

  Future<void> clear() async {
    final file = _file;
    if (file != null && await file.exists()) await file.delete();
    notifyListeners();
  }
}

const _entryMarker = '--- Alpha NetScope diagnostic ---';

/// Keeps roughly the last [keepBytes] of [text], cut at an entry boundary so
/// the log never starts mid-entry (or mid-character).
String trimDiagnosticLog(String text, {int keepBytes = 192 * 1024}) {
  if (text.length <= keepBytes) return text;
  final cut = text.indexOf(_entryMarker, text.length - keepBytes);
  if (cut <= 0) return text;
  return '\n${text.substring(cut)}';
}

String formatDiagnosticEntry({
  required Object error,
  required StackTrace stack,
  required String source,
  required DateTime timestamp,
}) =>
    '''\n$_entryMarker
UTC: ${timestamp.toIso8601String()}
Source: $source
Error: $error
Stack:\n$stack
''';

import 'dart:collection';

import 'package:clipsync_core/clipsync_core.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

/// One retained log line.
class LogEntry {
  /// Creates an entry.
  LogEntry(this.time, this.level, this.message);

  /// Timestamp (local).
  final DateTime time;

  /// Severity.
  final Level level;

  /// Already redacted message.
  final String message;

  @override
  String toString() =>
      '${time.toIso8601String()} ${level.name.padRight(7)} $message';
}

/// App-wide logger that redacts secrets and keeps the last [capacity] lines
/// for the diagnostics screen.
class AppLog {
  AppLog._();

  /// Singleton.
  static final AppLog instance = AppLog._();

  /// Lines kept in memory.
  static const int capacity = 500;

  final Queue<LogEntry> _buffer = Queue();
  final Logger _logger = Logger(
    printer: SimplePrinter(colors: false, printTime: true),
    level: kReleaseMode ? Level.info : Level.debug,
  );
  final ValueNotifier<int> _revision = ValueNotifier(0);

  /// Bumps whenever a line is added; UI listens to refresh.
  ValueListenable<int> get revision => _revision;

  /// Snapshot of retained lines, oldest first.
  List<LogEntry> get entries => List.unmodifiable(_buffer);

  /// Debug-level message.
  void d(String message) => _add(Level.debug, message);

  /// Info-level message.
  void i(String message) => _add(Level.info, message);

  /// Warning-level message.
  void w(String message, {Object? error}) =>
      _add(Level.warning, _fmt(message, error));

  /// Error-level message.
  void e(String message, {Object? error, StackTrace? stack}) =>
      _add(Level.error, _fmt(message, error), stack: stack);

  /// Adapter for `SyncEngine`'s logger callback.
  void sync(String message, {Object? error}) =>
      error == null ? i('[sync] $message') : w('[sync] $message', error: error);

  /// Redacted plain-text export for bug reports.
  String export() => _buffer.map((e) => e.toString()).join('\n');

  void _add(Level level, String message, {StackTrace? stack}) {
    final safe = redactSecrets(message);
    _buffer.addLast(LogEntry(DateTime.now(), level, safe));
    while (_buffer.length > capacity) {
      _buffer.removeFirst();
    }
    _logger.log(level, safe, stackTrace: stack);
    _revision.value++;
  }

  static String _fmt(String message, Object? error) =>
      error == null ? message : '$message: $error';
}

/// Shorthand.
AppLog get log => AppLog.instance;

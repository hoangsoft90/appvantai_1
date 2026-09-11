import 'package:flutter/foundation.dart';

/// Logger tối giản cho P0: chỉ log khi debug build (kDebugMode).
/// Điểm gắn logging/monitoring thật (P1) nếu cần — đổi phần thân hàm.
class AppLogger {
  AppLogger._();

  static void debug(String message) => _log('DEBUG', message);
  static void info(String message) => _log('INFO', message);
  static void warn(String message) => _log('WARN', message);
  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    _log('ERROR', message, error);
    if (stackTrace != null && kDebugMode) {
      debugPrintStack(stackTrace: stackTrace, label: message);
    }
  }

  static void _log(String level, String message, [Object? error]) {
    if (!kDebugMode) return;
    final suffix = error == null ? '' : '\n$error';
    debugPrint('[$level] $message$suffix');
  }
}
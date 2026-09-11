import 'package:appvantai_mobile/core/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// fix_p7_1.md #2 — invariant release build:
///  1. release mà không APP_ENV=production/staging → chặn (trước đây bị lọt)
///  2. production → API HTTPS non-local bắt buộc
///  3. production → Firebase auth bật + đủ config bắt buộc
///  4. dev/không-production → không chặn (dev local vẫn chạy được)
void main() {
  group('AppConfig.validateProductionConfig (fix_p7_1 #2)', () {
    test('release + APP_ENV=dev (quên dart-define) → CHẶN', () {
      final err = AppConfig.validateProductionConfig(
        releaseMode: true,
        appEnv: 'dev',
        apiBaseUrl: 'http://localhost:8787',
        firebaseEnabled: false,
        firebaseConfigured: false,
      );
      expect(err, isNotNull);
      expect(err, contains('APP_ENV=production'));
    });

    test('release + APP_ENV rỗng (operator quên hẳn) → CHẶN', () {
      final err = AppConfig.validateProductionConfig(
        releaseMode: true,
        appEnv: '',
        apiBaseUrl: 'http://localhost:8787',
        firebaseEnabled: false,
        firebaseConfigured: false,
      );
      expect(err, isNotNull);
    });

    test('release + APP_ENV=staging → CHO PHÉP (bản test nội bộ)', () {
      final err = AppConfig.validateProductionConfig(
        releaseMode: true,
        appEnv: 'staging',
        apiBaseUrl: 'http://10.0.2.2:8787',
        firebaseEnabled: false,
        firebaseConfigured: false,
      );
      expect(err, isNull);
    });

    test('debug (releaseMode=false) + dev → không chặn', () {
      final err = AppConfig.validateProductionConfig(
        releaseMode: false,
        appEnv: 'dev',
        apiBaseUrl: 'http://localhost:8787',
        firebaseEnabled: false,
        firebaseConfigured: false,
      );
      expect(err, isNull);
    });

    test('production + API localhost → CHẶN', () {
      final err = AppConfig.validateProductionConfig(
        releaseMode: true,
        appEnv: 'production',
        apiBaseUrl: 'http://localhost:8787',
        firebaseEnabled: true,
        firebaseConfigured: true,
      );
      expect(err, isNotNull);
      expect(err, contains('API_BASE_URL'));
    });

    test('production + API HTTP không phải localhost → CHẶN', () {
      final err = AppConfig.validateProductionConfig(
        releaseMode: true,
        appEnv: 'production',
        apiBaseUrl: 'http://api.example.com',
        firebaseEnabled: true,
        firebaseConfigured: true,
      );
      expect(err, isNotNull);
    });

    test('production + Firebase tắt (đi auth dev) → CHẶN', () {
      final err = AppConfig.validateProductionConfig(
        releaseMode: true,
        appEnv: 'production',
        apiBaseUrl: 'https://api.example.com',
        firebaseEnabled: false,
        firebaseConfigured: true,
      );
      expect(err, isNotNull);
      expect(err, contains('Firebase'));
    });

    test('production + Firebase bật nhưng thiếu config → CHẶN', () {
      final err = AppConfig.validateProductionConfig(
        releaseMode: true,
        appEnv: 'production',
        apiBaseUrl: 'https://api.example.com',
        firebaseEnabled: true,
        firebaseConfigured: false,
      );
      expect(err, isNotNull);
      expect(err, contains('Firebase'));
    });

    test('production đúng chuẩn (HTTPS + Firebase đủ) → PASS', () {
      final err = AppConfig.validateProductionConfig(
        releaseMode: true,
        appEnv: 'production',
        apiBaseUrl: 'https://api.example.com',
        firebaseEnabled: true,
        firebaseConfigured: true,
      );
      expect(err, isNull);
    });
  });
}

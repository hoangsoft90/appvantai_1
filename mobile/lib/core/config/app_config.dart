import 'package:flutter/foundation.dart';

import 'app_auth_mode.dart';

/// Cấu hình môi trường, inject qua --dart-define (không commit secret vào code).
///
/// Run dev:
///   flutter run --dart-define=APP_ENV=dev
///               --dart-define=API_BASE_URL=http://localhost:8787
///
/// Android emulator truy cập host qua 10.0.2.2:
///   --dart-define=API_BASE_URL=http://10.0.2.2:8787
///
/// Release (plan2_final §7.3 + fix_p7_1.md #2):
///   flutter build apk --release --dart-define=APP_ENV=production \
///                     --dart-define=API_BASE_URL=https://api.example.com \
///                     --dart-define=USE_FIREBASE_AUTH=true \
///                     --dart-define=FIREBASE_API_KEY=... (xem AppAuthMode)
///   → build release thiếu APP_ENV=production sẽ FAIL-FAST (kReleaseMode thực,
///     không tin dart-define "declare" — operator quên truyền vẫn bị chặn).
///   → production additionally: API HTTPS non-local + Firebase auth bật + đủ config.
class AppConfig {
  AppConfig._();

  static const String appName = 'App Vận Tải';

  static const String appEnv = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'dev',
  );

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8787',
  );

  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 20);

  static bool get isDev => appEnv == 'dev';
  static bool get isProduction => appEnv == 'production';

  /// plan2_final §7.3 + fix_p7_1.md #2: gọi sớm ở main() — fail-fast.
  ///
  /// Invariant 1 (mới — fix lỗ hổng "release nhưng APP_ENV=dev"):
  /// kReleaseMode (biên dịch thật của Flutter, không phụ thuộc dart-define)
  /// mà không khai báo APP_ENV=production → sai quy trình build, chặn ngay.
  /// (Bản release test nội bộ dùng APP_ENV=staging.)
  ///
  /// Invariant 2: APP_ENV=production → API bắt buộc HTTPS + non-local,
  /// Firebase auth bắt buộc bật + đủ config (login production không đi auth dev).
  static void assertReleaseConfig() {
    final error = validateProductionConfig(
      releaseMode: kReleaseMode,
      appEnv: appEnv,
      apiBaseUrl: apiBaseUrl,
      firebaseEnabled: AppAuthMode.isFirebase,
      firebaseConfigured: AppAuthMode.firebaseConfigured,
    );
    if (error != null) throw StateError(error);
  }

  /// Logic invariant tách hàm thuần để unit test được (kReleaseMode/appEnv là
  /// const compile-time nên không override được trong test).
  /// Trả về null khi hợp lệ, string mô tả lỗi khi vi phạm.
  @visibleForTesting
  static String? validateProductionConfig({
    required bool releaseMode,
    required String appEnv,
    required String apiBaseUrl,
    required bool firebaseEnabled,
    required bool firebaseConfigured,
  }) {
    if (releaseMode && appEnv != 'production' && appEnv != 'staging') {
      return 'Release build nhưng không có --dart-define=APP_ENV=production '
          '(APP_ENV hiện tại: "$appEnv"). Bản release test nội bộ dùng '
          'APP_ENV=staging; bản phát hành dùng production.';
    }
    if (appEnv != 'production') return null;

    final uri = Uri.tryParse(apiBaseUrl);
    final host = uri?.host ?? '';
    final isLocalhost =
        host == 'localhost' || host == '127.0.0.1' || host == '10.0.2.2';
    if (isLocalhost || !apiBaseUrl.startsWith('https://')) {
      return 'Release build với APP_ENV=production nhưng API_BASE_URL không hợp lệ '
          '("$apiBaseUrl"). Cung cấp --dart-define=API_BASE_URL=https://<production-host>';
    }
    // fix_p7_1.md #2: production KHÔNG được chạy auth dev — Firebase bắt buộc.
    if (!firebaseEnabled || !firebaseConfigured) {
      return 'Release build APP_ENV=production bắt buộc Firebase auth: '
          '--dart-define=USE_FIREBASE_AUTH=true + đầy đủ FIREBASE_API_KEY/'
          'FIREBASE_PROJECT_ID/FIREBASE_APP_ID/FIREBASE_MSG_SENDER_ID';
    }
    return null;
  }
}

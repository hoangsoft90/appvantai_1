/// Cấu hình auth production (phase7 §7.1) — đọc từ --dart-define.
/// Tách khỏi app_config.dart để không tạo phụ thuộc auth → config ngược.
///
/// Dev build (mặc định):
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8787
///   → authStrategy = DevOtpAuthStrategy (OTP dev, không cần Firebase)
///
/// Production build:
///   flutter build apk --release \
///     --dart-define=APP_ENV=production \///   --dart-define=API_BASE_URL=https://`<prod-worker>` \
///     --dart-define=USE_FIREBASE_AUTH=true \
///     --dart-define=FIREBASE_API_KEY=... \
///     --dart-define=FIREBASE_PROJECT_ID=... \
///     --dart-define=FIREBASE_APP_ID=... \
///     --dart-define=FIREBASE_MSG_SENDER_ID=...
class AppAuthMode {
  AppAuthMode._();

  static const bool isFirebase = bool.fromEnvironment('USE_FIREBASE_AUTH');

  static const String firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const String firebaseProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const String firebaseAppId = String.fromEnvironment('FIREBASE_APP_ID');
  static const String firebaseSenderId = String.fromEnvironment('FIREBASE_MSG_SENDER_ID');

  static bool get firebaseConfigured =>
      firebaseApiKey.isNotEmpty &&
      firebaseProjectId.isNotEmpty &&
      firebaseAppId.isNotEmpty &&
      firebaseSenderId.isNotEmpty;

  /// Gọi sớm ở main() — fail-fast nếu USE_FIREBASE_AUTH=true mà thiếu config.
  static void assertFirebaseConfigIfEnabled() {
    if (isFirebase && !firebaseConfigured) {
      throw StateError(
        'USE_FIREBASE_AUTH=true nhưng thiếu --dart-define FIREBASE_API_KEY/'
        'FIREBASE_PROJECT_ID/FIREBASE_APP_ID/FIREBASE_MSG_SENDER_ID',
      );
    }
  }
}

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../shared/services/api_exception.dart';
import '../../../shared/services/logger.dart';
import '../../../shared/services/token_storage.dart';
import '../data/auth_repository.dart';
import '../data/auth_strategy.dart';
import '../domain/auth_models.dart';

part 'auth_controller.g.dart';

/// AuthController — single source of truth cho trạng thái đăng nhập.
///
/// bootstrap (build):
///  1. Đọc token từ storage
///  2. Nếu có token → gọi /me để xác thực
///  3. 401 → xóa token, về unauthenticated (phiên hết hạn)
///     Lỗi mạng → coi như unauthenticated nhưng GIỮ token (lần sau thử lại)
@riverpod
class AuthController extends _$AuthController {
  @override
  Future<AuthState> build() async {
    final storage = ref.watch(tokenStorageProvider);
    final token = await storage.readToken();
    if (token == null || token.isEmpty) {
      return const AuthUnauthenticated();
    }
    try {
      final user = await ref.watch(authRepositoryProvider).me();
      return AuthAuthenticated(user: user);
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        AppLogger.info('Phiên hết hạn, xóa token');
        await storage.clearToken();
        return const AuthUnauthenticated();
      }
      AppLogger.warn('Không xác thực được session (giữ token): ${e.message}');
      return const AuthUnauthenticated();
    }
  }

  /// Bắt đầu đăng nhập (phase7 §7.1): dev OTP hoặc Firebase SMS tuỳ strategy
  /// (--dart-define USE_FIREBASE_AUTH). Trả dev OTP nếu có — production rỗng.
  /// Ném ApiException để UI hiển thị lỗi.
  Future<String> startLogin(String phone) async {
    return ref.read(authStrategyProvider).startLogin(phone);
  }

  /// Xác thực mã (OTP dev hoặc mã SMS Firebase) → lưu token → cập nhật state
  /// (router tự redirect /home).
  Future<void> verifyOtp(String phone, String otp) async {
    final session = await ref.read(authStrategyProvider).verify(phone, otp);
    await ref.read(tokenStorageProvider).saveToken(session.token);
    state = AsyncData(AuthAuthenticated(user: session.user));
  }

  /// Cập nhật user trong state (sau khi PATCH /me hoặc lưu xe) —
  /// router sẽ tự redirect theo trạng thái onboarding/vehicle.
  void applyUser(AuthUser user) {
    state = AsyncData(AuthAuthenticated(user: user));
  }

  Future<void> logout() async {
    await ref.read(tokenStorageProvider).clearToken();
    state = const AsyncData(AuthUnauthenticated());
  }
}
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_auth_mode.dart';
import '../../../shared/services/api_exception.dart';
import '../domain/auth_models.dart';
import 'auth_repository.dart';
import 'firebase_phone_auth_service.dart';

/// Contract gửi SMS + xác minh mã với Firebase (platform channel thật),
/// tách biệt để test fake được — không import trực tiếp firebase_auth.
abstract class PhoneAuthProvider {
  /// Gửi mã SMS tới [phone] (E.164). Ném [ApiException] khi Firebase lỗi.
  Future<void> sendCode(String phone);

  /// Xác minh mã [code] → trả Firebase ID token.
  /// Ném [ApiException] khi sai mã / hết hạn / Firebase lỗi.
  Future<String> confirmCode(String code);
}

/// Contract auth production (phase7 §7.1) — 2 implement:
///  - [DevOtpAuthStrategy]: OTP dev qua /auth/request-otp + /auth/verify-otp
///    (chỉ APP_ENV=dev — server ÉP không trả dev_otp ở môi trường khác)
///  - [FirebaseAuthStrategy]: Firebase Phone Auth thật → /auth/firebase
///    (SMS thật, mobile tự xác minh mã với Firebase, Worker verify ID token)
abstract class AuthStrategy {
  /// Bắt đầu flow đăng nhập cho [phone].
  /// Trả dev OTP (chuỗi rỗng nếu server không trả) cho strategy dev;
  /// Firebase: gửi SMS — mã xác minh do Firebase quản lý, không qua API app.
  Future<String> startLogin(String phone);

  /// Hoàn tất đăng nhập → [AuthSession].
  Future<AuthSession> verify(String phone, String code);
}

/// OTP dev (Phase 0) — mặc định, chỉ hoạt động khi backend APP_ENV=dev.
class DevOtpAuthStrategy implements AuthStrategy {
  DevOtpAuthStrategy(this._repo);

  final AuthRepository _repo;

  @override
  Future<String> startLogin(String phone) => _repo.requestOtp(phone);

  @override
  Future<AuthSession> verify(String phone, String code) => _repo.verifyOtp(phone, code);
}

/// Firebase Phone Auth (phase7 §7.1) — login production.
class FirebaseAuthStrategy implements AuthStrategy {
  FirebaseAuthStrategy(this._repo, this._phoneAuth);

  final AuthRepository _repo;
  final PhoneAuthProvider _phoneAuth;

  @override
  Future<String> startLogin(String phone) async {
    try {
      // PhoneValidator.normalize cho 0xxxxxxxxx (định dạng identity của app),
      // nhưng Firebase verifyPhoneNumber BẮT BUỘC E.164 → đổi 0xxx → +84xxx.
      await _phoneAuth.sendCode(toE164(phone));
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(
        statusCode: null,
        code: 'FIREBASE_SEND_FAILED',
        message: 'Không gửi được SMS xác minh: ${e.toString()}',
      );
    }
    return ''; // production không có dev_otp
  }

  /// 0xxxxxxxxx (Việt Nam) → +84xxxxxxxxx (E.164 bắt buộc của Firebase).
  static String toE164(String phone) {
    if (phone.startsWith('+')) return phone;
    if (phone.startsWith('84') && phone.length == 11) return '+$phone';
    if (phone.startsWith('0') && phone.length == 10) return '+84${phone.substring(1)}';
    return '+$phone'; // fallback — để Firebase tự chấm nếu format lạ
  }

  @override
  Future<AuthSession> verify(String phone, String code) async {
    String idToken;
    try {
      // Đổi mã SMS → ID token Firebase (mobile tự xác minh với Firebase servers)
      idToken = await _phoneAuth.confirmCode(code);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(
        statusCode: null,
        code: 'FIREBASE_CODE_FAILED',
        message: 'Mã xác minh không đúng hoặc đã hết hạn',
      );
    }
    try {
      // Gửi ID token lên Worker → verify server-side → JWT app (contract như OTP dev)
      return await _repo.loginWithFirebaseIdToken(idToken);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(
        statusCode: null,
        code: 'FIREBASE_LOGIN_FAILED',
        message: 'Đăng nhập thất bại: ${e.toString()}',
      );
    }
  }
}

/// Strategy theo môi trường: dev → OTP local (test không cần SMS thật),
/// production/other → Firebase Phone Auth. Quyết định bởi --dart-define.
/// Test override `authStrategyProvider` trực tiếp khi cần.
final authStrategyProvider = Provider<AuthStrategy>((ref) {
  if (AppAuthMode.isFirebase) {
    return FirebaseAuthStrategy(
      ref.watch(authRepositoryProvider),
      ref.watch(firebasePhoneAuthProvider),
    );
  }
  return DevOtpAuthStrategy(ref.watch(authRepositoryProvider));
});

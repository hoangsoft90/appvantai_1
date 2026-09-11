import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/services/api_exception.dart';
import '../../../shared/services/logger.dart';
import '../data/auth_strategy.dart';

/// Phase 7 §7.1 — Firebase Phone Auth qua package firebase_auth.
///
/// Firebase.initializeApp() được gọi ở main() CHỈ khi build với
/// USE_FIREBASE_AUTH=true (options từ --dart-define FIREBASE_*). Với dev
/// build thường, provider này không bao giờ được chạm → app chạy bình thường.
class FirebasePhoneAuthService implements PhoneAuthProvider {
  /// verificationId từ callback codeSent — bắt buộc để đổi mã SMS thành credential.
  String? _verificationId;

  /// Credential auto-retrieval (Android) — nếu có thì confirmCode dùng luôn,
  /// không cần verificationId (user không hề nhập mã).
  fa.PhoneAuthCredential? _pendingCredential;

  fa.FirebaseAuth get _instance {
    try {
      return fa.FirebaseAuth.instance;
    } on Object {
      // Chỉ xảy ra khi USE_FIREBASE_AUTH=true nhưng main() chưa init
      // (config sai) — fail với message rõ thay vì crash mơ hồ.
      throw const ApiException(
        statusCode: null,
        code: 'FIREBASE_NOT_INITIALIZED',
        message: 'Firebase chưa khởi tạo — kiểm tra dart-define FIREBASE_*',
      );
    }
  }

  @override
  Future<void> sendCode(String phone) async {
    try {
      await _instance.verifyPhoneNumber(
        phoneNumber: phone,
        timeout: const Duration(seconds: 60),
        // Auto-retrieval (Android): hoàn tất đăng nhập không cần nhập mã —
        // giữ credential lại để confirmCode() dùng tiếp (mobile vẫn đi qua
        // màn OTP nhưng user có thể dán mã; luồng tự động thì confirm ngay).
        verificationCompleted: (fa.PhoneAuthCredential credential) async {
          _pendingCredential = credential;
        },
        verificationFailed: (fa.FirebaseAuthException e) {
          throw ApiException(
            statusCode: null,
            code: 'FIREBASE_SEND_FAILED',
            message: _friendlyError(e),
          );
        },
        codeSent: (String verificationId, int? resendToken) {
          // Lại verificationId để confirmCode() tạo credential với mã user nhập.
          _verificationId = verificationId;
          AppLogger.info('Firebase SMS đã gửi tới $phone');
        },
        codeAutoRetrievalTimeout: (String verificationId) {},
      );
    } on ApiException {
      rethrow;
    } on Exception catch (e) {
      throw ApiException(
        statusCode: null,
        code: 'FIREBASE_SEND_FAILED',
        message: 'Không gửi được SMS xác minh: ${e.toString()}',
      );
    }
  }

  @override
  Future<String> confirmCode(String code) async {
    try {
      // Ưu tiên credential auto-retrieval; không có thì tạo từ mã user nhập.
      fa.PhoneAuthCredential? credential = _pendingCredential;
      if (credential == null) {
        final verificationId = _verificationId;
        if (verificationId == null || verificationId.isEmpty) {
          throw const ApiException(
            statusCode: null,
            code: 'FIREBASE_CODE_FAILED',
            message: 'Chưa gửi mã xác minh, vui lòng gửi lại',
          );
        }
        credential = fa.PhoneAuthProvider.credential(
          verificationId: verificationId,
          smsCode: code,
        );
      }
      _pendingCredential = null;
      final result = await _instance.signInWithCredential(credential);
      final idToken = await result.user?.getIdToken();
      if (idToken == null || idToken.isEmpty) {
        throw const ApiException(
          statusCode: null,
          code: 'FIREBASE_NO_TOKEN',
          message: 'Không lấy được ID token từ Firebase',
        );
      }
      return idToken;
    } on ApiException {
      rethrow;
    } on fa.FirebaseAuthException catch (e) {
      throw ApiException(
        statusCode: null,
        code: 'FIREBASE_CODE_FAILED',
        message: _friendlyError(e),
      );
    } on Exception catch (e) {
      throw ApiException(
        statusCode: null,
        code: 'FIREBASE_CODE_FAILED',
        message: 'Xác minh mã thất bại: ${e.toString()}',
      );
    }
  }

  String _friendlyError(fa.FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-phone-number':
        return 'Số điện thoại không hợp lệ';
      case 'invalid-verification-code':
        return 'Mã xác minh không đúng';
      case 'code-expired':
        return 'Mã xác minh đã hết hạn, vui lòng gửi lại';
      case 'too-many-requests':
        return 'Bạn đã thử quá nhiều lần, vui lòng thử lại sau';
      case 'quota-exceeded':
        return 'Hệ thống đang quá tải, vui lòng thử lại sau';
      default:
        return 'Lỗi xác minh: ${e.message ?? e.code}';
    }
  }
}

/// Provider dùng lazy — chỉ đọc khi authStrategyProvider chọn Firebase.
final firebasePhoneAuthProvider = Provider<PhoneAuthProvider>((ref) {
  return FirebasePhoneAuthService();
});

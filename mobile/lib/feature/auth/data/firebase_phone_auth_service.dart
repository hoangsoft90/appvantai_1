import 'dart:async';

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
    // BUG đã fix (2026-09-11): verifyPhoneNumber là API fire-and-forget — kết quả
    // đến qua callback, và `throw` bên trong callback KHÔNG propagate về caller
    // (bị nuốt). Hệ quả cũ: verificationFailed chạy nhưng sendCode vẫn "thành
    // công" → app nhảy màn OTP → user nhập mã → "Chưa gửi mã xác minh" vì
    // codeSent chưa từng chạy (_verificationId = null).
    // Fix: Completer — sendCode() chỉ hoàn tất khi callback đầu tiên báo kết quả:
    //  - codeSent (nhận verificationId) / verificationCompleted (auto-retrieval)
    //    → thành công;
    //  - verificationFailed → ném LỖI THẬT của Firebase ra màn login.
    final firstResult = Completer<void>();
    try {
      _instance.verifyPhoneNumber(
        phoneNumber: phone,
        timeout: const Duration(seconds: 60),
        // Auto-retrieval (Android): hoàn tất đăng nhập không cần nhập mã —
        // giữ credential lại để confirmCode() dùng tiếp (mobile vẫn đi qua
        // màn OTP nhưng user có thể dán mã; luồng tự động thì confirm ngay).
        // Instant validation cũng rơi vào đây và codeSent CÓ THỂ không chạy
        // nên hoàn tất completer ở đây luôn — credential đã đủ để verify.
        verificationCompleted: (fa.PhoneAuthCredential credential) {
          _pendingCredential = credential;
          AppLogger.info('Firebase auto-retrieval/instant validation cho $phone');
          if (!firstResult.isCompleted) firstResult.complete();
        },
        verificationFailed: (fa.FirebaseAuthException e) {
          // KHÔNG throw ở đây (bị nuốt) — đưa lỗi về qua completer.
          if (!firstResult.isCompleted) {
            firstResult.completeError(
              ApiException(
                statusCode: null,
                code: 'FIREBASE_SEND_FAILED',
                message: _friendlyError(e),
              ),
              StackTrace.current,
            );
          }
        },
        codeSent: (String verificationId, int? resendToken) {
          // Lại verificationId để confirmCode() tạo credential với mã user nhập.
          _verificationId = verificationId;
          AppLogger.info('Firebase SMS đã gửi tới $phone');
          if (!firstResult.isCompleted) firstResult.complete();
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          // SMS auto-retrieval hết chờ — user sẽ nhập tay, vẫn dùng được ID này.
          _verificationId = verificationId;
        },
      );
      // Chờ callback đầu tiên; giới hạn 90s chống treo vĩnh viễn (Firebase có
      // timeout 60s nội bộ nhưng không đảm bảo luôn gọi callback).
      await firstResult.future.timeout(
        const Duration(seconds: 90),
        onTimeout: () {
          throw const ApiException(
            statusCode: null,
            code: 'FIREBASE_SEND_TIMEOUT',
            message: 'Không nhận được phản hồi xác minh từ Firebase, vui lòng thử lại',
          );
        },
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
      // Lỗi cấu hình dự án — thường gặp khi setup Firebase Phone Auth mới:
      case 'app-not-authorized':
      case 'invalid-app-credential':
        return 'App chưa được phép gọi Firebase (SHA-1/SHA-256 keystore chưa đăng ký '
            'trên Firebase console — Project settings → Android app)';
      case 'operation-not-allowed':
        return 'Chưa gửi được SMS tới khu vực này — Firebase đang chặn region/quota. '
            'Mở Firebase console → Authentication → Settings → User actions → '
            '“SMS region allowlist” và cho phép Vietnam (+84), hoặc kiểm tra billing/quota.';
      case 'app-not-verified':
      case 'captcha-check-failed':
        return 'Firebase chưa xác thực được app — kiểm tra SHA fingerprint '
            'và thử lại sau ít phút';
      default:
        return 'Lỗi xác minh: ${e.message ?? e.code}';
    }
  }
}

/// Provider dùng lazy — chỉ đọc khi authStrategyProvider chọn Firebase.
final firebasePhoneAuthProvider = Provider<PhoneAuthProvider>((ref) {
  return FirebasePhoneAuthService();
});

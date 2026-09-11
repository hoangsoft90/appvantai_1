import 'package:appvantai_mobile/feature/auth/data/auth_repository.dart';
import 'package:appvantai_mobile/feature/auth/data/auth_strategy.dart';
import 'package:appvantai_mobile/shared/services/api_exception.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_repository.dart';

/// Fake PhoneAuthProvider — mô phỏng firebase_auth không cần platform channel.
class FakePhoneAuthProvider implements PhoneAuthProvider {
  final sentPhones = <String>[];
  String? nextSendError;
  String? nextConfirmError;
  String idTokenToReturn = 'fb-id-token-abc';

  @override
  Future<void> sendCode(String phone) async {
    if (nextSendError != null) {
      throw ApiException(statusCode: null, code: 'FIREBASE_SEND_FAILED', message: nextSendError!);
    }
    sentPhones.add(phone);
  }

  @override
  Future<String> confirmCode(String code) async {
    if (nextConfirmError != null) {
      throw ApiException(statusCode: null, code: 'FIREBASE_CODE_FAILED', message: nextConfirmError!);
    }
    return idTokenToReturn;
  }
}

void main() {

  test('DevOtpAuthStrategy: startLogin trả dev OTP; verify gọi verify-otp', () async {
    final fake = FakeAuthRepository();
    final strategy = DevOtpAuthStrategy(fake);

    final devOtp = await strategy.startLogin('0912345678');
    expect(devOtp, '123456'); // fake dev OTP
    expect(fake.requestedPhones, ['0912345678']);

    final session = await strategy.verify('0912345678', '123456');
    expect(session.token, isNotEmpty);
    expect(session.user.phone, '0912345678');
  });

  test('FirebaseAuthStrategy: startLogin gửi SMS (không có dev OTP), verify đổi ID token lấy JWT', () async {
    final fake = FakeAuthRepository();
    final phone = FakePhoneAuthProvider();
    final strategy = FirebaseAuthStrategy(fake, phone);

    final devOtp = await strategy.startLogin('+84912345678');
    expect(devOtp, ''); // production KHÔNG có dev_otp
    expect(phone.sentPhones, ['+84912345678']);

    final session = await strategy.verify('+84912345678', '654321');
    expect(session.token, 'jwt-firebase-test'); // từ loginWithFirebaseIdToken fake
  });

  test('FirebaseAuthStrategy.toE164: 0xxx/84xxx → +84xxx; giữ nguyên dạng +', () {
    expect(FirebaseAuthStrategy.toE164('0912345678'), '+84912345678');
    expect(FirebaseAuthStrategy.toE164('84912345678'), '+84912345678');
    expect(FirebaseAuthStrategy.toE164('+84912345678'), '+84912345678');
  });

  test('FirebaseAuthStrategy: startLogin nhận 0xxx (identity app) → gửi SMS E.164', () async {
    final fake = FakeAuthRepository();
    final phone = FakePhoneAuthProvider();
    final strategy = FirebaseAuthStrategy(fake, phone);

    await strategy.startLogin('0912345678');
    expect(phone.sentPhones, ['+84912345678']);
  });

  test('FirebaseAuthStrategy: sai mã SMS → ApiException thân thiện (không crash)', () async {
    final fake = FakeAuthRepository();
    final phone = FakePhoneAuthProvider()..nextConfirmError = 'Mã xác minh không đúng';
    final strategy = FirebaseAuthStrategy(fake, phone);

    await expectLater(
      strategy.verify('+84912345678', '000000'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'FIREBASE_CODE_FAILED')),
    );
  });

  test('FirebaseAuthStrategy: gửi SMS lỗi → ApiException, startLogin không trả OTP', () async {
    final fake = FakeAuthRepository();
    final phone = FakePhoneAuthProvider()..nextSendError = 'Số điện thoại không hợp lệ';
    final strategy = FirebaseAuthStrategy(fake, phone);

    await expectLater(
      strategy.startLogin('abc'),
      throwsA(isA<ApiException>()),
    );
  });

  test('authStrategyProvider mặc định DevOtpAuthStrategy khi không bật dart-define', () {
    // Test runner không có USE_FIREBASE_AUTH=true → phải chọn dev OTP.
    final container = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWithValue(FakeAuthRepository())],
    );
    addTearDown(container.dispose);
    final strategy = container.read(authStrategyProvider);
    expect(strategy, isA<DevOtpAuthStrategy>());
  });

  // AuthController.startLogin đi qua strategy được chứng minh trong
  // auth_flow_test.dart (widget test login → OTP → onboarding chạy strategy dev).
}

import 'package:appvantai_mobile/app/app.dart';
import 'package:appvantai_mobile/feature/auth/data/auth_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/onboarding_helper.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('luồng login → OTP → onboarding → home (chủ hàng)', (tester) async {
    final fake = FakeAuthRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(fake)],
        child: const App(),
      ),
    );
    await tester.pumpAndSettle();

    // Đang ở màn login (chưa có token)
    expect(find.text('Gửi mã OTP'), findsOneWidget);

    // Nhập số điện thoại + gửi OTP
    await tester.enterText(find.byType(TextField), '0912345678');
    await tester.tap(find.text('Gửi mã OTP'));
    await tester.pumpAndSettle();

    // Repository nhận số đã chuẩn hóa; snackbar hiện dev OTP
    expect(fake.requestedPhones, ['0912345678']);
    expect(find.textContaining('123456'), findsWidgets);

    // Chuyển sang màn OTP
    expect(find.text('Xác nhận'), findsOneWidget);

    // Nhập OTP sai → lỗi inline, không navigate
    await tester.enterText(find.byType(TextField), '000000');
    await tester.tap(find.text('Xác nhận'));
    await tester.pumpAndSettle();
    expect(find.text('Xác nhận'), findsOneWidget);

    // Nhập OTP đúng → user mới (name rỗng) → onboarding
    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('Xác nhận'));
    await tester.pumpAndSettle();
    expect(find.text('Hoàn tất hồ sơ'), findsOneWidget);

    // Điền tên + tick legal consent (§18), giữ vai trò "Chủ hàng" → home
    await submitOnboarding(tester);

    expect(find.byIcon(Icons.logout), findsOneWidget);
    expect(find.text('Xin chào, Nguyễn Văn A'), findsOneWidget);
    expect(find.text('Chủ hàng'), findsOneWidget);

    // Đăng xuất → quay lại login
    await tester.tap(find.byIcon(Icons.logout));
    await tester.pumpAndSettle();
    expect(find.text('Gửi mã OTP'), findsOneWidget);
  });

  testWidgets('lỗi mạng khi gửi OTP hiển thị thông báo, không navigate', (tester) async {
    final fake = FakeAuthRepository()..failRequestOtp = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(fake)],
        child: const App(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '0912345678');
    await tester.tap(find.text('Gửi mã OTP'));
    await tester.pumpAndSettle();

    expect(find.textContaining('kiểm tra mạng'), findsWidgets);
    expect(find.text('Gửi mã OTP'), findsOneWidget); // vẫn ở màn login
  });
}
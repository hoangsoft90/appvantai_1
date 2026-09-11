import 'package:appvantai_mobile/app/app.dart';
import 'package:appvantai_mobile/feature/auth/data/auth_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/onboarding_helper.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('legal docs là trang PUBLIC — đọc được khi CHƯA đăng nhập (§7.5)', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(FakeAuthRepository())],
        child: const App(),
      ),
    );
    await tester.pumpAndSettle();

    // Chưa login → app redirect về /login
    expect(find.text('Gửi mã OTP'), findsOneWidget);

    // Điều hướng thẳng /legal/terms khi chưa login → KHÔNG bị redirect về login
    tester.element(find.text('Gửi mã OTP')).go('/legal/terms');
    await tester.pumpAndSettle();

    expect(find.text('Điều khoản sử dụng'), findsWidgets);
    expect(find.textContaining('CHỈ là nền tảng trung gian'), findsOneWidget);
  });

  testWidgets('Privacy policy render nội dung bắt buộc: GPS chỉ khi active', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(FakeAuthRepository())],
        child: const App(),
      ),
    );
    await tester.pumpAndSettle();

    tester.element(find.text('Gửi mã OTP')).go('/legal/privacy');
    await tester.pumpAndSettle();

    expect(find.text('Chính sách riêng tư'), findsWidgets);
    expect(find.textContaining('chỉ khi chuyến đang chạy'), findsOneWidget);
    // ListView lazy — cuộn tới mục section 4 mới render
    await tester.scrollUntilVisible(
      find.textContaining('Không bán dữ liệu'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('Không bán dữ liệu'), findsOneWidget);
  });

  testWidgets('Login screen có link Điều khoản + Privacy (đọc trước lúc đăng ký)', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(FakeAuthRepository())],
        child: const App(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Điều khoản sử dụng'), findsOneWidget);
    expect(find.text('Chính sách riêng tư'), findsOneWidget);

    // Bấm link → sang màn điều khoản
    await tester.tap(find.text('Điều khoản sử dụng'));
    await tester.pumpAndSettle();
    expect(find.textContaining('CHỈ là nền tảng trung gian'), findsOneWidget);
  });

  testWidgets('Profile có mục Điều khoản + Privacy sau khi đăng nhập', (tester) async {
    final fake = FakeAuthRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(fake)],
        child: const App(),
      ),
    );
    await tester.pumpAndSettle();

    // Login nhanh (dev OTP fake 123456) → onboarding → home
    await tester.enterText(find.byType(TextField), '0912345678');
    await tester.tap(find.text('Gửi mã OTP'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('Xác nhận'));
    await tester.pumpAndSettle();
    await submitOnboarding(tester);

    // Vào profile → thấy 2 mục legal
    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();
    expect(find.text('Điều khoản sử dụng'), findsOneWidget);
    expect(find.text('Chính sách riêng tư'), findsOneWidget);

    // Mở privacy từ profile
    await tester.tap(find.text('Chính sách riêng tư'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining('Không bán dữ liệu'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('Không bán dữ liệu'), findsOneWidget);
  });
}

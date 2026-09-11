import 'package:appvantai_mobile/app/app.dart';
import 'package:appvantai_mobile/feature/auth/data/auth_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/onboarding_helper.dart';

/// Helper: login bằng dev OTP, dừng ở màn onboarding.
Future<void> loginToOnboarding(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField), '0912345678');
  await tester.tap(find.text('Gửi mã OTP'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), '123456');
  await tester.tap(find.text('Xác nhận'));
  await tester.pumpAndSettle();
  expect(find.text('Hoàn tất hồ sơ'), findsOneWidget);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('luồng tài xế: onboarding → khai xe → home → hồ sơ/sửa xe', (tester) async {
    final fake = FakeAuthRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(fake)],
        child: const App(),
      ),
    );
    await tester.pumpAndSettle();
    await loginToOnboarding(tester);

    // Chọn vai trò Tài xế + nhập tên + tick legal consent (§18)
    await tester.tap(find.text('Tài xế'));
    await tester.pumpAndSettle();
    await submitOnboarding(tester);

    // Driver chưa khai xe → bị đưa tới màn xe
    expect(find.text('Thông tin xe'), findsOneWidget);

    // Điền thông tin xe: [0]=biển, [1]=tải trọng, [2..4]=kích thước, [5]=khu vực
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '29C-123.45');
    await tester.enterText(fields.at(1), '5000');
    await tester.enterText(fields.at(2), '620');
    await tester.enterText(fields.at(3), '220');
    await tester.enterText(fields.at(4), '220');
    await tester.enterText(fields.at(5), 'Hà Nội – Hải Phòng');
    await tester.ensureVisible(find.text('Hoàn tất'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hoàn tất'));
    await tester.pumpAndSettle();

    // Về home với vai trò Tài xế
    expect(find.text('Xin chào, Nguyễn Văn A'), findsOneWidget);
    expect(find.text('Tài xế'), findsOneWidget);

    // Vào hồ sơ → thấy thông tin xe
    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();
    expect(find.text('Hồ sơ của tôi'), findsOneWidget);
    expect(find.text('29C-123.45'), findsOneWidget);
    expect(find.text('5000 kg'), findsOneWidget);
    // Phase 8 §8.3 — version app hiển thị trong Hồ sơ (test env thiếu plugin → '—')
    expect(find.text('Phiên bản'), findsOneWidget);

    // Sửa xe (chế độ edit, form đã prefill)
    // ListView lazy: nút nằm dưới màn hình (legal card Phase 7 đẩy xuống) → scroll tới trước khi tap.
    await tester.scrollUntilVisible(
      find.text('Cập nhật thông tin xe'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cập nhật thông tin xe'));
    await tester.pumpAndSettle();
    expect(find.text('Sửa thông tin xe'), findsOneWidget);
    expect(find.text('29C-123.45'), findsOneWidget); // prefill biển số

    await tester.enterText(find.byType(TextFormField).at(1), '8000');
    await tester.ensureVisible(find.text('Lưu thay đổi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lưu thay đổi'));
    await tester.pumpAndSettle();

    // Quay lại hồ sơ với tải trọng mới
    expect(find.text('Hồ sơ của tôi'), findsOneWidget);
    expect(find.text('8000 kg'), findsOneWidget);
  });
}
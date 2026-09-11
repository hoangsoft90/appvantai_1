import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Hoàn tất bước onboarding: điền tên + tick legal consent (§18) + bấm Tiếp tục.
/// Trả về true nếu điều hướng xảy ra (rời khỏi màn onboarding).
Future<void> submitOnboarding(
  WidgetTester tester, {
  String name = 'Nguyễn Văn A',
  bool tapContinue = true,
}) async {
  await tester.enterText(find.byType(TextField), name);
  // Legal disclaimer checkbox nằm cuối form — cuộn tới rồi tick
  await tester.ensureVisible(find.byType(Checkbox));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(Checkbox));
  await tester.pumpAndSettle();
  if (tapContinue) {
    await tester.ensureVisible(find.text('Tiếp tục'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tiếp tục'));
    await tester.pumpAndSettle();
  }
}

/// Verify onboarding báo lỗi khi chưa tick legal consent.
Future<void> expectOnboardingRequiresConsent(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField), 'Nguyễn Văn A');
  await tester.ensureVisible(find.text('Tiếp tục'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Tiếp tục'));
  await tester.pumpAndSettle();
  expect(find.textContaining('tick xác nhận điều khoản'), findsOneWidget);
}
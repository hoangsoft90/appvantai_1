import 'package:appvantai_mobile/app/app.dart';
import 'package:appvantai_mobile/feature/auth/data/auth_repository.dart';
import 'package:appvantai_mobile/feature/order/data/order_repository.dart';
import 'package:appvantai_mobile/feature/trip/data/trip_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_order_repository.dart';
import '../../helpers/fake_trip_repository.dart';
import '../../helpers/onboarding_helper.dart';

/// Login + onboarding + khai xe cho tài xế, dừng ở home.
Future<void> setupDriver(WidgetTester tester, FakeAuthRepository auth) async {
  await tester.enterText(find.byType(TextField), '0912345678');
  await tester.tap(find.text('Gửi mã OTP'));
  await tester.pumpAndSettle();
  // Chờ SnackBar dev OTP hết hạn (4s) — nếu không nó đè nút ở đáy màn hình
  // làm hit test trượt (bài học Phase 2).
  await tester.pump(const Duration(seconds: 5));
  await tester.enterText(find.byType(TextField), '123456');
  await tester.tap(find.text('Xác nhận'));
  await tester.pumpAndSettle();

  // Onboarding: chọn Tài xế + tên + tick legal consent (§18)
  await tester.tap(find.text('Tài xế'));
  await tester.pumpAndSettle();
  await submitOnboarding(tester);

  // Khai xe
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
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// plan2_final §5.1: form mới dùng search địa chỉ (geocode) thay vì nhập tọa độ.
  /// Điền 2 ô địa chỉ → bấm search icon TỪNG điểm → preview hiện ra → submit.
  Future<void> fillTripForm(WidgetTester tester) async {
    Finder addrField(String label) => find.byWidgetPredicate(
          (w) => w is TextField && (w.decoration?.labelText ?? '').contains(label),
        );
    await tester.enterText(addrField('điểm đi'), 'Hà Nội');
    await tester.enterText(addrField('điểm đến'), 'Hải Phòng');
    final searchIcons = find.byIcon(Icons.search);
    await tester.tap(searchIcons.first, warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(searchIcons.at(1), warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.textContaining('Tạo chuyến & quét radar'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Tạo chuyến & quét radar'), warnIfMissed: false);
    await tester.pumpAndSettle();
  }

  testWidgets('tài xế: tạo chuyến → radar hiển thị score + lý do', (tester) async {
    final auth = FakeAuthRepository();
    final trips = FakeTripRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          tripRepositoryProvider.overrideWithValue(trips),
          orderRepositoryProvider.overrideWithValue(FakeOrderRepository()),
        ],
        child: const App(),
      ),
    );
    await tester.pumpAndSettle();

    await setupDriver(tester, auth);
    // Chờ mọi SnackBar còn treo hết hạn trước khi tương tác nút ở đáy màn hình.
    await tester.pump(const Duration(seconds: 5));

    // Home tài xế có nút radar
    expect(find.text('Xin chào, Nguyễn Văn A'), findsOneWidget);
    await tester.tap(find.textContaining('Tôi đang chạy'));
    await tester.pumpAndSettle();

    // Form mới: search địa chỉ (geocode) thay vì nhập tọa độ (§5.1)
    expect(find.text('Tạo chuyến đi'), findsOneWidget);
    expect(find.text('Vĩ độ (vd: 21.0285)'), findsNothing); // không còn tọa độ thủ công
    await fillTripForm(tester);

    // Màn radar: score + reasons + thông tin order
    expect(find.text('Mối hàng tiện đường'), findsOneWidget);
    expect(find.text('92'), findsOneWidget); // score badge
    expect(find.text('1.200.000đ · 800 kg'), findsOneWidget);
    expect(find.text('KCN Quế Võ, Bắc Ninh'), findsOneWidget);
    expect(find.text('Điểm lấy cách tuyến 1.2 km'), findsOneWidget);
    expect(find.text('Điểm giao cùng hướng tuyến'), findsOneWidget);
    // plan3 Mục 4: detour giờ nằm trong hàng stats ("Độ lệch" + "3.4 km")
    expect(find.text('Độ lệch'), findsOneWidget);
    expect(find.text('3.4 km'), findsOneWidget);
    expect(find.text('Liên hệ chủ hàng'), findsOneWidget);
    expect(find.text('Nhận chuyến'), findsOneWidget); // Phase 5 accept
  });

  testWidgets('tài xế: liên hệ → thấy số phone → nhận chuyến (Phase 5)', (tester) async {
    final auth = FakeAuthRepository();
    final trips = FakeTripRepository();
    final orders = FakeOrderRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          tripRepositoryProvider.overrideWithValue(trips),
          orderRepositoryProvider.overrideWithValue(orders),
        ],
        child: const App(),
      ),
    );
    await tester.pumpAndSettle();
    await setupDriver(tester, auth);
    await tester.pump(const Duration(seconds: 5));

    await tester.tap(find.textContaining('Tôi đang chạy'));
    await tester.pumpAndSettle();
    await fillTripForm(tester);

    // Contact: hiện số điện thoại chủ hàng (chỉ sau contact — §18 privacy)
    await tester.tap(find.text('Liên hệ chủ hàng'));
    await tester.pumpAndSettle();
    // Số phone hiện trong dialog + trên label nút đã liên hệ
    expect(find.textContaining('0912000001'), findsWidgets);
    await tester.tap(find.text('Đóng'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Đã liên hệ'), findsOneWidget);

    // Accept: đơn chuyển accepted
    await tester.tap(find.text('Nhận chuyến'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Bạn đã nhận chuyến'), findsOneWidget);
  });

  testWidgets('radar rỗng → empty state có thể quét lại', (tester) async {
    final auth = FakeAuthRepository();
    final trips = FakeTripRepository()..matchesByTrip['t1'] = [];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          tripRepositoryProvider.overrideWithValue(trips),
        ],
        child: const App(),
      ),
    );
    await tester.pumpAndSettle();

    await setupDriver(tester, auth);
    await tester.tap(find.textContaining('Tôi đang chạy'));
    await tester.pumpAndSettle();
    await fillTripForm(tester);

    // plan3 Mục 4: empty state mới có gợi ý hành động
    expect(find.textContaining('Chưa có mối phù hợp'), findsOneWidget);
    expect(find.text('Khai báo chiều về'), findsOneWidget);
  });
}
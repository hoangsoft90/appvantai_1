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

Future<void> loginAsCustomer(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField), '0912345678');
  await tester.tap(find.text('Gửi mã OTP'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), '123456');
  await tester.tap(find.text('Xác nhận'));
  await tester.pumpAndSettle();
  await submitOnboarding(tester);
  expect(find.text('Xin chào, Nguyễn Văn A'), findsOneWidget);
  // Cho SnackBar dev OTP hết hạn — nó đè đáy màn hình, làm trượt hit test
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('chủ hàng: tạo đơn → danh sách → chi tiết → hủy', (tester) async {
    // Viewport cao hơn để form dài hiển thị trọn, tránh nút ở mép màn hình
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final fakeOrders = FakeOrderRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
          orderRepositoryProvider.overrideWithValue(fakeOrders),
          // plan3 Mục 5: form search geocode → cần fake trip repo (geocode giả)
          tripRepositoryProvider.overrideWithValue(FakeTripRepository()),
        ],
        child: const App(),
      ),
    );
    await tester.pumpAndSettle();
    await loginAsCustomer(tester);

    // Vào danh sách đơn (trống)
    await tester.tap(find.text('Đơn hàng của tôi'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Chưa có đơn hàng'), findsOneWidget);

    // Tạo đơn (FAB)
    await tester.tap(find.widgetWithText(FloatingActionButton, 'Tạo đơn'));
    await tester.pumpAndSettle();
    expect(find.text('Tạo đơn hàng'), findsOneWidget);

    // plan3 Mục 5: search geocode cho 2 điểm (không còn ô lat/lng)
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Hà Nội');
    await tester.tap(find.byIcon(Icons.search).first);
    await tester.pumpAndSettle();
    await tester.enterText(fields.at(1), 'Hải Phòng');
    await tester.tap(find.byIcon(Icons.search).at(1));
    await tester.pumpAndSettle();
    // Preview tọa độ ẩn — chỉ địa chỉ đọc được
    expect(find.text('Hà Nội, Việt Nam'), findsOneWidget);
    expect(find.text('Hải Phòng, Việt Nam'), findsOneWidget);

    await tester.enterText(fields.at(2), '800');
    await tester.enterText(fields.at(6), '2500000');
    await tester.enterText(fields.at(7), 'giao trong ngày');

    // Tick legal consent (§18) trước khi đăng
    await tester.ensureVisible(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Đăng đơn hàng'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Đăng đơn hàng'));
    await tester.pumpAndSettle();

    // Về danh sách, thấy đơn vừa tạo
    expect(find.text('Đơn hàng của tôi'), findsOneWidget);
    expect(find.textContaining('Hà Nội'), findsOneWidget);
    expect(find.textContaining('2.500.000đ'), findsOneWidget);

    // Vào chi tiết → hủy
    await tester.tap(find.textContaining('Hà Nội'));
    await tester.pumpAndSettle();
    expect(find.text('Chi tiết đơn hàng'), findsOneWidget);
    expect(find.text('Đang chờ'), findsOneWidget);

    await tester.tap(find.text('Hủy đơn hàng'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hủy đơn'));
    await tester.pumpAndSettle();

    // Về danh sách, trạng thái Đã hủy (trong chuỗi subtitle của card)
    expect(find.text('Đơn hàng của tôi'), findsOneWidget);
    expect(find.textContaining('Đã hủy'), findsOneWidget);
  });
}
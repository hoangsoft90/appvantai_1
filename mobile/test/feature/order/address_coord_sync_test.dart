import 'package:appvantai_mobile/feature/order/presentation/screens/order_form_screen.dart';
import 'package:appvantai_mobile/feature/trip/data/trip_repository.dart';
import 'package:appvantai_mobile/feature/trip/presentation/screens/trip_form_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_trip_repository.dart';

/// plan4_final §4.2 — Đồng bộ địa chỉ text ↔ tọa độ:
/// sửa text sau khi geocode → tọa độ cũ bị clear → submit bị chặn đến khi
/// tìm lại. Không cho xảy ra case "địa chỉ A + tọa độ B".
void main() {
  testWidgets('order form: sửa địa chỉ sau geocode → chặn submit với lỗi rõ ràng',
      (tester) async {
    final trips = FakeTripRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [tripRepositoryProvider.overrideWithValue(trips)],
        child: const MaterialApp(home: Scaffold(body: OrderFormScreen())),
      ),
    );

    // Nhập + tìm điểm lấy, điểm giao → cả 2 point được set.
    await tester.enterText(find.byType(TextFormField).first, 'KCN Thăng Long Hà Nội');
    await tester.tap(find.byTooltip('Tìm địa chỉ').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(1), 'Cảng Hải Phòng');
    await tester.tap(find.byTooltip('Tìm địa chỉ').at(1));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.location_on), findsNWidgets(2)); // 2 preview hiện

    // User SỬA text điểm lấy → tọa độ cũ phải bị clear ngay.
    await tester.enterText(find.byType(TextFormField).first, 'KCN Thăng Long Hà Nội - sửa');
    await tester.pump();
    expect(find.byIcon(Icons.location_on), findsOneWidget); // preview lấy biến mất

    // Điền các trường bắt buộc còn lại rồi submit → bị chặn, báo lỗi rõ ràng.
    await tester.enterText(find.byType(TextFormField).at(2), '500'); // khối lượng
    await tester.enterText(find.byType(TextFormField).at(5), '800000'); // giá
    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, 'Đăng đơn hàng'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Đăng đơn hàng'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.textContaining('cần tìm lại'), findsOneWidget);
  });

  testWidgets('trip form: sửa địa chỉ sau geocode → chặn submit', (tester) async {
    final trips = FakeTripRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [tripRepositoryProvider.overrideWithValue(trips)],
        child: const MaterialApp(home: Scaffold(body: TripFormScreen())),
      ),
    );

    await tester.enterText(find.byType(TextFormField).first, 'Hà Nội');
    await tester.tap(find.byTooltip('Tìm địa chỉ').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(1), 'Hải Phòng');
    await tester.tap(find.byTooltip('Tìm địa chỉ').at(1));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.location_on), findsNWidgets(2));

    // Sửa text điểm đến → point cũ clear.
    await tester.enterText(find.byType(TextFormField).at(1), 'Hải Phòng - sửa');
    await tester.pump();
    expect(find.byIcon(Icons.location_on), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Tạo chuyến & quét radar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('cần tìm lại'), findsOneWidget);
  });
}

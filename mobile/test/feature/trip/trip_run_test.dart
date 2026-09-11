import 'package:appvantai_mobile/app/app.dart';
import 'package:appvantai_mobile/feature/auth/data/auth_repository.dart';
import 'package:appvantai_mobile/feature/auth/domain/auth_models.dart';
import 'package:appvantai_mobile/feature/order/data/order_repository.dart';
import 'package:appvantai_mobile/feature/order/domain/order_models.dart';
import 'package:appvantai_mobile/feature/trip/data/trip_repository.dart';
import 'package:appvantai_mobile/shared/services/location_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_location_service.dart';
import '../../helpers/fake_order_repository.dart';
import '../../helpers/fake_trip_repository.dart';
import '../../helpers/onboarding_helper.dart';

/// Login + onboarding + khai xe cho tài xế, dừng ở home.
Future<void> setupDriver(WidgetTester tester, FakeAuthRepository auth) async {
  await tester.enterText(find.byType(TextField), '0912345678');
  await tester.tap(find.text('Gửi mã OTP'));
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 5)); // SnackBar OTP hết hạn
  await tester.enterText(find.byType(TextField), '123456');
  await tester.tap(find.text('Xác nhận'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Tài xế'));
  await tester.pumpAndSettle();
  await submitOnboarding(tester);
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

/// Tạo chuyến từ home (đi qua form + radar) rồi vào màn Đang chạy.
/// plan2_final §5.1: form mới dùng search địa chỉ (geocode) — onFieldSubmitted
/// tự trigger search, sau đó submit (fake geocode trả điểm cố định).
Future<void> createTripAndOpenRun(WidgetTester tester) async {
  await tester.tap(find.textContaining('Tôi đang chạy'), warnIfMissed: false);
  await tester.pumpAndSettle();
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
  // Màn radar → icon play (bắt đầu chuyến)
  await tester.tap(find.byIcon(Icons.play_circle_outline));
  await tester.pumpAndSettle();
  expect(find.text('Chuyến của tôi'), findsOneWidget);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('tài xế: bắt đầu chuyến → GPS gửi vị trí → kết thúc', (tester) async {
    final auth = FakeAuthRepository();
    final trips = FakeTripRepository();
    final location = FakeLocationService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          tripRepositoryProvider.overrideWithValue(trips),
          orderRepositoryProvider.overrideWithValue(FakeOrderRepository()),
          locationServiceProvider.overrideWithValue(location),
        ],
        child: const App(),
      ),
    );
    await tester.pumpAndSettle();
    await setupDriver(tester, auth);
    await tester.pump(const Duration(seconds: 5));
    await createTripAndOpenRun(tester);

    // Chưa bắt đầu → nút Bắt đầu hiển thị
    expect(find.text('Bắt đầu chuyến'), findsOneWidget);
    expect(find.textContaining('GPS tắt'), findsOneWidget);

    await tester.tap(find.text('Bắt đầu chuyến'));
    await tester.pumpAndSettle();

    // Đã chạy: GPS bật, vị trí được gửi ít nhất 1 lần (ngay lập tức)
    expect(find.textContaining('GPS bật'), findsOneWidget);
    expect(find.text('Kết thúc chuyến'), findsOneWidget);
    expect(trips.startCount, 1);
    expect(trips.sentLocations.length, greaterThanOrEqualTo(1));
    expect(location.positionCalls, greaterThanOrEqualTo(1));

    // Kết thúc chuyến → về home, không còn track
    await tester.tap(find.text('Kết thúc chuyến'));
    await tester.pumpAndSettle();
    expect(find.text('Xin chào, Nguyễn Văn A'), findsOneWidget);
    expect(trips.endCount, 1);
  });

  testWidgets('end API fail → giữ pending "chưa sync", retry thành công (§6.2)', (tester) async {
    final auth = FakeAuthRepository();
    final trips = FakeTripRepository();
    final location = FakeLocationService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          tripRepositoryProvider.overrideWithValue(trips),
          orderRepositoryProvider.overrideWithValue(FakeOrderRepository()),
          locationServiceProvider.overrideWithValue(location),
        ],
        child: const App(),
      ),
    );
    await tester.pumpAndSettle();
    await setupDriver(tester, auth);
    await tester.pump(const Duration(seconds: 5));
    await createTripAndOpenRun(tester);

    await tester.tap(find.text('Bắt đầu chuyến'));
    await tester.pumpAndSettle();
    expect(trips.startCount, 1);

    // End fail lần 1 (mạng lỗi) → KHÔNG rời màn, hiện banner chưa sync
    trips.failEnd = true;
    await tester.tap(find.text('Kết thúc chuyến'));
    await tester.pumpAndSettle();
    expect(find.text('Chuyến của tôi'), findsOneWidget); // vẫn ở màn run
    expect(find.textContaining('chưa được kết thúc trên máy chủ'), findsOneWidget);
    expect(find.textContaining('Kết thúc chuyến'), findsWidgets); // retry vẫn hiện (nút + banner)

    // End thành công lần 2 → về home (tap đúng nút, không banner)
    trips.failEnd = false;
    await tester.tap(find.text('Kết thúc chuyến'));
    await tester.pumpAndSettle();
    expect(find.text('Xin chào, Nguyễn Văn A'), findsOneWidget);
    expect(trips.endCount, 2);
  });

  testWidgets('từ chối quyền GPS → báo lỗi, không bắt đầu', (tester) async {
    final auth = FakeAuthRepository();
    final trips = FakeTripRepository();
    final location = FakeLocationService()..denyPermission = true;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          tripRepositoryProvider.overrideWithValue(trips),
          orderRepositoryProvider.overrideWithValue(FakeOrderRepository()),
          locationServiceProvider.overrideWithValue(location),
        ],
        child: const App(),
      ),
    );
    await tester.pumpAndSettle();
    await setupDriver(tester, auth);
    await tester.pump(const Duration(seconds: 5));
    await createTripAndOpenRun(tester);

    await tester.tap(find.text('Bắt đầu chuyến'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Cần quyền truy cập vị trí'), findsOneWidget);
    expect(find.text('Bắt đầu chuyến'), findsOneWidget); // vẫn chưa chạy
    expect(trips.startCount, 0);
  });

  testWidgets('customer thấy tài xế cách bao xa trên đơn đã accept', (tester) async {
    final auth = FakeAuthRepository()
      ..currentUser = const AuthUser(
        id: 'u1',
        name: 'Chủ Hàng B',
        phone: '0912345678',
        role: 'customer',
        status: 'active',
        legalConsentAt: null,
      );
    final orders = FakeOrderRepository();
    // Đơn đã có driver nhận (accepted) — giống response backend Phase 5
    orders.orders.add(CargoOrder(
      id: 'o1',
      driverId: 'd1',
      pickupLat: 21.0285,
      pickupLng: 105.8542,
      pickupAddress: 'Hà Nội',
      deliveryLat: 20.8449,
      deliveryLng: 106.6881,
      deliveryAddress: 'Hải Phòng',
      cargoType: 'general',
      weightKg: 500,
      lengthCm: 200,
      widthCm: 150,
      heightCm: 120,
      vehicleRequirement: 'truck',
      pickupFrom: DateTime.now().add(const Duration(hours: 2)),
      pickupTo: DateTime.now().add(const Duration(hours: 10)),
      price: 1200000,
      notes: '',
      status: 'accepted',
      expiresAt: DateTime.now().add(const Duration(hours: 10)),
    ));
    orders.driverDistanceResult =
        const DriverDistance(distanceKm: 2.3, updatedAt: null);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          orderRepositoryProvider.overrideWithValue(orders),
        ],
        child: const App(),
      ),
    );
    await tester.pumpAndSettle();

    // Login trực tiếp (customer đã có sẵn name — không cần onboarding)
    await tester.enterText(find.byType(TextField), '0912345678');
    await tester.tap(find.text('Gửi mã OTP'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('Xác nhận'));
    await tester.pumpAndSettle();

    // Vào đơn hàng của tôi → chi tiết đơn đã accept
    await tester.tap(find.text('Đơn hàng của tôi'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Hà Nội'));
    await tester.pumpAndSettle();

    expect(find.text('Chi tiết đơn hàng'), findsOneWidget);
    expect(find.textContaining('2.3 km'), findsOneWidget);
    expect(find.textContaining('Vị trí ẩn danh'), findsOneWidget);
  });
}
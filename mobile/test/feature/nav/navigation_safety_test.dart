import 'package:appvantai_mobile/app/app.dart';
import 'package:appvantai_mobile/feature/auth/data/auth_repository.dart';
import 'package:appvantai_mobile/feature/auth/domain/auth_models.dart';
import 'package:appvantai_mobile/feature/order/data/order_repository.dart';
import 'package:appvantai_mobile/feature/trip/data/trip_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_order_repository.dart';
import '../../helpers/fake_trip_repository.dart';

/// Nav audit 2026-09-12 — không dead end, deep link an toàn:
///  - deep link sai vai trò → đưa về home (không vào màn hình gọi API 403)
///  - deep link /otp thiếu phone → về login (trước đây crash cast null)
///  - deep link không khớp route → màn "Không tìm thấy trang" có nút về home
///  - màn mở bằng deep link (stack rỗng) vẫn có nút back hoạt động
///  - validate địa chỉ hiện khi gõ và tự mất khi đủ 3 ký tự

/// Bootstrap cần `me()` trả user (FakeAuthRepository.me mặc định unimplemented).
class _AuthRepo extends FakeAuthRepository {
  @override
  Future<AuthUser> me() async => currentUser;
}

const _driverVehicle = VehicleProfile(
  vehicleType: 'truck',
  licensePlate: '29C-123.45',
  capacityKg: 5000,
  lengthCm: 620,
  widthCm: 220,
  heightCm: 220,
  operatingArea: 'HN-HP',
);

Future<FakeOrderRepository> _pumpLoggedIn(
  WidgetTester tester, {
  required String role,
  String name = 'Nguyễn Văn A',
}) async {
  final orders = FakeOrderRepository();
  final auth = _AuthRepo()
    ..currentUser = AuthUser(
      id: 'u1',
      name: name,
      phone: '0912345678',
      role: role,
      status: 'active',
      vehicle: role == 'driver' ? _driverVehicle : null,
      legalConsentAt: DateTime.now(),
    );
  SharedPreferences.setMockInitialValues({'auth_token': 'fake-token'});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        orderRepositoryProvider.overrideWithValue(orders),
        tripRepositoryProvider.overrideWithValue(FakeTripRepository()),
      ],
      child: const App(),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
  return orders;
}

/// Deep link: đổi location của router đang chạy (mô phỏng mở link ngoài app).
Future<void> _deepLink(WidgetTester tester, String location) async {
  final ctx = tester.element(find.byType(Scaffold).first);
  GoRouter.of(ctx).go(location);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('chủ hàng deep link vào route tài xế (/trips/new) → bị đưa về home',
      (tester) async {
    await _pumpLoggedIn(tester, role: 'customer');
    expect(find.text('Xin chào, Nguyễn Văn A'), findsOneWidget);

    await _deepLink(tester, '/trips/new');

    expect(find.text('Tạo chuyến đi'), findsNothing);
    expect(find.text('Xin chào, Nguyễn Văn A'), findsOneWidget);
  });

  testWidgets('tài xế deep link vào danh sách đơn (/orders) → về home', (tester) async {
    await _pumpLoggedIn(tester, role: 'driver', name: 'Tài Xế A');
    expect(find.text('Xin chào, Tài Xế A'), findsOneWidget);

    await _deepLink(tester, '/orders');

    expect(find.text('Đơn hàng của tôi'), findsNothing);
    expect(find.text('Xin chào, Tài Xế A'), findsOneWidget);
  });

  testWidgets('tài xế VẪN mở được chi tiết đơn /orders/:id (radar dùng route này)',
      (tester) async {
    final orders = await _pumpLoggedIn(tester, role: 'driver', name: 'Tài Xế A');
    orders.seedAccepted('o1');

    await _deepLink(tester, '/orders/o1');

    expect(find.text('Chi tiết đơn hàng'), findsOneWidget);
  });

  testWidgets('tài xế mở chi tiết đơn posted: KHÔNG thấy "Hủy đơn hàng" (quyền chủ hàng)',
      (tester) async {
    final orders = await _pumpLoggedIn(tester, role: 'driver', name: 'Tài Xế A');
    orders.orders.add(FakeTripRepository.emptyOrder('o1')); // status posted

    await _deepLink(tester, '/orders/o1');

    expect(find.text('Chi tiết đơn hàng'), findsOneWidget);
    expect(find.text('Hủy đơn hàng'), findsNothing);
  });

  testWidgets('chủ hàng mở chi tiết đơn posted: CÓ nút "Hủy đơn hàng"', (tester) async {
    final orders = await _pumpLoggedIn(tester, role: 'customer');
    orders.orders.add(FakeTripRepository.emptyOrder('o2'));

    await _deepLink(tester, '/orders/o2');

    expect(find.text('Hủy đơn hàng'), findsOneWidget);
  });

  testWidgets('deep link /otp thiếu phone → về login (không crash)', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_AuthRepo()),
          orderRepositoryProvider.overrideWithValue(FakeOrderRepository()),
        ],
        child: const App(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Gửi mã OTP'), findsOneWidget);

    await _deepLink(tester, '/otp');

    expect(find.text('Xác thực OTP'), findsNothing);
    expect(find.text('Gửi mã OTP'), findsOneWidget);
  });

  testWidgets('deep link không khớp route → "Không tìm thấy trang" + về được home',
      (tester) async {
    await _pumpLoggedIn(tester, role: 'customer');

    await _deepLink(tester, '/duong-dan-khong-ton-tai');

    expect(find.text('Không tìm thấy trang'), findsOneWidget);
    expect(find.textContaining('GoException'), findsNothing);

    await tester.tap(find.text('Về trang chủ'));
    await tester.pumpAndSettle();
    expect(find.text('Xin chào, Nguyễn Văn A'), findsOneWidget);
  });

  testWidgets('màn mở bằng deep link (stack rỗng) vẫn có nút back hoạt động',
      (tester) async {
    await _pumpLoggedIn(tester, role: 'customer');

    await _deepLink(tester, '/orders');
    expect(find.text('Đơn hàng của tôi'), findsOneWidget);

    // Stack rỗng → AppBar mặc định sẽ ẩn nút back (dead end). SafeBackButton
    // vẫn hiện và đưa user về fallback.
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('Xin chào, Nguyễn Văn A'), findsOneWidget);
  });

  testWidgets('validate địa chỉ: hiện lỗi khi gõ, tự mất khi đủ 3 ký tự', (tester) async {
    await _pumpLoggedIn(tester, role: 'customer');
    await _deepLink(tester, '/orders/new');
    expect(find.text('Tạo đơn hàng'), findsOneWidget);

    final pickup = find.byWidgetPredicate(
      (w) => w is TextField && (w.decoration?.labelText ?? '').contains('điểm lấy'),
    );
    expect(pickup, findsOneWidget);
    await tester.enterText(pickup, 'H');
    await tester.pumpAndSettle();
    expect(find.text('Nhập địa chỉ ít nhất 3 ký tự'), findsOneWidget);

    await tester.enterText(pickup, 'Hà Nội');
    await tester.pumpAndSettle();
    expect(find.text('Nhập địa chỉ ít nhất 3 ký tự'), findsNothing);
  });

  testWidgets('home hiển thị đúng vai trò admin (không còn hiện "Chủ hàng")', (tester) async {
    await _pumpLoggedIn(tester, role: 'admin', name: 'Quản Trị Viên');

    expect(find.text('Quản trị'), findsOneWidget);
    expect(find.text('Chủ hàng'), findsNothing);
    // Admin không có màn "đơn của tôi" (backend customer-only) → không có nút
    // dẫn vào danh sách rỗng / form tạo đơn 403.
    expect(find.text('Đơn hàng của tôi'), findsNothing);
    expect(find.textContaining('Màn quản trị trong app chưa có'), findsOneWidget);
  });

  testWidgets('admin deep link vào /orders → về home (không vào màn rỗng + FAB 403)',
      (tester) async {
    await _pumpLoggedIn(tester, role: 'admin', name: 'Quản Trị Viên');

    await _deepLink(tester, '/orders');

    expect(find.text('Đơn hàng của tôi'), findsNothing);
    expect(find.text('Quản trị'), findsOneWidget);
  });

  testWidgets('admin VẪN mở được chi tiết đơn (/orders/:id — backend cho admin xem)',
      (tester) async {
    final orders = await _pumpLoggedIn(tester, role: 'admin', name: 'Quản Trị Viên');
    orders.orders.add(FakeTripRepository.emptyOrder('o9'));

    await _deepLink(tester, '/orders/o9');

    expect(find.text('Chi tiết đơn hàng'), findsOneWidget);
  });
}

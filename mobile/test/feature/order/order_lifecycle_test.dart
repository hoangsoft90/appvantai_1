import 'dart:async';

import 'package:appvantai_mobile/app/app.dart';
import 'package:appvantai_mobile/feature/auth/data/auth_repository.dart';
import 'package:appvantai_mobile/feature/auth/domain/auth_models.dart';
import 'package:appvantai_mobile/feature/order/data/order_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_order_repository.dart';
import '../../helpers/onboarding_helper.dart';

/// FakeAuthRepository.me() mặc định ném UnimplementedError — bootstrap cần
/// me() trả về user để vào thẳng app từ token đã lưu.
class _AuthRepo extends FakeAuthRepository {
  @override
  Future<AuthUser> me() async => currentUser;
}

Future<void> _login(WidgetTester tester, FakeAuthRepository auth, FakeOrderRepository orders) async {
  SharedPreferences.setMockInitialValues({'auth_token': 'fake-token'});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        orderRepositoryProvider.overrideWithValue(orders),
      ],
      child: const App(),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
  // Đã có token → bootstrap /me → onboarding (name rỗng)
  await submitOnboarding(tester);
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('driver: accepted → pickup → in_transit → delivered (đúng 1 nút mỗi state)', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final auth = _AuthRepo()
      ..currentUser = const AuthUser(
        id: 'u-driver',
        name: '',
        phone: '0911111101',
        role: 'driver',
        status: 'active',
      );
    final orders = FakeOrderRepository();
    // Preset token để bootstrap /me vào thẳng onboarding (không qua login)
    SharedPreferences.setMockInitialValues({'auth_token': 'fake-token'});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          orderRepositoryProvider.overrideWithValue(orders),
        ],
        child: const App(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    // Chọn vai trò Tài xế trước khi Tiếp tục (onboarding gửi role theo segment)
    await tester.tap(find.text('Tài xế'));
    await tester.pumpAndSettle();
    await submitOnboarding(tester);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    // Driver bị redirect về /vehicle (chưa khai xe) — điền form.
    // (index 0=biển số, 1=tải trọng, 2=dài, 3=rộng, 4=cao — dropdown không phải TextFormField;
    // ô chiều rỗng bị _intOf chặn 'không hợp lệ' nên phải điền đủ)
    expect(find.text('Thông tin xe'), findsOneWidget);
    final vehicleFields = find.byType(TextFormField);
    await tester.enterText(vehicleFields.at(0), '29A-12345');
    await tester.enterText(vehicleFields.at(1), '5000');
    await tester.enterText(vehicleFields.at(2), '620');
    await tester.enterText(vehicleFields.at(3), '220');
    await tester.enterText(vehicleFields.at(4), '220');
    final saveBtn = find.widgetWithText(FilledButton, 'Hoàn tất');
    await tester.ensureVisible(saveBtn);
    await tester.pumpAndSettle();
    await tester.tap(saveBtn);
    await tester.pumpAndSettle();

    // Seed đơn đã accept RỒI rebuild — cùng ProviderScope, cùng 2 instance fake.
    orders.seedAccepted('o1');
    await tester.pumpAndSettle();

    Future<void> openDetail() async {
      // Đi THẲNG route chi tiết đơn (focus test = lifecycle buttons trên detail).
      // Nav audit 2026-09-12: danh sách /orders là màn của chủ hàng — tài xế bị
      // redirect về /home, nên tài xế chỉ vào được chi tiết qua /orders/:id
      // (đúng như radar/match card mở chi tiết đơn).
      final ctx = tester.element(find.byType(Scaffold).first);
      GoRouter.of(ctx).go('/orders/o1');
      await tester.pumpAndSettle();
    }

    // accepted → nút "Đã lấy hàng"
    await openDetail();
    expect(find.text('Đã nhận'), findsOneWidget);
    expect(find.text('Đã lấy hàng'), findsOneWidget);
    expect(find.text('Bắt đầu giao'), findsNothing);

    await tester.tap(find.text('Đã lấy hàng'));
    await tester.pumpAndSettle();
    // exact match: chip trạng thái (toast "Đã lấy hàng — Đang lấy hàng" là chuỗi khác)
    expect(find.text('Đang lấy hàng'), findsOneWidget);

    // pickup → nút "Bắt đầu giao"
    expect(find.text('Bắt đầu giao'), findsOneWidget);
    expect(find.text('Đã lấy hàng'), findsNothing);
    await tester.tap(find.text('Bắt đầu giao'));
    await tester.pumpAndSettle();
    expect(find.text('Đang vận chuyển'), findsOneWidget);

    // in_transit → nút "Đã giao hàng"
    expect(find.text('Đã giao hàng'), findsOneWidget);
    await tester.tap(find.text('Đã giao hàng'));
    await tester.pumpAndSettle();
    expect(find.text('Đã giao'), findsOneWidget);

    // delivered: driver KHÔNG còn nút lifecycle nào (customer mới complete)
    expect(find.text('Xác nhận hoàn tất'), findsNothing);
    expect(find.text('Đã lấy hàng'), findsNothing);
  });

  testWidgets('customer: delivered → Xác nhận hoàn tất → completed; không có nút sai state', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final auth = _AuthRepo();
    final orders = FakeOrderRepository()..seedDelivered('o2');
    await _login(tester, auth, orders);

    // Tạo xong thì nằm ở home — vào danh sách đơn
    await tester.tap(find.text('Đơn hàng của tôi'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('KCN Quế Võ'));
    await tester.pumpAndSettle();

    expect(find.text('Đã giao'), findsOneWidget);
    expect(find.text('Xác nhận hoàn tất'), findsOneWidget);
    // Không hiện nút sai state: cancel đã hết, không có nút driver
    expect(find.text('Hủy đơn hàng'), findsNothing);
    expect(find.text('Đã lấy hàng'), findsNothing);

    await tester.tap(find.text('Xác nhận hoàn tất'));
    await tester.pumpAndSettle();
    // exact match: chip trạng thái (toast + section tài xế là chuỗi khác)
    expect(find.text('Hoàn thành'), findsOneWidget);
    // completed: terminal — không còn nút lifecycle nào
    expect(find.text('Xác nhận hoàn tất'), findsNothing);
  });

  testWidgets('bấm liên tục không crash — action biến mất khi state đã chuyển', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final auth = _AuthRepo();
    final orders = FakeOrderRepository()..seedDelivered('o3');
    await _login(tester, auth, orders);

    await tester.tap(find.text('Đơn hàng của tôi'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('KCN Quế Võ'));
    await tester.pumpAndSettle();

    // plan4_final §4.1: giữ request đầu pending (mạng chậm) — các tap trong
    // window đó phải bị flag _processing chặn → fake chỉ nhận ĐÚNG 1 request.
    orders.transitionGate = Completer<void>();
    await tester.tap(find.text('Xác nhận hoàn tất'), warnIfMissed: false);
    await tester.pump(); // request đang bay, nút disable
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.text('Xác nhận hoàn tất'), warnIfMissed: false);
    await tester.tap(find.text('Xác nhận hoàn tất'), warnIfMissed: false);
    expect(orders.transitionCallCount, 1); // double-tap bị chặn — không spam
    orders.transitionGate!.complete(); // thả request đầu hoàn tất
    await tester.pumpAndSettle();
    expect(find.text('Hoàn thành'), findsOneWidget);
    expect(orders.transitionCallCount, 1);
  });
}

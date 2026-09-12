import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../feature/auth/application/auth_controller.dart';
import '../../feature/auth/domain/auth_models.dart';
import '../../feature/auth/presentation/screens/login_screen.dart';
import '../../feature/auth/presentation/screens/otp_screen.dart';
import '../../feature/home/presentation/screens/home_screen.dart';
import '../../feature/identity/presentation/screens/onboarding_screen.dart';
import '../../feature/identity/presentation/screens/profile_screen.dart';
import '../../feature/identity/presentation/screens/vehicle_form_screen.dart';
import '../../feature/legal/presentation/screens/legal_docs.dart';
import '../../feature/order/presentation/screens/order_detail_screen.dart';
import '../../feature/order/presentation/screens/order_form_screen.dart';
import '../../feature/order/presentation/screens/order_list_screen.dart';
import '../../feature/trip/presentation/screens/trip_form_screen.dart';
import '../../feature/trip/presentation/screens/trip_matches_screen.dart';
import '../../feature/trip/presentation/screens/trip_run_screen.dart';
import 'safe_nav.dart';

/// Nơi user "bắt buộc phải ở" theo trạng thái auth:
///  - chưa đăng nhập → /login
///  - name rỗng (chưa onboarding) → /onboarding
///  - driver chưa khai xe → /vehicle
///  - còn lại → /home
String? _landing(AuthState? auth) {
  if (auth is! AuthAuthenticated) return '/login';
  final user = auth.user;
  if (user.needsOnboarding) return '/onboarding';
  if (user.isDriver && user.vehicle == null) return '/vehicle';
  return '/home';
}

/// Router duy nhất. Redirect dựa trên AuthState (single source of truth).
///
/// QUAN TRỌNG: không refresh router trên mọi thay đổi auth state —
/// GoRouter.refresh() re-parse theo URL và XÓA stack push (go_router 16),
/// làm hỏng luồng /profile → /vehicle (pop "nothing to pop").
/// Chỉ notify khi _landing() thay đổi (login/logout/onboarding/xe đầu tiên);
/// sửa tên hoặc sửa xe (không đổi target) giữ nguyên navigation.
final routerProvider = Provider<GoRouter>((ref) {
  final initialAuth =
      ref.read(authControllerProvider).value ?? const AuthUnauthenticated();
  final authNotifier = ValueNotifier<AuthState>(initialAuth);

  ref.listen(authControllerProvider, (prev, next) {
    if (_landing(prev?.value) != _landing(next.value)) {
      authNotifier.value = next.value ?? const AuthUnauthenticated();
    }
  });

  return GoRouter(
    initialLocation: '/home',
    refreshListenable: authNotifier,
    // Deep link không khớp route nào → màn hình tiếng Việt có nút về home
    // (mặc định go_router chỉ hiện "Page Not Found: GoException ...").
    errorBuilder: (context, state) => RouteNotFoundScreen(uri: state.uri.toString()),
    redirect: (context, state) {
      final auth = authNotifier.value;
      final loggedIn = auth is AuthAuthenticated;
      final location = state.matchedLocation;
      final onAuthPage = location == '/login' || location == '/otp';
      // Phase 7 §7.5: legal docs là trang public — đọc được cả khi chưa đăng nhập.
      final onLegalPage = location.startsWith('/legal/');

      if (!loggedIn && !onAuthPage && !onLegalPage) return '/login';
      if (loggedIn && onAuthPage) return _landing(auth)!;

      // Deep link thẳng vào /otp mà không kèm phone (state.extra) → không có
      // gì để xác thực (trước đây cast cứng `extra as String` gây crash).
      if (location == '/otp' && state.extra is! String) return '/login';

      if (loggedIn) {
        final user = auth.user;
        final onOnboarding = location == '/onboarding';
        if (user.needsOnboarding && !onOnboarding) return '/onboarding';
        if (!user.needsOnboarding && onOnboarding) return _landing(auth)!;

        final isDriver = user.isDriver;
        final hasVehicle = user.vehicle != null;
        final onVehicle = location == '/vehicle';
        // Bắt buộc khai xe cho tài xế mới; customer không nên ở màn xe.
        // (Khi tài xế đã có xe, /vehicle là chế độ sửa — không redirect đi.)
        if (isDriver && !hasVehicle && !onVehicle) return '/vehicle';
        if (!isDriver && onVehicle) return _landing(auth)!;

        // Nav audit 2026-09-12: route thuộc vai trò khác thì đưa về home —
        // không để deep link dẫn user vào màn hình gọi API chắc chắn 403.
        //  - /orders (danh sách) + /orders/new: chỉ chủ hàng (POST /orders
        //    requireRole customer; list là "đơn của tôi" nên vô nghĩa với
        //    tài xế/admin — để vào chỉ thấy danh sách rỗng + nút tạo đơn 403).
        //  - /orders/:id (chi tiết): tài xế VẪN vào được — radar (match card)
        //    mở chi tiết đơn để chạy lifecycle pickup → in_transit → delivered;
        //    admin cũng vào được (worker `assertOrderViewAccess` cho admin).
        //  - /trips*: chỉ tài xế.
        final onOrdersList = location == '/orders' || location == '/orders/new';
        final onTrips = location == '/trips' || location.startsWith('/trips/');
        if (!user.hasOrdersRole && onOrdersList) return '/home';
        if (!isDriver && onTrips) return '/home';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/otp',
        builder: (context, state) => OtpScreen(
          // Deep link không kèm extra → redirect về /login (xem redirect ở trên).
          phone: state.extra is String ? state.extra! as String : '',
        ),
      ),
      // Phase 7 §7.5 — legal docs: đọc được từ login (chưa login) và profile.
      GoRoute(
        path: '/legal/terms',
        builder: (context, state) => const TermsOfServiceScreen(),
      ),
      GoRoute(
        path: '/legal/privacy',
        builder: (context, state) => const PrivacyPolicyScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      // Không truyền vehicle qua state.extra: VehicleFormScreen tự đọc từ
      // AuthController (single source of truth) — tránh cast lỗi khi
      // redirect rebuild route với extra không đúng kiểu (go_router 16).
      GoRoute(
        path: '/vehicle',
        builder: (context, state) => const VehicleFormScreen(),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/profile',
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: '/orders',
        builder: (context, state) => const OrderListScreen(),
        routes: [
          GoRoute(
            path: 'new',
            builder: (context, state) => const OrderFormScreen(),
          ),
          GoRoute(
            path: ':orderId',
            builder: (context, state) =>
                OrderDetailScreen(orderId: state.pathParameters['orderId']!),
          ),
        ],
      ),
      GoRoute(
        path: '/trips/new',
        builder: (context, state) => const TripFormScreen(),
      ),
      GoRoute(
        path: '/trips/:tripId/matches',
        builder: (context, state) => TripMatchesScreen(
          tripId: state.pathParameters['tripId']!,
        ),
      ),
      GoRoute(
        path: '/trips/:tripId/run',
        builder: (context, state) => TripRunScreen(
          tripId: state.pathParameters['tripId']!,
        ),
      ),
    ],
  );
});
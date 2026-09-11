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
    redirect: (context, state) {
      final auth = authNotifier.value;
      final loggedIn = auth is AuthAuthenticated;
      final location = state.matchedLocation;
      final onAuthPage = location == '/login' || location == '/otp';
      // Phase 7 §7.5: legal docs là trang public — đọc được cả khi chưa đăng nhập.
      final onLegalPage = location.startsWith('/legal/');

      if (!loggedIn && !onAuthPage && !onLegalPage) return '/login';
      if (loggedIn && onAuthPage) return _landing(auth)!;

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
        builder: (context, state) => OtpScreen(phone: state.extra as String),
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
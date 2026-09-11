import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../feature/auth/application/auth_controller.dart';
import '../shared/widgets/splash_screen.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authAsync = ref.watch(authControllerProvider);

    // Gate: đợi bootstrap auth (đọc token + /me) xong mới mount router,
    // tránh redirect flicker; splash không bao giờ kẹt vô hạn (plan §26).
    if (authAsync.isLoading) {
      return MaterialApp(
        title: AppConfig.appName,
        theme: AppTheme.light(),
        debugShowCheckedModeBanner: false,
        home: const SplashScreen(),
      );
    }

    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: AppConfig.appName,
      theme: AppTheme.light(),
      debugShowCheckedModeBanner: false,
      routerConfig: router,
    );
  }
}
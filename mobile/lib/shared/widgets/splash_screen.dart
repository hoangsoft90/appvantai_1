import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';

/// Hiển thị trong lúc AuthController build (đọc token + /me).
/// Đảm bảo không có "infinite loading": luôn có kết quả hoặc chuyển màn hình.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.local_shipping, size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(AppConfig.appName, style: theme.textTheme.titleLarge),
            const SizedBox(height: 32),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../auth/application/auth_controller.dart';
import '../../../auth/domain/auth_models.dart';
import '../../../../shared/widgets/banner_ad_widget.dart';

/// Màn hình chính (Phase 1: hiển thị hồ sơ + điều hướng).
/// Phase 2+: đơn hàng (customer) / Phase 3+: radar matches (driver, plan §4.1).
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final auth = ref.watch(authControllerProvider).value;
    if (auth is! AuthAuthenticated) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final user = auth.user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('App Vận Tải'),
        actions: [
          IconButton(
            tooltip: 'Hồ sơ',
            icon: const Icon(Icons.person_outline),
            onPressed: () => context.push('/profile'),
          ),
          IconButton(
            tooltip: 'Đăng xuất',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.radar, size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                'Xin chào, ${user.name.isEmpty ? user.phone : user.name}',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Chip(
                avatar: Icon(
                  user.isDriver ? Icons.local_shipping : Icons.inventory_2_outlined,
                  size: 18,
                ),
                label: Text(user.isDriver ? 'Tài xế' : 'Chủ hàng'),
              ),
              const SizedBox(height: 16),
              Text(
                user.isDriver
                    ? 'Nhập tuyến đường của bạn, chúng tôi sẽ quét mối hàng tiện đường (radar).'
                    : 'Đăng hàng hoặc theo dõi đơn hàng của bạn.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
              ),
              const SizedBox(height: 16),
              if (user.isDriver)
                FilledButton.icon(
                  onPressed: () => context.push('/trips/new'),
                  icon: const Icon(Icons.radar),
                  label: const Text('Tôi đang chạy — quét radar'),
                )
              else
                FilledButton.icon(
                  onPressed: () => context.push('/orders'),
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: const Text('Đơn hàng của tôi'),
                ),
            ],
          ),
        ),
      ),
      // AdMob banner (test/real theo flag TEST_ADS) — ẩn khi debug/test env.
      bottomNavigationBar: const BannerAdWidget(),
    );
  }
}
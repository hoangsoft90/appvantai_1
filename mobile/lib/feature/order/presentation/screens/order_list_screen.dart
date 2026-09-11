import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/widgets/async_view.dart';
import '../../../../shared/widgets/empty_view.dart';
import '../../application/order_list_controller.dart';
import '../../domain/order_models.dart';
import '../widgets/order_card.dart';

/// Danh sách đơn hàng của tôi (Loading/Error/Retry/Empty — plan §26).
class OrderListScreen extends ConsumerWidget {
  const OrderListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(orderListControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Đơn hàng của tôi')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/orders/new'),
        icon: const Icon(Icons.add),
        label: const Text('Tạo đơn'),
      ),
      body: AsyncView<List<CargoOrder>>(
        value: ordersAsync,
        onRetry: () => ref.invalidate(orderListControllerProvider),
        builder: (orders) {
          if (orders.isEmpty) {
            return EmptyView(
              message: 'Chưa có đơn hàng nào.\nBấm "Tạo đơn" để đăng mối hàng đầu tiên.',
              icon: Icons.inventory_2_outlined,
              actionLabel: 'Tạo đơn',
              onAction: () => context.push('/orders/new'),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(orderListControllerProvider),
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: orders.length,
              itemBuilder: (context, i) => OrderCard(
                order: orders[i],
                onTap: () => context.push('/orders/${orders[i].id}'),
              ),
            ),
          );
        },
      ),
    );
  }
}
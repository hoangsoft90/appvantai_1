import 'package:flutter/material.dart';

import '../../../../core/utils/formatters.dart';
import '../../domain/order_models.dart';

/// Card tóm tắt đơn hàng cho danh sách (plan §4.1 — pickup→delivery, tải trọng, giá, trạng thái).
class OrderCard extends StatelessWidget {
  const OrderCard({super.key, required this.order, this.onTap});

  final CargoOrder order;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = order.status == 'posted' || order.status == 'matched';
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          active ? Icons.local_shipping : Icons.inventory_2_outlined,
          color: active ? theme.colorScheme.primary : theme.colorScheme.outline,
        ),
        title: Text(
          '${order.pickupAddress.isEmpty ? 'Lấy hàng' : order.pickupAddress}'
          ' → '
          '${order.deliveryAddress.isEmpty ? 'Giao hàng' : order.deliveryAddress}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${order.weightKg} kg • ${orderStatusLabel(order.status)} • ${formatDateTime(order.pickupFrom)}',
        ),
        trailing: Text(
          formatVnd(order.price),
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
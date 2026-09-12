import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/router/safe_nav.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/services/api_exception.dart';
import '../../../../shared/widgets/async_view.dart';
import '../../../auth/application/auth_controller.dart';
import '../../../auth/domain/auth_models.dart';
import '../../../identity/domain/vehicle_types.dart';
import '../../../safety/data/safety_repository.dart';
import '../../../safety/domain/safety_models.dart';
import '../../application/driver_distance_provider.dart';
import '../../application/order_detail_provider.dart';
import '../../application/order_list_controller.dart';
import '../../data/order_repository.dart';
import '../../domain/order_models.dart';

/// Chi tiết đơn hàng.
/// - Customer: hủy đơn (posted/matched/contacted) + report/block tài xế (nếu đã accept)
/// - Driver: xem trạng thái đơn đã nhận
/// plan4_final §4.1: ConsumerStatefulWidget + flag `_processing` — mỗi
/// lifecycle/cancel action chỉ gửi 1 request tại một thời điểm (disable nút
/// + loading trong lúc chờ, tránh spam khi mạng chậm).
class OrderDetailScreen extends ConsumerStatefulWidget {
  const OrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends ConsumerState<OrderDetailScreen> {
  /// plan4_final §4.1: true khi đang chờ 1 lifecycle/cancel request —
  /// double-tap trong lúc đó bị bỏ qua, nút disable + spinner.
  bool _processing = false;

  String get orderId => widget.orderId;

  Future<void> _confirmCancel(BuildContext context, WidgetRef ref, CargoOrder order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hủy đơn hàng?'),
        content: const Text('Đơn hàng sẽ chuyển sang trạng thái "Đã hủy" và không còn hiển thị cho tài xế.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Không')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('Hủy đơn'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    if (_processing) return; // plan4_final §4.1 — chặn double-tap
    setState(() => _processing = true);
    try {
      await ref.read(orderRepositoryProvider).cancelOrder(order.id);
      ref.invalidate(orderListControllerProvider);
      // Hủy xong: pop về danh sách nếu đang có stack, ngược lại (deep link)
      // điều hướng về /orders — không để user ở lại màn đơn đã hủy.
      if (context.mounted) backOrGo(context, '/orders');
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  /// Chạy 1 bước lifecycle (plan3 Mục 2) — loading + toast kết quả,
  /// refresh provider sau khi thành công. Không crash khi bấm liên tục
  /// (nút đang loading thì vô hiệu; lỗi backend chỉ hiện SnackBar).
  Future<void> _runLifecycle(
    BuildContext context,
    WidgetRef ref,
    CargoOrder order,
    NextLifecycleAction action,
  ) async {
    if (_processing) return; // plan4_final §4.1 — chặn double-tap
    setState(() => _processing = true);
    try {
      final updated =
          await ref.read(orderRepositoryProvider).transitionOrder(order.id, action.method);
      ref.invalidate(orderDetailProvider(order.id));
      ref.invalidate(orderListControllerProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('${action.label} — ${orderStatusLabel(updated.status)}')));
      }
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  /// Menu report/block cho customer khi đơn đã có tài xế (Phase 5 §18).
  Future<void> _showSafetyActions(
    BuildContext context,
    WidgetRef ref,
    CargoOrder order,
    String driverId,
  ) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.report_outlined),
              title: const Text('Báo cáo tài xế'),
              subtitle: const Text('Spam, thông tin giả, lừa đảo...'),
              onTap: () => Navigator.pop(ctx, 'report'),
            ),
            ListTile(
              leading: const Icon(Icons.block_outlined),
              title: const Text('Chặn tài xế'),
              subtitle: const Text('Không còn nhìn thấy nhau trên app'),
              onTap: () => Navigator.pop(ctx, 'block'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;

    final repo = ref.read(safetyRepositoryProvider);
    try {
      if (action == 'report') {
        final reason = await showDialog<String>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: const Text('Lý do báo cáo'),
            children: [
              for (final entry in reportReasonLabels.entries)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, entry.key),
                  child: Text(entry.value),
                ),
            ],
          ),
        );
        if (reason == null || !context.mounted) return;
        await repo.reportUser(
          targetUserId: driverId,
          reason: reason,
          orderId: order.id,
        );
      } else {
        await repo.blockUser(driverId);
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(action == 'report' ? 'Đã gửi báo cáo, admin sẽ xem xét' : 'Đã chặn tài xế')),
      );
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final orderAsync = ref.watch(orderDetailProvider(orderId));
    return Scaffold(
      appBar: AppBar(
        leading: const SafeBackButton(fallback: '/orders'),
        title: const Text('Chi tiết đơn hàng'),
      ),
      body: AsyncView<CargoOrder>(
        value: orderAsync,
        onRetry: () => ref.invalidate(orderDetailProvider(orderId)),
        builder: (order) {
          final theme = Theme.of(context);
          final auth = ref.watch(authControllerProvider).value;
          final currentUser = auth is AuthAuthenticated ? auth.user : null;
          final isCustomer = currentUser?.role == 'customer';
          final isDriver = currentUser?.role == 'driver';
          // Hủy đơn là quyền của CHỦ HÀNG (worker `lifecycle.ts` RULES.cancel
          // actor: customer). Tài xế mở chi tiết đơn từ radar KHÔNG được thấy
          // nút này — bấm vào chỉ nhận 403 (nav audit 2026-09-12).
          final canCancel = isCustomer && canCancelOrder(order.status);
          final showSafety = isCustomer && order.hasDriver;
          // plan3 Mục 2: mỗi trạng thái chỉ hiện đúng 1 action hợp lệ.
          final lifecycle = nextLifecycleAction(status: order.status, isDriver: isDriver);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Chip(
                    label: Text(orderStatusLabel(order.status)),
                    backgroundColor: canCancel
                        ? theme.colorScheme.primaryContainer
                        : theme.colorScheme.surfaceContainerHighest,
                  ),
                  const Spacer(),
                  Text(
                    formatVnd(order.price),
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // plan2_final §14: không hiện tọa độ thô cho user — chỉ địa chỉ.
              _section(theme, 'Điểm lấy hàng', order.pickupAddress, ''),
              _section(theme, 'Điểm giao hàng', order.deliveryAddress, ''),
              _section(theme, 'Hàng hóa',
                  '${cargoTypeLabel(order.cargoType)} • ${order.weightKg} kg',
                  order.lengthCm + order.widthCm + order.heightCm > 0
                      ? '${order.lengthCm} × ${order.widthCm} × ${order.heightCm} cm'
                      : ''),
              _section(theme, 'Yêu cầu xe',
                  order.vehicleRequirement == 'any' ? 'Xe bất kỳ' : vehicleTypeLabel(order.vehicleRequirement),
                  ''),
              _section(theme, 'Thời gian lấy hàng',
                  '${formatDateTime(order.pickupFrom)} → ${formatDateTime(order.pickupTo)}',
                  ''),
              if (order.notes.isNotEmpty) _section(theme, 'Ghi chú', order.notes, ''),
              // Phase 4: đơn đã accept → customer thấy tài xế cách bao xa (privacy §13)
              if (order.status == 'accepted') ...[
                _DriverDistanceTile(orderId: order.id),
                const SizedBox(height: 8),
              ],
              // Phase 5: đơn đã có tài xế → customer thấy trạng thái + report/block (§18)
              if (showSafety) ...[
                _section(theme, 'Tài xế',
                    'Đã nhận chuyến — trạng thái ${orderStatusLabel(order.status)}',
                    ''),
                OutlinedButton.icon(
                  onPressed: () => _showSafetyActions(context, ref, order, order.driverId!),
                  icon: const Icon(Icons.flag_outlined),
                  label: const Text('Báo cáo / Chặn tài xế'),
                ),
                const SizedBox(height: 16),
              ],
              // plan3 Mục 2 — driver: Đã lấy hàng / Bắt đầu giao / Đã giao hàng;
              // customer: Xác nhận hoàn tất (khi 'delivered').
              if (lifecycle != null)
                FilledButton.icon(
                  // plan4_final §4.1: disable + spinner khi đang chờ request.
                  onPressed:
                      _processing ? null : () => _runLifecycle(context, ref, order, lifecycle),
                  icon: _processing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.local_shipping_outlined),
                  label: Text(lifecycle.label),
                ),
              if (canCancel)
                OutlinedButton.icon(
                  onPressed: _processing ? null : () => _confirmCancel(context, ref, order),
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Hủy đơn hàng'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                    side: BorderSide(color: theme.colorScheme.error),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _section(ThemeData theme, String label, String value, String sub) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.outline)),
              const SizedBox(height: 4),
              Text(value, style: theme.textTheme.bodyLarge),
              if (sub.isNotEmpty) Text(sub, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      );
}

/// Hiển thị khoảng cách ẩn danh của tài xế (Phase 4 — privacy §13:
/// chỉ "cách ~X km", không bao giờ tọa độ chính xác).
class _DriverDistanceTile extends ConsumerWidget {
  const _DriverDistanceTile({required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final distance = ref.watch(driverDistanceProvider(orderId));
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.gps_fixed),
        title: distance.when(
          loading: () => const Text('Đang xác định vị trí tài xế...'),
          error: (e, _) => const Text('Chưa có vị trí tài xế'),
          data: (d) {
            if (d.distanceKm == null) {
              return const Text('Tài xế chưa bật định vị');
            }
            return Text(
              'Tài xế đang cách điểm lấy khoảng ${d.distanceKm!.toStringAsFixed(1)} km',
            );
          },
        ),
        subtitle: const Text('Vị trí ẩn danh — bảo mật theo chính sách'),
        trailing: IconButton(
          tooltip: 'Làm mới',
          icon: const Icon(Icons.refresh),
          onPressed: () => ref.invalidate(driverDistanceProvider(orderId)),
        ),
      ),
    );
  }
}
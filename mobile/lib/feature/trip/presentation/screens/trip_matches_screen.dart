import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../shared/services/api_exception.dart';
import '../../../../shared/widgets/async_view.dart';
import '../../../order/data/order_repository.dart';
import '../../../order/domain/order_models.dart';
import '../../application/trip_controller.dart';
import '../../domain/trip_models.dart';

/// Màn hình "quét radar" (plan §4.1): danh sách mối hàng tiện đường
/// sắp theo score, kèm lý do giải thích (§4.2 — không trả số mà không giải thích).
class TripMatchesScreen extends ConsumerWidget {
  const TripMatchesScreen({super.key, required this.tripId});

  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matches = ref.watch(tripMatchesProvider(tripId));
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mối hàng tiện đường'),
        actions: [
          IconButton(
            tooltip: 'Quét lại',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(tripMatchesProvider(tripId)),
          ),
          IconButton(
            tooltip: 'Bắt đầu chuyến (GPS)',
            icon: const Icon(Icons.play_circle_outline),
            onPressed: () => context.push('/trips/$tripId/run'),
          ),
        ],
      ),
      body: AsyncView(
        value: matches,
        onRetry: () => ref.invalidate(tripMatchesProvider(tripId)),
        builder: (list) {
          if (list.isEmpty) {
            // plan3 Mục 4 — Empty state có gợi ý hành động, không để màn trống.
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const SizedBox(height: 48),
                Icon(Icons.radar, size: 64, color: theme.colorScheme.outline),
                const SizedBox(height: 16),
                Text(
                  'Chưa có mối phù hợp trên tuyến này',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Thử các gợi ý sau để tăng cơ hội bắt mối:',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.u_turn_left),
                        title: const Text('Khai báo chiều về'),
                        subtitle: const Text('Thêm chuyến ngược chiều để bắt hàng chiều về'),
                        onTap: () => context.push('/trips/new'),
                      ),
                      ListTile(
                        leading: const Icon(Icons.schedule),
                        title: const Text('Mở rộng thời gian lấy hàng'),
                        subtitle: const Text('Đơn có khung giờ rộng dễ khớp hơn'),
                        onTap: () => context.push('/trips'),
                      ),
                      ListTile(
                        leading: const Icon(Icons.refresh),
                        title: const Text('Quét lại radar'),
                        subtitle: const Text('Mối hàng mới có thể vừa đăng'),
                        onTap: () => ref.invalidate(tripMatchesProvider(tripId)),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }
          return RefreshIndicator(
            onRefresh: () async =>
                ref.invalidate(tripMatchesProvider(tripId)),
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: list.length,
              itemBuilder: (context, i) => _MatchCard(match: list[i]),
            ),
          );
        },
      ),
    );
  }
}

class _MatchCard extends ConsumerStatefulWidget {
  const _MatchCard({required this.match});

  final MatchResult match;

  @override
  ConsumerState<_MatchCard> createState() => _MatchCardState();
}

class _MatchCardState extends ConsumerState<_MatchCard> {
  ContactInfo? _contactInfo;
  bool _contacting = false;
  bool _accepting = false;

  MatchResult get match => widget.match;

  Future<void> _contact(OrderRepository repo, CargoOrder order) async {
    setState(() => _contacting = true);
    try {
      final info = await repo.contact(order.id);
      if (!mounted) return;
      // Tắt spinner TRƯỚC khi mở dialog — nếu không CircularProgressIndicator
      // chạy vô hạn làm pumpAndSettle (test) treo và UX kẹt.
      setState(() {
        _contactInfo = info;
        _contacting = false;
      });
      // Hiện số điện thoại chủ hàng (§17) — không public trước khi contact (§18)
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Liên hệ chủ hàng'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(info.name),
              const SizedBox(height: 8),
              SelectableText(info.phone, style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text('Gọi điện hoặc nhắn để thống nhất nhận chuyến.',
                  style: Theme.of(ctx).textTheme.bodySmall),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
          ],
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _contacting = false);
    }
  }

  Future<void> _accept(OrderRepository repo, CargoOrder order) async {
    setState(() => _accepting = true);
    try {
      await repo.accept(order.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bạn đã nhận chuyến! Chủ hàng sẽ thấy bạn.')),
      );
      // Làm mới matches để trạng thái cập nhật (đơn không còn nhận accept nữa)
      ref.invalidate(tripMatchesProvider);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final order = match.order;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Score badge — tròn, màu theo độ tốt
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _scoreColor(match.score),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${match.score}',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cargoTypeLabel(order.cargoType),
                        style: theme.textTheme.titleMedium,
                      ),
                      Text(
                        '${formatVnd(order.price)} · ${order.weightKg} kg',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Chi tiết đơn hàng',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => context.push('/orders/${order.id}'),
                ),
              ],
            ),
            const Divider(height: 16),
            _Row(icon: Icons.trip_origin, text: order.pickupAddress),
            _Row(icon: Icons.location_on, text: order.deliveryAddress),
            const SizedBox(height: 8),
            // plan3 Mục 4 — hàng stats đọc trong < 3 giây: khỏi tuyến · detour · khối lượng
            Row(
              children: [
                _Stat(
                  label: 'Khỏi tuyến',
                  value: match.pickupKm != null
                      ? '${match.pickupKm!.toStringAsFixed(1)} km'
                      : '—',
                ),
                const SizedBox(width: 16),
                _Stat(
                  label: 'Độ lệch',
                  value: match.detourKm != null ? '${match.detourKm!.toStringAsFixed(1)} km' : '—',
                ),
                const SizedBox(width: 16),
                _Stat(label: 'Khối lượng', value: '${order.weightKg} kg'),
              ],
            ),
            const SizedBox(height: 8),
            // Reasons (plan §4.2) — vì sao mối này hợp tuyến, tối đa 5 lý do ngắn
            ...match.reasons.take(5).map(
              (r) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_circle_outline,
                        size: 16, color: theme.colorScheme.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(r, style: theme.textTheme.bodySmall),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _contacting
                        ? null
                        : () => _contact(
                            ref.read(orderRepositoryProvider), order),
                    icon: _contacting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.call_outlined, size: 18),
                    label: Text(
                      _contactInfo != null
                          ? 'Đã liên hệ (${_contactInfo!.phone})'
                          : 'Liên hệ chủ hàng',
                    ),
                  ),
                ),
                if (order.canAccept) ...[const SizedBox(width: 8)],
                if (order.canAccept)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _accepting
                          ? null
                          : () => _accept(
                              ref.read(orderRepositoryProvider), order),
                      icon: _accepting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check_circle_outline, size: 18),
                      label: Text(order.hasDriver ? 'Đã nhận' : 'Nhận chuyến'),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      'Trạng thái: ${orderStatusLabel(order.status)}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => context.push('/orders/${order.id}'),
              child: const Text('Xem chi tiết đơn hàng'),
            ),
          ],
        ),
      ),
    );
  }

  Color _scoreColor(int score) {
    if (score >= 85) return Colors.green;
    if (score >= 70) return Colors.orange;
    return Colors.blueGrey;
  }
}

/// Một ô stat nhỏ trên match card (plan3 Mục 4).
class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline)),
        Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Theme.of(context).colorScheme.outline),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
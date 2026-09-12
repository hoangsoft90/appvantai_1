import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/safe_nav.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/services/location_service.dart';
import '../../application/trip_controller.dart';
import '../../application/trip_run_controller.dart';

/// Màn hình "Đang chạy" (Phase 4 — plan §13).
/// Bấm Bắt đầu → xin quyền GPS → gửi vị trí mỗi 30s → Bấm Kết thúc.
class TripRunScreen extends ConsumerStatefulWidget {
  const TripRunScreen({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<TripRunScreen> createState() => _TripRunScreenState();
}

class _TripRunScreenState extends ConsumerState<TripRunScreen> {
  bool _starting = false;
  bool _ending = false;
  bool _running = false;
  bool _endPending = false; // plan2_final §6.2: end fail → hiện "chưa sync"
  String? _permissionWarning; // plan4_final §4.4: active mà thiếu quyền vị trí

  @override
  void initState() {
    super.initState();
    // §6.3 + plan4_final §4.4: app reopen → reconcile với server. Trip active
    // → resume GPS (chip "Đang chạy" + nút Kết thúc); thiếu quyền → báo rõ;
    // ended → GPS local dừng; planned → giữ nút Bắt đầu.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final result =
          await ref.read(tripRunControllerProvider(widget.tripId).notifier).reconcile();
      if (!mounted) return;
      setState(() {
        switch (result) {
          case ReconcileResult.activeResumed:
            _running = true;
            _endPending = false;
          case ReconcileResult.activeNoPermission:
            _running = true; // server vẫn đang chạy chuyến
            _permissionWarning =
                'Chuyến đang chạy nhưng thiếu quyền vị trí — cấp quyền để GPS tiếp tục';
          case ReconcileResult.ended:
            _running = false;
            _endPending = false;
          case ReconcileResult.planned || ReconcileResult.unknown:
            break; // giữ state hiện tại
        }
      });
    });
  }

  Future<void> _start() async {
    setState(() => _starting = true);
    try {
      await ref.read(tripRunControllerProvider(widget.tripId).notifier).start();
      if (!mounted) return;
      setState(() {
        _running = true;
        _endPending = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chuyến đã bắt đầu — GPS đang hoạt động')),
      );
    } on LocationPermissionDenied {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cần quyền truy cập vị trí để chạy chuyến')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không thể bắt đầu: $e')),
      );
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  /// plan2_final §6.2: end API fail → KHÔNG rời màn hình, KHÔNG đánh dấu kết thúc.
  /// Giữ trạng thái "chưa sync" + cho retry (nút Kết thúc vẫn hiện).
  Future<void> _end() async {
    setState(() => _ending = true);
    final synced =
        await ref.read(tripRunControllerProvider(widget.tripId).notifier).end();
    if (!mounted) return;
    setState(() {
      _ending = false;
      if (!synced) {
        _endPending = true;
      } else {
        _running = false;
        _endPending = false;
      }
    });
    if (!synced) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chưa sync được với máy chủ — GPS đã tắt, vui lòng thử lại'),
        ),
      );
      return;
    }
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tripAsync = ref.watch(tripDetailProvider(widget.tripId));
    // Watch để giữ controller alive — nếu chỉ read, Riverpod dispose provider
    // khi màn hình rời build → "Ref disposed" khi gọi start()/end().
    ref.watch(tripRunControllerProvider(widget.tripId));

    return Scaffold(
      appBar: AppBar(
        leading: const SafeBackButton(fallback: '/home'),
        title: const Text('Chuyến của tôi'),
      ),
      body: tripAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (trip) {
          final running = _running;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // plan4_final §4.4: trip active nhưng thiếu quyền vị trí → báo rõ,
              // không để server active mà UI im lặng không gửi GPS.
              if (_permissionWarning != null)
                Card(
                  color: theme.colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(Icons.location_disabled, size: 20),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_permissionWarning!)),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              // plan2_final §6.2: UI cho biết trip chưa sync sau khi end fail.
              if (_endPending)
                Card(
                  color: theme.colorScheme.errorContainer,
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(Icons.sync_problem, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Chuyến chưa được kết thúc trên máy chủ — bấm "Kết thúc chuyến" để thử lại',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Đi từ', style: theme.textTheme.labelMedium),
                      // plan2_final §14: fallback không hiện tọa độ thô.
                      Text(trip.originAddress.isEmpty ? '(không có địa chỉ)' : trip.originAddress),
                      const SizedBox(height: 8),
                      Text('Đến', style: theme.textTheme.labelMedium),
                      Text(trip.destinationAddress.isEmpty ? '(không có địa chỉ)' : trip.destinationAddress),
                      const SizedBox(height: 12),
                      Text(
                        'Quãng đường: ${(trip.distanceM / 1000).toStringAsFixed(1)} km · ${formatDateTime(trip.createdAt)}',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      Chip(
                        avatar: Icon(
                          running ? Icons.gps_fixed : Icons.gps_off,
                          size: 18,
                        ),
                        label: Text(
                          running
                              ? 'Đang chạy — GPS bật (30s/lần)'
                              : 'Chưa bắt đầu — GPS tắt',
                        ),
                        backgroundColor: running
                            ? theme.colorScheme.primaryContainer
                            : theme.colorScheme.surfaceContainerHighest,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (!running)
                FilledButton.icon(
                  onPressed: _starting ? null : _start,
                  icon: _starting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow),
                  label: Text(_starting ? 'Đang bắt đầu...' : 'Bắt đầu chuyến'),
                )
              else
                OutlinedButton.icon(
                  onPressed: _ending ? null : _end,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                    side: BorderSide(color: theme.colorScheme.error),
                  ),
                  icon: _ending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.stop),
                  label: Text(_ending ? 'Đang kết thúc...' : 'Kết thúc chuyến'),
                ),
            ],
          );
        },
      ),
    );
  }
}
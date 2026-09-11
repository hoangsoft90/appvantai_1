import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/order_repository.dart';

part 'driver_distance_provider.g.dart';

/// Khoảng cách ẩn danh của tài xế (Phase 4 — privacy §13).
/// Chỉ chủ hàng của đơn đã accept gọi được; null khi tài xế chưa bật GPS.
/// Refresh: `ref.invalidate(driverDistanceProvider(orderId))`.
@riverpod
Future<DriverDistance> driverDistance(Ref ref, String orderId) {
  return ref.watch(orderRepositoryProvider).driverDistance(orderId);
}
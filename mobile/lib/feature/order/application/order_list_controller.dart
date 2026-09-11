import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/order_repository.dart';
import '../domain/order_models.dart';

part 'order_list_controller.g.dart';

/// Danh sách đơn hàng của user hiện tại.
/// Retry/refresh: gọi `ref.invalidate(orderListControllerProvider)`.
@riverpod
class OrderListController extends _$OrderListController {
  @override
  Future<List<CargoOrder>> build() {
    return ref.watch(orderRepositoryProvider).listOrders();
  }
}
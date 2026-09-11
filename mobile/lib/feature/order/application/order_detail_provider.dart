import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/order_repository.dart';
import '../domain/order_models.dart';

part 'order_detail_provider.g.dart';

@riverpod
Future<CargoOrder> orderDetail(Ref ref, String orderId) {
  return ref.watch(orderRepositoryProvider).getOrder(orderId);
}
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/services/api_client.dart';
import '../../../shared/services/api_exception.dart';
import '../domain/order_models.dart';

/// Repository đơn hàng (Phase 2 — /orders/*).
class OrderRepository {
  OrderRepository(this._api);

  final ApiClient _api;

  Future<List<CargoOrder>> listOrders() async {
    try {
      final res = await _api.dio.get('/orders');
      final data = (res.data as Map<String, dynamic>?) ?? const {};
      final list = (data['orders'] as List<dynamic>?) ?? const [];
      return list
          .whereType<Map<String, dynamic>>()
          .map(CargoOrder.fromJson)
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<CargoOrder> createOrder(OrderDraft draft) async {
    try {
      final res = await _api.dio.post('/orders', data: draft.toJson());
      final data = (res.data as Map<String, dynamic>?) ?? const {};
      return CargoOrder.fromJson((data['order'] as Map<String, dynamic>?) ?? const {});
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<CargoOrder> getOrder(String id) async {
    try {
      final res = await _api.dio.get('/orders/$id');
      final data = (res.data as Map<String, dynamic>?) ?? const {};
      return CargoOrder.fromJson((data['order'] as Map<String, dynamic>?) ?? const {});
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<CargoOrder> cancelOrder(String id) async {
    try {
      final res = await _api.dio.post('/orders/$id/cancel');
      final data = (res.data as Map<String, dynamic>?) ?? const {};
      return CargoOrder.fromJson((data['order'] as Map<String, dynamic>?) ?? const {});
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// POST /orders/:id/{pickup|in-transit|delivered|complete} — lifecycle
  /// (plan3 Mục 2). Backend trả `{ data: { order, status } }`.
  Future<CargoOrder> transitionOrder(String id, String method) async {
    try {
      final res = await _api.dio.post('/orders/$id/$method');
      final data = (res.data as Map<String, dynamic>?) ?? const {};
      return CargoOrder.fromJson(
        ((data['data'] as Map<String, dynamic>?)?['order'] as Map<String, dynamic>?) ??
            const {},
     );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// POST /orders/:id/contact — driver liên hệ chủ hàng (Phase 5 §17).
  /// Trả về thông tin liên hệ (số điện thoại chủ hàng sau khi contact).
  Future<ContactInfo> contact(String id) async {
    try {
      final res = await _api.dio.post('/orders/$id/contact');
      final data = (res.data as Map<String, dynamic>?) ?? const {};
      return ContactInfo.fromJson(
        (data['data'] as Map<String, dynamic>?) ?? const {},
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// POST /orders/:id/accept — Atomic Accept (Phase 5 §10).
  /// Backend đảm bảo chỉ 1 driver thắng race; lỗi ORDER_ALREADY_ACCEPTED
  /// được map thành ApiException để UI hiển thị.
  Future<void> accept(String id) async {
    try {
      await _api.dio.post('/orders/$id/accept');
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// GET /orders/:id/driver-location — khoảng cách ẩn danh từ điểm lấy
  /// (Phase 4, privacy §13). Không bao giờ trả tọa độ chính xác.
  Future<DriverDistance> driverDistance(String id) async {
    try {
      final res = await _api.dio.get('/orders/$id/driver-location');
      final data = (res.data as Map<String, dynamic>?) ?? const {};
      return DriverDistance.fromJson(
        (data['data'] as Map<String, dynamic>?) ?? const {},
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

/// Khoảng cách ẩn danh từ điểm lấy (privacy §13) — customer thấy trên đơn.
class DriverDistance {
  const DriverDistance({this.distanceKm, this.updatedAt});

  factory DriverDistance.fromJson(Map<String, dynamic> json) => DriverDistance(
        distanceKm: (json['distance_km'] as num?)?.toDouble(),
        updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? ''),
      );

  final double? distanceKm;
  final DateTime? updatedAt;
}

/// Thông tin liên hệ trả về sau khi driver bấm "Liên hệ" (§17).
class ContactInfo {
  const ContactInfo({
    required this.orderId,
    required this.status,
    required this.phone,
    required this.name,
  });

  factory ContactInfo.fromJson(Map<String, dynamic> json) => ContactInfo(
        orderId: (json['order_id'] as String?) ?? '',
        status: (json['status'] as String?) ?? 'contacted',
        phone: (json['phone'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
      );

  final String orderId;
  final String status;
  final String phone;
  final String name;
}

final orderRepositoryProvider = Provider<OrderRepository>(
  (ref) => OrderRepository(ref.watch(apiClientProvider)),
);
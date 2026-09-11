import 'dart:async';

import 'package:appvantai_mobile/feature/order/data/order_repository.dart';
import 'package:appvantai_mobile/feature/order/domain/order_models.dart';

/// Fake order repository (in-memory, không cần Dio).
class FakeOrderRepository implements OrderRepository {
  final orders = <CargoOrder>[];
  int _seq = 0;

  /// plan4_final §4.1: đếm số lần lifecycle/cancel được gọi — test double-tap
  /// dùng để khẳng định UI chỉ gửi ĐÚNG 1 request dù bấm nhiều lần.
  int transitionCallCount = 0;
  int cancelCallCount = 0;

  /// plan4_final §4.1: khi được set, [transitionOrder] chờ gate này trước khi
  /// trả kết quả — mô phỏng mạng chậm để test thấy đúng window _processing
  /// (fake trả ngay thì window đóng giữa 2 tap, không đo được lock).
  Completer<void>? transitionGate;

  @override
  Future<List<CargoOrder>> listOrders() async => List.of(orders);

  @override
  Future<CargoOrder> createOrder(OrderDraft draft) async {
    final order = CargoOrder(
      id: 'o${++_seq}',
      pickupLat: draft.pickupLat,
      pickupLng: draft.pickupLng,
      pickupAddress: draft.pickupAddress,
      deliveryLat: draft.deliveryLat,
      deliveryLng: draft.deliveryLng,
      deliveryAddress: draft.deliveryAddress,
      cargoType: draft.cargoType,
      weightKg: draft.weightKg,
      lengthCm: draft.lengthCm,
      widthCm: draft.widthCm,
      heightCm: draft.heightCm,
      vehicleRequirement: draft.vehicleRequirement,
      pickupFrom: draft.pickupFrom,
      pickupTo: draft.pickupTo,
      price: draft.price,
      notes: draft.notes,
      status: 'posted',
      expiresAt: draft.pickupTo,
    );
    orders.insert(0, order);
    return order;
  }

  @override
  Future<CargoOrder> getOrder(String id) async =>
      orders.firstWhere((o) => o.id == id, orElse: () => throw StateError('not found'));

  @override
  Future<CargoOrder> cancelOrder(String id) async {
    cancelCallCount++;
    final i = orders.indexWhere((o) => o.id == id);
    final old = orders[i];
    final updated = CargoOrder(
      id: old.id,
      pickupLat: old.pickupLat,
      pickupLng: old.pickupLng,
      pickupAddress: old.pickupAddress,
      deliveryLat: old.deliveryLat,
      deliveryLng: old.deliveryLng,
      deliveryAddress: old.deliveryAddress,
      cargoType: old.cargoType,
      weightKg: old.weightKg,
      lengthCm: old.lengthCm,
      widthCm: old.widthCm,
      heightCm: old.heightCm,
      vehicleRequirement: old.vehicleRequirement,
      pickupFrom: old.pickupFrom,
      pickupTo: old.pickupTo,
      price: old.price,
      notes: old.notes,
      status: 'cancelled',
      expiresAt: old.expiresAt,
    );
    orders[i] = updated;
    return updated;
  }

  /// Đảm bảo có order với [id] — match card trên radar tạo CargoOrder mới
  /// độc lập với repo đơn hàng, nên contact/accept có thể gặp order lạ.
  CargoOrder _ensure(String id) {
    final i = orders.indexWhere((o) => o.id == id);
    if (i >= 0) return orders[i];
    final created = CargoOrder(
      id: id,
      pickupLat: 20.99,
      pickupLng: 105.99,
      pickupAddress: 'KCN Quế Võ, Bắc Ninh',
      deliveryLat: 20.87,
      deliveryLng: 106.64,
      deliveryAddress: 'KCN Đình Vũ, Hải Phòng',
      cargoType: 'general',
      weightKg: 800,
      lengthCm: 300,
      widthCm: 200,
      heightCm: 180,
      vehicleRequirement: 'truck',
      pickupFrom: DateTime.now().add(const Duration(hours: 6)),
      pickupTo: DateTime.now().add(const Duration(hours: 18)),
      price: 1200000,
      notes: '',
      status: 'posted',
      expiresAt: DateTime.now().add(const Duration(hours: 18)),
    );
    orders.add(created);
    return created;
  }

  @override
  Future<ContactInfo> contact(String id) async {
    final old = _ensure(id);
    final i = orders.indexWhere((o) => o.id == id);
    final updated = CargoOrder(
      id: old.id,
      pickupLat: old.pickupLat,
      pickupLng: old.pickupLng,
      pickupAddress: old.pickupAddress,
      deliveryLat: old.deliveryLat,
      deliveryLng: old.deliveryLng,
      deliveryAddress: old.deliveryAddress,
      cargoType: old.cargoType,
      weightKg: old.weightKg,
      lengthCm: old.lengthCm,
      widthCm: old.widthCm,
      heightCm: old.heightCm,
      vehicleRequirement: old.vehicleRequirement,
      pickupFrom: old.pickupFrom,
      pickupTo: old.pickupTo,
      price: old.price,
      notes: old.notes,
      status: 'contacted',
      expiresAt: old.expiresAt,
    );
    orders[i] = updated;
    return const ContactInfo(
      orderId: '',
      status: 'contacted',
      phone: '0912000001',
      name: 'Chủ Hàng',
    );
  }

  @override
  Future<void> accept(String id) async {
    final old = _ensure(id);
    final i = orders.indexWhere((o) => o.id == id);
    orders[i] = CargoOrder(
      id: old.id,
      driverId: 'd1',
      pickupLat: old.pickupLat,
      pickupLng: old.pickupLng,
      pickupAddress: old.pickupAddress,
      deliveryLat: old.deliveryLat,
      deliveryLng: old.deliveryLng,
      deliveryAddress: old.deliveryAddress,
      cargoType: old.cargoType,
      weightKg: old.weightKg,
      lengthCm: old.lengthCm,
      widthCm: old.widthCm,
      heightCm: old.heightCm,
      vehicleRequirement: old.vehicleRequirement,
      pickupFrom: old.pickupFrom,
      pickupTo: old.pickupTo,
      price: old.price,
      notes: old.notes,
      status: 'accepted',
      expiresAt: old.expiresAt,
    );
  }

  /// Lifecycle transition giả — đi theo state machine backend (plan3 Mục 2):
  /// accepted→pickup→in_transit→delivered→completed, driver_id = 'd1'.
  @override
  Future<CargoOrder> transitionOrder(String id, String method) async {
    transitionCallCount++;
    if (transitionGate != null) await transitionGate!.future;
    const next = {
      'pickup': 'pickup',
      'in-transit': 'in_transit',
      'delivered': 'delivered',
      'complete': 'completed',
    };
    final target = next[method];
    if (target == null) throw StateError('unknown method: $method');
    final i = orders.indexWhere((o) => o.id == id);
    final old = orders[i];
    final updated = CargoOrder(
      id: old.id,
      driverId: old.driverId ?? 'd1',
      pickupLat: old.pickupLat,
      pickupLng: old.pickupLng,
      pickupAddress: old.pickupAddress,
      deliveryLat: old.deliveryLat,
      deliveryLng: old.deliveryLng,
      deliveryAddress: old.deliveryAddress,
      cargoType: old.cargoType,
      weightKg: old.weightKg,
      lengthCm: old.lengthCm,
      widthCm: old.widthCm,
      heightCm: old.heightCm,
      vehicleRequirement: old.vehicleRequirement,
      pickupFrom: old.pickupFrom,
      pickupTo: old.pickupTo,
      price: old.price,
      notes: old.notes,
      status: target,
      expiresAt: old.expiresAt,
    );
    orders[i] = updated;
    return updated;
  }

  /// Copy helper cho seed/transition (tránh lặp 20 trường).
  CargoOrder _copy(CargoOrder o, {String? status, String? driverId}) => CargoOrder(
        id: o.id,
        driverId: driverId ?? o.driverId,
        pickupLat: o.pickupLat,
        pickupLng: o.pickupLng,
        pickupAddress: o.pickupAddress,
        deliveryLat: o.deliveryLat,
        deliveryLng: o.deliveryLng,
        deliveryAddress: o.deliveryAddress,
        cargoType: o.cargoType,
        weightKg: o.weightKg,
        lengthCm: o.lengthCm,
        widthCm: o.widthCm,
        heightCm: o.heightCm,
        vehicleRequirement: o.vehicleRequirement,
        pickupFrom: o.pickupFrom,
        pickupTo: o.pickupTo,
        price: o.price,
        notes: o.notes,
        status: status ?? o.status,
        expiresAt: o.expiresAt,
      );

  /// Seed đơn đã accept (driver test lifecycle — plan3 Mục 2).
  void seedAccepted(String id) {
    _ensure(id);
    final i = orders.indexWhere((o) => o.id == id);
    orders[i] = _copy(orders[i], status: 'accepted', driverId: 'd1');
  }

  /// Seed đơn đã delivered (customer test hoàn tất — plan3 Mục 2).
  void seedDelivered(String id) {
    _ensure(id);
    final i = orders.indexWhere((o) => o.id == id);
    orders[i] = _copy(orders[i], status: 'delivered', driverId: 'd1');
  }

  /// Khoảng cách ẩn danh — cấu hình qua [driverDistanceResult].
  DriverDistance driverDistanceResult =
      const DriverDistance(distanceKm: 2.3, updatedAt: null);

  @override
  Future<DriverDistance> driverDistance(String id) async => driverDistanceResult;
}
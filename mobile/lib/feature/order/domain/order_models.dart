// Domain entities cho đơn hàng (Phase 2 — Marketplace).

/// Trạng thái đơn hàng (plan §9) — khớp worker migration 0003.
const orderStatusLabels = <String, String>{
  'posted': 'Đang chờ',
  'matched': 'Đã ghép',
  'contacted': 'Đã liên hệ',
  'accepted': 'Đã nhận',
  'pickup': 'Đang lấy hàng',
  'in_transit': 'Đang vận chuyển',
  'delivered': 'Đã giao',
  'completed': 'Hoàn thành',
  'cancelled': 'Đã hủy',
  'expired': 'Hết hạn',
  'rejected': 'Từ chối',
};

String orderStatusLabel(String status) => orderStatusLabels[status] ?? status;

/// Trạng thái có thể hủy trên UI — plan3 Mục 2: nút Hủy chỉ khi còn cho phép
/// (posted/matched/contacted). Backend vẫn chặn theo state machine của nó.
bool canCancelOrder(String status) =>
    status == 'posted' || status == 'matched' || status == 'contacted';

/// Hành động lifecycle tiếp theo cho 1 đơn theo vai trò (plan3 Mục 2).
///  - Driver:   accepted→pickup, pickup→in_transit, in_transit→delivered.
///  - Customer: delivered→complete.
/// Trả null khi không có action hợp lệ → UI ẩn nút (không hiện nút sai state).
class NextLifecycleAction {
  const NextLifecycleAction({required this.method, required this.label});

  /// Đoạn path của endpoint: pickup | in-transit | delivered | complete.
  final String method;

  /// Nhãn tiếng Việt cho nút — không dùng tên state kỹ thuật.
  final String label;
}

NextLifecycleAction? nextLifecycleAction({
  required String status,
  required bool isDriver,
}) {
  if (isDriver) {
    switch (status) {
      case 'accepted':
        return const NextLifecycleAction(
            method: 'pickup', label: 'Đã lấy hàng');
      case 'pickup':
        return const NextLifecycleAction(
            method: 'in-transit', label: 'Bắt đầu giao');
      case 'in_transit':
        return const NextLifecycleAction(
            method: 'delivered', label: 'Đã giao hàng');
    }
  } else if (status == 'delivered') {
    return const NextLifecycleAction(
        method: 'complete', label: 'Xác nhận hoàn tất');
  }
  return null;
}

const cargoTypeLabels = <String, String>{
  'general': 'Hàng thường',
  'food': 'Thực phẩm',
  'fragile': 'Hàng dễ vỡ',
  'furniture': 'Nội thất',
  'electronics': 'Điện tử',
  'building': 'Vật liệu xây dựng',
  'other': 'Khác',
};

String cargoTypeLabel(String type) => cargoTypeLabels[type] ?? type;

class CargoOrder {
  const CargoOrder({
    required this.id,
    this.driverId,
    required this.pickupLat,
    required this.pickupLng,
    required this.pickupAddress,
    required this.deliveryLat,
    required this.deliveryLng,
    required this.deliveryAddress,
    required this.cargoType,
    required this.weightKg,
    required this.lengthCm,
    required this.widthCm,
    required this.heightCm,
    required this.vehicleRequirement,
    required this.pickupFrom,
    required this.pickupTo,
    required this.price,
    required this.notes,
    required this.status,
    required this.expiresAt,
  });

  factory CargoOrder.fromJson(Map<String, dynamic> json) => CargoOrder(
        id: (json['id'] as String?) ?? '',
        driverId: json['driver_id'] as String?,
        pickupLat: (json['pickup_lat'] as num?)?.toDouble() ?? 0,
        pickupLng: (json['pickup_lng'] as num?)?.toDouble() ?? 0,
        pickupAddress: (json['pickup_address'] as String?) ?? '',
        deliveryLat: (json['delivery_lat'] as num?)?.toDouble() ?? 0,
        deliveryLng: (json['delivery_lng'] as num?)?.toDouble() ?? 0,
        deliveryAddress: (json['delivery_address'] as String?) ?? '',
        cargoType: (json['cargo_type'] as String?) ?? 'general',
        weightKg: (json['weight_kg'] as num?)?.toInt() ?? 0,
        lengthCm: (json['length_cm'] as num?)?.toInt() ?? 0,
        widthCm: (json['width_cm'] as num?)?.toInt() ?? 0,
        heightCm: (json['height_cm'] as num?)?.toInt() ?? 0,
        vehicleRequirement: (json['vehicle_requirement'] as String?) ?? 'any',
        pickupFrom: DateTime.parse(json['pickup_from'] as String),
        pickupTo: DateTime.parse(json['pickup_to'] as String),
        price: (json['price'] as num?)?.toInt() ?? 0,
        notes: (json['notes'] as String?) ?? '',
        status: (json['status'] as String?) ?? 'posted',
        expiresAt: DateTime.parse(json['expires_at'] as String),
      );

  final String id;

  /// Driver đã nhận đơn (null khi chưa) — Phase 5 Atomic Accept (§10).
  final String? driverId;
  final double pickupLat;
  final double pickupLng;
  final String pickupAddress;
  final double deliveryLat;
  final double deliveryLng;
  final String deliveryAddress;
  final String cargoType;
  final int weightKg;
  final int lengthCm;
  final int widthCm;
  final int heightCm;
  final String vehicleRequirement;
  final DateTime pickupFrom;
  final DateTime pickupTo;
  final int price;
  final String notes;
  final String status;
  final DateTime expiresAt;

  bool get hasDriver => driverId != null && driverId!.isNotEmpty;

  /// Đơn còn nhận liên hệ (driver) — Phase 5.
  bool get canContact => status == 'posted' || status == 'matched';

  /// Đơn còn nhận accept.
  bool get canAccept =>
      status == 'posted' || status == 'matched' || status == 'contacted';
}

/// Input form tạo đơn (chưa có id/status — backend tự gán).
class OrderDraft {
  const OrderDraft({
    required this.pickupLat,
    required this.pickupLng,
    required this.pickupAddress,
    required this.deliveryLat,
    required this.deliveryLng,
    required this.deliveryAddress,
    required this.cargoType,
    required this.weightKg,
    required this.lengthCm,
    required this.widthCm,
    required this.heightCm,
    required this.vehicleRequirement,
    required this.pickupFrom,
    required this.pickupTo,
    required this.price,
    required this.notes,
  });

  final double pickupLat;
  final double pickupLng;
  final String pickupAddress;
  final double deliveryLat;
  final double deliveryLng;
  final String deliveryAddress;
  final String cargoType;
  final int weightKg;
  final int lengthCm;
  final int widthCm;
  final int heightCm;
  final String vehicleRequirement;
  final DateTime pickupFrom;
  final DateTime pickupTo;
  final int price;
  final String notes;

  Map<String, dynamic> toJson() => {
        'pickup_lat': pickupLat,
        'pickup_lng': pickupLng,
        'pickup_address': pickupAddress,
        'delivery_lat': deliveryLat,
        'delivery_lng': deliveryLng,
        'delivery_address': deliveryAddress,
        'cargo_type': cargoType,
        'weight_kg': weightKg,
        'length_cm': lengthCm,
        'width_cm': widthCm,
        'height_cm': heightCm,
        'vehicle_requirement': vehicleRequirement,
        'pickup_from': pickupFrom.toUtc().toIso8601String(),
        'pickup_to': pickupTo.toUtc().toIso8601String(),
        'price': price,
        'notes': notes,
      };
}
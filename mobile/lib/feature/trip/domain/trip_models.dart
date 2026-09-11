// Domain entities cho chuyến + kết quả matching (Phase 3 — Maps + Matching).

import '../../order/domain/order_models.dart';

const tripStatusLabels = <String, String>{
  'planned': 'Đã lên kế hoạch',
  'active': 'Đang chạy',
  'ended': 'Đã kết thúc',
  'cancelled': 'Đã hủy',
};

String tripStatusLabel(String status) => tripStatusLabels[status] ?? status;

/// Chuyến của tài xế (worker: trips). Route đã được OSRM tính + lưu polyline.
class Trip {
  const Trip({
    required this.id,
    required this.originLat,
    required this.originLng,
    required this.originAddress,
    required this.destinationLat,
    required this.destinationLng,
    required this.destinationAddress,
    required this.distanceM,
    required this.durationS,
    required this.status,
    required this.createdAt,
  });

  factory Trip.fromJson(Map<String, dynamic> json) => Trip(
        id: (json['id'] as String?) ?? '',
        originLat: (json['origin_lat'] as num?)?.toDouble() ?? 0,
        originLng: (json['origin_lng'] as num?)?.toDouble() ?? 0,
        originAddress: (json['origin_address'] as String?) ?? '',
        destinationLat: (json['destination_lat'] as num?)?.toDouble() ?? 0,
        destinationLng: (json['destination_lng'] as num?)?.toDouble() ?? 0,
        destinationAddress: (json['destination_address'] as String?) ?? '',
        distanceM: (json['distance_m'] as num?)?.toInt() ?? 0,
        durationS: (json['duration_s'] as num?)?.toInt() ?? 0,
        status: (json['status'] as String?) ?? 'planned',
        createdAt:
            DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      );

  final String id;
  final double originLat;
  final double originLng;
  final String originAddress;
  final double destinationLat;
  final double destinationLng;
  final String destinationAddress;
  final int distanceM;
  final int durationS;
  final String status;
  final DateTime createdAt;
}

/// Một kết quả matching (worker: MatchResult) — score + lý do giải thích (§4.2).
class MatchResult {
  const MatchResult({
    required this.score,
    required this.detourKm,
    required this.pickupKm,
    required this.reasons,
    required this.order,
  });

  factory MatchResult.fromJson(Map<String, dynamic> json) => MatchResult(
        score: (json['score'] as num?)?.toInt() ?? 0,
        detourKm: (json['detour_km'] as num?)?.toDouble(),
        // plan4_final §4.3: nullable — KHÔNG default 0 để tránh hiện "0.0 km"
        // giả khi backend thiếu field. UI hiển thị "—" khi null.
        pickupKm: (json['pickup_km'] as num?)?.toDouble(),
        reasons: ((json['reasons'] as List<dynamic>?) ?? const [])
            .whereType<String>()
            .toList(),
        order: CargoOrder.fromJson(
            (json['order'] as Map<String, dynamic>?) ?? const {}),
      );

  final int score;
  final double? detourKm;

  /// Khoảng cách điểm lấy hàng khỏi tuyến (km) — plan3 Mục 4: stat trên card.
  /// null = backend không trả field (hiển thị "—", không nói dối "0 km").
  final double? pickupKm;
  final List<String> reasons;
  final CargoOrder order;
}

/// Form tạo chuyến (tài xế nhập điểm đi → điểm đến).
class TripDraft {
  const TripDraft({
    required this.fromLat,
    required this.fromLng,
    required this.fromAddress,
    required this.toLat,
    required this.toLng,
    required this.toAddress,
    this.tripType = 'one_way',
  });

  final double fromLat;
  final double fromLng;
  final String fromAddress;
  final double toLat;
  final double toLng;
  final String toAddress;

  /// 'one_way' | 'return' — return = xe rỗng lúc đi, tìm hàng cho chặng về
  /// (plan2_final §4.1; plan3 Mục 4: empty state gợi ý khai chiều về).
  final String tripType;

  Map<String, dynamic> toJson() => {
        'from_lat': fromLat,
        'from_lng': fromLng,
        'from_address': fromAddress,
        'to_lat': toLat,
        'to_lng': toLng,
        'to_address': toAddress,
        'trip_type': tripType,
      };
}
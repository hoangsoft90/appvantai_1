import 'package:appvantai_mobile/feature/order/domain/order_models.dart';
import 'package:appvantai_mobile/feature/trip/data/trip_repository.dart';
import 'package:appvantai_mobile/feature/trip/domain/trip_models.dart';
import 'package:appvantai_mobile/shared/services/api_exception.dart';

/// Fake trip repository (in-memory, không cần Dio).
/// createTrip tạo chuyến với id tăng dần; findMatches trả về
/// danh sách match cấu hình trước (mặc định 1 match score 92).
class FakeTripRepository implements TripRepository {
  final trips = <Trip>[];
  final matchesByTrip = <String, List<MatchResult>>{};
  int _seq = 0;


  /// Đơn mẫu cho test match card (plan3 Mục 4) — id khác nhau mỗi lần gọi.
  static CargoOrder emptyOrder(String id) => CargoOrder(
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

  /// Match mặc định nếu chưa cấu hình riêng.
  List<MatchResult> get defaultMatches => [
        MatchResult(
          score: 92,
          detourKm: 3.4,
          pickupKm: 1.2, // null khi backend không trả — UI hiển thị '—'
          reasons: const [
            'Điểm lấy cách tuyến 1.2 km',
            'Điểm giao cùng hướng tuyến',
            'Phù hợp yêu cầu xe truck',
            'Đủ tải trọng (800 kg)',
            'Thời gian lấy hàng phù hợp',
            'Độ lệch tuyến chỉ 3.4 km',
          ],
          order: CargoOrder(
            id: 'm1',
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
          ),
        ),
      ];

  /// Geocode giả (plan2_final §5.1) — trả điểm cố định theo từ khóa.
  GeocodeResult? Function(String query)? onGeocode;

  @override
  Future<GeocodeResult> geocode(String query) async {
    final custom = onGeocode?.call(query);
    if (custom != null) return custom;
    if (query.toLowerCase().contains('hà nội') || query.toLowerCase().contains('hanoi')) {
      return const GeocodeResult(lat: 21.0285, lng: 105.8542, label: 'Hà Nội, Việt Nam');
    }
    if (query.toLowerCase().contains('hải phòng') || query.toLowerCase().contains('haiphong')) {
      return const GeocodeResult(lat: 20.8449, lng: 106.6881, label: 'Hải Phòng, Việt Nam');
    }
    throw const ApiException(
      statusCode: 400,
      code: 'GEOCODE_FAILED',
      message: 'Không tìm thấy địa chỉ, vui lòng thử từ khóa khác',
    );
  }

  @override
  Future<List<Trip>> listTrips() async => List.of(trips);

  @override
  Future<Trip> createTrip(TripDraft draft) async {
    final trip = Trip(
      id: 't${++_seq}',
      originLat: draft.fromLat,
      originLng: draft.fromLng,
      originAddress: draft.fromAddress,
      destinationLat: draft.toLat,
      destinationLng: draft.toLng,
      destinationAddress: draft.toAddress,
      distanceM: 110000,
      durationS: 7200,
      status: 'planned',
      createdAt: DateTime.now(),
    );
    trips.add(trip);
    return trip;
  }

  @override
  Future<List<MatchResult>> findMatches(String tripId) async {
    return List.of(matchesByTrip[tripId] ?? defaultMatches);
  }

  @override
  Future<Trip> getTrip(String id) async =>
      trips.firstWhere((t) => t.id == id, orElse: () => throw StateError('not found'));

  // --- Phase 4 GPS + plan2_final §6.2 failure injection ---
  int startCount = 0;
  int endCount = 0;
  bool failEnd = false; // true → endTrip ném lỗi (mô phỏng mạng fail)
  final sentLocations = <(double, double)>[];

  @override
  Future<void> startTrip(String id) async {
    startCount++;
  }

  @override
  Future<void> endTrip(String id) async {
    if (failEnd) {
      endCount++; // đếm cả lần fail để assert retry thực sự gọi API lại
      throw const ApiException(
        statusCode: null,
        code: 'NETWORK_ERROR',
        message: 'Không thể kết nối máy chủ',
      );
    }
    endCount++;
  }

  @override
  Future<void> sendLocation(String id, {required double lat, required double lng}) async {
    sentLocations.add((lat, lng));
  }
}
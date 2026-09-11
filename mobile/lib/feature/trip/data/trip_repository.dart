import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/services/api_client.dart';
import '../../../shared/services/api_exception.dart';
import '../domain/trip_models.dart';

/// Kết quả geocode 1 địa chỉ (plan2_final §5.1).
class GeocodeResult {
  const GeocodeResult({required this.lat, required this.lng, required this.label});

  final double lat;
  final double lng;
  final String label;

  factory GeocodeResult.fromJson(Map<String, dynamic> j) => GeocodeResult(
        lat: (j['point']?['lat'] as num?)?.toDouble() ?? 0,
        lng: (j['point']?['lng'] as num?)?.toDouble() ?? 0,
        label: (j['label'] as String?) ?? '',
      );
}

/// Repository chuyến + matching (Phase 3 — /trips/*).
class TripRepository {
  TripRepository(this._api);

  final ApiClient _api;

  Future<List<Trip>> listTrips() async {
    try {
      final res = await _api.dio.get('/trips');
      final data = (res.data as Map<String, dynamic>?) ?? const {};
      final list = (data['data'] as List<dynamic>?) ?? const [];
      return list
          .whereType<Map<String, dynamic>>()
          .map(Trip.fromJson)
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<Trip> createTrip(TripDraft draft) async {
    try {
      final res = await _api.dio.post('/trips', data: draft.toJson());
      final data = (res.data as Map<String, dynamic>?) ?? const {};
      return Trip.fromJson((data['data'] as Map<String, dynamic>?) ?? const {});
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Chạy matching pipeline ("quét radar") — trả về danh sách match đã sort.
  Future<List<MatchResult>> findMatches(String tripId) async {
    try {
      final res = await _api.dio.post('/trips/$tripId/matches');
      final data = (res.data as Map<String, dynamic>?) ?? const {};
      final list = (data['data'] as List<dynamic>?) ?? const [];
      return list
          .whereType<Map<String, dynamic>>()
          .map(MatchResult.fromJson)
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// GET /maps/geocode?q= — địa chỉ → tọa độ (plan2_final §5.1).
  /// Lỗi GEOCODE_FAILED → thông báo rõ cho user thử từ khóa khác.
  Future<GeocodeResult> geocode(String query) async {
    try {
      final res = await _api.dio.get('/maps/geocode', queryParameters: {'q': query});
      final data = (res.data as Map<String, dynamic>?) ?? const {};
      return GeocodeResult.fromJson((data['data'] as Map<String, dynamic>?) ?? const {});
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<Trip> getTrip(String id) async {
    try {
      final res = await _api.dio.get('/trips/$id');
      final data = (res.data as Map<String, dynamic>?) ?? const {};
      return Trip.fromJson((data['data'] as Map<String, dynamic>?) ?? const {});
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// POST /trips/:id/start — bắt đầu chuyến (GPS bật, Phase 4 §13).
  Future<void> startTrip(String id) async {
    try {
      await _api.dio.post('/trips/$id/start');
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// POST /trips/:id/end — kết thúc chuyến (ngừng track GPS).
  Future<void> endTrip(String id) async {
    try {
      await _api.dio.post('/trips/$id/end');
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// POST /trips/:id/location — gửi GPS hiện tại (backend throttle 30s).
  Future<void> sendLocation(String id, {required double lat, required double lng}) async {
    try {
      await _api.dio.post('/trips/$id/location', data: {'lat': lat, 'lng': lng});
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

final tripRepositoryProvider = Provider<TripRepository>(
  (ref) => TripRepository(ref.watch(apiClientProvider)),
);
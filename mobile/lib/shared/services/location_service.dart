import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

/// Vị trí GPS (Phase 4 — plan §13).
class GeoPosition {
  const GeoPosition({required this.lat, required this.lng, required this.accuracyM});

  final double lat;
  final double lng;
  final double accuracyM;
}

/// Lỗi permission — UI hiển thị hướng dẫn mở quyền.
class LocationPermissionDenied implements Exception {
  const LocationPermissionDenied();
}

/// Abstraction GPS — dễ fake trong test (widget test không có platform channel).
/// Implement thật dùng geolocator; test dùng [FakeLocationService].
abstract class LocationService {
  /// Xin quyền truy cập vị trí (foreground). Ném [LocationPermissionDenied].
  Future<void> requestPermission();

  /// Lấy vị trí hiện tại (1 lần).
  Future<GeoPosition> getCurrentPosition();
}

class GeolocatorLocationService implements LocationService {
  @override
  Future<void> requestPermission() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const LocationPermissionDenied();
    }
  }

  @override
  Future<GeoPosition> getCurrentPosition() async {
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        // Thời gian chờ tối đa — nếu không có fix, trả về vị trí thô nhất
        timeLimit: Duration(seconds: 10),
      ),
    );
    return GeoPosition(
      lat: pos.latitude,
      lng: pos.longitude,
      accuracyM: pos.accuracy,
    );
  }
}

final locationServiceProvider = Provider<LocationService>((ref) {
  return GeolocatorLocationService();
});
import 'package:appvantai_mobile/shared/services/location_service.dart';

/// Fake GPS — không cần platform channel trong widget test.
class FakeLocationService implements LocationService {
  bool denyPermission = false;
  final positions = <GeoPosition>[];
  int positionCalls = 0;

  @override
  Future<void> requestPermission() async {
    if (denyPermission) throw const LocationPermissionDenied();
  }

  @override
  Future<GeoPosition> getCurrentPosition() async {
    positionCalls++;
    if (positions.isNotEmpty) return positions.first;
    return const GeoPosition(lat: 21.03, lng: 105.86, accuracyM: 5);
  }
}
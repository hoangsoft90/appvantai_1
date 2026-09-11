import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/trip_repository.dart';
import '../domain/trip_models.dart';

part 'trip_controller.g.dart';

/// Danh sách chuyến của tài xế (mới nhất trước).
/// Refresh: `ref.invalidate(tripListControllerProvider)`.
@riverpod
class TripListController extends _$TripListController {
  @override
  Future<List<Trip>> build() {
    return ref.watch(tripRepositoryProvider).listTrips();
  }
}

/// Kết quả "quét radar" (matching) cho một chuyến.
@riverpod
Future<List<MatchResult>> tripMatches(Ref ref, String tripId) {
  return ref.watch(tripRepositoryProvider).findMatches(tripId);
}

/// Chi tiết một chuyến (Phase 4 — màn hình Đang chạy).
@riverpod
Future<Trip> tripDetail(Ref ref, String tripId) {
  return ref.watch(tripRepositoryProvider).getTrip(tripId);
}
import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../shared/services/location_service.dart';
import '../data/trip_repository.dart';

part 'trip_run_controller.g.dart';

const gpsSendInterval = Duration(seconds: 30);

/// Trạng thái sync của end-trip (plan2_final §6.2 — client/server consistency).
enum EndSyncState { none, pending, synced, failed }

/// Kết quả reconcile (plan4_final §4.4) — UI dùng để đồng bộ nút/chip GPS
/// khi app reopen với trip server còn `active`.
enum ReconcileResult {
  /// Trip đã ended/cancelled phía server — GPS local đã dừng.
  ended,

  /// Trip active → đã resume GPS (gửi ngay + timer 30s).
  activeResumed,

  /// Trip active NHƯNG thiếu quyền vị trí → không gửi được GPS,
  /// UI phải báo rõ để user cấp quyền (server vẫn coi chuyến đang chạy).
  activeNoPermission,

  /// Trip planned — chưa bắt đầu, UI giữ nút Bắt đầu.
  planned,

  /// Lỗi mạng khi hỏi server — giữ state hiện tại.
  unknown,
}

/// Điều khiển chuyến đang chạy (Phase 4 — plan §13; plan2_final §6):
///  - start: xin quyền GPS → bắt đầu chuyến → bật timer gửi vị trí 30s
///  - mỗi tick: lấy vị trí hiện tại → POST /trips/:id/location (backend throttle)
///  - end: tắt timer → POST /trips/:id/end
///
/// plan2_final §6.2 — KHÔNG silently swallow error:
///  - end API fail → giữ trạng thái `pending`, UI hiện "chưa sync", retry khi user bấm.
///  - Không giả định Timer.periodic chạy sau app killed — app reopen sẽ
///    reconcile qua tripDetailProvider (status planned/active từ server).
@riverpod
class TripRunController extends _$TripRunController {
  Timer? _timer;
  bool _running = false;
  EndSyncState _endSync = EndSyncState.none;

  @override
  FutureOr<void> build(String tripId) {
    // Hủy timer khi provider bị dispose (rời màn hình)
    ref.onDispose(() {
      _timer?.cancel();
      _timer = null;
    });
  }

  bool get isRunning => _running;
  EndSyncState get endSync => _endSync;

  /// Bắt đầu chuyến: permission → start trip → timer gửi GPS.
  /// Ném lỗi để UI hiển thị (vd: từ chối quyền GPS).
  Future<void> start() async {
    if (_running) return;
    final location = ref.read(locationServiceProvider);
    await location.requestPermission(); // ném LocationPermissionDenied
    await ref.read(tripRepositoryProvider).startTrip(tripId);

    _running = true;
    _endSync = EndSyncState.none;
    // Gửi ngay vị trí đầu tiên, sau đó định kỳ 30s
    unawaited(_sendOnce(location));
    _timer = Timer.periodic(gpsSendInterval, (_) => unawaited(_sendOnce(location)));
  }

  Future<void> _sendOnce(LocationService location) async {
    try {
      final pos = await location.getCurrentPosition();
      await ref
          .read(tripRepositoryProvider)
          .sendLocation(tripId, lat: pos.lat, lng: pos.lng);
    } catch (_) {
      // GPS lỗi 1 tick không chặn chuyến — thử lại ở tick sau.
      // (LocationPermissionDenied đã xử lý ở start(); ở đây chỉ là fix lỗi/network.)
    }
  }

  /// Kết thúc chuyến (plan2_final §6.2):
  ///  - Tắt timer TRƯỚC (ngừng gửi location — backend đã chặn với terminal trip).
  ///  - Gọi end API; nếu fail → giữ `_running` + `_endSync = pending`
  ///    để UI hiện "chưa sync" và user retry — KHÔNG tự đánh dấu đã kết thúc.
  ///  - Trả true nếu server xác nhận (UI mới điều hướng đi).
  Future<bool> end() async {
    _timer?.cancel();
    _timer = null;
    try {
      await ref.read(tripRepositoryProvider).endTrip(tripId);
      _running = false;
      _endSync = EndSyncState.synced;
      return true;
    } catch (_) {
      // End fail (mạng/5xx): server vẫn đang active → giữ running=true
      // và báo pending. Retry an toàn: endTrip idempotent (end lại → TRIP_NOT_ACTIVE
      // nhưng trạng thái server đã ended — client chỉ cần sync lại).
      _endSync = EndSyncState.pending;
      return false;
    }
  }

  /// Reconcile sau app restart / trở lại màn hình (§6.2, §6.3 + plan4_final §4.4):
  /// hỏi server trạng thái trip và đồng bộ 2 chiều:
  ///  - ended/cancelled → dừng GPS local.
  ///  - active mà local chưa chạy (app reopen) → RESUME: xin quyền (nếu thiếu →
  ///    báo UI qua activeNoPermission), gửi ngay + bật lại timer 30s.
  ///  - planned → không đổi (UI giữ nút Bắt đầu).
  /// Không để xảy ra "server active mà UI nghĩ đã dừng" (hoặc ngược lại).
  Future<ReconcileResult> reconcile() async {
    try {
      final trip = await ref.read(tripRepositoryProvider).getTrip(tripId);
      if (trip.status == 'ended' || trip.status == 'cancelled') {
        _timer?.cancel();
        _timer = null;
        _running = false;
        _endSync = EndSyncState.synced;
        return ReconcileResult.ended;
      }
      if (trip.status == 'active' && !_running) {
        final location = ref.read(locationServiceProvider);
        try {
          await location.requestPermission();
        } on LocationPermissionDenied {
          return ReconcileResult.activeNoPermission;
        }
        _running = true;
        _endSync = EndSyncState.none;
        // Gửi ngay vị trí đầu tiên rồi tiếp tục theo throttle 30s.
        unawaited(_sendOnce(location));
        _timer ??= Timer.periodic(gpsSendInterval, (_) => unawaited(_sendOnce(location)));
        return ReconcileResult.activeResumed;
      }
      return ReconcileResult.planned;
    } catch (_) {
      // Network fail khi reconcile — giữ state hiện tại, không crash.
      return ReconcileResult.unknown;
    }
  }
}

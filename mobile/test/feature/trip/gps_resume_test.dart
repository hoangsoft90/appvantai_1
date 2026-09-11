import 'package:appvantai_mobile/feature/trip/data/trip_repository.dart';
import 'package:appvantai_mobile/feature/trip/domain/trip_models.dart';
import 'package:appvantai_mobile/feature/trip/presentation/screens/trip_run_screen.dart';
import 'package:appvantai_mobile/shared/services/location_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_location_service.dart';
import '../../helpers/fake_trip_repository.dart';

/// plan4_final §4.4 — Resume GPS khi app reopen với trip `active`:
/// - Màn run mở lại (controller mới, _running=false) nhưng server báo active
///   → UI phải hiện "Đang chạy — GPS bật" + nút Kết thúc + gửi vị trí ngay.
/// - Trip planned → UI giữ "Chưa bắt đầu".
/// - Trip ended → UI không tự chạy GPS.
/// - Active nhưng từ chối quyền → banner cảnh báo rõ (không im lặng).
void main() {
  Trip mkTrip(String id, String status) => Trip(
        id: id,
        originLat: 21.03,
        originLng: 105.84,
        originAddress: 'Bắc Giang',
        destinationLat: 21.0,
        destinationLng: 105.83,
        destinationAddress: 'Bắc Ninh',
        distanceM: 110000,
        durationS: 7200,
        status: status,
        createdAt: DateTime.now(),
      );

  Future<void> pumpRun(WidgetTester tester, FakeTripRepository trips,
      FakeLocationService location, String tripId) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tripRepositoryProvider.overrideWithValue(trips),
          locationServiceProvider.overrideWithValue(location),
        ],
        child: MaterialApp(home: TripRunScreen(tripId: tripId)),
      ),
    );
    await tester.pump(); // loading
    await tester.pumpAndSettle(); // reconcile + data
  }

  testWidgets('reopen với trip active → resume GPS: chip bật, nút Kết thúc, gửi vị trí',
      (tester) async {
    final trips = FakeTripRepository();
    final location = FakeLocationService();
    trips.trips.add(mkTrip('t-resume', 'active'));

    await pumpRun(tester, trips, location, 't-resume');

    // UI nhận đúng trạng thái đang chạy — KHÔNG hiện "Chưa bắt đầu"
    expect(find.textContaining('GPS bật'), findsOneWidget);
    expect(find.textContaining('GPS tắt'), findsNothing);
    expect(find.text('Kết thúc chuyến'), findsOneWidget);
    expect(find.text('Bắt đầu chuyến'), findsNothing);
    // GPS đã gửi ngay khi resume (§4.4: tiếp tục gửi theo throttle)
    expect(trips.sentLocations.length, greaterThanOrEqualTo(1));
    expect(find.text('Bắt đầu chuyến'), findsNothing);
  });

  testWidgets('reopen với trip planned → giữ trạng thái chưa bắt đầu', (tester) async {
    final trips = FakeTripRepository();
    final location = FakeLocationService();
    trips.trips.add(mkTrip('t-planned', 'planned'));

    await pumpRun(tester, trips, location, 't-planned');

    expect(find.textContaining('GPS tắt'), findsOneWidget);
    expect(find.text('Bắt đầu chuyến'), findsOneWidget);
    expect(trips.sentLocations, isEmpty);
  });

  testWidgets('reopen với trip ended → không chạy GPS', (tester) async {
    final trips = FakeTripRepository();
    final location = FakeLocationService();
    trips.trips.add(mkTrip('t-ended', 'ended'));

    await pumpRun(tester, trips, location, 't-ended');

    expect(trips.sentLocations, isEmpty);
    expect(find.text('Kết thúc chuyến'), findsNothing);
  });

  testWidgets('reopen active + từ chối quyền → banner cảnh báo rõ, không im lặng',
      (tester) async {
    final trips = FakeTripRepository();
    final location = FakeLocationService()..denyPermission = true;
    trips.trips.add(mkTrip('t-noperm', 'active'));

    await pumpRun(tester, trips, location, 't-noperm');

    // Server coi chuyến đang chạy → UI hiện đang chạy + cảnh báo quyền rõ ràng
    expect(find.textContaining('thiếu quyền vị trí'), findsOneWidget);
    expect(trips.sentLocations, isEmpty); // không gửi GPS khi chưa có quyền
  });
}

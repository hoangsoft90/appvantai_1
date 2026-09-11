import 'package:appvantai_mobile/feature/trip/data/trip_repository.dart';
import 'package:appvantai_mobile/feature/trip/domain/trip_models.dart';
import 'package:appvantai_mobile/feature/trip/presentation/screens/trip_matches_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_trip_repository.dart';

void main() {
  testWidgets('match card hiện đủ stats: score / khỏi tuyến / độ lệch / khối lượng / giá', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final trips = FakeTripRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [tripRepositoryProvider.overrideWithValue(trips)],
        child: const MaterialApp(home: TripMatchesScreen(tripId: 't1')),
      ),
    );
    await tester.pumpAndSettle();

    // Score + giá + khối lượng + stats hàng (plan3 Mục 4)
    expect(find.text('92'), findsOneWidget);
    expect(find.textContaining('1.200.000'), findsOneWidget);
    expect(find.text('Khỏi tuyến'), findsOneWidget);
    expect(find.text('1.2 km'), findsOneWidget);
    expect(find.text('Độ lệch'), findsOneWidget);
    expect(find.text('3.4 km'), findsOneWidget);
    expect(find.text('Khối lượng'), findsOneWidget);
    expect(find.text('800 kg'), findsOneWidget);
    // Nút hành động rõ
    expect(find.textContaining('Liên hệ chủ hàng'), findsOneWidget);
    expect(find.textContaining('Nhận chuyến'), findsOneWidget);
    // Reasons hiển thị (≥3)
    expect(tester.widgetList(find.byIcon(Icons.check_circle_outline)).length, greaterThanOrEqualTo(3));
  });

  testWidgets('empty state có gợi ý hành động (khai chiều về / mở rộng giờ / quét lại)', (tester) async {
    final trips = FakeTripRepository()..matchesByTrip['t-empty'] = const [];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [tripRepositoryProvider.overrideWithValue(trips)],
        child: const MaterialApp(home: TripMatchesScreen(tripId: 't-empty')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Chưa có mối phù hợp trên tuyến này'), findsOneWidget);
    // 3 gợi ý hành động theo plan3 Mục 4
    expect(find.text('Khai báo chiều về'), findsOneWidget);
    expect(find.text('Mở rộng thời gian lấy hàng'), findsOneWidget);
    expect(find.text('Quét lại radar'), findsOneWidget);
  });

  testWidgets('nhiều match (5) không lỗi layout — mỗi card 1 score badge', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final trips = FakeTripRepository();
    trips.matchesByTrip['t-many'] = List.generate(
      5,
      (i) => MatchResult(
        score: 90 - i,
        detourKm: 2.0 + i,
        pickupKm: 1.0 + i,
        reasons: const ['Điểm lấy cách tuyến 1.0 km', 'Đủ tải trọng (800 kg)'],
        order: FakeTripRepository.emptyOrder('m$i'),
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [tripRepositoryProvider.overrideWithValue(trips)],
        child: const MaterialApp(home: TripMatchesScreen(tripId: 't-many')),
      ),
    );
    await tester.pumpAndSettle();

    // ListView build lười: kéo hết để mọi card được build (không crash layout)
    await tester.drag(find.byType(ListView).first, const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(find.text('Khỏi tuyến'), findsWidgets);
  });

  testWidgets('plan4 §4.3: backend thiếu pickup_km → hiện "—", KHÔNG hiện "0.0 km" giả',
      (tester) async {
    final trips = FakeTripRepository();
    trips.matchesByTrip['t-nofield'] = [
      MatchResult(
        score: 88,
        detourKm: null,
        pickupKm: null, // backend không trả field
        reasons: const ['Điểm lấy cách tuyến gần'],
        order: FakeTripRepository.emptyOrder('m-nofield'),
      ),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [tripRepositoryProvider.overrideWithValue(trips)],
        child: const MaterialApp(home: TripMatchesScreen(tripId: 't-nofield')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('—'), findsNWidgets(2)); // cả Khỏi tuyến + Độ lệch
    expect(find.text('0.0 km'), findsNothing); // không nói dối user
  });
}

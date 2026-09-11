import 'package:appvantai_mobile/shared/widgets/async_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AsyncView hiển thị spinner khi loading', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: AsyncView<String>(
              value: AsyncLoading(),
              builder: (data) => Text(data),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('AsyncView hiển thị data khi thành công', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: AsyncView<String>(
              value: AsyncData('5 mối hàng phù hợp'),
              builder: (data) => Text(data),
            ),
          ),
        ),
      ),
    );
    expect(find.text('5 mối hàng phù hợp'), findsOneWidget);
  });

  testWidgets('AsyncView hiển thị lỗi + nút Thử lại gọi onRetry', (tester) async {
    var retried = 0;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: AsyncView<String>(
              value: AsyncError('Mất mạng', StackTrace.empty),
              builder: (data) => Text(data),
              onRetry: () => retried++,
            ),
          ),
        ),
      ),
    );
    expect(find.text('Mất mạng'), findsOneWidget);
    await tester.tap(find.text('Thử lại'));
    expect(retried, 1);
  });
}
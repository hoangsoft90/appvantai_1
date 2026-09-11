import 'package:appvantai_mobile/shared/services/app_open_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 9, 11, 10);

  test('cold start (chưa từng show) → luôn hiện', () {
    expect(
      AppOpenPolicy.shouldShow(
        everShown: false,
        pausedAt: null,
        now: now,
        minBackground: const Duration(seconds: 30),
      ),
      isTrue,
    );
  });

  test('resume sau 10s background → KHÔNG hiện (dưới ngưỡng 30s)', () {
    expect(
      AppOpenPolicy.shouldShow(
        everShown: true,
        pausedAt: now.subtract(const Duration(seconds: 10)),
        now: now,
        minBackground: const Duration(seconds: 30),
      ),
      isFalse,
    );
  });

  test('resume sau 45s background → hiện', () {
    expect(
      AppOpenPolicy.shouldShow(
        everShown: true,
        pausedAt: now.subtract(const Duration(seconds: 45)),
        now: now,
        minBackground: const Duration(seconds: 30),
      ),
      isTrue,
    );
  });

  test('resume mà không qua paused/hidden → không hiện', () {
    expect(
      AppOpenPolicy.shouldShow(
        everShown: true,
        pausedAt: null,
        now: now,
        minBackground: const Duration(seconds: 30),
      ),
      isFalse,
    );
  });
}

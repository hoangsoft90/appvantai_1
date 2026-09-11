import 'package:appvantai_mobile/core/config/admob_config.dart';
import 'package:flutter_test/flutter_test.dart';

// Lock hành vi flag TEST_ADS — tránh tai nạn "build production mà dùng test IDs"
// hoặc ngược lại (ads thật khi dev → traffic rác + AdMob giới hạn tài khoản).
void main() {
  test('mặc định (không dart-define) → TEST_ADS = true (chế độ an toàn)', () {
    expect(AdmobConfig.testAds, isTrue);
  });

  test('TEST_ADS=true → dùng TEST unit IDs chính thức của Google', () {
    // Test banner ID của Google (docs AdMob) — mọi unit test mode đều có prefix này.
    const googleTestPrefix = 'ca-app-pub-3940256099942544/';
    expect(AdmobConfig.bannerUnitId, startsWith(googleTestPrefix));
    expect(AdmobConfig.interstitialUnitId, startsWith(googleTestPrefix));
    expect(AdmobConfig.appOpenUnitId, startsWith(googleTestPrefix));
    expect(AdmobConfig.rewardedUnitId, startsWith(googleTestPrefix));
  });

  test('validateProductionConfig(testAds: true) → hợp lệ, không cần ID thật', () {
    expect(AdmobConfig.validateProductionConfig(testAds: true), isNull);
  });

  test('validateProductionConfig(testAds: false) → PASS vì ID thật đã điền đủ', () {
    // File config đã chứa 4 ID thật từ AdMob console (app 6917313063209470):
    // validate check non-empty + prefix ca-app-pub- cho từng format.
    expect(AdmobConfig.validateProductionConfig(testAds: false), isNull);
  });
}

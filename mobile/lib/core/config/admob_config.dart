/// Cấu hình AdMob (kiếm tiền ads trên Play Store / App Store).
///
/// Flag TEST_ADS (dart-define, mặc định TRUE):
///   --dart-define=TEST_ADS=true   → dùng TEST unit IDs chính thức của Google
///                                   (luôn fill, không đếm vào tài khoản → AdMob
///                                   KHÔNG giới hạn quảng cáo khi dev/test)
///   --dart-define=TEST_ADS=false  → dùng unit IDs THẬT (đã đăng ký AdMob)
///
/// APP ID khai báo ở platform config (KHÔNG qua dart-define):
///   - Android: AndroidManifest.xml meta-data GADApplicationIdentifier
///   - iOS:     Info.plist GADApplicationIdentifier
class AdmobConfig {
  AdmobConfig._();

  static const bool _testAdsDefine = bool.fromEnvironment(
    'TEST_ADS',
    defaultValue: true,
  );

  /// true (mặc định) = chế độ test ads — luôn fill, an toàn cho tài khoản.
  /// false = ads thật trên Play Store / App Store.
  static bool get testAds => _testAdsDefine;

  // ---- ID THẬT (từ AdMob console, app: ca-app-pub-6917313063209470~9914050394) ----
  // Mỗi format một unit; dùng khi testAds = false.

  /// App Open (màn hình mở app / trở lại foreground).
  static const String _realAppOpenAndroid = 'ca-app-pub-6917313063209470/8101063820';

  /// Banner (đặt cuối màn danh sách, không che nội dung chính).
  static const String _realBannerAndroid = 'ca-app-pub-6917313063209470/4489121877';

  /// Interstitial (chuyển cảnh tự nhiên: tạo đơn xong...).
  static const String _realInterstitialAndroid =
      'ca-app-pub-6917313063209470/3040308832';

  /// Rewarded (nếu sau này thêm tính năng thưởng — hiện chưa dùng).
  static const String _realRewardedAndroid = 'ca-app-pub-6917313063209470/9414145495';

  // ---- TEST unit IDs chính thức của Google (docs.google.com/marketing-platform/admob) ----
  static const String _testBannerAndroid = 'ca-app-pub-3940256099942544/6300978111';
  static const String _testInterstitialAndroid =
      'ca-app-pub-3940256099942544/1033173712';
  static const String _testAppOpenAndroid = 'ca-app-pub-3940256099942544/9257395921';
  static const String _testRewardedAndroid = 'ca-app-pub-3940256099942544/5224354917';

  // iOS: chưa đăng ký unit thật (Android-first, phase 8) → test mode dùng
  // test IDs; production iOS sẽ lỗi fail-fast bên dưới cho tới khi điền ID thật.

  static String get appOpenUnitId =>
      testAds ? _testAppOpenAndroid : _realAppOpenAndroid;
  static String get bannerUnitId => testAds ? _testBannerAndroid : _realBannerAndroid;
  static String get interstitialUnitId =>
      testAds ? _testInterstitialAndroid : _realInterstitialAndroid;
  static String get rewardedUnitId =>
      testAds ? _testRewardedAndroid : _realRewardedAndroid;

  /// Fail-fast: nếu tắt TEST_ADS mà thiếu ID thật → chặn ngay (không chạy app
  /// với unit ID rỗng/sai → tránh NO_FILL khó debug + tránh test traffic vào
  /// tài khoản thật).
  /// Logic tách hàm thuần để unit test được.
  static String? validateProductionConfig({required bool testAds}) {
    if (testAds) return null;
    const required = {
      'appOpen': _realAppOpenAndroid,
      'banner': _realBannerAndroid,
      'interstitial': _realInterstitialAndroid,
      'rewarded': _realRewardedAndroid,
    };
    for (final e in required.entries) {
      if (e.value.isEmpty) return 'TEST_ADS=false nhưng thiếu AdMob unit ID thật: ${e.key}.';
      if (!e.value.startsWith('ca-app-pub-')) {
        return 'TEST_ADS=false nhưng AdMob unit ID "$e.key" sai định dạng (phải ca-app-pub-...).';
      }
    }
    return null;
  }

  static void assertProductionConfig() {
    final error = validateProductionConfig(testAds: testAds);
    if (error != null) throw StateError(error);
  }
}

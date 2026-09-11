import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../core/config/admob_config.dart';

/// Service quảng cáo — khởi tạo SDK 1 lần ở main(), preload interstitial,
/// show khi cần (chuyển cảnh tự nhiên). Banner dùng widget riêng.
///
/// TEST_ADS=true (mặc định): test unit IDs Google → luôn fill, không đụng
/// giới hạn tài khoản AdMob. TEST_ADS=false: ID thật (production).
class AdsService {
  AdsService._();
  static final AdsService instance = AdsService._();

  bool _sdkReady = false;
  InterstitialAd? _interstitial;
  bool _loadingInterstitial = false;

  /// Gọi 1 lần ở main() trước runApp. Không crash khi SDK lỗi init
  /// (ads là phụ trợ — app chính phải chạy được cả khi ads hỏng).
  Future<void> init() async {
    if (kIsWeb || kDebugMode) return; // test env: flutter test — không init SDK
    try {
      await MobileAds.instance.initialize();
      _sdkReady = true;
      // TEST_ADS=true: đánh dấu thiết bị test (phòng hờ khi sau này dùng
      // production unit cho minh hoạ nội bộ — AdMob không giới hạn).
      if (AdmobConfig.testAds) {
        await MobileAds.instance.updateRequestConfiguration(
          // ID thiết bị test mẫu của Google (docs) — phòng hờ dùng production unit.
          RequestConfiguration(testDeviceIds: <String>['33BE2250B43518CCDA7DE426D04EE231']),
        );
      }
      loadInterstitial();
    } catch (_) {
      // Không rethrow — app phải chạy được kể cả khi ads SDK lỗi.
    }
  }

  bool get sdkReady => _sdkReady;

  void loadInterstitial() {
    if (kIsWeb || kDebugMode || !_sdkReady || _loadingInterstitial) return;
    _loadingInterstitial = true;
    InterstitialAd.load(
      adUnitId: AdmobConfig.interstitialUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitial = ad;
          _loadingInterstitial = false;
        },
        onAdFailedToLoad: (error) {
          _interstitial?.dispose();
          _interstitial = null;
          _loadingInterstitial = false;
          // NO_FILL (code 3) ở production = chuyện tài khoản AdMob, không phải code.
          loadInterstitial(); // thử load lại lần sau (throttle tự nhiên bởi fail)
        },
      ),
    );
  }

  /// Show nếu có sẵn (fire-and-forget). Ưu tiên await sẵn loaded trước
  /// navigation để không nuốt đi cảnh chuyển; nếu chưa có → bỏ qua.
  Future<void> showInterstitial({VoidCallback? onDismissed}) async {
    final ad = _interstitial;
    if (ad == null) {
      onDismissed?.call();
      return;
    }
    _interstitial = null; // mỗi ad chỉ show 1 lần
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        loadInterstitial(); // preload cho lần sau
        onDismissed?.call();
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        loadInterstitial();
        onDismissed?.call();
      },
    );
    await ad.show();
  }
}

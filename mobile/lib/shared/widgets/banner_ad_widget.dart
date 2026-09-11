import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../core/config/admob_config.dart';

/// Banner AdMob đặt cuối màn danh sách. Chiều cao adaptive (theo màn hình).
/// - kDebugMode / test env → render SizedBox.shrink (ads là phụ trợ, widget
///   test không phụ thuộc SDK native).
/// - SDK chưa init → placeholder trống, không crash.
class BannerAdWidget extends StatefulWidget {
  const BannerAdWidget({super.key});

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  BannerAd? _banner;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb || kDebugMode) return;
    _banner = BannerAd(
      adUnitId: AdmobConfig.bannerUnitId,
      request: const AdRequest(),
      size: AdSize.banner,
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _banner = null;
          // Giữ placeholder trống — không bơm lại liên tục (NO_FILL ở prod
          // là chuyện tài khoản, retry ập vào chỉ tốn quota).
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _banner?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || kDebugMode) return const SizedBox.shrink();
    if (!_loaded) return const SizedBox.shrink();
    return SafeArea(
      top: false,
      child: SizedBox(
        width: _banner!.size.width.toDouble(),
        height: _banner!.size.height.toDouble(),
        child: AdWidget(ad: _banner!),
      ),
    );
  }
}

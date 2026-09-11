import 'package:flutter/material.dart';

import '../services/ads_service.dart';

/// Listener vòng đời app cho App Open ad: cold start (frame đầu) + resume
/// sau background. Widget vô hình bọc quanh MaterialApp — bên trong dùng
/// AppLifecycleListener (object, KHÔNG phải widget — tạo ở initState, dispose
/// ở dispose; dùng như widget sẽ lỗi compile).
class AppOpenAdListener extends StatefulWidget {
  const AppOpenAdListener({super.key, required this.child});

  final Widget child;

  @override
  State<AppOpenAdListener> createState() => _AppOpenAdListenerState();
}

class _AppOpenAdListenerState extends State<AppOpenAdListener> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onStateChange: _onStateChange);
    // Cold start: chờ frame đầu render xong (ads là phụ trợ — không chặn splash).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AdsService.instance.maybeShowAppOpen(isColdStart: true);
    });
  }

  void _onStateChange(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        AdsService.instance.markPaused();
      case AppLifecycleState.resumed:
        AdsService.instance.maybeShowAppOpen(isColdStart: false);
      default:
        break;
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

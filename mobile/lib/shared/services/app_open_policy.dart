/// Chính sách hiển thị App Open ad — tách hàm thuần để unit test được
/// (không đụng SDK native trong test).
class AppOpenPolicy {
  AppOpenPolicy._();

  /// Hiện App Open khi:
  /// - Cold start (chưa từng show trong phiên này) → luôn hiện nếu ad đã load;
  /// - Resume sau khi app background đủ lâu (>= [minBackground], mặc định 30s) —
  ///   tránh khó chịu khi user chỉ bật tắt liên tục.
  static bool shouldShow({
    required bool everShown,
    required DateTime? pausedAt,
    required DateTime now,
    required Duration minBackground,
  }) {
    if (!everShown) return true; // cold start
    final p = pausedAt;
    if (p == null) return false; // resume mà không qua background — bỏ qua
    return now.difference(p) >= minBackground;
  }
}

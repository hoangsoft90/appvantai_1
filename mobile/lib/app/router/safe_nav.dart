import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Điều hướng "an toàn" cho các màn hình có thể được mở bằng **deep link**
/// (hoặc bởi redirect của router) — lúc đó navigation stack RỖNG:
///  - `context.pop()` → ném lỗi "nothing to pop" hoặc rơi vào hư không;
///  - AppBar mặc định KHÔNG hiện nút back (vì `canPop() == false`)
///    → user kẹt trong màn hình = điểm chết.
///
/// Quy tắc duy nhất: **còn stack thì pop, hết stack thì `go(fallback)`** —
/// luôn tồn tại đường ra, bất kể màn hình được mở bằng cách nào.

/// Pop nếu có thể, ngược lại điều hướng về [fallback].
void backOrGo(BuildContext context, String fallback) {
  final router = GoRouter.maybeOf(context);
  if (router == null) {
    // Không có GoRouter (widget test / preview) — thoái lui về Navigator.
    Navigator.maybePop(context);
    return;
  }
  if (router.canPop()) {
    router.pop();
  } else {
    router.go(fallback);
  }
}

/// Màn hình cho deep link KHÔNG khớp route nào (go_router `errorBuilder`).
/// Mặc định go_router hiện "Page Not Found: GoException: no routes for
/// location ..." — text lỗi kỹ thuật và user không có đường ra. Thay bằng
/// thông báo tiếng Việt + nút về trang chủ.
class RouteNotFoundScreen extends StatelessWidget {
  const RouteNotFoundScreen({super.key, this.uri});

  final String? uri;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Không tìm thấy trang')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.explore_off_outlined, size: 64, color: theme.colorScheme.outline),
              const SizedBox(height: 16),
              Text(
                'Đường dẫn này không còn tồn tại hoặc đã được thay đổi.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => backOrGo(context, '/home'),
                icon: const Icon(Icons.home_outlined),
                label: const Text('Về trang chủ'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Nút back trên AppBar: y hệt nút mặc định khi có stack, nhưng khi stack rỗng
/// (deep link) thì vẫn hiện và dẫn về [fallback] thay vì biến mất.
class SafeBackButton extends StatelessWidget {
  const SafeBackButton({super.key, required this.fallback});

  /// Đích đến khi không còn gì để pop (thường là màn cha logic của màn này).
  final String fallback;

  @override
  Widget build(BuildContext context) {
    final router = GoRouter.maybeOf(context);
    if (router == null || router.canPop()) return const BackButton();
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      onPressed: () => router.go(fallback),
    );
  }
}

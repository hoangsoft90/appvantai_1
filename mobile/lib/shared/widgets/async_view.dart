import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'error_view.dart';
import 'loading_view.dart';

/// Wrapper chuẩn cho mọi AsyncValue (plan §26):
/// Loading → spinner, Error → ErrorView (kèm retry), Data → builder.
///
/// Empty state: builder tự quyết định (vd: data rỗng → EmptyView),
/// vì "empty" phụ thuộc domain, không phải trạng thái async.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.value,
    required this.builder,
    this.onRetry,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: builder,
      loading: () => const LoadingView(),
      error: (error, stackTrace) => ErrorView(
        message: _messageOf(error),
        onRetry: onRetry,
      ),
    );
  }

  String _messageOf(Object error) {
    // ApiException đã có message thân thiện; lỗi khác dùng text chung.
    return error.toString();
  }
}
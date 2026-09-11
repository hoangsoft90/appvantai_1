# design-system.md — Design system & UI components

> Cập nhật 2026-09-10. Hệ thống tối giản có chủ đích (anti-overengineering) —
> Material 3 mặc định + 1 seed color, không tự chế token phức tạp.

## Theme

File duy nhất: `mobile/lib/app/theme/app_theme.dart` — `AppTheme.light()`:

| Token | Giá trị | Ghi chú |
|---|---|---|
| Seed color | `0xFFFF6D00` (cam) | `ColorScheme.fromSeed` → toàn bộ palette M3 tự sinh |
| useMaterial3 | `true` | Component mặc định M3 (FilledButton, SegmentedButton, Chip…) |
| scaffoldBackground | `scheme.surface` | — |
| Input | `OutlineInputBorder()` toàn cục | Không viền riêng từng form |

## Typography & spacing

- Typography: mặc định Material 3 (không custom font).
- Spacing: quy ước 8/16/32 (`EdgeInsets.all(16)` cho màn chi tiết, `SizedBox(height: 16)`
  giữa section) — không có token riêng, giữ nguyên như code hiện có.

## Ngôn ngữ UI

100% tiếng Việt, giọng người thật ("Đã lấy hàng", "Quét radar", "Khỏi tuyến").
Message lỗi hiển thị trực tiếp từ `ApiException.message` (server trả VN).

## Shared widgets (tái sử dụng bắt buộc)

| Widget | File | Dùng khi |
|---|---|---|
| `AsyncView<T>` | `shared/widgets/async_view.dart` | **Mọi** bề mặt async: Loading/Error/Retry/Empty + builder; lỗi hiện `messageOf` |
| `ErrorView` | `shared/widgets/error_view.dart` | Có retry callback |
| `EmptyView` | `shared/widgets/empty_view.dart` | Empty state (radar 0 match có 3 gợi ý hành động) |
| `LoadingView` | `shared/widgets/loading_view.dart` | Spinner trung tâm |
| `SplashScreen` | `shared/widgets/splash_screen.dart` | Bootstrap gate (đọc token + /me trước khi vào route) |

## Pattern UI đáng nhớ

- Match Card (radar): hàng stats score / Khỏi tuyến / Độ lệch / khối lượng /
  giá + tối đa 5 reasons; `pickupKm`/`detourKm` nullable → hiện "—", **không
  bao giờ hiện "0.0 km" giả**.
- Lifecycle: mỗi trạng thái đơn đúng 1 nút (từ `nextLifecycleAction()`),
  double-tap locked (`_processing` + `onPressed: null` + spinner icon).
- Form geocode: search địa chỉ → preview đọc được; sửa text sau geocode →
  clear point + chặn submit ("địa chỉ vừa sửa cần tìm lại").
- Chip trạng thái đơn: VN label map từ status (Đang chờ/Đã ghép/Đã liên hệ/…).

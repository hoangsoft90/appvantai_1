# state-routing.md — State management & Routing

> Cập nhật 2026-09-10.

## Riverpod 3 (codegen)

- Mọi provider khai báo `@riverpod` trong `application/` + chạy
  `dart run build_runner build --delete-conflicting-outputs` sau khi đổi.
- **Watch-in-build rule** (trap thật): controller phải được `ref.watch` trong
  `build` — chỉ `ref.read` → Riverpod dispose provider → "Ref disposed" khi gọi.
- Pattern chính:
  - `AuthController` — phiên đăng nhập, onboarding stage, `refreshSelective()`
    (go_router 16: refresh CHỈ khi `_landing()` đổi — login/logout/onboarding/xe
    đầu tiên; refresh bừa xóa push stack, pop() fail).
  - `orderDetailProvider(orderId)` / `tripMatchesProvider(tripId)` — per-id
    AsyncNotifier, invalidate sau mutation.
  - `TripRunController` — start trip → xin quyền → gửi GPS ngay + Timer 30s →
    end (offline-safe: pending "chưa sync" + retry); `reconcile()` khi app reopen
    trả `ReconcileResult` (ended/activeResumed/activeNoPermission/planned/unknown).
- Async UI luôn qua `AsyncView` (Loading/Error/Retry/Empty) — không tự viết
  switch AsyncValue trong screen.

## GoRouter 16

- File: `mobile/lib/app/router/app_router.dart`.
- Redirect theo `_landing()` của AuthController: chưa login → `/login`;
  driver thiếu xe → `/vehicle`; else home role-aware (`/` customer, `/driver`).
- Refresh có chọn lọc (xem trên) — KHÔNG gọi `GoRouter.refresh()` trong mỗi
  auth change.
- Route đáng nhớ: `/orders/:id` (chi tiết đơn), `/order/new` (form geocode),
  `/trips/new`, `/trips/:id/matches` (radar), `/trips/:id/run` (GPS run),
  `/safety/report/:userId`.

## Deep link

Chưa có (P1, frozen tới khi pilot pass). App mở không qua link; điều hướng
nội bộ bằng GoRouter push/named routes.

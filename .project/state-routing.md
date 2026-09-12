# state-routing.md — State management & Routing

> Cập nhật 2026-09-12 (nav audit: guard vai trò + safe back + deep link).

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

- File: `mobile/lib/app/router/app_router.dart` + `app/router/safe_nav.dart`.
- Redirect theo `_landing()` của AuthController: chưa login → `/login`;
  chưa onboarding (name rỗng) → `/onboarding`; driver thiếu xe → `/vehicle`;
  else `/home`.
- Refresh có chọn lọc (xem trên) — KHÔNG gọi `GoRouter.refresh()` trong mỗi
  auth change.
- **Route registry thật** (nav audit 2026-09-12 — bản cũ ghi sai
  `/order/new`, `/safety/report/:userId`, `/` `/driver`: không tồn tại):
  `/login`, `/otp`, `/legal/terms|privacy`, `/onboarding`, `/vehicle`, `/home`,
  `/profile`, `/orders`, `/orders/new`, `/orders/:orderId`, `/trips/new`,
  `/trips/:tripId/matches`, `/trips/:tripId/run`.
- **Guard theo vai trò** (deep link): `/orders` + `/orders/new` → chỉ chủ hàng;
  `/orders/:orderId` → tài xế VẪN vào được (radar mở chi tiết để chạy lifecycle);
  `/trips*` → chỉ tài xế. Sai vai trò → `/home` (tránh màn gọi API 403).
- **Safe back** (`safe_nav.dart`): `SafeBackButton(fallback:)` làm `leading` của
  mọi màn push được → stack rỗng (deep link) vẫn có nút back về màn cha logic;
  `backOrGo(context, fallback)` cho điều hướng sau mutation (hủy đơn/tạo đơn/lưu xe):
  có stack thì `pop()` (giữ stack), hết stack thì `go(fallback)`. KHÔNG dùng
  `pop()` trần (nothing-to-pop) hay `go()` luôn (xóa stack).
- **`errorBuilder`** → `RouteNotFoundScreen` ("Không tìm thấy trang" + nút về home);
  deep link `/otp` thiếu `state.extra` → redirect `/login` (trước đây crash cast null).
- `trip_form` sau khi tạo chuyến dùng `pushReplacement` sang radar — back từ radar
  về `/home`, không quay lại form đã submit (tránh tạo trùng chuyến).
- Test khóa hành vi: `mobile/test/feature/nav/navigation_safety_test.dart` (8 case).

## Deep link

Chưa có deep link OS-level (App Links / Universal Links) — P1, vẫn frozen tới khi
pilot pass. NHƯNG mọi route đã tự vệ với entry-point lạ (deep link/redirect):
guard vai trò, safe back, not-found screen — xem `safe_nav.dart`.

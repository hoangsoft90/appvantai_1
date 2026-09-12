# app-shell-navigation Specification

## Purpose

Khung app mobile (plan §26, plan2_final §6.3): **bootstrap gate** (đợi auth bootstrap
xong mới mount router — không flicker, splash không kẹt vô hạn), **GoRouter duy nhất
với redirect theo AuthState** (single source of truth — nơi user "bắt buộc phải ở"
được tính tập trung), **home screen role-aware** (tài xế thấy radar, chủ hàng thấy
đơn), và bộ **shared widgets chuẩn** (`AsyncView`/`LoadingView`/`ErrorView`/Splash)
để mọi màn hình render trạng thái async thống nhất.

Phạm vi: Mobile (`mobile/lib/app/{app,router/app_router}.dart`,
`mobile/lib/app/theme/app_theme.dart`, `mobile/lib/feature/home/**`,
`mobile/lib/shared/widgets/**`).

## Requirements

### Requirement: Bootstrap gate + splash

`App` (`mobile/lib/app/app.dart:12-33`) **PHẢI**:

1. Watch `authControllerProvider` — khi đang bootstrap (đọc token từ storage + gọi
   `/me`) → render `MaterialApp` thường với `SplashScreen`, **chưa mount router**
   (tránh redirect flicker sang /login rồi quay lại)
2. Bootstrap xong → chuyển `MaterialApp.router` với `routerProvider`
3. Bootstrap không bao giờ kẹt vô hạn: controller luôn kết thúc ở một AuthState
   (kể cả lỗi mạng → giữ token, vào app offline — chi tiết thuộc `auth-otp`)

#### Scenario: Mở app với token đã lưu

- **GIVEN** user đã đăng nhập, mở app lại
- **WHEN** bootstrap chạy
- **THEN** splash hiện trong lúc đọc token + `/me`, sau đó router mount thẳng ở
  landing đúng role — không nhấp nháy màn login

#### Scenario: Bootstrap xong luôn mount router

- **WHEN** authController kết thúc (bất kể thành công/thất bại)
- **THEN** `MaterialApp.router` được mount — splash không hiển thị vĩnh viễn

### Requirement: GoRouter — redirect tập trung theo AuthState

`routerProvider` (`mobile/lib/app/router/app_router.dart:31-120`) **PHẢI**:

1. **`_landing()`** (`:16-23`) tính nơi user phải ở: chưa đăng nhập → `/login`;
   `needsOnboarding` (name rỗng) → `/onboarding`; driver chưa có xe → `/vehicle`;
   còn lại → `/home`
2. Redirect logic (`:41-64`):
   - Chưa login + không ở trang auth → `/login`
   - Đã login + đang ở trang auth → `_landing()`
   - Đã login: `needsOnboarding` mà không ở `/onboarding` → ép về; đã onboarding
     mà ở `/onboarding` → đẩy đi `_landing()`
   - Driver chưa có xe mà không ở `/vehicle` → ép về `/vehicle`; customer ở
     `/vehicle` → đẩy đi (driver đã có xe vào `/vehicle` là chế độ sửa — không redirect)
3. **Refresh có chọn lọc** (`:33-39`): chỉ notify router khi **đích `_landing()`
   thay đổi** (login/logout/onboarding/khai xe đầu tiên) — KHÔNG `GoRouter.refresh()`
   trên mọi thay đổi auth state (go_router 16: refresh re-parse URL theo XÓA navigation
   stack, làm hỏng `/profile → /vehicle` — comment `:27-30`)
4. Route registry: `/login`, `/otp` (phone qua `state.extra`), `/onboarding`,
   `/vehicle`, `/home`, `/profile`, `/orders` (+ `new`, `:orderId` nested),
   `/trips/new`, `/trips/:tripId/matches`, `/trips/:tripId/run`
5. `/vehicle` KHÔNG truyền vehicle qua `state.extra` — `VehicleFormScreen` tự đọc
   từ AuthController (single source of truth; tránh cast lỗi go_router 16 —
   comment `:88-90`)

#### Scenario: Chưa đăng nhập vào route được bảo vệ

- **GIVEN** user chưa đăng nhập
- **WHEN** mở `/orders`
- **THEN** redirect về `/login`

#### Scenario: Driver chưa khai xe bị giữ ở /vehicle

- **GIVEN** driver mới onboarding, chưa có xe
- **WHEN** cố mở `/orders`
- **THEN** redirect về `/vehicle`

#### Scenario: Sửa tên không phá navigation stack

- **GIVEN** user đang `/profile → push /vehicle` (chế độ sửa xe)
- **WHEN** `applyUser` cập nhật tên (landing không đổi)
- **THEN** router KHÔNG refresh — stack giữ nguyên, pop về `/profile` bình thường

#### Scenario: Đăng xuất đẩy về login

- **WHEN** `logout()` đổi AuthState sang unauthenticated
- **THEN** `_landing()` đổi → router notify → redirect `/login`

### Requirement: Deep link & lối thoát an toàn (nav audit 2026-09-12)

Mọi route đều phải có đường ra khi được mở **không qua stack nội bộ** (deep link /
redirect) — không tồn tại màn hình mà user bị kẹt. `app_router.dart` + 
`app/router/safe_nav.dart` **PHẢI**:

1. **Guard theo vai trò** (redirect, `app_router.dart`):
   - `/orders` (danh sách) + `/orders/new` → chỉ chủ hàng; tài xế bị đưa về `/home`
     (POST /orders `requireRole customer` → để tài xế vào là chắc chắn 403)
   - `/orders/:orderId` → **tài xế VẪN vào được** (radar/match card mở chi tiết để
     chạy lifecycle pickup → in_transit → delivered)
   - `/trips*` → chỉ tài xế; chủ hàng/admin bị đưa về `/home`
2. **`/otp` thiếu `state.extra`** (deep link không kèm phone) → redirect `/login`
   thay vì cast null; route builder dùng `extra is String ? extra : ''`
3. **Deep link không khớp route** → `errorBuilder` render `RouteNotFoundScreen`
   (tiếng Việt + nút "Về trang chủ") — không lộ `GoException` trần
4. **`SafeBackButton`** (`safe_nav.dart`) là `leading` của mọi màn push được:
   có stack → `BackButton` mặc định; stack rỗng (deep link) → IconButton dẫn về
   `fallback` của màn đó (`/home`, `/orders`, `/login`, `/profile`, …)
5. **`backOrGo(context, fallback)`** dùng cho điều hướng sau mutation
   (hủy đơn, tạo đơn, lưu xe): còn stack → `pop()` (giữ stack), hết stack → `go(fallback)`
   — thay cho `pop()` trần ("nothing to pop") và `go()` luôn (xóa stack)
6. **Onboarding không gửi `role` khi user hiện tại là `admin`** — `PATCH /me` chỉ
   nhận driver|customer nên sẽ tự giáng quyền quản trị

#### Scenario: Deep link vào route của vai trò khác

- **GIVEN** tài xế đã đăng nhập
- **WHEN** mở `/orders` (danh sách đơn của chủ hàng)
- **THEN** router redirect về `/home`; mở `/orders/:id` thì vẫn vào được chi tiết

#### Scenario: Deep link lạc đường

- **GIVEN** user đang ở bất kỳ màn nào
- **WHEN** mở `/duong-dan-khong-ton-tai`
- **THEN** hiện "Không tìm thấy trang" + nút "Về trang chủ" dẫn về `/home`
  (không hiện `GoException`)

#### Scenario: Màn mở bằng deep link vẫn back được

- **GIVEN** user mở `/orders` bằng deep link (stack rỗng)
- **WHEN** màn danh sách render
- **THEN** AppBar vẫn có nút back (`SafeBackButton`) và bấm vào đưa về `/home`

### Requirement: Home screen role-aware

`HomeScreen` (`mobile/lib/feature/home/presentation/screens/home_screen.dart:13-66`)
**PHẢI**:

1. AuthState chưa authenticated (race ngắn) → spinner, không crash
2. AppBar: tên app "App Vận Tải" + icon hồ sơ (`push /profile`) + icon đăng xuất
   (`logout()`)
3. Body: icon radar, lời chào (name rỗng → hiện SĐT), Chip vai trò
   (`roleLabel()` — "Tài xế" / "Chủ hàng" / "Quản trị" kèm icon), mô tả giá trị
   theo vai trò (nav audit 2026-09-12: trước đây `admin` bị hiện nhầm "Chủ hàng")
4. **CTA chính theo vai trò**: driver → FilledButton "Tôi đang chạy — quét radar"
   (`push /trips/new`); customer → "Đơn hàng của tôi" (`push /orders`)

#### Scenario: Driver mở home

- **WHEN** driver đã onboarding + có xe, mở `/home`
- **THEN** thấy CTA "Tôi đang chạy — quét radar" dẫn tới form tạo chuyến

#### Scenario: Customer mở home

- **WHEN** customer mở `/home`
- **THEN** thấy CTA "Đơn hàng của tôi" dẫn tới danh sách đơn; không thấy nút radar

### Requirement: Shared async widgets — AsyncView / ErrorView / LoadingView

1. **`AsyncView<T>`** (`mobile/lib/shared/widgets/async_view.dart:14-37`): wrapper
   chuẩn cho `AsyncValue` — `data` → builder, `loading` → `LoadingView`, `error` →
   `ErrorView` với nút "Thử lại" (callback `onRetry` do caller cung cấp, thường là
   `ref.invalidate(...)`); **empty state do builder tự quyết** (empty phụ thuộc
   domain, không phải trạng thái async)
2. **`ErrorView`** (`mobile/lib/shared/widgets/error_view.dart:10-38`): icon lỗi +
   message + nút "Thử lại" khi có onRetry — mọi màn lỗi luôn có lối thoát (plan §26:
   không được infinite loading)
3. **`LoadingView`**: spinner giữa màn hình
4. Các màn danh sách/chi tiết (orders, trips, matches) đều render qua `AsyncView`

#### Scenario: Danh sách đơn lỗi mạng

- **GIVEN** `GET /orders` fail lỗi mạng
- **WHEN** màn list render
- **THEN** ErrorView với message từ ApiException + nút "Thử lại"; bấm → invalidate
  provider → tải lại

#### Scenario: Danh sách rỗng ≠ lỗi

- **GIVEN** customer chưa có đơn (API trả `[]`)
- **WHEN** màn list render qua AsyncView
- **THEN** builder chạy với data rỗng → màn hình tự hiện EmptyView (không rơi vào
  ErrorView)

## Cần làm rõ

1. **`AsyncView._messageOf` dùng `error.toString()`** thay vì extract message từ
   `ApiException` — khi lỗi là ApiException, text hiển thị dạng
   `ApiException(400, CODE): <message VN>` thay vì chỉ message. UI vẫn dùng được
   nhưng hơi kỹ thuật. Sửa để extract `message` khi là ApiException hay chấp nhận?
2. **`/otp` nhận phone qua `state.extra`** — ✅ ĐÃ GIẢI QUYẾT (nav audit
   2026-09-12): bỏ cast cứng, deep link thiếu extra → redirect `/login`; có test
   `navigation_safety_test.dart` khóa hành vi.
3. **Home driver chưa có shortcut tới danh sách chuyến** — `GET /trips` + trip
   detail/run screen tồn tại nhưng chỉ vào được qua flow tạo chuyến mới → radar;
   không có màn "chuyến của tôi" từ home. Đúng phạm vi P0 hay cần thêm entry?

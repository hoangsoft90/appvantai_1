# platform-core Specification

## Purpose

Nền tảng chung mọi capability phụ thuộc vào (plan §26, plan2_final §7):
**error envelope thống nhất** `{ error: { code, message, status } }` cho mọi lỗi,
**auth middleware** (JWT HS256, role đọc từ DB mỗi request), **request ID + access
log**, **health check**, **environment guard 2 chiều** (Worker fail-loud + Mobile
fail-fast release), và cấu hình API client mobile (token injection tự động).

Phạm vi: Worker (`worker/src/index.ts`, `worker/src/lib/errors.ts`,
`worker/src/lib/env_guard.ts`, `worker/src/lib/logger.ts`,
`worker/src/middleware/{auth,request-id}.ts`, `worker/src/env.ts`) + Mobile
(`mobile/lib/shared/services/{api_client,api_exception,token_storage}.dart`,
`mobile/lib/core/config/app_config.dart`).

Chi tiết luồng đăng nhập/xác thực thuộc capability `auth-otp`; spec này mô tả
**contract nền** mà mọi route + client dùng chung.

## Requirements

### Requirement: Error envelope thống nhất

`worker/src/index.ts` **PHẢI**:

1. Mọi handler ném `ApiError` (`worker/src/lib/errors.ts:7-21` — constructor
   `status, code, message, details?`); helper factory `Errors.badRequest /
   unauthorized / forbidden / notFound / conflict / tooManyRequests / internal`
   với message tiếng Việt mặc định
2. `app.onError` (`worker/src/index.ts:50-70`): `ApiError` → JSON
   `{ error: { code, message, status } }` với HTTP status tương ứng; log `info`
   cho 4xx, `error` cho ≥500; lỗi KHÔNG phải ApiError → bọc thành 500
   `INTERNAL_ERROR` ("Lỗi hệ thống, vui lòng thử lại") + log full error/stack
   với `requestId` — client không bao giờ thấy stack trace
3. `app.notFound` (`:72-78`): route không tồn tại → cùng envelope, 404 `NOT_FOUND`
   ("Endpoint không tồn tại")

#### Scenario: Lỗi nghiệp vụ trả envelope

- **WHEN** driver accept đơn đã có người nhận
- **THEN** HTTP 400 với body `{ "error": { "code": "ORDER_ALREADY_ACCEPTED", "message": "Đơn đã được tài xế khác nhận", "status": 400 } }`

#### Scenario: Unhandled exception không lộ nội bộ

- **GIVEN** handler ném `TypeError` (bug)
- **WHEN** request xử lý
- **THEN** HTTP 500 `{ error: { code: "INTERNAL_ERROR", message: "Lỗi hệ thống, vui lòng thử lại", status: 500 } }` — message chung, chi tiết chỉ nằm trong log

#### Scenario: Route không tồn tại

- **WHEN** `GET /khong-ton-tai`
- **THEN** HTTP 404 envelope `NOT_FOUND` "Endpoint không tồn tại"

### Requirement: Auth middleware — Bearer JWT, role từ DB

`authMiddleware` (`worker/src/middleware/auth.ts:13-41`) **PHẢI**:

1. Yêu cầu header `Authorization: Bearer <token>` — thiếu/sai format → 401
   `UNAUTHORIZED` ("Chưa đăng nhập hoặc phiên đã hết hạn")
2. Verify JWT **HS256** bằng `JWT_SECRET` qua `hono/jwt` — sai/hết hạn → 401
   `INVALID_TOKEN` ("Token không hợp lệ hoặc đã hết hạn")
3. `payload.sub` phải là string → lấy `userId`
4. **Đọc user từ DB mỗi request** (JWT chỉ là bằng chứng danh tính, role không tin
   từ token): user không tồn tại hoặc `status !== 'active'` → 401 `USER_NOT_FOUND`
   ("Người dùng không tồn tại hoặc đã bị khóa") — ban/suspend có hiệu lực tức thì
   với token còn hạn; đổi role qua PATCH /me được phản ánh ngay ở request sau
5. Set `c.set('userId', sub)` + `c.set('userRole', user.role)` cho downstream

#### Scenario: Token còn hạn nhưng user bị ban

- **GIVEN** JWT của B còn hạn 30 ngày, admin ban B
- **WHEN** B gọi API
- **THEN** HTTP 401 `USER_NOT_FOUND` ("đã bị khóa") — không thể dùng token cũ

#### Scenario: Đổi role có hiệu lực ngay

- **GIVEN** user đổi role customer → driver thành công
- **WHEN** request tiếp theo với token cũ (không có claim role mới)
- **THEN** middleware set `userRole='driver'` từ DB — không có bug stale role

#### Scenario: Thiếu header Authorization

- **WHEN** gọi API không kèm token
- **THEN** HTTP 401 `UNAUTHORIZED`

### Requirement: Request ID + access log + health check

1. `requestIdMiddleware` + `accessLogMiddleware` (`worker/src/middleware/request-id.ts`)
   chạy trước mọi route (`worker/src/index.ts:23-24`): mỗi request có ID duy nhất
   đưa vào log structured JSON (không lưu D1 — 0đ cost)
2. `GET /health` (`worker/src/index.ts:27-31`): không cần auth, trả
   `{ ok: true, env: APP_ENV, time: <ISO> }` — dùng cho monitor/deploy check

#### Scenario: Health check công khai

- **WHEN** `GET /health` không kèm token
- **THEN** HTTP 200 `{ ok: true, env: "...", time: "..." }`

#### Scenario: Pilot scripts chờ server sẵn bằng /health

- **GIVEN** `seed_pilot.sh` / `pilot_smoke.sh` vừa start `wrangler dev` (mock)
- **WHEN** script poll `$BASE/health` (tối đa 30s)
- **THEN** script chỉ tiếp tục sau khi health trả 200 — server chưa sẵn sàng thì
  seed/smoke không chạy (tránh E2E fail ảo do server chậm start)

### Requirement: Environment guard 2 chiều (Worker fail-loud + Mobile fail-fast)

1. **Worker** `assertProductionEnv` (`worker/src/lib/env_guard.ts:13-27`): chạy
   middleware toàn cục mỗi request, **no-op trừ khi `APP_ENV=production`**; khi
   production mà `ALLOW_DEV_OTP=true` hoặc `JWT_SECRET` rỗng/dev placeholder →
   log ERROR `PRODUCTION_ENV_GUARD` liệt kê problems (Workers không fail boot được
   — lỗi hiện ngay trong `wrangler tail` khi deploy, không âm thầm chạy dev secret)
2. **Mobile** `AppConfig.assertReleaseConfig()` (`mobile/lib/core/config/
   app_config.dart:40-53`): gọi sớm ở `main.dart`; khi `APP_ENV=production` mà
   `API_BASE_URL` là localhost/127.0.0.1/10.0.2.2 hoặc không `https://` → ném
   `StateError` — **release build fail-fast**, không đóng gói dev config
3. Config mobile inject qua `--dart-define` (không commit secret): `APP_ENV`
   (default `dev`), `API_BASE_URL` (default `http://localhost:8787`)

#### Scenario: Production còn dev OTP

- **GIVEN** deploy production với `ALLOW_DEV_OTP=true`
- **WHEN** bất kỳ request nào
- **THEN** log `[ERROR] PRODUCTION_ENV_GUARD` với mô tả vấn đề (nhìn thấy trong tail)

#### Scenario: Release build thiếu API URL

- **GIVEN** build release với `APP_ENV=production` nhưng quên `API_BASE_URL`
- **WHEN** app khởi động
- **THEN** crash ngay với StateError mô tả cách sửa — không chạy nửa vời trỏ localhost

#### Scenario: Dev config không bị guard làm phiền

- **GIVEN** chạy dev `APP_ENV=dev` + localhost
- **WHEN** app/worker khởi động
- **THEN** guard no-op, không lỗi

### Requirement: Pilot tooling (Phase 6 — harness, không phải production)

Phase 6 KHÔNG thêm API mới — chỉ thêm tooling vận hành dùng đúng API surface hiện có:

1. **Seed idempotent** (`worker/scripts/seed_pilot.sh` = `npm run seed:pilot`):
   tạo corridor HN→HP — 4 tài xế (truck 5t/8t, van 1.5t, pickup 1.2t, xe khai qua
   `PATCH /me/vehicle`) + 8 customer + 8 đơn `notes='pilot'` (6 trên corridor,
   2 nhiễu ngoài corridor) + 1 trip HN→HP mỗi tài xế + chạy matching. Mỗi lần chạy
   reset đúng data seed cũ (matches/contacts của đơn `notes='pilot'`, trip của
   phone `0983%`) — không nhân đôi, không đụng data user thật. Flag
   `--reset-seed` xóa rồi thoát. Khung giờ lấy hàng tính động (+2h→+12h).
   Mỗi user seed set role+name qua `PATCH /me` + `POST /me/legal-consent` (đúng
   onboarding — user mới mặc định customer, không set role thì `POST /trips` 403).
2. **Smoke full loop** (`worker/scripts/pilot_smoke.sh` = `npm run pilot:smoke`):
   chọn động 1 đơn seed còn `posted` khớp truck 5t → match (radar thấy đơn, reasons
   ≥3) → contact (nhận SĐT) → accept → **cancel-sau-accept phải 409
   `CANCEL_NOT_ALLOWED`** → GPS planned-reject/active-OK/end-dừng → pickup →
   in_transit → delivered → customer complete → in PASS/FAIL + funnel counts.
3. **Metrics SQL** (`scripts/pilot_metrics.sql` = `npm run pilot:metrics`): 4 nhóm
   query — liquidity (drivers/customers/open orders/active trips), funnel
   (matches → contacts → accepts → completed/cancelled), phân bố score band,
   reject heuristics từ score components. Local DB chứa residue E2E cũ → số liệu
   chỉ chuẩn khi chạy trên DB sạch.

#### Scenario: Seed chạy lại không nhân đôi

- **GIVEN** seed đã chạy 1 lần (8 đơn pilot, 4 trip)
- **WHEN** chạy `npm run seed:pilot` lần 2
- **THEN** vẫn đúng 8 đơn seed + 4 trip — data seed cũ đã bị xóa trước khi tạo lại;
  data user thật (phone khác 0983%) không bị đụng

#### Scenario: Vòng lặp cốt lõi hoàn tất trên data seed

- **GIVEN** seed vừa chạy (4/4 tài xế có ≥1 match, 12 match)
- **WHEN** chạy `npm run pilot:smoke`
- **THEN** 14/14 PASS — trong đó cancel sau accept bị chặn bằng
  `CANCEL_NOT_ALLOWED` (không phải `INVALID_TRANSITION` chung) và đơn kết thúc
  ở `completed`

### Requirement: Mobile API client — token injection + error mapping

1. **ApiClient** (`mobile/lib/shared/services/api_client.dart:11-55`): Dio với
   `baseUrl` + timeout từ AppConfig (connect 10s, receive 20s); interceptor tự gắn
   `Authorization: Bearer <token>` từ TokenStorage cho mọi request có token;
   dev mode thêm `LogInterceptor` — **không log request header** (tránh lộ token)
2. **ApiException** (`mobile/lib/shared/services/api_exception.dart:6-77`): mọi
   repository map `DioException` về đây qua `fromDio` — timeout/network/cancel/
   badCertificate → message tiếng Việt thân thiện với `statusCode: null`
   (`isNetworkError`); có response → parse **đúng envelope worker**
   `{ error: { code, message } }` giữ nguyên code + message VN cho UI hiển thị
   trực tiếp; shape lạ → `UNKNOWN` với fallback message
3. Token lưu qua `TokenStorage` (shared_preferences — chi tiết thuộc `auth-otp`)

#### Scenario: Lỗi 400 từ server hiển thị message VN

- **GIVEN** server trả envelope `ORDER_ALREADY_ACCEPTED` "Đơn đã được tài xế khác nhận"
- **WHEN** UI catch `ApiException`
- **THEN** `e.message` = "Đơn đã được tài xế khác nhận" — hiện nguyên văn lên SnackBar

#### Scenario: Mất mạng khi gọi API

- **WHEN** request fail connectionError
- **THEN** `ApiException(isNetworkError: true)` message "Không thể kết nối máy chủ,
  vui lòng kiểm tra mạng"

#### Scenario: Token được gắn tự động

- **GIVEN** user đã đăng nhập (token trong storage)
- **WHEN** bất kỳ repository gọi API
- **THEN** header Authorization tự có Bearer — repository không tự xử lý token

## Cần làm rõ

1. **`GET /health` trả `APP_ENV` công khai** — không cần auth, lộ thông tin môi
   trường (độ nhạy thấp, thường chấp nhận cho health check). OK cho P0?
2. **`c.env.APP_ENV` của /health đọc từ wrangler vars nhưng guard đọc mỗi request** —
   `assertProductionEnv` chạy mỗi request (middleware `app.use('*')`) dù chỉ cần
   boot-once; chi phí CPU không đáng kể nhưng có thể chuyển sang chạy 1 lần. Chủ đích
   đơn giản hay cần tối ưu?
3. **Mobile không có interceptor xử lý 401 toàn cục** — khi token hết hạn (30 ngày)
   hoặc user bị ban, mỗi màn hình tự catch `ApiException.isUnauthorized` (hiện có
   bootstrap check ở app start); không có auto-logout/redirect tập trung khi 401
   phát sinh giữa phiên. Chấp nhận cho P0 hay cần interceptor?
4. **`ApiException.fromDio` case `unknown` gộp với `badResponse`** — DioException
   unknown (lỗi máy chủ cứng/thrown trong interceptor) sẽ rơi vào nhánh parse
   response (thường null → `UNKNOWN`). Hành vi chấp nhận được nhưng error reporting
   sau này sẽ khó phân loại.

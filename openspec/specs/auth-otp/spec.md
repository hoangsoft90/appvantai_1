# auth-otp Specification

## Purpose

Capability xác thực người dùng bằng số điện thoại Việt Nam qua mã OTP, phát hành JWT
do chính Worker ký, và duy trì phiên đăng nhập trên app Flutter.

Đây là capability baseline: mô tả **hành vi đã implement** (Phase 0 + hardening), không
phải đề xuất. Provider OTP hiện tại là "dev OTP" (mã echo về client khi dev mode);
điểm thay provider sau này là `services/otp.ts` — API surface không đổi
(`worker/src/services/otp.ts:3-10`).

Phạm vi: Worker (`worker/src/routes/auth.ts`, `services/otp.ts`, `services/users.ts`,
`middleware/auth.ts`, `lib/phone.ts`) + Mobile (`mobile/lib/feature/auth/**`,
`shared/services/token_storage.dart`, `shared/services/api_client.dart`,
`core/utils/validators.dart`).

## Requirements

### Requirement: Chuẩn hóa và validate số điện thoại Việt Nam

Hệ thống **PHẢI** chuẩn hóa số điện thoại về dạng `0xxxxxxxxx` (10 chữ số) trước khi
bất kỳ thao tác OTP nào: bỏ space/dash, bỏ prefix `+`, đổi prefix `84` → `0`; số không
khớp `^0(3|5|7|8|9)\d{8}$` bị từ chối.

- Rule được implement 2 nơi, cùng một regex:
  - Worker: `normalizePhone` — `worker/src/lib/phone.ts:8-14`
  - Mobile: `PhoneValidator.normalize` — `mobile/lib/core/utils/validators.dart:6-13`
    (comment ghi rõ "giống worker/src/lib/phone.ts")

#### Scenario: Số hợp lệ được chuẩn hóa về 10 chữ số

- **GIVEN** input `+84912345678` (hoặc `0912345678`, `84 912 345 678`, `0912-345-678`)
- **WHEN** `normalizePhone` được gọi
- **THEN** trả về `0912345678`

#### Scenario: Số không hợp lệ bị từ chối ở endpoint request-otp

- **GIVEN** body `{ "phone": "12345" }` gọi `POST /auth/request-otp`
- **WHEN** route xử lý (`worker/src/routes/auth.ts:22-27`)
- **THEN** trả HTTP 400 với envelope `{ error: { code: "INVALID_PHONE", message: "Số điện thoại không hợp lệ", status: 400 } }`

### Requirement: Request OTP — sinh mã, lưu KV, rate limit theo số điện thoại

Khi `POST /auth/request-otp` với số hợp lệ, hệ thống **PHẢI**:

1. Kiểm tra rate limit theo phone: tối đa **5 request / 15 phút**, vượt → HTTP 429
   (`RATE_LIMITED`) — `worker/src/services/otp.ts:12-14, 24-29`
2. Sinh mã OTP 6 chữ số ngẫu nhiên, lưu KV key `otp:<phone>` với **TTL 300 giây (5 phút)**
   — `worker/src/services/otp.ts:16-20` (tạo code), `:31-32` (KV put TTL)
3. Chỉ trả `dev_otp` trong response khi env `ALLOW_DEV_OTP === "true"`; production
   **KHÔNG BAO GIỜ** echo mã — `worker/src/routes/auth.ts:29-35`

Lý do lưu KV thay vì D1: dữ liệu session ngắn hạn, tiết kiệm quota D1
(`worker/src/services/otp.ts:5-7`).

#### Scenario: Dev mode trả mã OTP trong response

- **GIVEN** `ALLOW_DEV_OTP = "true"`
- **WHEN** `POST /auth/request-otp` với `{ "phone": "0912345678" }`
- **THEN** response HTTP 200 dạng `{ "ok": true, "dev_otp": "<6 chữ số>" }`

#### Scenario: Production không echo mã

- **GIVEN** `ALLOW_DEV_OTP != "true"`
- **WHEN** `POST /auth/request-otp` thành công
- **THEN** response chỉ có `{ "ok": true }`, không chứa trường `dev_otp`

#### Scenario: Vượt rate limit

- **GIVEN** số `0912345678` đã request OTP 5 lần trong 15 phút (KV `otprl:0912345678` ≥ 5)
- **WHEN** request OTP thứ 6
- **THEN** trả HTTP 429 `{ error: { code: "RATE_LIMITED", ... } }`
  (`Errors.tooManyRequests` — `worker/src/lib/errors.ts:28-29`)

### Requirement: Verify OTP — đối chiếu mã, dùng 1 lần

Khi `POST /auth/verify-otp` với `{ phone, otp }`, hệ thống **PHẢI**:

1. Validate: phone hợp lệ và otp khớp `^\d{6}$`, sai → HTTP 400 `INVALID_REQUEST`
   (`worker/src/routes/auth.ts:38-44`)
2. Đối chiếu otp với mã trong KV `otp:<phone>`:
   - Không tìm thấy key (hết hạn 5 phút / chưa request) → HTTP 400 `INVALID_OTP`
     ("Mã OTP không đúng hoặc đã hết hạn") — `worker/src/services/otp.ts:39-43`
   - Mã không khớp → HTTP 400 `INVALID_OTP` — `worker/src/services/otp.ts:51-53`
3. **OTP dùng 1 lần**: xóa key KV ngay sau khi verify thành công
   (`worker/src/services/otp.ts:55-56`)

#### Scenario: Verify thành công tiêu thụ mã

- **GIVEN** OTP `123456` đang còn hiệu lực cho `0912345678`
- **WHEN** verify thành công, rồi verify lần nữa với cùng `123456`
- **THEN** lần 1 thành công; lần 2 trả HTTP 400 `INVALID_OTP` (key đã bị xóa)

#### Scenario: OTP hết hạn

- **GIVEN** đã request OTP hơn 5 phút trước (KV key hết hạn TTL)
- **WHEN** verify với đúng mã cũ
- **THEN** trả HTTP 400 `INVALID_OTP`

### Requirement: Đăng nhập — upsert user và phát hành JWT

Sau khi verify OTP thành công, hệ thống **PHẢI**:

1. Upsert user theo phone: user mới được tạo với `name=''`, `role='customer'`,
   `status='active'`; user đã tồn tại giữ nguyên dữ liệu (chỉ update `updated_at`)
   — `worker/src/services/users.ts:22-34`
2. Ký JWT **HS256** với payload `{ sub: user.id, role: user.role, phone,
   exp: now + 30 ngày }` bằng `JWT_SECRET` — `worker/src/routes/auth.ts:10, 47-52`
3. Trả `{ token, user }` với `user` là PublicUser `{ id, name, phone, role, status }`
   (không expose `legal_consent_at`/timestamp trong response login)
   — `worker/src/routes/auth.ts:54`, `worker/src/services/users.ts:15-18`

#### Scenario: User mới đăng nhập lần đầu

- **GIVEN** chưa tồn tại user với phone `0912345678`
- **WHEN** verify OTP thành công
- **THEN** tạo user mới role `customer`, response chứa JWT (exp 30 ngày) và
  `user.role = "customer"`, `user.name = ""`

#### Scenario: User cũ đăng nhập lại

- **GIVEN** user `0912345678` đã tồn tại với `role='driver'`, name đã đặt
- **WHEN** verify OTP thành công
- **THEN** response giữ nguyên `role`/`name` cũ (UPSERT không ghi đè dữ liệu profile)

### Requirement: Xác thực request bằng JWT và role từ DB

Mọi route có bảo vệ **PHẢI** đi qua `authMiddleware`:

1. Yêu cầu header `Authorization: Bearer <token>`; thiếu/sai → HTTP 401 `UNAUTHORIZED`
   — `worker/src/middleware/auth.ts:12-19`
2. Verify JWT HS256 bằng `JWT_SECRET`; token hỏng/hết hạn → HTTP 401 `INVALID_TOKEN`
   — `worker/src/middleware/auth.ts:21-23, 38-40`
3. **Role và trạng thái đọc từ DB mỗi request** (JWT chỉ là bằng chứng danh tính, claim
   `role` trong token không được tin): user không tồn tại hoặc `status !== 'active'`
   (suspended/banned) → HTTP 401 `USER_NOT_FOUND` — `worker/src/middleware/auth.ts:27-31`
4. Gắn `userId` + `userRole` (từ DB) vào context cho downstream
   — `worker/src/middleware/auth.ts:34-35`

#### Scenario: Token hết hạn bị từ chối

- **GIVEN** JWT đã quá `exp` (30 ngày sau phát hành)
- **WHEN** gọi bất kỳ endpoint cần auth
- **THEN** HTTP 401 `INVALID_TOKEN` ("Token không hợp lệ hoặc đã hết hạn")

#### Scenario: User bị ban → token cũ lập tức vô hiệu

- **GIVEN** JWT còn hạn nhưng user tương ứng đã bị admin ban (`status='banned'`)
- **WHEN** gọi endpoint cần auth với token đó
- **THEN** HTTP 401 `USER_NOT_FOUND` ("Người dùng không tồn tại hoặc đã bị khóa")

#### Scenario: Role đổi sau khi phát hành token vẫn có hiệu lực

- **GIVEN** JWT được phát khi user còn `role='customer'`, sau đó user tự đổi role thành
  `driver` qua `PATCH /me`
- **WHEN** gọi `POST /trips` với token cũ
- **THEN** request đi qua (middleware gắn `userRole='driver'` đọc từ DB, không phải
  `customer` trong claim JWT)

### Requirement: Logout stateless

`POST /auth/logout` **PHẢI** trả `{ "ok": true }` và không vô hiệu hóa JWT nào.
Đây là hành vi P0 chủ đích: JWT stateless, logout = client tự xóa token; endpoint giữ
chỗ gắn KV blocklist khi cần sau này (`worker/src/routes/auth.ts:57-62`).

#### Scenario: Logout không cần token hợp lệ để gọi

- **WHEN** `POST /auth/logout`
- **THEN** HTTP 200 `{ "ok": true }` (endpoint không qua auth middleware)

### Requirement: Mobile — luồng đăng nhập OTP

App Flutter **PHẢI** implement luồng:

1. **LoginScreen**: form số điện thoại (`maxLength: 15`, chỉ nhập số), validate bằng
   `PhoneValidator` (cùng rule backend); bấm gửi → `requestOtp` → nếu response có
   `dev_otp` thì hiện SnackBar "Mã OTP (dev): <code>" → điều hướng `/otp` kèm phone qua
   `extra` — `mobile/lib/feature/auth/presentation/screens/login_screen.dart:26-48, 100-107`
2. **OtpScreen**: TextField 6 số (`digitsOnly`, `maxLength: 6`); submit kiểm tra đủ 6
   chữ số ("Vui lòng nhập đủ 6 chữ số"); gọi `verifyOtp`; thành công → `context.go('/home')`
   (thay toàn bộ stack); lỗi → hiện `e.message` —
   `mobile/lib/feature/auth/presentation/screens/otp_screen.dart:22-45`
3. Nút gửi lại OTP gọi lại `requestOtp` và hiện SnackBar dev OTP tương tự
   — `mobile/lib/feature/auth/presentation/screens/otp_screen.dart:47-73`

#### Scenario: Nhập thiếu 6 chữ số

- **GIVEN** người dùng nhập `12345`
- **WHEN** bấm verify
- **THEN** hiện lỗi "Vui lòng nhập đủ 6 chữ số" và không gọi API

#### Scenario: Sai mã OTP

- **GIVEN** người dùng nhập 6 chữ số nhưng không khớp mã backend
- **WHEN** verify
- **THEN** hiện message lỗi tiếng Việt lấy từ `ApiException.message` (bắt từ envelope
  `INVALID_OTP` của server)

### Requirement: Mobile — lưu trữ và khôi phục phiên

1. Token lưu qua `TokenStorage` bằng `shared_preferences`, key `auth_token`; interface
   `readToken/saveToken/clearToken` để sau đổi sang secure storage không đụng call-site
   — `mobile/lib/shared/services/token_storage.dart:6-24`
2. Mọi request tự gắn `Authorization: Bearer <token>` từ TokenStorage qua interceptor
   của `ApiClient` — `mobile/lib/shared/services/api_client.dart:22-31`
3. Khởi động app, `AuthController.build` đọc token: không có token → `AuthUnauthenticated`;
   có token → gọi `GET /me` xác thực:
   - 401 → xóa token, về `AuthUnauthenticated` (phiên hết hạn)
   - Lỗi mạng → về `AuthUnauthenticated` nhưng **GIỮ token** (lần sau thử lại)
   — `mobile/lib/feature/auth/application/auth_controller.dart:14-36`
4. Verify OTP thành công: lưu token rồi set state `AuthAuthenticated`; GoRouter redirect
   dựa trên AuthState đưa user về `_landing` — `mobile/lib/feature/auth/application/auth_controller.dart:43-47`,
   `mobile/lib/app/router/app_router.dart:12-19, 40-52`
5. Logout: xóa token + state về `AuthUnauthenticated`
   — `mobile/lib/feature/auth/application/auth_controller.dart:56-59`

#### Scenario: Mở lại app với token còn hạn

- **GIVEN** token hợp lệ đã lưu, user đã hoàn tất onboarding
- **WHEN** khởi động app
- **THEN** `GET /me` thành công → state `AuthAuthenticated` → router cho vào `/home`

#### Scenario: Mở lại app khi mất mạng

- **GIVEN** token đã lưu nhưng không gọi được API (lỗi mạng, không phải 401)
- **WHEN** khởi động app
- **THEN** state là `AuthUnauthenticated` nhưng token vẫn còn trong storage; mở app lần
  sau (có mạng) vẫn tự đăng nhập lại bằng token cũ

#### Scenario: Token hết hạn khi mở lại app

- **GIVEN** token đã lưu nhưng `GET /me` trả 401
- **WHEN** khởi động app
- **THEN** token bị xóa khỏi storage, user thấy màn `/login`

### Requirement: Lỗi auth theo envelope thống nhất

Mọi lỗi của capability này **PHẢI** theo envelope `{ error: { code, message, status } }`
(`worker/src/lib/errors.ts:1-9`, error handler `worker/src/index.ts`), và mobile map
DioException → `ApiException` với message tiếng Việt hiển thị trực tiếp cho UI
(`mobile/lib/shared/services/api_exception.dart:16-64`).

#### Scenario: Lỗi 400 từ server hiển thị đúng message

- **GIVEN** server trả `400 INVALID_OTP` với message "Mã OTP không đúng hoặc đã hết hạn"
- **WHEN** mobile nhận `badResponse`
- **THEN** `ApiException` có `statusCode=400`, `code="INVALID_OTP"`,
  `message="Mã OTP không đúng hoặc đã hết hạn"`; UI hiển thị đúng chuỗi này

#### Scenario: Mất mạng khi request OTP

- **WHEN** `requestOtp` fail với `DioExceptionType.connectionError`
- **THEN** `ApiException` có `statusCode=null`, `code="NETWORK_ERROR"`,
  `message="Không thể kết nối máy chủ, vui lòng kiểm tra mạng"`

## Cần làm rõ

1. **Verify OTP không có giới hạn số lần thử.** Rate limit chỉ áp dụng cho *request* OTP
   (5/15'); phía verify không có counter — trong TTL 5 phút của một mã, có thể thử
   không giới hạn số tổ hợp 6 số (`worker/src/services/otp.ts:37-56` chỉ so sánh và
   xóa khi đúng). Đây có phải rủi ro chấp nhận được cho MVP/dev OTP, hay cần thêm
   counter verify? (Không tự sửa — chỉ hỏi.)
2. **Rate limit OTP phía KV không atomic** (read → check → put, `worker/src/services/otp.ts:25-29`),
   khác với rate limit D1 atomic (UPSERT RETURNING) đã harden ở Phase C cho các
   endpoint khác. Dưới request đồng thời, count có thể bị đếm thiếu. Đây là chủ đích
   "OTP chỉ là anti-spam, chấp nhận xấp xỉ" hay cần đổi sang D1 như các limit khác?
3. **JWT claim `role` không được dùng.** Token mang `role` (`worker/src/routes/auth.ts:50`)
   nhưng `authMiddleware` bỏ qua claim này và đọc role từ DB mỗi request
   (`worker/src/middleware/auth.ts:27-35`). Có thể claim này chỉ để debug/informational —
   xác nhận đây là chủ đích (spec hiện mô tả đúng hành vi này).
4. **`upsertUserByPhone` sinh UUID mới mỗi lần gọi** kể cả khi user đã tồn tại; giá trị
   id này bị bỏ qua khi INSERT conflict (`worker/src/services/users.ts:24, 27-31`).
   Không ảnh hưởng hành vi (id giữ nguyên trong DB) nhưng là giá trị chết — có chủ đích
   hay nên sinh id chỉ khi insert thật sự?

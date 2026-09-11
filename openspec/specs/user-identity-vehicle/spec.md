# user-identity-vehicle Specification

## Purpose

Capability hồ sơ người dùng sau đăng nhập: hoàn tất onboarding (tên + vai trò),
quản lý xe cho tài xế theo mô hình **1 tài xế = 1 xe** (P0 không có fleet management —
plan §11, §2.2, thể hiện ở comment `worker/src/routes/me.ts:8-10`), và ghi nhận
legal consent (disclaimer trung gian).

Phạm vi: Worker (`worker/src/routes/me.ts`, `services/users.ts`,
`services/profiles.ts`, `migrations/0002_identity.sql`) + Mobile
(`mobile/lib/feature/identity/**`, phần onboarding/vehicle của `feature/auth`).

## Requirements

### Requirement: GET /me — thông tin hồ sơ hiện tại

`GET /me` (yêu cầu auth) **PHẢI** trả `{ user, driver_profile, legal_consent_at }`:

- `user` là PublicUser `{ id, name, phone, role, status }` — `worker/src/routes/me.ts:24-33`
- `driver_profile` chỉ trả khi `role === 'driver'`, ngược lại `null` — `worker/src/routes/me.ts:28`
- `legal_consent_at` nằm ở **top-level** response (client dùng để gate form tạo/nhận đơn) — `worker/src/routes/me.ts:28-32`

#### Scenario: Customer gọi /me

- **GIVEN** user role `customer`, đã consent
- **WHEN** `GET /me`
- **THEN** response `{ user: {...}, driver_profile: null, legal_consent_at: "<ISO>" }`

#### Scenario: Driver gọi /me

- **GIVEN** user role `driver` đã khai xe
- **WHEN** `GET /me`
- **THEN** response chứa `driver_profile` đầy đủ (vehicle_type, license_plate,
  capacity_kg, kích thước, operating_area, status)

### Requirement: PATCH /me — cập nhật tên và/hoặc vai trò (validate cơ bản)

`PATCH /me` **PHẢI**:

1. Validate `name`: trim, độ dài 2–100 ký tự, sai → HTTP 400 `INVALID_NAME`
   ("Tên phải từ 2 đến 100 ký tự") — `worker/src/routes/me.ts:42-48`
2. Validate `role`: chỉ chấp nhận `driver` | `customer` (không cho tự phong `admin`),
   sai → HTTP 400 `INVALID_ROLE` — `worker/src/routes/me.ts:49-56`
3. Không có trường nào để cập nhật → HTTP 400 `INVALID_REQUEST` — `worker/src/routes/me.ts:57-60`
4. Chọn role `driver` → tự tạo `driver_profiles` rỗng (điền xe sau)
   — `worker/src/routes/me.ts:63-64`, `ensureDriverProfile` `worker/src/services/profiles.ts:75-90`
   (INSERT `ON CONFLICT(user_id) DO NOTHING` — idempotent)

#### Scenario: Onboarding driver

- **GIVEN** user mới (name rỗng)
- **WHEN** `PATCH /me` với `{ "name": "Nguyễn Văn A", "role": "driver" }`
- **THEN** user được cập nhật, `driver_profiles` có row mới cho user đó
  (vehicle fields mặc định rỗng/0 theo `migrations/0002_identity.sql:6-12`),
  response `{ user, driver_profile }`

#### Scenario: Thử tự phong admin

- **WHEN** `PATCH /me` với `{ "role": "admin" }`
- **THEN** HTTP 400 `INVALID_ROLE` ("Vai trò phải là driver hoặc customer")

#### Scenario: Tên quá ngắn

- **WHEN** `PATCH /me` với `{ "name": "A" }`
- **THEN** HTTP 400 `INVALID_NAME`

#### Scenario: PATCH body rỗng

- **WHEN** `PATCH /me` với `{}`
- **THEN** HTTP 400 `INVALID_REQUEST` ("Không có trường nào để cập nhật")

### Requirement: PATCH /me — khóa role khi còn đơn/chuyến active (plan3_final Mục 1)

`PATCH /me` **PHẢI** chặn **đổi** role (role mới ≠ role hiện tại) khi user đang có
nghiệp vụ đang chạy — guard `assertRoleChangeAllowed`
(`worker/src/routes/me.ts:22-46`):

1. Active order (customer): `COUNT(*)` trên `cargo_orders` với `customer_id = userId`,
   `status IN ('posted','matched','contacted','accepted','pickup','in_transit','delivered')`
   **và** `expires_at > now` (đơn quá hạn không tính — lazy expiry coi như đã xong) —
   `worker/src/routes/me.ts:19-28`
2. Active trip (driver): `COUNT(*)` trên `trips` với `driver_id = userId`,
   `status IN ('planned','active')` — `worker/src/routes/me.ts:30-38`
3. Vi phạm → HTTP 409 `ROLE_LOCKED` ("Không thể đổi vai trò khi đang có đơn/chuyến
   đang hoạt động")
4. **Re-submit cùng role vẫn cho qua** (idempotent — onboarding bấm lại không vỡ):
   guard chỉ chạy khi `role !== user.role` — `worker/src/routes/me.ts:99-104`
5. Đổi `name` không bao giờ bị guard chặn — `worker/src/routes/me.ts:85-91`

Mobile đã thỏa sẵn: profile screen **không có** nút đổi role (chỉ sửa tên + xe);
role chỉ chọn 1 lần duy nhất ở onboarding.

#### Scenario: Đổi role khi còn đơn active

- **GIVEN** customer A có 1 đơn `posted` chưa quá `expires_at`
- **WHEN** A gọi `PATCH /me` với `{ "role": "driver" }`
- **THEN** HTTP 409 `ROLE_LOCKED`, role không đổi

#### Scenario: Đổi role sau khi hủy hết đơn

- **GIVEN** customer A có 1 đơn `cancelled` (hoặc `expired`)
- **WHEN** A gọi `PATCH /me` với `{ "role": "driver" }`
- **THEN** HTTP 200, role đổi thành `driver`, `driver_profiles` rỗng được tạo

#### Scenario: Đổi role khi có chuyến planned/active

- **GIVEN** driver B có 1 trip `planned`
- **WHEN** B gọi `PATCH /me` với `{ "role": "customer" }`
- **THEN** HTTP 409 `ROLE_LOCKED`

#### Scenario: Re-submit cùng role (idempotent onboarding)

- **GIVEN** user role `customer`, không có đơn nào
- **WHEN** `PATCH /me` với `{ "name": "Tên mới", "role": "customer" }`
- **THEN** HTTP 200 — guard không chạy (role trùng), chỉ name được cập nhật

#### Scenario: Đơn quá hạn không chặn đổi role

- **GIVEN** customer A có 1 đơn `posted` nhưng `expires_at` đã qua (lazy expiry)
- **WHEN** A đổi role sang `driver`
- **THEN** HTTP 200 (đơn quá hạn không tính là active)

### Requirement: GET/PATCH /me/vehicle — 1 tài xế 1 xe

- `GET /me/vehicle`: trả `driver_profile` của chính user; chưa có profile →
  HTTP 404 `NO_DRIVER_PROFILE` — `worker/src/routes/me.ts:73-79`
- `PATCH /me/vehicle` (upsert): validate input rồi UPSERT theo `user_id` —
  `worker/src/routes/me.ts:81-85`, `upsertDriverProfile` `worker/src/services/profiles.ts:92-136`
  (`ON CONFLICT(user_id) DO UPDATE` toàn bộ field xe + `updated_at`)

Validate `VehicleInput` (`worker/src/services/profiles.ts:31-63`):

| Trường | Rule | Lỗi |
|---|---|---|
| `vehicle_type` | ∈ `van` \| `pickup` \| `truck` \| `container` | 400 `INVALID_VEHICLE_TYPE` |
| `license_plate` | regex `^[A-Za-z0-9.\- ]{4,12}$` sau trim | 400 `INVALID_LICENSE_PLATE` |
| `capacity_kg` | integer, 0 ≤ n ≤ 100.000 | 400 `INVALID_FIELD` |
| `vehicle_length_cm` / `width` / `height` | integer, 0 ≤ n ≤ 2.000 | 400 `INVALID_FIELD` |
| `operating_area` | string, cắt còn 200 ký tự (không lỗi) | — |

Lưu ý schema: `driver_profiles.user_id` có `UNIQUE` constraint
(`migrations/0002_identity.sql:6`) — đây là enforcement DB cho "1 tài xế = 1 xe".

#### Scenario: Driver khai xe lần đầu

- **GIVEN** driver profile rỗng vừa được tạo khi chọn role
- **WHEN** `PATCH /me/vehicle` với `{ vehicle_type: "truck", license_plate: "29H-123.45", capacity_kg: 8000, vehicle_length_cm: 600, vehicle_width_cm: 220, vehicle_height_cm: 230, operating_area: "Hà Nội" }`
- **THEN** profile được cập nhật đầy đủ, response chứa `driver_profile` mới

#### Scenario: Cập nhật lại xe (upsert, không tạo row thứ 2)

- **GIVEN** driver đã có xe capacity 8000
- **WHEN** `PATCH /me/vehicle` với `capacity_kg: 5000` (các trường khác giữ)
- **THEN** vẫn chỉ có 1 row `driver_profiles` cho user, `capacity_kg = 5000`

#### Scenario: Loại xe không hợp lệ

- **WHEN** `PATCH /me/vehicle` với `{ "vehicle_type": "rocket" }`
- **THEN** HTTP 400 `INVALID_VEHICLE_TYPE` liệt kê 4 loại được phép

#### Scenario: Customer gọi GET /me/vehicle

- **GIVEN** user role `customer` (không có driver_profiles)
- **WHEN** `GET /me/vehicle`
- **THEN** HTTP 404 `NO_DRIVER_PROFILE` ("Chưa có hồ sơ tài xế")

### Requirement: POST /me/legal-consent — ghi nhận disclaimer

`POST /me/legal-consent` **PHẢI**:

1. Nếu đã consent trước đó (`legal_consent_at` không null) → trả nguyên trạng,
   **không** ghi đè timestamp, **không** ghi audit lần 2 (idempotent)
   — `worker/src/routes/me.ts:96-99`
2. Lần đầu: set `users.legal_consent_at = now`, ghi `audit_logs` với
   `action='legal_consent'`, `metadata.text='disclaimer_v1'`, IP lấy từ header
   `CF-Connecting-IP` — `worker/src/routes/me.ts:101-116`

(Việc **enforce** consent ở các nghiệp vụ khác — tạo đơn, tạo chuyến, geocode —
được mô tả trong spec tương ứng: `order-marketplace`, `trip-matching`, `maps-geocoding`.)

#### Scenario: Consent lần đầu

- **GIVEN** user chưa có `legal_consent_at`
- **WHEN** `POST /me/legal-consent`
- **THEN** response `{ user, legal_consent_at: <ISO mới> }`; bảng `audit_logs` có dòng
  `action='legal_consent'` kèm IP

#### Scenario: Gọi consent lần 2

- **GIVEN** user đã consent tại T1
- **WHEN** gọi `POST /me/legal-consent` lần nữa
- **THEN** `legal_consent_at` trong response vẫn là T1 (không đổi)

### Requirement: Mobile — onboarding (tên + vai trò + disclaimer)

`OnboardingScreen` **PHẢI**:

1. Chỉ hiển thị khi `user.needsOnboarding` (name rỗng — router redirect, xem
   `mobile/lib/app/router/app_router.dart:64-67`)
2. Form: tên (validator tối thiểu 2 ký tự) + SegmentedButton chọn vai trò
   (`customer` = "Chủ hàng" | `driver` = "Tài xế") —
   `mobile/lib/feature/identity/presentation/screens/onboarding_screen.dart:94-124`
3. **Checkbox disclaimer bắt buộc**: chưa tick → chặn submit với lỗi
   "Vui lòng tick xác nhận điều khoản để tiếp tục"; nội dung disclaimer nêu rõ app
   chỉ trung gian kết nối, không tham gia vận chuyển —
   `mobile/lib/feature/identity/presentation/screens/onboarding_screen.dart:35-39, 126-144`
4. Submit: gọi `PATCH /me` (name + role) → nếu user chưa consent thì gọi tiếp
   `POST /me/legal-consent` → `AuthController.applyUser(user)` để router redirect
   (driver → `/vehicle`, customer → `/home`) —
   `mobile/lib/feature/identity/presentation/screens/onboarding_screen.dart:41-58`

#### Scenario: Driver hoàn tất onboarding

- **GIVEN** user mới đăng nhập lần đầu (name rỗng)
- **WHEN** nhập tên "Nguyễn Văn A", chọn "Tài xế", tick disclaimer, bấm "Tiếp tục"
- **THEN** app gọi `PATCH /me` rồi `POST /me/legal-consent`, sau đó router tự đưa tới
  `/vehicle` (driver chưa có xe)

#### Scenario: Chưa tick disclaimer

- **WHEN** nhập tên hợp lệ, chọn vai trò, nhưng chưa tick, bấm "Tiếp tục"
- **THEN** hiện lỗi "Vui lòng tick xác nhận điều khoản để tiếp tục", không gọi API

### Requirement: Mobile — vehicle form (khai xe bắt buộc cho driver)

`VehicleFormScreen` **PHẢI**:

1. Hoạt động 2 chế độ chốt **tại lúc mở màn hình** (`_isEdit`): chưa có xe (onboarding)
   → lưu xong `context.go('/home')`; đã có xe (vào từ `/profile`) → lưu xong
   `context.pop()` về `/profile`. Flag này KHÔNG tính lại lúc lưu vì `applyUser`
   đã set vehicle trước đó — `mobile/lib/feature/identity/presentation/screens/vehicle_form_screen.dart:33-40, 116-127`
2. Prefill từ `AuthController` (single source of truth); đọc vehicle qua state auth,
   **không** nhận qua `state.extra` của route (tránh cast lỗi go_router 16 —
   comment `mobile/lib/app/router/app_router.dart:92-95`)
3. Validate client: tải trọng > 0 bắt buộc; kích thước tùy chọn (≥ 0); biển số
   uppercase trước khi gửi — `mobile/lib/feature/identity/presentation/screens/vehicle_form_screen.dart:70-86, 100-110`
4. Sau lưu thành công: `applyUser(user.copyWith(vehicle: ...))` cập nhật state →
   router gate `isDriver && !hasVehicle` hết hiệu lực —
   `mobile/lib/feature/identity/presentation/screens/vehicle_form_screen.dart:112-119`
5. Loại xe hiển thị bằng nhãn tiếng Việt khớp enum backend:
   van/pickup/truck/container → "Xe van"/"Xe bán tải"/"Xe tải"/"Xe container" —
   `mobile/lib/feature/identity/domain/vehicle_types.dart:2-8`

#### Scenario: Driver mới lưu xe lần đầu

- **GIVEN** driver vừa onboarding, chưa có xe, đang bị router giữ ở `/vehicle`
- **WHEN** điền loại xe "Xe tải", biển số "29h-123.45", tải trọng "8000", bấm lưu
- **THEN** app gọi `PATCH /me/vehicle` (biển số gửi đi là "29H-123.45" đã uppercase),
  applyUser cập nhật vehicle, điều hướng tới `/home`

#### Scenario: Thiếu tải trọng

- **WHEN** để trống tải trọng và bấm lưu
- **THEN** hiện lỗi "Vui lòng nhập tải trọng (kg)", không gọi API

#### Scenario: Driver đã có xe vào lại form từ profile

- **GIVEN** driver đã khai xe, vào `/profile` → "Cập nhật thông tin xe"
- **WHEN** form mở với dữ liệu prefill, sửa tải trọng rồi lưu
- **THEN** app pop về `/profile` và hiển thị thông tin xe mới

### Requirement: Mobile — profile screen

`ProfileScreen` **PHẢI** hiển thị: tên + SĐT (nút sửa tên qua dialog → `PATCH /me`
chỉ gửi name), vai trò, và với driver: thẻ thông tin xe + nút vào `/vehicle` sửa —
`mobile/lib/feature/identity/presentation/screens/profile_screen.dart:14-39, 42-110`.
Nếu tên rỗng hiển thị "Chưa có tên"; nếu vehicle rỗng hiển thị "Chưa khai báo xe".

#### Scenario: Sửa tên từ profile

- **GIVEN** user "Nguyễn Văn A" đang ở `/profile`
- **WHEN** bấm icon sửa, nhập "Nguyễn Văn B", lưu
- **THEN** app gọi `PATCH /me` `{ "name": "Nguyễn Văn B" }`, state auth cập nhật,
  UI hiển thị tên mới (không redirect — landing không đổi)

#### Scenario: Customer không thấy phần xe

- **GIVEN** user role `customer`
- **WHEN** mở `/profile`
- **THEN** chỉ thấy tên/SĐT/vai trò, không có mục "Thông tin xe"

## Cần làm rõ

> Đã hỏi user và được chốt ngày 2026-09-09:

1. **`PATCH /me/vehicle` không kiểm tra role.** Route không có `requireRole('driver')`
   (`worker/src/routes/me.ts:81-85`) — một customer có thể gọi trực tiếp API này để
   tạo `driver_profiles` cho mình (UPSERT không chặn). Router mobile chặn customer
   vào màn xe (`app_router.dart:74-75`) nhưng đó chỉ là UX.
   **→ Chốt: CHẤP NHẬN như hiện trạng** (profile rỗng vô hại khi không tạo chuyến).
   Spec mô tả đúng hành vi này, không xem là lỗi.
2. **Consent chỉ ghi 1 lần, không có version hóa nội dung disclaimer.** Metadata audit
   cố định `text: 'disclaimer_v1'` (`worker/src/routes/me.ts:108`) — khi đổi nội dung
   disclaimer sau này, user cũ không được yêu cầu tick lại.
   **→ Chốt: CHẤP NHẬN cho P0** (một nội dung disclaimer duy nhất trong suốt P0).
3. **`GET /me` trả `driver_profile` rỗng (non-null) cho driver mới chọn role** — mobile
   parse thành `VehicleProfile` non-null (`auth_repository.dart:102-104`) nên router gate
   `user.vehicle == null` (`app_router.dart:29`) KHÔNG giữ được driver chưa khai xe ở
   `/vehicle` trong các luồng reload/ reopened app.
   **→ Chốt: LÀ BUG CẦN FIX** (driver chưa khai xe phải bị giữ ở `/vehicle`).
   Ghi nhận để sửa code SAU khi hoàn tất baseline specs — spec hiện tại vẫn mô tả
   hành vi đang chạy, không tự sửa code trong quá trình viết spec.

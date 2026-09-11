# trip-gps Specification

## Purpose

Tracking vị trí tài xế **chỉ khi có chuyến đang chạy** (không track toàn bộ users —
plan §13): start/end chuyến ghi D1 (ít write), vị trí realtime lưu **KV TTL 2h**
(bảo vệ quota 100k writes/ngày của D1), throttle 30s, và customer chỉ thấy
**khoảng cách ẩn danh** ("cách ~2.3 km") — không bao giờ thấy tọa độ chính xác
(privacy plan §13, §18).

Phạm vi: Worker (`worker/src/services/gps.ts`, `worker/src/routes/trips.ts` phần
start/end/location, `GET /orders/:id/driver-location` — quyền xem thuộc
`driver-engagement`) + Mobile (`mobile/lib/feature/trip/application/trip_run_controller.dart`,
`trip_run_screen.dart`, `mobile/lib/shared/services/location_service.dart`).

## Requirements

### Requirement: POST /trips/:id/start — bắt đầu chuyến

`POST /trips/:id/start` (role gate driver — `worker/src/routes/trips.ts:107-116`)
qua `startTrip` (`worker/src/services/gps.ts:107-127`) **PHẢI**:

1. Trip phải thuộc driver (`getTripById` WHERE `driver_id = ?`) — không → 404
   `TRIP_NOT_FOUND`
2. `ended|cancelled` → HTTP 400 `TRIP_NOT_ACTIVE`; `active` → **idempotent** trả
   `{ status: 'active', started_at }` hiện tại không ghi lại
3. `planned → active`: UPDATE 1 statement (SET `status='active'`, `started_at`) +
   audit log `trip_start` kèm IP — đúng 1 D1 write

#### Scenario: Start chuyến planned

- **GIVEN** trip `planned` của driver A
- **WHEN** A gọi `POST /trips/<id>/start`
- **THEN** HTTP 200 `{ data: { status: 'active', started_at } }`, trip `active`,
  audit `trip_start`

#### Scenario: Start lại chuyến đang chạy (idempotent)

- **GIVEN** trip `active` với `started_at = T1`
- **WHEN** gọi start lần nữa
- **THEN** HTTP 200 trả lại `started_at = T1`, không ghi đè

#### Scenario: Start chuyến đã kết thúc

- **WHEN** start trip `ended`
- **THEN** HTTP 400 `TRIP_NOT_ACTIVE` ("Chuyến đã kết thúc hoặc bị hủy")

### Requirement: POST /trips/:id/location — chỉ nhận GPS khi trip active (plan3_final Mục 3)

`POST /trips/:id/location` (role gate driver — `worker/src/routes/trips.ts:132-158`)
**PHẢI**:

1. Ownership: trip phải của driver → 404 `TRIP_NOT_FOUND`
2. **Status gate theo từng trạng thái** (`trips.ts:139-146`):
   `planned` → HTTP 400 `TRIP_NOT_ACTIVE` ("Chuyến chưa bắt đầu — hãy start chuyến
   trước khi gửi vị trí"); `ended|cancelled` → HTTP 400 `TRIP_NOT_ACTIVE`
   ("Chuyến đã kết thúc — không nhận vị trí nữa") — **chỉ `active` được nhận**
3. Validate `lat`/`lng`: số hữu hạn, lat ∈ [-90,90], lng ∈ [-180,180] → 400
   `INVALID_COORD`
4. Ghi KV qua `updateDriverLocation` (`gps.ts:49-72`):
   - Throttle **30s** theo `loclast:<driverId>` — trong window → trả
     `{ updated_at, throttled: true }` (HTTP 200, không ghi)
   - Ghi `loc:<driverId>` JSON `{lat, lng, updated_at}` **TTL 2h** (tự hết hạn nếu
     driver ngừng update) — không ghi D1 realtime
5. Client đã đúng flow: timer chỉ start **sau khi** `startTrip` thành công
   (`trip_run_controller.dart:48-54`) — planned không bao giờ gửi GPS từ app

#### Scenario: Gửi vị trí khi trip planned bị chặn

- **GIVEN** trip `planned` (chưa start)
- **WHEN** `POST /trips/<id>/location` với tọa độ hợp lệ
- **THEN** HTTP 400 `TRIP_NOT_ACTIVE` ("Chuyến chưa bắt đầu...")

#### Scenario: Gửi vị trí khi trip active

- **GIVEN** trip `active`, lần gửi cuối cách đây > 30s
- **WHEN** POST location
- **THEN** HTTP 200 `{ data: { updated_at, throttled: false } }`; KV `loc:<driverId>`
  chứa tọa độ mới TTL 2h

#### Scenario: Throttle 30s

- **GIVEN** driver vừa gửi location 10s trước
- **WHEN** gửi tiếp
- **THEN** HTTP 200 với `throttled: true` — KV không bị ghi, không lỗi

#### Scenario: Gửi vị trí sau khi end

- **GIVEN** trip đã `ended` (KV loc đã bị xóa)
- **WHEN** POST location
- **THEN** HTTP 400 `TRIP_NOT_ACTIVE` ("Chuyến đã kết thúc — không nhận vị trí nữa")

#### Scenario: Customer gửi location

- **WHEN** user role customer gọi `POST /trips/<id>/location`
- **THEN** HTTP 403 `FORBIDDEN` ("Chỉ tài xế mới gửi vị trí.")

### Requirement: POST /trips/:id/end — kết thúc + xóa vị trí

`POST /trips/:id/end` (role gate driver — `worker/src/routes/trips.ts:118-130`) qua
`endTrip` (`worker/src/services/gps.ts:129-152`) **PHẢI**:

1. Ownership + terminal check như start (ended/cancelled → 400 `TRIP_NOT_ACTIVE`)
2. UPDATE `planned|active → ended` SET `ended_at`
3. **Xóa cả 2 key KV** `loc:<driverId>` + `loclast:<driverId>` (ngừng track ngay —
   `GET /orders/:id/driver-location` sẽ trả `distance_km: null`)
4. Audit log `trip_end` kèm IP; response `{ data: { status: 'ended', ended_at } }`

#### Scenario: End chuyến đang chạy

- **GIVEN** trip `active`
- **WHEN** end
- **THEN** HTTP 200 `status='ended'`; KV loc + loclast bị xóa; audit `trip_end`

#### Scenario: Customer không còn thấy vị trí sau end

- **GIVEN** đơn có driver, trip vừa end
- **WHEN** chủ đơn hỏi driver-location
- **THEN** `distance_km: null`, `updated_at: null` (loc không còn trong KV)

### Requirement: GET /orders/:id/driver-location — khoảng cách ẩn danh (privacy)

`driverDistanceForOrder` (`worker/src/services/gps.ts:83-105`) **PHẢI**:

1. Chỉ chủ đơn (404 nếu `customer_id ≠ userId` — không leak); đơn chưa có driver →
   HTTP 400 `NO_DRIVER` ("Đơn chưa có tài xế nhận")
2. Đọc `loc:<driverId>` từ KV; không có/hết hạn → trả `{ distance_km: null,
   updated_at: null }` (HTTP 200 — không phải lỗi)
3. Haversine từ **điểm lấy hàng** tới vị trí driver → **làm tròn 0.1 km** — response
   KHÔNG có trường lat/lng nào (`gps.ts:101-104`)

#### Scenario: Khoảng cách làm tròn 0.1km

- **GIVEN** driver location cách điểm lấy 2.34 km
- **WHEN** chủ đơn hỏi driver-location
- **THEN** `distance_km: 2.3` — không có tọa độ chính xác trong response

### Requirement: Mobile — Trip Run (offline-safe end + reconcile)

1. **LocationService** abstraction (`mobile/lib/shared/services/location_service.dart`):
   `GeolocatorLocationService` — xin permission foreground (denied/deniedForever →
   ném `LocationPermissionDenied`), `getCurrentPosition` accuracy high + timeLimit
   10s; test dùng `FakeLocationService`
2. **TripRunController** (`trip_run_controller.dart`):
   - `start()`: xin permission → `POST /start` → gửi vị trí đầu tiên ngay + timer
     định kỳ **30s** (`gpsSendInterval`); GPS lỗi 1 tick → bỏ qua, tick sau thử lại
     (`:57-77`)
   - `end()`: tắt timer TRƯỚC → `POST /end`; thành công → `EndSyncState.synced`,
     trả true; **fail → KHÔNG đánh dấu kết thúc**, `_endSync = pending`, trả false
     (`:79-99`) — plan2_final §6.2 không silently swallow
   - `reconcile()`: app reopen → hỏi server trạng thái trip; ended/cancelled → dừng
     GPS local + synced; còn active → gửi ngay 1 vị trí resume (`:101-116`)
   - Hủy timer khi provider dispose (`ref.onDispose`)
3. **TripRunScreen** (`trip_run_screen.dart`):
   - initState → `reconcile()` (§6.3)
   - start fail do permission → SnackBar "Cần quyền truy cập vị trí để chạy chuyến"
   - end fail → **banner lỗi đỏ** "Chuyến chưa được kết thúc trên máy chủ — bấm
     'Kết thúc chuyến' để thử lại" + SnackBar "Chưa sync được với máy chủ — GPS đã
     tắt, vui lòng thử lại" + KHÔNG rời màn hình (nút Kết thúc vẫn hiện để retry)
   - end thành công → điều hướng `context.go('/home')`
   - Watch controller để giữ alive (tránh "Ref disposed")

#### Scenario: End offline → banner chưa sync

- **GIVEN** driver đang chạy chuyến, mất mạng
- **WHEN** bấm "Kết thúc chuyến"
- **THEN** timer GPS tắt, banner "chưa sync" hiện, app vẫn ở màn chuyến; có mạng lại
  bấm Kết thúc lần nữa → sync OK → về home

#### Scenario: Reopen app giữa chuyến

- **GIVEN** trip `active` phía server, app bị kill và mở lại
- **WHEN** vào màn chuyến
- **THEN** reconcile thấy active → tiếp tục gửi GPS; nếu server đã ended (do 1 lần
  retry trước) → dừng GPS local, không lỗi

#### Scenario: Từ chối quyền GPS

- **WHEN** bấm Bắt đầu nhưng user từ chối permission
- **THEN** SnackBar hướng dẫn mở quyền, chuyến KHÔNG được start (không gọi POST /start)

## Cần làm rõ

1. **Throttle KV (`loclast`) cũng TTL 2h** — dùng chung `LOC_TTL_SECONDS` cho key
   throttle; nghĩa là sau 2h không chạy, throttle tự reset (đúng ý — vô hại), nhưng
   về mặt khái niệm throttle window (30s) và TTL là 2 đơn vị khác nhau dùng chung
   1 hằng. Chấp nhận cho P0?
2. **`updateDriverLocation` không kiểm tra trip thuộc driver** — comment ghi rõ
   "route đã làm"; route check ownership + status trước khi gọi. An toàn hiện tại
   nhờ 1 điểm gọi duy nhất — nếu sau này có đường gọi khác sẽ bỏ sàng. Chấp nhận
   bố trí này?
3. **`startTrip` cho phép start từ `planned` nhưng không chặn `end` từ `planned`** —
   `endTrip` nhận cả planned → ended (driver tạo chuyến rồi kết thúc mà không chạy).
   Chủ đích (cho phép bỏ chuyến) hay cần tách "hủy chuyến" riêng? Hiện không có
   API cancel trip.

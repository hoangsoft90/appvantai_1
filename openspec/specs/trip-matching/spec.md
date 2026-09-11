# trip-matching Specification

## Purpose

Core value của app — "Cargo radar": tài xế khai chuyến (điểm đi → điểm đến), hệ thống
vẽ tuyến (OSRM, có cache) và chạy **Route-aware Matching Pipeline 6 bước** để tìm các
đơn hàng nằm trên/ gần tuyến, cùng hướng, kịp thời gian, vừa xe — trả Top-5 kèm score
chuẩn hóa 100 và **reasons giải thích được** (plan §5-§7, plan2_final §4).

Phạm vi: Worker (`worker/src/routes/trips.ts`, `worker/src/services/trips.ts`,
`worker/src/services/matching.ts`, `worker/src/lib/geo.ts`, `worker/src/services/route_cache.ts`,
`worker/migrations/0004_route_matching.sql`, `0008_trip_type.sql`) + Mobile
(`mobile/lib/feature/trip/**` — form tạo chuyến, radar matches). Tooling pilot
(seed/smoke/metrics scripts trong `worker/scripts/`) là harness tái tạo hành vi
này trên corridor thật — xem Verification evidence cuối spec.

## Requirements

### Requirement: POST /trips — driver khai chuyến

`POST /trips` (role gate driver → 403 `FORBIDDEN`, consent enforce cho mọi method
non-GET — `worker/src/routes/trips.ts:64-95`) **PHẢI**:

1. Validate input qua `parseTripInput` (`trips.ts:12-43`): `from_lat/from_lng/to_lat/to_lng`
   là số hữu hạn (400 `INVALID_FIELD`), lat ∈ [-90,90], lng ∈ [-180,180];
   `from_address`/`to_address` trim, cắt còn 200 ký tự
2. `trip_type` ∈ `one_way` | `return` (default `one_way`), khác → HTTP 400
   `INVALID_TRIP_TYPE` (`trips.ts:81-85`) — `return` = xe rỗng chiều đi, tìm hàng
   chiều về B→A (plan2_final §4.1)
3. Rate limit tạo chuyến **20/giờ trên KV** (key `triprl:<driverId>`, TTL 1h) —
   `worker/src/services/trips.ts:59-68` — khác với orders/contact dùng D1 atomic
   (xem Cần làm rõ #2)
4. Tính route qua `getCachedRoute` (D1 `route_cache` trước, maps provider sau —
   chi tiết cache thuộc capability `maps-geocoding`) — `trips.ts:78`
5. INSERT trip `status='planned'` với `route_polyline` (encode 1e6), `distance_m`,
   `duration_s`, `trip_type` — `trips.ts:72-93`
6. Response 201 `{ data: Trip }`

#### Scenario: Driver tạo chuyến one_way

- **GIVEN** driver đã consent
- **WHEN** `POST /trips` với tọa độ A→B hợp lệ, `trip_type: 'one_way'`
- **THEN** HTTP 201, trip `status='planned'`, có `route_polyline` + `distance_m` +
  `duration_s` từ provider maps, `trip_type='one_way'`

#### Scenario: Driver tạo chuyến return

- **WHEN** `POST /trips` với `trip_type: 'return'`
- **THEN** trip lưu `trip_type='return'` — matching sẽ tính bearing theo chiều B→A

#### Scenario: trip_type sai

- **WHEN** `POST /trips` với `trip_type: 'round'`
- **THEN** HTTP 400 `INVALID_TRIP_TYPE` ("trip_type phải là one_way hoặc return")

#### Scenario: Customer tạo chuyến

- **GIVEN** user role customer
- **WHEN** `POST /trips`
- **THEN** HTTP 403 `FORBIDDEN` ("Chỉ tài xế mới được tạo chuyến.")

#### Scenario: Vượt 20 chuyến/giờ

- **GIVEN** driver đã tạo 20 chuyến trong 1 giờ
- **WHEN** tạo chuyến 21
- **THEN** HTTP 429 `TRIP_RATE_LIMITED`

### Requirement: POST /trips/:id/matches — pipeline matching 6 bước

`POST /trips/:id/matches` (role gate driver — `worker/src/routes/trips.ts:98-105`)
**PHẢI** chạy `runMatching` (`worker/src/services/matching.ts:74-181`) theo pipeline:

**Điều kiện vào**: driver_profile tồn tại + `status='active'`, không → trả `[]`;
trip `ended|cancelled` → HTTP 400 `TRIP_NOT_ACTIVE` (`worker/src/services/trips.ts:118-125`).

**Bước 1 — Pre-filter SQL theo corridor grid** (`corridorFilter`
`matching.ts:186-241`): resample polyline còn ~300 điểm → tính bounding box grid
(cell 0.05°, mở rộng ±1 ô) → 1 query D1 chỉ lấy đơn
`status='posted' AND expires_at > now AND (vehicle_requirement='any' OR = xe driver)
AND weight_kg ≤ capacity AND grid_lat BETWEEN ... AND grid_lng BETWEEN ...` —
kèm **NOT EXISTS blocks 2 chiều** (plan2_final §1.5: block chặn matching ngay ở SQL).

**Bước 2 — Corridor**: `distanceToPolylineKm(pickup, corridor)` — pickup cách tuyến
> **10 km** → hard reject (`MAX_PICKUP_DISTANCE_KM`, `matching.ts:101-102`).

**Bước 3 — Direction**: `bearingDiffDeg(driverBearing, bearing(pickup→delivery))`;
driver bearing = A→B nếu `one_way`, **B→A nếu `return`**; angle > **135°** → hard
reject (`OPPOSITE_ANGLE`, `matching.ts:104-112`).

**Bước 4 — Time**: hết khung giờ (`pickup_to < now`) → hard reject; **pickup
feasibility** (plan2_final §4.2): khoảng cách từ điểm xuất phát hiệu lực
(one_way: origin; return: destination) tới pickup, tốc độ kế hoạch bảo thủ
40 km/h + buffer 30 phút — không kịp trước `pickup_to` → hard reject
(`matching.ts:114-128`).

**Bước 5 — Score 6 thành phần** (tổng 110, `matching.ts:244-279`):
distance (từ origin hiệu lực tới pickup, max 20) + route (pickup khỏi tuyến,
max 30) + direction (angle, max 25) + vehicle (15 — đã qua filter) + capacity
(tỉ lệ weight/capacity, max 10) + time (độ sớm pickup_from, max 10).

**Bước 6 — Top-5 detour OSRM**: sort theo subtotal, chỉ Top **5** (`TOP_N`) gọi
routing (tiết kiệm API — plan §14): routeStart→pickup→delivery→routeEnd
(one_way: origin→…→destination; return: destination→…→origin); detour =
(3 chặng) − baseKm; **detour > 15 km → hard reject** (`MAX_DETOUR_KM`);
routing lỗi → `detour_km = null`, bỏ bonus, vẫn giữ kết quả.

**Score cuối**: bonus detour (15 nếu <3km, 10 nếu ≤7km, 5 nếu còn lại);
`score = round((subtotal + bonus) / 125 × 100)` — `matching.ts:161-167`.

**Persist**: toàn bộ results lưu bảng `matches` qua **db.batch atomic**
(DELETE cũ của trip + INSERT mới; batch rỗng vẫn DELETE để clear snapshot) —
`matching.ts:286-313` (plan2_final §3.5).

**Reasons giải thích được** (plan §7): luôn gồm "Điểm lấy cách tuyến X km",
hướng giao, yêu cầu xe, tải trọng, thời gian; thêm "Độ lệch tuyến chỉ X km"
khi có detour — `matching.ts:281-297`.

#### Scenario: Đơn trên tuyến cùng hướng được match

- **GIVEN** trip A→B (one_way), đơn pickup cách tuyến 1km, giao cùng hướng, khung giờ còn, weight ≤ capacity
- **WHEN** driver quét radar
- **THEN** đơn xuất hiện trong results với score > 0, reasons có "Điểm lấy cách tuyến 1.x km"

#### Scenario: Pickup quá xa tuyến bị loại

- **GIVEN** đơn pickup cách tuyến 12 km (> 10)
- **WHEN** quét radar
- **THEN** đơn KHÔNG xuất hiện (hard reject bước 2), không tốn detour call

#### Scenario: Ngược hướng bị loại

- **GIVEN** đơn có bearing pickup→delivery ngược > 135° so với hướng driver
- **WHEN** quét radar
- **THEN** đơn bị loại ở bước 3

#### Scenario: Return trip tìm hàng chiều về

- **GIVEN** trip `trip_type='return'` A→B, đơn hàng B→A trên tuyến
- **WHEN** quét radar
- **THEN** bearing driver tính B→A, điểm xuất phát hiệu lực là B, detour tính
  destination→pickup→delivery→origin — đơn B→A được match bình thường

#### Scenario: Không kịp lấy hàng bị loại

- **GIVEN** đơn `pickup_to` sau now 20 phút, driver cách pickup 15 km
  (15/40×60 + 30 = 52.5 phút > 20)
- **WHEN** quét radar
- **THEN** đơn bị loại (pickup feasibility hard reject)

#### Scenario: Detour quá lớn bị loại

- **GIVEN** đơn lọt Top-5 nhưng OSRM trả detour 19 km (> 15)
- **WHEN** quét radar
- **THEN** đơn bị loại ở bước 6

#### Scenario: OSRM lỗi vẫn trả kết quả

- **GIVEN** routing provider timeout cho 1 đơn trong Top-5
- **WHEN** quét radar
- **THEN** đơn đó vẫn trả về với `detour_km: null`, không có bonus, không có reason detour

#### Scenario: Quét lại thay thế snapshot cũ nguyên vẹn

- **GIVEN** trip đã có 3 match trong bảng `matches` từ lần quét trước
- **WHEN** quét lại trả 2 match mới
- **THEN** db.batch xóa 3 cũ + insert 2 mới trong 1 transaction — không bao giờ
  thấy trạng thái rỗng hoặc trộn lẫn

#### Scenario: Đơn của user đã block bị loại ở SQL

- **GIVEN** customer đã block driver (1 chiều)
- **WHEN** driver quét radar
- **THEN** đơn của customer đó không bao giờ vào kết quả (NOT EXISTS trong corridorFilter)

#### Scenario: Driver profile chưa active

- **GIVEN** driver mới onboarding chưa khai xe (profile rỗng)
- **WHEN** quét radar
- **THEN** trả `[]` ngay (không chạy pipeline)

#### Scenario: Đơn yêu cầu loại xe khác bị loại ngay ở pre-filter

- **GIVEN** driver xe van, đơn `vehicle_requirement='truck'` nằm trên tuyến
- **WHEN** quét radar
- **THEN** đơn bị loại ở bước 1 (WHERE của corridorFilter), không tốn scoring
  hay detour call

### Verification evidence — Phase 6 pilot corridor (2026-09-10)

Pipeline được chứng minh trên dữ liệu corridor seed HN→HP (MAPS_PROVIDER=mock):

- **Seed** `bash worker/scripts/seed_pilot.sh` (= `npm run seed:pilot`;
  idempotent — reset data seed `notes='pilot'` mỗi lần chạy, `--reset-seed`
  để xóa không tạo lại): 4 tài xế (truck 5t/8t, van 1.5t, pickup 1.2t) +
  8 đơn (6 trên corridor + 2 nhiễu) + trip HN→HP mỗi tài xế.
- **Kết quả**: 4/4 tài xế có ≥1 match — truck 4 match (score 100/100/90/61),
  van 2, pickup 2 → filter `vehicle_requirement` + capacity hoạt động đúng;
  2 đơn nhiễu (Quảng Ninh, Thanh Hóa) bị grid pre-filter loại — không tài xế
  nào thấy.
- **Smoke full loop** `npm run pilot:smoke` (`worker/scripts/pilot_smoke.sh`)
  **14/14 PASS**: radar thấy đơn seed (score, pickup_km, reasons ≥3) → contact
  trả SĐT → accept → cancel-sau-accept bị chặn 409 `CANCEL_NOT_ALLOWED` →
  GPS planned-reject / active-OK / end-dừng → pickup → in_transit → delivered
  → customer complete → `completed`.
- Matches persist vào bảng `matches` — `npm run pilot:metrics`
  (`scripts/pilot_metrics.sql`) đọc funnel từ đó.

### Requirement: GET /trips + GET /trips/:id — xem chuyến của mình

1. `GET /trips`: trả tối đa 20 chuyến gần nhất của chính driver
   (`listTrips` `worker/src/services/trips.ts:96-102`)
2. `GET /trips/:id`: chi tiết chuyến, chỉ chủ chuyến — sai chủ → HTTP 404
   `TRIP_NOT_FOUND` (`getTrip` `trips.ts:112-117`, ownership trong WHERE)

#### Scenario: Driver chỉ thấy chuyến của mình

- **GIVEN** driver A có 2 chuyến, driver B có 1
- **WHEN** A gọi `GET /trips`
- **THEN** chỉ nhận 2 chuyến của A

#### Scenario: Đọc chuyến người khác

- **WHEN** driver B gọi `GET /trips/<id-của-A>`
- **THEN** HTTP 404 `TRIP_NOT_FOUND` (WHERE `driver_id = ?`)

### Requirement: Mobile — trip form (geocode + trip_type) và radar matches

1. **Trip form** (`mobile/lib/feature/trip/presentation/screens/trip_form_screen.dart`):
   nhập 2 điểm bằng **geocode search** (không nhập tọa độ tay — Phase E), preview
   địa chỉ đọc được; **SegmentedButton chiều chuyến** "Đi 1 chiều / Có chiều về"
   (plan3 Mục 4) map `trip_type` `one_way`/`return`; tạo xong → radar
2. **Radar** (`trip_matches_screen.dart`): chạy `POST /trips/:id/matches` qua
   `TripRepository.findMatches`; mỗi `MatchResult` parse `score`, `detour_km`,
   `pickup_km` (plan3 Mục 4), `reasons`, `order`
3. **Match Card** (plan3 Mục 4): hàng stats rõ ràng — score, "Khỏi tuyến" (pickup_km),
   "Độ lệch" (detour_km, hiện "—" khi null), khối lượng; reasons tối đa 5 dòng;
   nút Liên hệ / Nhận chuyến (chi tiết hành vi thuộc capability `driver-engagement`)
4. **Empty state** (plan3 Mục 4): khi 0 match hiện gợi ý hành động — nới khung giờ,
   tạo đơn thử/doi tuyến, khai báo **chiều về** (điều hướng lại trip form khi
   đang one_way)

#### Scenario: Driver quét radar thấy match kèm stats

- **GIVEN** có 1 đơn trên tuyến hợp lệ
- **WHEN** bấm quét radar
- **THEN** match card hiển thị score + khoảng cách khỏi tuyến + độ lệch + reasons

#### Scenario: Radar rỗng gợi ý chiều về

- **GIVEN** trip one_way không có match nào
- **WHEN** màn radar hiển thị
- **THEN** empty state có gợi ý khai báo chuyến chiều về (và các gợi ý khác), bấm
  được để quay lại form

## Cần làm rõ

1. **Cột `direction` luôn được ghi `'one_way'` cứng** — INSERT trong `createTrip`
   hardcode `'one_way'` vào cột `direction` và bind `tripType` vào cột `trip_type`
   (`worker/src/services/trips.ts:75-93`). `direction` là cột thừa từ trước migration
   0008 (thêm `trip_type`); mọi logic hiện tại đọc `trip_type`, không ai đọc
   `direction`. Dead column — giữ để backward-compat hay xóa trong migration sau?
2. **Rate limit tạo chuyến dùng KV (không atomic)** — `enforceTripRateLimit` dùng
   KV GET→check→PUT (TOCTOU), trong khi orders/contact đã harden sang D1 atomic
   (plan2_final §3.4). Tạo chuyến ít nhạy cảm hơn (tự làm mình, không tác động
   người khác) nên xấp xỉ chấp nhận được — chủ đích hay còn nợ harden?
3. **Comment route `GET /trips` ghi "active first" nhưng ORDER BY `created_at DESC`**
   (`trips.ts:95-102`) — comment lệch code. Mobile hiện tự sắp lại nếu cần. Bên nào
   là ý định đúng?

# maps-geocoding Specification

## Purpose

Nền tảng maps **0đ chi phí** cho toàn hệ thống: search địa chỉ (geocode) và tính
tuyến (route) qua **Nominatim + OSRM public** (OpenStreetMap — không Google Maps
trả phí, plan §14), với **cache 2 tầng** (KV cho geocode, D1 cho route) để tôn
trọng usage policy (Nominatim 1 req/s) và quota, kèm **timeout 10s + circuit
breaker** để provider chậm không treo matching (plan2_final §5.1-§5.2).

Phạm vi: Worker (`worker/src/routes/maps.ts`, `worker/src/maps/{provider,osrm,
nominatim,mock,resilience}.ts`, `worker/src/services/route_cache.ts`,
`worker/migrations/0004_route_matching.sql` — bảng `route_cache`) + Mobile
(các form dùng geocode search — chi tiết UX thuộc `order-marketplace` /
`trip-matching`).

## Requirements

### Requirement: GET /maps/geocode — search địa chỉ

`GET /maps/geocode?q=<address>` (auth middleware — `worker/src/routes/maps.ts:17-33`)
**PHẢI**:

1. Validate `q`: trim; < 3 ký tự → HTTP 400 `INVALID_QUERY` ("Từ khóa địa chỉ phải
   có ít nhất 3 ký tự"); > 200 ký tự → HTTP 400 `INVALID_QUERY` ("...tối đa 200 ký tự")
2. **Enforce legal consent** (`requireLegalConsent`) — geocode là action tốn resource
   bên thứ 3, chỉ user đã tick disclaimer mới dùng được
3. Gọi `geocodeWithCache` (KV cache 30 ngày, key `geo:<query lowercase trim>`) —
   `worker/src/services/route_cache.ts:75-92`
4. Mọi lỗi từ provider (kể cả không tìm thấy địa danh) → chuẩn hóa HTTP 400
   `GEOCODE_FAILED` ("Không tìm thấy địa chỉ, vui lòng thử từ khóa khác")
5. Response `{ data: { point: {lat, lng}, label } }` — label là `display_name` của
   Nominatim

#### Scenario: Geocode hợp lệ

- **GIVEN** user đã consent, provider hoạt động
- **WHEN** `GET /maps/geocode?q=Hải Phòng`
- **THEN** HTTP 200 `{ data: { point: {lat, lng}, label: "..." } }`; lần gọi sau với
  cùng query (case-insensitive) đọc KV cache, không gọi provider

#### Scenario: Query quá ngắn

- **WHEN** `GET /maps/geocode?q=Ha`
- **THEN** HTTP 400 `INVALID_QUERY` ("ít nhất 3 ký tự")

#### Scenario: Chưa consent

- **GIVEN** user chưa tick disclaimer
- **WHEN** gọi geocode
- **THEN** HTTP 403 `LEGAL_CONSENT_REQUIRED`

#### Scenario: Provider lỗi / không tìm thấy

- **GIVEN** Nominatim timeout (breaker open) hoặc không trả kết quả
- **WHEN** gọi geocode
- **THEN** HTTP 400 `GEOCODE_FAILED` (không leak lỗi hạ tầng, message thân thiện)

### Requirement: MapsProvider — mock | osrm|nominatim theo env

`getMapsProvider` (`worker/src/maps/provider.ts:23-28`) **PHẢI**:

1. `MAPS_PROVIDER=mock` → `mockProvider()` — deterministic, không network: geocode
   tra bảng ~12 địa danh corridor pilot HN→HP (Hà Nội, Hải Phòng, Hải Dương, Hưng Yên,
   Bắc Ninh, Thái Bình — có cả key không dấu), fallback điểm (21.0, 105.85); route =
   polyline 3 điểm (từ → midpoint lệch nhẹ → đến), distance = haversine × 1.3
   (road factor), duration = distance / 45km/h — `worker/src/maps/mock.ts:14-58`
2. Mặc định (không set / giá trị khác) → Nominatim geocode + OSRM route
3. Interface `MapsProvider` chỉ có 2 method `geocode(query)` và `route(from, to)` —
   business logic không bao giờ gọi fetch trực tiếp tới provider (plan §14: thay
   provider không phải sửa business logic)

#### Scenario: Dev/test dùng mock

- **GIVEN** `MAPS_PROVIDER=mock` (wrangler.toml dev)
- **WHEN** geocode "KCN Thăng Long, Hà Nội"
- **THEN** trả điểm Hà Nội từ bảng địa danh, không có request ra internet

#### Scenario: Production dùng OSRM/Nominatim

- **GIVEN** env production không set `MAPS_PROVIDER`
- **WHEN** tạo trip
- **THEN** route lấy từ OSRM public server, geocode từ Nominatim

### Requirement: OSRM route — polyline + resilience

`osrmRouter` (`worker/src/maps/osrm.ts:13-45`) **PHẢI**:

1. Gọi `https://router.project-osrm.org/route/v1/driving/<lng,lat>;<lng,lat>` với
   `overview=full&geometries=polyline6&steps=false`, User-Agent `appvantai-mvp/0.1`
2. Parse `routes[0]` → decode polyline6 thành mảng LatLng, `distance_m`/`duration_s`
   làm tròn integer; `code !== 'Ok'` hoặc rỗng → throw
3. Bọc `withResilience` — timeout **10s** (AbortController) + circuit breaker
   (`worker/src/maps/resilience.ts`): ≥ **3 lỗi liên tiếp** → OPEN mạch 30s — mọi
   call trong cooldown fail ngay `ROUTING_BREAKER_OPEN` (fail-fast, không treo);
   hết cooldown → HALF-OPEN cho thử lại; thành công reset breaker
4. Kết quả route phải đi qua cache trước khi dùng tiếp (xem requirement cache)

#### Scenario: Route thành công

- **WHEN** OSRM trả route hợp lệ
- **THEN** nhận polyline đầy đủ + distance/duration, breaker reset về 0 lỗi

#### Scenario: OSRM chậm > 10s

- **WHEN** fetch bị abort sau 10s
- **THEN** throw timeout — caller (createTrip) fail request này, không treo

#### Scenario: 3 lỗi liên tiếp → breaker open

- **GIVEN** OSRM đang sập, 3 request liên tiếp fail
- **WHEN** request thứ 4 đến ngay sau đó (trong 30s cooldown)
- **THEN** fail ngay `ROUTING_BREAKER_OPEN` — không tốn 10s timeout mỗi request

### Requirement: Nominatim geocode — throttle theo usage policy

`nominatimGeocoder` (`worker/src/maps/nominatim.ts:24-56`) **PHẢI**:

1. **Throttle 1.1s giữa các request** (policy Nominatim tối đa 1 req/s) — xếp hàng
   tuần tự qua promise chain + wait gap; apply cho mọi call trong cùng isolate
2. Gọi `https://nominatim.openstreetmap.org/search?format=json&limit=1&countrycodes=vn
   &accept-language=vi&q=...` — giới hạn VN, kết quả tiếng Việt, User-Agent rõ ràng
   `appvantai-mvp/0.1 (pilot HN-HP corridor)`
3. Không có kết quả → throw `GEOCODE_NOT_FOUND` (route /maps/geocode chuyển thành
   400 `GEOCODE_FAILED`)
4. Bọc `withResilience` (timeout 10s + circuit breaker như OSRM)

#### Scenario: 3 geocode liên tiếp không burst Nominatim

- **GIVEN** 3 user search địa chỉ cùng lúc
- **WHEN** 3 request tới geocodeWithCache (cache miss)
- **THEN** các call Nominatim bị dàn trải ≥ 1.1s mỗi cái — không vi phạm policy

#### Scenario: Geocode giới hạn Việt Nam

- **WHEN** search địa chỉ ở nước ngoài
- **THEN** Nominatim với `countrycodes=vn` không trả kết quả → 400 `GEOCODE_FAILED`

### Requirement: Cache 2 tầng — KV (geocode) + D1 (route)

`worker/src/services/route_cache.ts` **PHẢI**:

1. **Route cache D1** (bảng `route_cache` — migration 0004): key =
   `origin_key`/`destination_key` là tọa độ làm tròn 4 chữ số thập phân (~11m —
   `coordKey` `:14-16`); hit khi `expires_at > now`; TTL **30 ngày**; miss → gọi
   provider → UPSERT (`ON CONFLICT(origin_key, destination_key) DO UPDATE`); lỗi
   cache write **không chặn luồng chính** (try/catch bỏ qua — `route_cache.ts:22-72`)
2. **Geocode cache KV**: key `geo:<query lowercase trim>`, TTL 30 ngày; cache hỏng
   (JSON parse fail) → geocode lại; lỗi write bỏ qua — `route_cache.ts:75-92`
3. Route cache phục vụ cả createTrip lẫn detour verification trong matching
   (Top-5 × 3 chặng) — cùng 1 cặp điểm được tính tuyến đúng 1 lần trong 30 ngày

#### Scenario: Tạo 2 trip cùng cặp điểm

- **GIVEN** trip A→B đã tạo trước đó (route đã cache D1)
- **WHEN** driver khác tạo trip A→B (tọa độ trùng tới ~11m)
- **THEN** route đọc từ route_cache, không gọi OSRM

#### Scenario: Cache write fail không làm hỏng request

- **GIVEN** D1 write cache lỗi (tạm thời)
- **WHEN** create trip
- **THEN** trip vẫn tạo thành công với route tươi (chỉ mất cache lần này)

#### Scenario: Geocode cache case-insensitive

- **GIVEN** "hà nội" đã được cache
- **WHEN** search "Hà Nội  " (khác hoa/thường + space)
- **THEN** cache hit (key đã lowercase + trim)

### Requirement: Mobile — geocode search trong các form

1. `TripRepository.geocode(query)` → `GET /maps/geocode?q=...` parse
   `GeocodeResult { lat, lng, label }` — dùng chung cho trip form và order form
   (plan3 Mục 5); lỗi `ApiException` message VN từ error envelope
   (`mobile/lib/feature/trip/data/trip_repository.dart`)
2. Cả 2 form không bao giờ yêu cầu user nhập số tọa độ; tọa độ nội bộ ẩn (preview
   chỉ hiện label địa chỉ — privacy plan §14)
3. Trip form dùng route metadata (distance/duration) hiển thị thông tin chuyến sau
   khi tạo (trip detail đọc từ backend, không tự tính route client-side)

#### Scenario: Order form search địa chỉ thành công

- **GIVEN** customer đang tạo đơn
- **WHEN** nhập "Hà Nội" → bấm tìm
- **THEN** preview hiện label địa chỉ đọc được; tọa độ chỉ nằm trong OrderDraft gửi
  lên, không hiển thị UI

## Cần làm rõ

1. **Circuit breaker là biến module-global trong isolate** — state
   `breaker` (`resilience.ts:15-18`) không được chia sẻ giữa các Cloudflare isolate
   và reset khi redeploy: breaker chỉ giảm thiểu harm cục bộ, không phải protection
   toàn cục. Chấp nhận cho P0 (đơn giản, 0đ) — hay cần Durable Object sau pilot?
2. **Nominatim throttle chỉ hiệu quả trong 1 isolate** — cùng giới hạn như trên: 2
   isolate chạy song song có thể vi phạm 1 req/s trong burst ngắn. KV-based throttle
   sẽ tốn thêm read mỗi call — chấp nhận xấp xỉ hiện tại cho P0?
3. **`/maps/geocode` nuốt mọi lỗi provider thành 400 `GEOCODE_FAILED`** — kể cả lỗi
   hạ tầng 5xx từ Nominatim/OSRM cũng trả 400 (client hiểu là "sai từ khóa"). Message
   thân thiện với user nhưng client không phân biệt được "không tìm thấy" vs "provider
   đang sập". Chấp nhận cho P0?
4. **Mock geocode luôn trả label = query đầu vào** (`mock.ts:40-42`) — dev không thấy
   được display_name thật; vô hại vì mock chỉ dùng dev/test.

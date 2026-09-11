# order-marketplace Specification

## Purpose

Capability đăng và quản lý đơn hàng (cargo orders) phía chủ hàng: tạo đơn với tọa độ
điểm lấy/giao, khối lượng, loại hàng, yêu cầu xe, khung giờ lấy, giá; xem/sửa/hủy đơn
của chính mình. Đơn là đầu vào của matching engine (capability `trip-matching`).

Đặc điểm nền tảng:
- **Grid Index** (plan §12): `grid_lat/lng = FLOOR(tọa độ pickup / 0.05)` (~5,5km/ô)
  tính lúc tạo/sửa — dùng làm pre-filter rẻ cho matching — `migrations/0003_cargo.sql:3-4, 33-36`,
  `worker/src/services/orders.ts:67-69`
- **P0 không browse chéo**: `GET /orders` chỉ trả đơn của chính user; driver tìm hàng
  qua matching, không xem danh sách toàn hệ thống — comment `worker/src/routes/orders.ts:19-22`

Phạm vi: Worker (`worker/src/routes/orders.ts` phần create/list/detail/patch,
`services/orders.ts`, `services/rate_limit.ts`, `migrations/0003_cargo.sql`) + Mobile
(`mobile/lib/feature/order/**` trừ phần lifecycle/contact/accept — xem specs riêng).

## Requirements

### Requirement: Tạo đơn hàng (POST /orders)

`POST /orders` **PHẢI**:

1. Chỉ cho role `customer` (driver gọi API trực tiếp bị chặn) → HTTP 403 `FORBIDDEN`
   — `worker/src/routes/orders.ts:38`
2. Bắt buộc đã legal consent → HTTP 403 nếu chưa (enforce server-side, checkbox client
   chỉ là UX) — `worker/src/routes/orders.ts:39`
3. Rate limit tạo đơn **ATOMIC trên D1**: key `postrl:<userId>`, tối đa **10 lần/giờ**,
   vượt → HTTP 429 `POST_RATE_LIMITED` — `worker/src/routes/orders.ts:42-43`,
   `consumeRateLimit` dùng `INSERT ... ON CONFLICT DO UPDATE ... RETURNING count`
   (1 statement atomic, không có cửa sổ TOCTOU) — `worker/src/services/rate_limit.ts:22-56`
4. Giới hạn đơn active: tối đa **5 đơn** ở trạng thái `posted`/`matched` mỗi customer,
   kiểm tra **ATOMIC** theo chiến lược INSERT → COUNT → vượt limit thì DELETE chính
   đơn vừa insert + throw 429 `ACTIVE_ORDER_LIMIT` — `worker/src/routes/orders.ts:44`,
   `createOrderChecked` `worker/src/services/orders.ts:250-268`,
   `createOrderWithActiveLimit` `worker/src/services/rate_limit.ts:79-115`
5. Đơn mới luôn có `status='posted'` — `worker/src/services/orders.ts:320-341`

Validate input (`validateOrderInput` create mode — `worker/src/services/orders.ts:148-247`):

| Trường | Rule | Lỗi |
|---|---|---|
| `pickup_lat`/`pickup_lng`, `delivery_lat`/`delivery_lng` | số thực trong [-90,90] / [-180,180] | 400 `INVALID_COORD` |
| `cargo_type` | ∈ `general` \| `food` \| `fragile` \| `furniture` \| `electronics` \| `building` \| `other` | 400 `INVALID_CARGO_TYPE` |
| `vehicle_requirement` | `any` hoặc ∈ 4 loại xe (van/pickup/truck/container) | 400 `INVALID_VEHICLE_REQUIREMENT` |
| `weight_kg` | integer 0 < n ≤ 100.000, bắt buộc | 400 `INVALID_FIELD` |
| `length_cm`/`width_cm`/`height_cm` | integer 0 ≤ n ≤ 2.000, tùy chọn (default 0) | 400 `INVALID_FIELD` |
| `price` | integer 0 ≤ n ≤ 1.000.000.000, bắt buộc | 400 `INVALID_FIELD` |
| `pickup_from`/`pickup_to` | ISO datetime hợp lệ, bắt buộc; `pickup_to` ≥ `pickup_from` | 400 `INVALID_DATETIME` / `INVALID_TIME_RANGE` |
| `pickup_address`/`delivery_address`/`notes` | text ≤ 300/300/500 ký tự, tùy chọn (default `''`) | 400 `INVALID_FIELD` |
| `expires_at` | ISO datetime ở tương lai, tùy chọn — **default = `pickup_to`** | 400 `INVALID_EXPIRY` |
| Thiếu field bắt buộc | — | 400 `INVALID_FIELD` ("Thiếu trường: ...") |

#### Scenario: Customer tạo đơn hợp lệ

- **GIVEN** customer đã consent, đang có 2 đơn active
- **WHEN** `POST /orders` với payload đầy đủ hợp lệ (không gửi `expires_at`)
- **THEN** HTTP 201 `{ order }` với `status='posted'`, `expires_at == pickup_to`,
  `grid_lat/grid_lng = FLOOR(pickup/0.05)`, `driver_id` chưa có

#### Scenario: Driver bị chặn tạo đơn

- **GIVEN** user role `driver` đã consent
- **WHEN** `POST /orders`
- **THEN** HTTP 403 `FORBIDDEN` ("Chỉ chủ hàng mới được tạo đơn")

#### Scenario: Chưa legal consent

- **GIVEN** customer chưa tick disclaimer (legal_consent_at null)
- **WHEN** `POST /orders` với payload hợp lệ
- **THEN** HTTP 403 với code lỗi consent (client phải gọi `POST /me/legal-consent` trước)

#### Scenario: Vượt rate limit 10 đơn/giờ

- **GIVEN** customer đã tạo 10 đơn trong window 1 giờ hiện tại
- **WHEN** tạo đơn thứ 11
- **THEN** HTTP 429 `POST_RATE_LIMITED` (counter tăng atomic — request đồng thời
  không đếm chung 1 lần)

#### Scenario: Vượt giới hạn 5 đơn active

- **GIVEN** customer đang có đúng 5 đơn `posted`
- **WHEN** tạo đơn thứ 6
- **THEN** đơn thứ 6 bị rollback (DELETE) khỏi DB và trả HTTP 429 `ACTIVE_ORDER_LIMIT`
  ("Bạn đang có 5 đơn hàng đang hoạt động..."); sau request, customer vẫn có đúng 5 đơn

#### Scenario: pickup_to trước pickup_from

- **WHEN** tạo đơn với `pickup_from = 10:00`, `pickup_to = 09:00`
- **THEN** HTTP 400 `INVALID_TIME_RANGE` ('Thời gian lấy hàng "đến" phải sau "từ"')

#### Scenario: expires_at trong quá khứ

- **WHEN** tạo đơn với `expires_at` đã qua
- **THEN** HTTP 400 `INVALID_EXPIRY` ("Thời gian hết hạn phải ở tương lai")

### Requirement: Xem danh sách và chi tiết đơn

1. `GET /orders`: trả **chỉ** đơn của chính user (`customer_id = userId`), sắp xếp
   `created_at` giảm dần — `worker/src/routes/orders.ts:49-52`,
   `listOrdersByCustomer` `worker/src/services/orders.ts:383-389`
2. `GET /orders/:id`: quyền xem bị giới hạn (plan2_final §1.2) — cho phép:
   chủ đơn, driver được gán (`driver_id`), driver đã liên hệ (bảng `contacts`),
   admin; người khác (kể cả driver chưa liên hệ) → **HTTP 404 `ORDER_NOT_FOUND`**
   (không leak sự tồn tại của đơn) — `worker/src/routes/orders.ts:55-62`,
   `assertOrderViewAccess` `worker/src/services/orders.ts:397-410`

#### Scenario: Customer thấy đúng đơn của mình

- **GIVEN** customer A có 3 đơn, customer B có 2 đơn
- **WHEN** A gọi `GET /orders`
- **THEN** chỉ nhận đúng 3 đơn của A, mới nhất lên đầu

#### Scenario: Driver chưa liên hệ không xem được đơn

- **GIVEN** đơn X của customer A, driver B chưa từng contact/accept đơn X
- **WHEN** B gọi `GET /orders/<X>`
- **THEN** HTTP 404 `ORDER_NOT_FOUND` (giống trường hợp đơn không tồn tại)

#### Scenario: Driver đã liên hệ xem được đơn

- **GIVEN** driver B đã `POST /orders/<X>/contact` thành công
- **WHEN** B gọi `GET /orders/<X>`
- **THEN** HTTP 200 với đầy đủ thông tin đơn

### Requirement: Lazy expiry — hết hạn tại thời điểm đọc

Đơn `posted` mà `expires_at < now` **PHẢI** được trả về với `status='expired'` ở mọi
lần đọc (get by id, list) — biến đổi trong bộ nhớ qua `effectiveOrder`, **không có
background job, không ghi DB** — `worker/src/services/orders.ts:370-375` (comment
plan §19), áp dụng tại `getOrderById` (:378-381) và `listOrdersByCustomer` (:383-389).

#### Scenario: Đơn quá hạn hiển thị hết hạn

- **GIVEN** đơn `posted` với `expires_at` = 1 giờ trước
- **WHEN** customer gọi `GET /orders`
- **THEN** đơn trả về với `status='expired'` (row trong DB vẫn giữ `posted`)

#### Scenario: Đơn accepted không bị ảnh hưởng expiry

- **GIVEN** đơn đã `accepted`, `expires_at` đã qua
- **WHEN** đọc đơn
- **THEN** status vẫn `accepted` (chỉ `posted` mới bị chuyển `expired`)

### Requirement: Sửa đơn (PATCH /orders/:id)

`PATCH /orders/:id` **PHẢI**:

1. Chấp nhận payload partial — chỉ validate các field được gửi (cùng rule với create)
   — `worker/src/routes/orders.ts:64-68`, `validateOrderInput(body, { partial: true })`
2. Ownership: đơn không tồn tại hoặc không thuộc user → HTTP 404 `ORDER_NOT_FOUND`
   — `worker/src/services/orders.ts:328-331`
3. Chỉ sửa được khi `status === 'posted'`; trạng thái khác → HTTP 400 `INVALID_STATUS`
   ("Chỉ có thể chỉnh sửa đơn ở trạng thái \"đang chờ\"") — `worker/src/services/orders.ts:332-335`
4. Đổi `pickup_lat`/`pickup_lng` → tính lại `grid_lat`/`grid_lng` tương ứng
   — `worker/src/services/orders.ts:342-343`
5. Không có field nào để cập nhật → HTTP 400 `INVALID_REQUEST` — `worker/src/services/orders.ts:365-368`

#### Scenario: Sửa giá đơn đang chờ

- **GIVEN** đơn `posted` của customer A
- **WHEN** A gọi `PATCH /orders/<id>` với `{ "price": 2000000 }`
- **THEN** HTTP 200, giá mới được lưu, `updated_at` refresh

#### Scenario: Sửa đơn đã có driver nhận

- **GIVEN** đơn ở trạng thái `accepted`
- **WHEN** chủ đơn gọi `PATCH /orders/<id>`
- **THEN** HTTP 400 `INVALID_STATUS` ("Chỉ có thể chỉnh sửa đơn ở trạng thái \"đang chờ\"")

#### Scenario: Người khác sửa đơn

- **GIVEN** đơn của customer A
- **WHEN** customer B gọi `PATCH /orders/<id>` với `{ "price": 1 }`
- **THEN** HTTP 404 `ORDER_NOT_FOUND` (không leak)

#### Scenario: Đổi điểm lấy tính lại grid

- **GIVEN** đơn có `pickup_lat = 21.00` (grid_lat = 420)
- **WHEN** PATCH `pickup_lat = 21.10`
- **THEN** `grid_lat` được tính lại thành 422 cùng lúc với tọa độ mới

### Requirement: Hủy đơn (POST /orders/:id/cancel)

`POST /orders/:id/cancel` **PHẢI**:

1. Chỉ cho role `customer` (chủ đơn); driver hủy đơn là P1 chưa làm
   — `worker/src/routes/orders.ts:74-78` (comment plan2_final §2.4)
2. Đi qua state machine tập trung: `transitionOrder(c.env, 'cancel', ...)` — ownership
   và transition rule xử lý trong lifecycle service; chi tiết transition rule (cho phép
   từ `posted`/`matched`) và timestamp `cancelled_at` thuộc capability `order-lifecycle`
   — `worker/src/routes/orders.ts:76`

#### Scenario: Customer hủy đơn đang chờ

- **GIVEN** đơn `posted` của customer A
- **WHEN** A gọi `POST /orders/<id>/cancel`
- **THEN** HTTP 200 với `status='cancelled'`

#### Scenario: Driver gọi hủy đơn

- **WHEN** driver gọi `POST /orders/<id>/cancel`
- **THEN** HTTP 403 `FORBIDDEN` (role gate trước khi vào lifecycle)

### Requirement: Mobile — form tạo đơn

`OrderFormScreen` **PHẢI** (viết lại theo plan3_final Mục 5 — nhập địa điểm bằng
geocode search, **không** có ô lat/lng thủ công):

1. Nhập địa điểm: 2 ô địa chỉ text (điểm lấy + điểm giao), mỗi ô kèm nút tìm
   (IconButton search, hiển thị spinner khi đang tìm). Bấm tìm → gọi geocode
   (`TripRepository.geocode` → `GET /maps/geocode`, capability `maps-geocoding`);
   query < 3 ký tự → chặn với SnackBar "Nhập địa chỉ ít nhất 3 ký tự";
   lỗi API → SnackBar message VN từ `ApiException` —
   `mobile/lib/feature/order/presentation/screens/order_form_screen.dart:60-94, 316-352`
2. Sau khi tìm thành công: hiển thị preview điểm đã chọn (icon location + label địa
   chỉ đọc được, tối đa 2 dòng) — **tọa độ lat/lng không bao giờ hiển thị** cho user
   (plan2_final §14 privacy) — `order_form_screen.dart:355-380`
3. Chặn submit khi chưa chọn đủ 2 điểm geocode: "Vui lòng tìm và chọn điểm lấy +
   điểm giao trước" — `order_form_screen.dart:141-145`
4. Form còn lại: dropdown loại hàng + yêu cầu xe (nhãn tiếng Việt khớp enum backend:
   `any` = "Xe bất kỳ" + 4 loại xe), khối lượng/kích thước/giá (chỉ cho nhập số qua
   `FilteringTextInputFormatter.digitsOnly`), ghi chú (max 500), khung giờ lấy —
   `order_form_screen.dart:196-262`
5. Khung giờ mặc định: `pickup_from = now + 1h`, `pickup_to = now + 8h`; chọn ngày +
   giờ qua picker; nếu set `pickup_to` trước `pickup_from` thì tự đẩy `pickup_to`
   sang +4h — `order_form_screen.dart:53-56, 97-119`
6. Validate client trước khi gửi: khối lượng integer > 0 ("Khối lượng phải là số
   nguyên > 0"), giá integer ≥ 0; **checkbox disclaimer bắt buộc** ("Vui lòng tick
   xác nhận điều khoản để đăng hàng") — `order_form_screen.dart:147-165, 176-179`
7. Draft không gửi `expires_at` (backend tự default = `pickup_to`), thời gian gửi dạng
   UTC ISO — `mobile/lib/feature/order/domain/order_models.dart` (`OrderDraft.toJson`)
8. Tạo thành công: invalidate danh sách đơn, điều hướng `context.go('/orders')`;
   lỗi → hiện `e.message`; nút submit vô hiệu + spinner khi đang gửi —
   `order_form_screen.dart:183-205, 311-314`

#### Scenario: Chủ hàng đăng đơn thành công qua geocode search

- **GIVEN** customer đã onboarding + consent
- **WHEN** nhập "Hà Nội" vào ô điểm lấy → bấm tìm → preview hiện label địa chỉ;
  làm tương tự cho điểm giao; điền khối lượng 5000, giá 3000000, tick disclaimer,
  bấm "Đăng đơn hàng"
- **THEN** app gọi `POST /orders` với tọa độ lấy từ kết quả geocode (client không hề
  nhập số tọa độ nào), về màn danh sách đơn với đơn mới xuất hiện

#### Scenario: Chưa chọn điểm geocode

- **WHEN** điền form nhưng chưa bấm tìm cho ít nhất 1 trong 2 ô địa chỉ, bấm tạo
- **THEN** hiện lỗi "Vui lòng tìm và chọn điểm lấy + điểm giao trước", không gọi API

#### Scenario: Truy vấn tìm địa chỉ quá ngắn

- **WHEN** nhập "Hà" (2 ký tự) rồi bấm nút tìm
- **THEN** SnackBar "Nhập địa chỉ ít nhất 3 ký tự", không gọi API geocode

#### Scenario: Chưa tick disclaimer ở form

- **WHEN** điền form hợp lệ (đã chọn đủ 2 điểm) nhưng chưa tick, bấm tạo
- **THEN** hiện lỗi "Vui lòng tick xác nhận điều khoản để đăng hàng", không gọi API

#### Scenario: Khối lượng không hợp lệ

- **WHEN** nhập khối lượng "abc" hoặc "0" rồi submit
- **THEN** hiện lỗi "Khối lượng phải là số nguyên > 0", không gọi API

### Requirement: Mobile — danh sách và chi tiết đơn

1. `OrderListScreen`: dữ liệu qua `OrderListController` (Riverpod codegen, invalidate
   để refresh); render qua `AsyncView` (Loading/Error/Retry); rỗng → `EmptyView` với
   nút "Tạo đơn"; có dữ liệu → danh sách `OrderCard` + `RefreshIndicator`, FAB "Tạo đơn";
   bấm card → `/orders/:id` — `mobile/lib/feature/order/presentation/screens/order_list_screen.dart:13-48`,
   `mobile/lib/feature/order/application/order_list_controller.dart:10-17`
2. Nhãn trạng thái tiếng Việt đủ 11 trạng thái khớp backend; hằng số
   `canCancelOrder` = `posted` | `matched`; `canContact` = `posted` | `matched`;
   `canAccept` = `posted` | `matched` | `contacted` —
   `mobile/lib/feature/order/domain/order_models.dart:4-39`

#### Scenario: Danh sách đơn rỗng

- **GIVEN** customer chưa có đơn nào
- **WHEN** mở `/orders`
- **THEN** hiện EmptyView "Chưa có đơn hàng nào. Bấm \"Tạo đơn\" để đăng mối hàng đầu tiên."

#### Scenario: Lỗi mạng khi tải danh sách

- **WHEN** `GET /orders` fail lỗi mạng
- **THEN** AsyncView hiện ErrorView với nút Retry (gọi lại bằng invalidate provider)

## Cần làm rõ

1. **Form tạo đơn nhập tọa độ lat/lng tay — ĐÃ GIẢI QUYẾT 2026-09-09 (plan3_final
   Mục 5)**: order form đã được viết lại sang geocode search (giống trip form Phase E),
   tọa độ ẩn, chặn submit khi chưa chọn điểm. Test bằng chứng:
   `mobile/test/feature/order/order_flow_test.dart` (search → preview → tạo đơn OK).
   Requirement "Mobile — form tạo đơn" ở trên mô tả hành vi MỚI.
2. **Dead code ở orders service** — các export sau không còn route nào gọi sau khi
   harden (Phase C/plan2_final §2.3): `cancelOrder` (thay bằng `transitionOrder`),
   `createOrder` (thay bằng `createOrderChecked`), `enforcePostRateLimit` KV
   (thay bằng `enforceRateLimit` D1 atomic), `enforceActiveOrderLimit`
   (`worker/src/services/orders.ts:271-285` — comment ghi rõ "giữ cho backward-compat
   kiểm tra mềm, không còn gọi ở route"). Giữ lại hay xóa sau baseline?
3. **`PATCH /orders/:id` không enforce legal consent và không có role gate**
   (chỉ ownership qua `customer_id` check trong `updateOrder`). Consent chỉ enforce ở
   `POST /orders` — customer đã consent rồi bị thu hồi (không có cơ chế thu hồi) hoặc
   luồng bất thường không ảnh hưởng thực tế, nhưng về nguyên tắc PATCH lỏng hơn POST.
   Chấp nhận?
4. **Chi tiết concurrency của active-order limit**: `createOrderWithActiveLimit` dùng
   3 statement rời (INSERT → COUNT → DELETE) chứ không phải `db.batch`; comment khẳng
   định "D1 serialize writes nên order bị delete chắc chắn là của request hiện tại"
   (`rate_limit.ts:95-96`) — dưới 2 request đồng thời, DELETE xóa "đơn posted mới nhất"
   có thể là đơn của request kia, nhưng **invariant cuối cùng vẫn đúng** (≤5 active,
   E2E Phase C 15 POST đồng thời đã pass 12/12). Chấp nhận hành vi này đúng như được
   test, hay ghi nhận cần chuyển sang batch/transaction rõ ràng sau pilot?

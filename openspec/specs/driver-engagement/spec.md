# driver-engagement Specification

## Purpose

Capability tài xế "bám theo" một đơn hàng: **liên hệ chủ hàng** (mở khóa SĐT sau
khi contact — P0 không chat realtime) và **atomic accept** (invariant quan trọng
nhất của hệ thống: nhiều driver accept cùng đơn → chỉ 1 người thắng). Đây là
cầu nối giữa matching (capability `trip-matching`) và lifecycle
(capability `order-lifecycle`).

Phạm vi: Worker (`worker/src/services/contacts.ts`, `worker/src/services/accept.ts`,
`worker/src/services/authorization.ts`, `worker/src/routes/orders.ts` phần
contact/accept/driver-location, `worker/migrations/0005_safety.sql`) + Mobile
(`mobile/lib/feature/order/data/order_repository.dart` phần contact/accept/driverDistance,
`mobile/lib/feature/trip/presentation/screens/trip_matches_screen.dart` — Match Card).

## Requirements

### Requirement: POST /orders/:id/contact — driver liên hệ chủ hàng

`POST /orders/:id/contact` (role gate `driver` — `worker/src/routes/orders.ts:82-97`)
**PHẢI** thực hiện theo đúng thứ tự qua `contactDriverToCustomer`
(`worker/src/services/contacts.ts:63-120`):

1. Đọc đơn: không tồn tại hoặc `expired` → HTTP 404 `ORDER_NOT_FOUND`
2. Status chỉ nhận `posted` | `matched`, khác → HTTP 400 `INVALID_STATUS`
   ("Đơn hàng không còn nhận liên hệ")
3. Eligibility checks **TRƯỚC khi cấp SĐT** (plan2_final §1.3):
   `requireActiveDriverProfile` → 403 `DRIVER_PROFILE_INCOMPLETE`;
   `requireLegalConsent` → 403 `LEGAL_CONSENT_REQUIRED`;
   `requireNotBlockedEitherDirection` → 403 `USER_BLOCKED`
   (`worker/src/services/contacts.ts:76-79`, `authorization.ts:29-63`)
4. Rate limit **ATOMIC trên D1**: key `contactrl:<driverId>`, tối đa **20 lần/giờ**,
   vượt → HTTP 429 `CONTACT_RATE_LIMITED` — `worker/src/services/contacts.ts:27-40`
5. Customer phải tồn tại + `status='active'`, khác → HTTP 400 `USER_UNAVAILABLE`
6. **db.batch 2 statement atomically** (`contacts.ts:88-99`):
   INSERT `contacts` (`contact_type='phone'`) + UPDATE đơn
   `posted|matched → contacted` có re-check `status IN ('posted','matched')`
   trong WHERE (concurrent contact không resurrect đơn đã accept/cancel)
7. Ghi audit log `action: 'contact'` kèm IP; response `{ data: ContactResult }` với
   `phone`, `name` của customer — **SĐT chỉ trả khi contact thành công** (privacy §18)

#### Scenario: Driver contact đơn posted thành công

- **GIVEN** driver profile active, đã consent, không bị block
- **WHEN** `POST /orders/<id>/contact` với đơn `posted`
- **THEN** HTTP 200 `{ data: { order_id, status: 'contacted', phone: "<SĐT chủ hàng>", name, contact_type: 'phone', created_at } }`; bảng `contacts` có row mới; đơn chuyển `contacted`; audit log `contact` được ghi

#### Scenario: SĐT không leak trước khi contact

- **GIVEN** driver chưa từng contact đơn X
- **WHEN** driver gọi bất kỳ API nào không phải contact (list matches, GET order qua quyền hạn chế)
- **THEN** response KHÔNG chứa SĐT của customer; SĐT chỉ xuất hiện trong kết quả của `POST /contact`

#### Scenario: Contact đơn đã accept

- **GIVEN** đơn đang `accepted` (driver khác đã nhận)
- **WHEN** driver B gọi `POST /orders/<id>/contact`
- **THEN** HTTP 400 `INVALID_STATUS` ("Đơn hàng không còn nhận liên hệ")

#### Scenario: Vượt 20 contact/giờ

- **GIVEN** driver đã contact 20 lần trong 1 giờ
- **WHEN** contact lần 21
- **THEN** HTTP 429 `CONTACT_RATE_LIMITED` (counter D1 atomic — đồng thời không đếm chung)

#### Scenario: Customer bị block chặn contact

- **GIVEN** customer đã block driver B (1 chiều)
- **WHEN** B contact đơn của customer đó
- **THEN** HTTP 403 `USER_BLOCKED` ("Bạn không thể giao dịch với người dùng này")

#### Scenario: Driver chưa khai xe

- **GIVEN** user role driver nhưng driver_profile rỗng hoặc `status != 'active'`
- **WHEN** `POST /orders/<id>/contact`
- **THEN** HTTP 403 `DRIVER_PROFILE_INCOMPLETE` ("Hồ sơ tài xế chưa hoàn thiện...")

#### Scenario: Concurrent contact không resurrect

- **GIVEN** 2 driver contact cùng đơn `posted` gần đồng thời; driver A accept ngay giữa 2 request
- **WHEN** request của driver B chạm tới UPDATE `→ contacted`
- **THEN** UPDATE có `WHERE status IN ('posted','matched')` fail im lặng (0 changes) —
  đơn vẫn `accepted`, không bị kéo về `contacted` (row `contacts` của B vẫn được ghi —
  dùng cho quyền xem đơn, vô hại)

### Requirement: POST /orders/:id/accept — Atomic Accept

`POST /orders/:id/accept` (role gate `driver` — `worker/src/routes/orders.ts:100-112`)
**PHẢI** đi qua `atomicAccept` (`worker/src/services/accept.ts:20-103`) — đường riêng
tối ưu cho race quan trọng nhất, KHÔNG qua `transitionOrder`:

1. `requireActiveDriverProfile` → 403 nếu profile thiếu/không active
2. Quick checks (trước write, cho lỗi rõ ràng): đơn không tồn tại → 404
   `ORDER_NOT_FOUND`; đã là driver của đơn → **idempotent success** `{ accepted: true,
   status: 'accepted' }` (`accept.ts:33-35`); terminal
   (cancelled/expired/rejected) → HTTP 409 `INVALID_TRANSITION` ("Đơn đã ở trạng thái
   cuối..."); trạng thái khác posted/matched/contacted → HTTP 400
   `ORDER_ALREADY_ACCEPTED`
3. `requireLegalConsent` → 403; `requireNotBlockedEitherDirection` với customer → 403
   `USER_BLOCKED` — chạy sau status-check, trước write (`accept.ts:60-63`)
4. **Atomic UPDATE** (`accept.ts:69-76`): `SET driver_id=?, status='accepted',
   accepted_at=? WHERE id=? AND status IN ('posted','matched','contacted') AND
   driver_id IS NULL` — D1 single-writer, chỉ 1 request có `changes > 0`
5. `changes === 0` (thua race) → re-read: chính mình đã accept → 400 "Bạn đã nhận đơn
   này rồi"; người khác → 400 "Đơn đã được tài xế khác nhận" (`accept.ts:78-88`)
6. Audit log `action: 'accept'` kèm IP; response `{ data: { accepted, status } }`

#### Scenario: 8 driver race → 1 winner

- **GIVEN** đơn `posted`, 8 driver gọi accept gần đồng thời
- **WHEN** D1 thực thi tuần tự 8 atomic UPDATE
- **THEN** đúng 1 request thành công (`changes > 0`), 7 request còn lại nhận
  400 `ORDER_ALREADY_ACCEPTED` "Đơn đã được tài xế khác nhận" (E2E Phase C đã verify)

#### Scenario: Idempotent accept

- **GIVEN** driver A đã accept đơn
- **WHEN** A bấm accept lần nữa
- **THEN** HTTP 200 `{ data: { accepted: true, status: 'accepted' } }` — không lỗi,
  không ghi đè `accepted_at`

#### Scenario: Accept đơn terminal → 409 phân biệt

- **GIVEN** đơn `cancelled`
- **WHEN** driver accept
- **THEN** HTTP 409 `INVALID_TRANSITION` — khác mã 400 của "đã có người nhận",
  client phân biệt được 2 trường hợp

#### Scenario: Contacted vẫn accept được

- **GIVEN** driver đã contact (đơn `contacted`)
- **WHEN** driver đó accept
- **THEN** thành công `accepted` + `accepted_at` SET (contact không khóa quyền accept)

#### Scenario: Accept không cần contact trước

- **GIVEN** đơn `posted`, driver chưa từng contact
- **WHEN** driver accept trực tiếp
- **THEN** thành công (skip-step posted → accepted hợp lệ — xem spec `order-lifecycle` R1)

### Requirement: GET /orders/:id/driver-location — khoảng cách ẩn danh

`GET /orders/:id/driver-location` (`worker/src/routes/orders.ts:115-122`) **PHẢI**:

1. Chỉ chủ đơn được xem — `driverDistanceForOrder` check `customer_id`
   (chi tiết dữ liệu nguồn thuộc capability `trip-gps`)
2. Trả **khoảng cách làm tròn** từ driver tới điểm lấy + `updated_at`, **KHÔNG bao giờ**
   trả tọa độ chính xác của driver (privacy plan §13) — response `{ data: { distance_km, updated_at } }`

#### Scenario: Customer xem khoảng cách tài xế

- **GIVEN** đơn `accepted` có driver đang chạy trip active và đã POST location
- **WHEN** chủ đơn gọi `GET /orders/<id>/driver-location`
- **THEN** HTTP 200 `{ data: { distance_km: <số làm tròn>, updated_at } }` — không có
  trường lat/lng nào của driver

#### Scenario: Người khác gọi driver-location

- **WHEN** user không phải chủ đơn gọi endpoint
- **THEN** bị từ chối (404/403 theo check ownership trong `driverDistanceForOrder`)

### Requirement: Mobile — contact + accept từ Match Card

Match Card trong `TripMatchesScreen` **PHẢI**:

1. Nút "Liên hệ chủ hàng": gọi `OrderRepository.contact(id)` → `POST /orders/:id/contact`
   → tắt spinner **TRƯỚC** khi mở dialog → dialog "Liên hệ chủ hàng" hiển thị tên +
   SĐT (`SelectableText` cho phép copy) + hướng dẫn gọi điện; sau contact, nút chuyển
   thành "Đã liên hệ (<SĐT>)" —
   `mobile/lib/feature/trip/presentation/screens/trip_matches_screen.dart:122-157, 272-287`
2. Nút "Nhận chuyến": gọi `OrderRepository.accept(id)` → `POST /orders/:id/accept`
   → SnackBar "Bạn đã nhận chuyến! Chủ hàng sẽ thấy bạn." + invalidate
   `tripMatchesProvider` (đơn không còn nhận accept) —
   `trip_matches_screen.dart:163-178`
3. Cả 2 nút có trạng thái loading riêng (`_contacting`/`_accepting` — spinner thay
   icon, vô hiệu khi đang chạy); lỗi `ApiException` → SnackBar message VN từ error
   envelope — `trip_matches_screen.dart:158-160, 179-181`
4. Chi tiết đơn (customer, đơn có tài xế): tile khoảng cách tài xế ẩn danh qua
   `OrderRepository.driverDistance(id)` khi `status == 'accepted'` —
   `mobile/lib/feature/order/presentation/screens/order_detail_screen.dart`

#### Scenario: Driver contact từ radar và gọi điện

- **GIVEN** driver xem match card của đơn phù hợp
- **WHEN** bấm "Liên hệ chủ hàng"
- **THEN** dialog hiện SĐT copy được; đóng dialog → nút thành "Đã liên hệ (09xx...)"

#### Scenario: Driver accept và thấy xác nhận

- **WHEN** bấm "Nhận chuyến" trên đơn `posted`
- **THEN** SnackBar xác nhận, danh sách match refresh, đơn biến mất khỏi danh sách
  có thể accept

#### Scenario: Thua race accept trên mobile

- **GIVEN** driver khác đã accept đơn trước
- **WHEN** bấm "Nhận chuyến"
- **THEN** SnackBar hiện message 400 từ server "Đơn đã được tài xế khác nhận",
  không crash

## Cần làm rõ

1. **`contactDriverToCustomer` dùng `db.batch` nhưng batch không rollback khi statement
   thứ 2 ảnh hưởng 0 rows** — UPDATE `→ contacted` có thể fail im lặng trong race (mô tả
   ở scenario "Concurrent contact không resurrect") và row `contacts` vẫn được INSERT.
   Đây là chủ đích (row contacts dùng cho quyền xem đơn §1.2) hay cần check lại sau
   batch? Hiện trạng vô hại — chấp nhận được cho P0.
2. **Rate limit contact chạy TRƯỚC check `USER_UNAVAILABLE`** — driver contact đơn của
   customer đã bị deactivate vẫn bị trừ 1 lượt rate limit. Ảnh hưởng thực tế gần như
   bằng 0, ghi nhận để biết thứ tự check là chủ đích hay ngẫu nhiên.
3. **`atomicAccept` không kiểm tra `requireNotBlockedEitherDirection` cho chiều
   customer-block-driver đã bị block SAU khi order match** — block check chạy trước
   atomic UPDATE nên ổn; chỉ lưu ý block phát sinh giữa quick-check và UPDATE (cửa sổ
   nhỏ) không bị chặn. Chấp nhận cửa sổ race nhỏ này cho P0?

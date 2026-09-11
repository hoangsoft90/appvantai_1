# Spec: order-lifecycle

## Purpose

Quản lý vòng đời đơn hàng từ khi tạo đến khi hoàn thành/hủy/hết hạn thông qua **một state machine tập trung duy nhất** (`order_state_machine.ts`), đảm bảo:
- Mọi thay đổi trạng thái đều đi qua một contract duy nhất (không route/service nào tự viết điều kiện status rời rạc).
- Mỗi bước lifecycle có timestamp riêng để verify đúng trình tự (plan2_final §13 "correct timestamps").
- Concurrent request không ghi đè trạng thái nhau (conditional UPDATE).
- Đơn ở trạng thái terminal không thể "sống lại" (no-resurrect).

**Phạm vi**: backend Worker là authority (state machine + 5 lifecycle endpoints + cancel); mobile Flutter expose cancel (customer), hiển thị trạng thái và **UI lifecycle đầy đủ** cho cả driver (pickup/in-transit/delivered) lẫn customer (complete) — bổ sung theo plan3_final.md Mục 2 (chi tiết ở R7).

---

## Requirements

### R1 — State machine tập trung (source of truth duy nhất)

**`worker/src/services/order_state_machine.ts`**

- 11 trạng thái: `posted`, `matched`, `contacted`, `accepted`, `pickup`, `in_transit`, `delivered`, `completed`, `cancelled`, `expired`, `rejected`. (line 17-20)
- 4 trạng thái terminal: `completed`, `cancelled`, `expired`, `rejected` — `isTerminal()` dùng cho mọi check no-resurrect. (line 23)
- Ma trận transition `TRANSITIONS` (line 30-43):
  - `posted` → matched | contacted | accepted | cancelled | expired | rejected
  - `matched` → contacted | accepted | cancelled | expired | rejected
  - `contacted` → accepted | cancelled | expired | rejected
  - `accepted` → pickup | cancelled
  - `pickup` → in_transit | cancelled
  - `in_transit` → delivered | cancelled
  - `delivered` → completed | cancelled
  - terminal → (không gì cả)
- `canTransition(from, to)` ném **409 `INVALID_TRANSITION`** nếu from là terminal hoặc cặp (from, to) không có trong ma trận. (line 52-61)

#### Scenario
- **Terminal không thể chuyển tiếp** — Given order `status = 'completed'`, When gọi `canTransition('completed', bất kỳ)`, Then ném 409 `INVALID_TRANSITION` với message "Đơn đã ở trạng thái cuối..." (`order_state_machine.ts:54-56`).
- **Bước nhảy bị chặn** — Given order `status = 'accepted'`, When gọi `canTransition('accepted', 'delivered')`, Then ném 409 `INVALID_TRANSITION` (delivered không nằm trong allowed của accepted) (`order_state_machine.ts:57-60`).
- **Skip-step hợp lệ ở giai đoạn marketplace** — Given order `posted`, When driver accept trực tiếp (không contact), Then `posted → accepted` hợp lệ theo ma trận (lý do: driver có thể accept không cần contact trước) (`order_state_machine.ts:31`).
- **Chiều ngược bị chặn** — Given order `in_transit`, When gọi `canTransition('in_transit', 'accepted')`, Then ném 409 (không rollback trạng thái).

### R2 — Timestamp theo từng bước lifecycle

**`worker/migrations/0006_lifecycle.sql`**, **`worker/src/services/order_state_machine.ts:68-78`**

- Cột timestamp riêng trên `cargo_orders`: `accepted_at`, `pickup_at`, `in_transit_at`, `delivered_at`, `completed_at`, `cancelled_at` (migration 0006).
- `statusTimestampColumn(to)` map trạng thái đích → cột tương ứng; trả `null` cho `matched`/`contacted` (không có cột riêng).
- Mỗi transition SET đúng 1 cột timestamp + `updated_at` (ISO 8601 UTC).

#### Scenario
- **Accept ghi accepted_at** — Given driver accept thành công, Then `accepted_at` được SET cùng lúc `status = 'accepted'` (`lifecycle.ts` RULES.accept `tsColumn: 'accepted_at'`; `accept.ts:70-73`).
- **Delivered không đè accepted_at** — Given driver chuyển `in_transit → delivered`, Then chỉ `delivered_at` được SET, các timestamp trước đó giữ nguyên (mỗi rule chỉ SET `tsColumn` của đích).

### R3 — Contract actor → transition (RULES)

**`worker/src/services/lifecycle.ts:37-80`**

Mỗi lifecycle action ánh xạ đúng 1 rule với các trường: `actor` (ai được làm), `target` (trạng thái đích), `from` (danh sách trạng thái nguồn hợp lệ), `whereExtra`/`whereBindActor` (điều kiện ownership trong WHERE), `setDriverId` (chỉ accept), `requireAssigned` (chỉ driver được gán), `tsColumn`.

| Action | Actor | Target | From | Ownership trong WHERE | Ghi chú |
|---|---|---|---|---|---|
| `accept` | driver | accepted | posted, matched, contacted | `driver_id IS NULL` | SET `driver_id = actorId` |
| `pickup` | driver | pickup | accepted | `driver_id = ?` | chỉ driver được gán |
| `in_transit` | driver | in_transit | pickup | `driver_id = ?` | chỉ driver được gán |
| `delivered` | driver | delivered | in_transit | `driver_id = ?` | chỉ driver được gán |
| `complete` | customer | completed | delivered | `customer_id = ?` | chỉ chủ đơn |
| `cancel` | customer | cancelled | posted, matched, contacted, accepted, pickup | `customer_id = ?` | chỉ chủ đơn |

- `transitionOrder(env, action, orderId, actorId, ip)` là hàm duy nhất thực thi rule. (line 96-161)

#### Scenario
- **Driver chưa được gán gọi pickup → 404** — Given order `driver_id = NULL` (hoặc driver khác), When driver X gọi pickup, Then 404 `ORDER_NOT_FOUND` (requireAssigned fail — không leak sự tồn tại của đơn) (`lifecycle.ts:113-116`).
- **Driver là chủ đơn bị chặn** — Given user đồng thời là customer của đơn, When gọi action driver (pickup...), Then 403 `ROLE_FORBIDDEN` "Chỉ tài xế mới thực hiện được thao tác này" (`lifecycle.ts:122-124`).
- **Driver khác accept đơn đã có người nhận** — Given order `driver_id = driverA`, When driverB gọi accept, Then `order.driver_id !== null && !== actorId` → 404 (`lifecycle.ts:117-120`).
- **Customer gọi pickup → 403 role gate ở route** — Given user role customer, When POST `/orders/:id/pickup`, Then route chặn bằng `requireRole(userRole, 'driver')` trước khi vào `transitionOrder` (`routes/orders.ts:147-150`).

### R4 — Thực thi transition race-safe + audit

**`worker/src/services/lifecycle.ts:129-158`**

Trình tự bắt buộc của `transitionOrder`:
1. Đọc order → 404 nếu không tồn tại.
2. Ownership/actor check theo rule (404 cho người ngoài, không leak existence).
3. `requireLegalConsent` — mọi lifecycle action đều cần consent (§1.4). (`lifecycle.ts:127`)
4. `canTransition(order.status, rule.target)` — validate mặt state.
5. **Conditional UPDATE**: `UPDATE cargo_orders SET status=?, [driver_id=?], [ts=?], updated_at=... WHERE id=? AND status IN (from-list) [AND ownership]`.
6. Nếu `changes === 0` (race: ai đó đổi status trước) → re-read order + ném 409 `INVALID_TRANSITION` kèm trạng thái hiện tại.
7. `writeAuditLog` với `action: order_<action>`, metadata `{from, to}`, kèm IP.

#### Scenario
- **Race 2 driver accept qua transitionOrder** — Given 2 request đồng thời pass bước check, When cả 2 chạy UPDATE, Then D1 thực thi tuần tự: chỉ 1 request có `changes > 0`, request kia re-read thấy trạng thái mới và nhận 409 `INVALID_TRANSITION` "Đơn đang ở trạng thái..." (`lifecycle.ts:146-155`).
- **Consent thiếu → 403** — Given driver chưa tick legal consent, When gọi pickup, Then 403 `LEGAL_CONSENT_REQUIRED` trước khi UPDATE (`lifecycle.ts:127`).
- **Audit đủ mọi transition** — Given pickup thành công, Then bảng audit_logs có bản ghi `actorId`, `entityType: 'order'`, `action: 'order_pickup'`, `metadata.from = 'accepted'`, `metadata.to = 'pickup'` (`lifecycle.ts:156-163`).

### R5 — HTTP endpoints lifecycle

**`worker/src/routes/orders.ts:143-186`**

| Endpoint | Role gate | Hành vi |
|---|---|---|
| `POST /orders/:id/cancel` | customer | `transitionOrder('cancel')` → `{ order }` |
| `POST /orders/:id/pickup` | driver | `transitionOrder('pickup')` → `{ data: { order, status } }` |
| `POST /orders/:id/in-transit` | driver | `transitionOrder('in_transit')` → `{ data: { order, status } }` |
| `POST /orders/:id/delivered` | driver | `transitionOrder('delivered')` → `{ data: { order, status } }` |
| `POST /orders/:id/complete` | customer | `transitionOrder('complete')` → `{ data: { order, status } }` |

- Lưu ý shape response không đồng nhất: cancel trả `{ order }` (top-level), 4 endpoint còn lại trả `{ data: { order, status } }`.
- IP lấy từ header `CF-Connecting-IP` truyền vào audit log.

#### Scenario
- **Happy path đầy đủ** — Given đơn posted + driver đã accept, When driver gọi pickup → in-transit → delivered theo thứ tự và customer gọi complete, Then status lần lượt `accepted → pickup → in_transit → delivered → completed`, mỗi bước timestamp tương ứng được SET.
- **Skip transition qua API** — Given đơn `accepted`, When driver gọi trực tiếp `/in-transit`, Then 409 `INVALID_TRANSITION` (from-list của in_transit chỉ có `pickup`).
- **Hoàn thành trước khi giao** — Given đơn `in_transit`, When customer gọi `/complete`, Then 409 `INVALID_TRANSITION` (complete chỉ nhận from `delivered`).
- **Cancel sau khi hàng lên xe** — Given đơn `pickup` (đã lấy hàng), When customer cancel, Then thành công `cancelled` (backend cho phép; xem Cần làm rõ #1 về mobile).
- **Role sai** — Given token driver, When gọi `/complete`, Then 403 `ROLE_FORBIDDEN` (route gate customer).

### R6 — Accept đi qua đường riêng `atomicAccept` (cùng invariant)

**`worker/src/services/accept.ts`**

`POST /orders/:id/accept` **không** đi qua `transitionOrder` mà dùng `atomicAccept` — đường riêng tối ưu cho race quan trọng nhất, nhưng giữ cùng invariant state machine:
- Pre-checks: `requireActiveDriverProfile` → 404 nếu không thấy đơn → idempotent nếu `driver_id === actorId` (trả success không lỗi) → terminal → **409 `INVALID_TRANSITION`** → trạng thái khác (pickup/in_transit/...) → **400 `ORDER_ALREADY_ACCEPTED`** → consent + block-check 2 chiều.
- **Atomic UPDATE**: `SET driver_id=?, status='accepted', accepted_at=? WHERE id=? AND status IN ('posted','matched','contacted') AND driver_id IS NULL`. (`accept.ts:69-76`)
- `changes === 0` → re-read: nếu chính mình đã accept → 400 "Bạn đã nhận đơn này rồi"; người khác → 400 "Đơn đã được tài xế khác nhận". (`accept.ts:78-88`)
- Audit log `action: 'accept'`.

#### Scenario
- **Idempotent accept** — Given driver đã accept đơn, When bấm accept lần nữa, Then trả `{ accepted: true, status: 'accepted' }` không lỗi (`accept.ts:24-26`).
- **2 driver race → 1 winner** — Given 8 driver gọi accept đồng thời, Then đúng 1 request thành công, 7 request còn lại nhận 400 `ORDER_ALREADY_ACCEPTED` "Đơn đã được tài xế khác nhận" (E2E Phase C đã verify).
- **Đơn terminal không nhận được** — Given đơn `cancelled`, When accept, Then 409 `INVALID_TRANSITION` (khác mã 400 của "đã có người nhận" — client phân biệt được 2 trường hợp).
- **Driver bị block 2 chiều** — Given customer đã block driver, When driver accept đơn của customer đó, Then 403 `USER_BLOCKED` trước khi UPDATE (`accept.ts:60-62`).
- **Contacted vẫn accept được** — Given driver đã contact (đơn `contacted`), When driver đó accept, Then thành công `accepted` + `accepted_at` SET (contact không khóa quyền accept).

### R7 — Mobile: hiển thị trạng thái + hủy đơn (customer)

**`mobile/lib/feature/order/domain/order_models.dart`**, **`mobile/lib/feature/order/presentation/screens/order_detail_screen.dart`**, **`mobile/lib/feature/order/data/order_repository.dart`**

- `orderStatusLabel` map đủ 11 trạng thái backend sang tiếng Việt (posted→"Đang chờ", pickup→"Đang lấy hàng", in_transit→"Đang vận chuyển", delivered→"Đã giao", completed→"Hoàn thành"... trong `order_models.dart:3-16`).
- `canCancelOrder(status)` true với `posted | matched | contacted` — UI chỉ hiện nút hủy cho 3 trạng thái này (plan3 Mục 2 đã bổ sung `contacted`).
- **plan3 Mục 2 — UI lifecycle hoàn chỉnh**: `nextLifecycleAction(status, isDriver)` trả đúng 1 action cho mỗi trạng thái (driver: accepted→"Đã lấy hàng", pickup→"Bắt đầu giao", in_transit→"Đã giao hàng"; customer: delivered→"Xác nhận hoàn tất"), trả `null` khi không có action → UI ẩn nút, không bao giờ hiện nút sai state. `OrderRepository.transitionOrder(id, method)` gọi `POST /orders/:id/{pickup|in-transit|delivered|complete}`. Nút lifecycle có loading + toast kết quả ("Đã lấy hàng — Đang lấy hàng"), lỗi → SnackBar message VN, sau thành công invalidate detail + list.
- Flow hủy (`order_detail_screen.dart`): nút "Hủy đơn hàng" (chỉ khi `canCancelOrder`) → dialog xác nhận "Đơn hàng sẽ chuyển sang trạng thái 'Đã hủy'..." → `repository.cancelOrder(id)` → `POST /orders/:id/cancel` → invalidate list → `context.go('/orders')`; lỗi → SnackBar với message từ `ApiException` (message tiếng Việt từ error envelope).
- Chi tiết đơn hiển thị trạng thái chip + các section (điểm lấy/giao, hàng hóa, yêu cầu xe, thời gian); khi `status == 'accepted'` hiển thị tile khoảng cách tài xế ẩn danh; khi customer + đơn có tài xế → nút "Báo cáo / Chặn tài xế".

#### Scenario
- **Nút hủy đúng trạng thái** — Given đơn `contacted`, Khi mở chi tiết với tư cách customer, Thì thấy nút "Hủy đơn hàng".
- **Ẩn nút hủy sau accept** — Given đơn `accepted` + user customer, Khi mở chi tiết, Thì KHÔNG thấy nút hủy, CHỈ thấy nút driver lifecycle nếu là driver (đúng: customer không có action nào ở `accepted`).
- **Hủy thành công quay về danh sách** — Given customer xác nhận dialog, When cancel thành công, Thì danh sách đơn được invalidate + điều hướng về `/orders`.
- **Hủy bị chặn bởi backend** — Given đơn đã `in_transit` (lỗi đồng bộ UI), When cancel, Thì SnackBar hiện message 409 từ server.
- **Nhãn trạng thái tiếng Việt** — Given đơn `in_transit`, Thì chip hiển thị "Đang vận chuyển" (`order_models.dart`).
- **Driver thấy đúng 1 nút mỗi state** (plan3 Mục 2) — Given driver xem đơn `accepted`, Thì chỉ thấy "Đã lấy hàng"; bấm xong → đơn `pickup`, nút đổi thành "Bắt đầu giao"; nút cũ biến mất (không bao giờ 2 nút cùng lúc).
- **Customer hoàn tất đơn** (plan3 Mục 2) — Given customer xem đơn `delivered`, Thì thấy "Xác nhận hoàn tất"; bấm xong → chip "Hoàn thành", không còn nút lifecycle nào.
- **Bấm liên tục không crash** (plan3 Mục 2) — Given user bấm nút lifecycle 2 lần liên tiếp, Thì app không crash, state không vỡ (nút vô hiệu khi loading, lỗi backend chỉ hiện SnackBar).

---

## Cần làm rõ

> Các điểm dưới đây là hành vi code thực tế **mơ hồ hoặc mâu thuẫn** — không tự sửa, chờ xác nhận.
> (Cập nhật 2026-09-09 sau khi thực thi plan3_final.md: #1 xử lý một phần, #3 đã giải quyết — #2, #4, #5, #6 vẫn mở.)

1. **Mobile `canCancelOrder` hẹp hơn backend**: backend cho phép customer cancel tới cả `accepted` và `pickup` (`lifecycle.ts` RULES.cancel from-list), nhưng mobile chỉ hiện nút hủy cho `posted/matched/contacted` (`order_models.dart:111-113`). Comment trong `order_models.dart:20` còn ghi "posted/matched mới cancel được" — đã lỗi thời so với chính code của nó. → **Cập nhật 2026-09-09 (plan3_final Mục 2)**: `canCancelOrder` đã thêm `contacted` — UI giờ cho hủy ở posted/matched/contacted. Phần chênh còn lại (UI không cho hủy ở accepted/pickup dù backend cho phép) **giữ nguyên như hiện trạng** theo plan3 (không nằm trong 6 mục được yêu cầu); ghi nhận là chênh lệch UI↔backend đã biết.

2. **Comment state machine mâu thuẫn với from-list của cancel**: comment đầu file `order_state_machine.ts:12` ghi "posted → cancelled (customer, trước khi driver vào pickup)" nhưng RULES.cancel cho phép from `pickup` (đã vào pickup rồi vẫn hủy được). Comment vs code — bên nào là ý định đúng?

3. **Mobile không có UI cho driver lifecycle steps** (pickup/in-transit/delivered/complete): backend đầy đủ 5 endpoint nhưng Flutter không có method repository nào gọi chúng. Driver trên mobile sau khi accept sẽ không "đóng vòng" đơn được qua app. → **ĐÃ GIẢI QUYẾT 2026-09-09 (plan3_final Mục 2)**: mobile đã có UI lifecycle driver (pickup/in-transit/delivered) + customer (complete) qua `nextLifecycleAction` + `OrderRepository.transitionOrder` + nút trong `order_detail_screen.dart`. Test bằng chứng: `mobile/test/feature/order/order_lifecycle_test.dart` (3 test PASS — xem R7).

4. **2 đường code cho cùng target `accepted`**: `atomicAccept` (`accept.ts`) và `transitionOrder('accept')` (`lifecycle.ts` RULES.accept) cùng UPDATE về `accepted` nhưng mã lỗi không đồng nhất (atomicAccept: 400 `ORDER_ALREADY_ACCEPTED` cho hầu hết xung đột; transitionOrder: luôn 409 `INVALID_TRANSITION`). Route thực tế chỉ gọi `atomicAccept` — RULES.accept hiện không có route nào gọi. → Gộp về 1 đường (xóa rule accept khỏi state machine) hay giữ như một lớp dự phòng?

5. **Shape response không đồng nhất**: cancel trả `{ order }`, 4 endpoint kia trả `{ data: { order, status } }` (`routes/orders.ts:145` vs `routes/orders.ts:152`). Client hiện chỉ dùng cancel. → Chuẩn hóa trước pilot hay chấp nhận?

6. **`driver_id IS NULL` không nằm trong from-list check của `transitionOrder('accept')`** — RULES.accept có `whereExtra: 'AND driver_id IS NULL'` nên thực chất an toàn, nhưng nếu route sau này chuyển sang gọi `transitionOrder` thì mã lỗi race sẽ là 409 thay vì 400 như client mobile đang hiểu. Liên quan #4.

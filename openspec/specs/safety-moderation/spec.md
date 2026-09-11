# safety-moderation Specification

## Purpose

Trust layer (plan §18): **Report** (báo cáo user khác kèm ngữ cảnh đơn hàng),
**Block** (chặn 2 chiều — chặn thật ở mọi business operation: matching SQL,
contact, accept — không chỉ ẩn UI), **legal consent** (bằng pháp lý thời gian + IP),
**audit logs** (bằng chứng mọi hành động quan trọng) và **admin moderation**
(resolve report, suspend/ban user).

Phạm vi: Worker (`worker/src/routes/safety.ts`, `worker/src/routes/admin.ts`,
`worker/src/services/safety.ts`, `worker/src/services/audit.ts`,
`worker/src/services/authorization.ts` phần consent/block-guard,
`worker/migrations/0005_safety.sql`) + Mobile
(`mobile/lib/feature/safety/**`, phần report/block của `order_detail_screen.dart`).

## Requirements

### Requirement: POST /reports — báo cáo user

`POST /reports` (auth middleware — `worker/src/routes/safety.ts:22-28`) qua
`createReport` (`worker/src/services/safety.ts:49-103`) **PHẢI**:

1. Validate input (`validateReportInput` `safety.ts:25-44`): `target_user_id` bắt
   buộc (400 `INVALID_FIELD`); `reason` ∈ `spam | fake_info | harassment | fraud |
   other` (400 `INVALID_REASON`); `description` cắt còn 500 ký tự; `order_id` tùy chọn
2. Không thể report chính mình → 400 `INVALID_TARGET`; target không tồn tại →
   404 `USER_NOT_FOUND`
3. Khi có `order_id` (plan2_final §1.6 — enforce quan hệ):
   - Đơn phải tồn tại → 404 `ORDER_NOT_FOUND`
   - Reporter phải có quan hệ: participant (customer/driver được gán) hoặc driver
     đã contact → 403 `REPORT_NO_RELATION`
   - Target phải liên quan đơn: customer / driver được gán / driver đã contact →
     400 `INVALID_TARGET` ("Người bị báo cáo không liên quan đến đơn hàng này")
4. Rate limit **ATOMIC D1**: key `reportrl:<reporterId>`, tối đa **10 lần/giờ** →
   429 `REPORT_RATE_LIMITED`
5. INSERT report `status='open'` + audit log `action: 'report'` kèm metadata
   target/reason + IP; response 201 `{ data: { id, status: 'open' } }`

#### Scenario: Customer report tài xế sau contact

- **GIVEN** đơn X có driver được gán, customer là chủ đơn
- **WHEN** `POST /reports` `{ target_user_id: <driver>, order_id: X, reason: "harassment" }`
- **THEN** HTTP 201, report `status='open'`, audit log kèm IP

#### Scenario: Report không có quan hệ với đơn

- **GIVEN** user Z chưa từng contact/được gán đơn X
- **WHEN** report target là customer đơn X với `order_id: X`
- **THEN** HTTP 403 `REPORT_NO_RELATION`

#### Scenario: Target không liên quan đơn

- **GIVEN** customer chủ đơn X
- **WHEN** report user Y (không liên quan X) với `order_id: X`
- **THEN** HTTP 400 `INVALID_TARGET`

#### Scenario: Lý do không hợp lệ

- **WHEN** `reason: "khác"`
- **THEN** HTTP 400 `INVALID_REASON` liệt kê 5 lý do được phép

#### Scenario: Vượt 10 report/giờ

- **GIVEN** user đã report 10 lần trong giờ
- **WHEN** report lần 11
- **THEN** HTTP 429 `REPORT_RATE_LIMITED`

### Requirement: POST /blocks + DELETE /blocks/:userId — chặn / bỏ chặn

`blockUser` / `unblockUser` (`worker/src/services/safety.ts:108-146`) **PHẢI**:

1. Block: không thể chặn chính mình (400 `INVALID_TARGET`); target phải tồn tại
   (404); INSERT **idempotent** `ON CONFLICT(user_id, blocked_user_id) DO NOTHING`
   (block lại không lỗi, không tạo row thứ 2); audit `action: 'block'` kèm IP
2. Unblock: DELETE row block của chính user — trả `{ blocked: false }` kể cả khi
   chưa từng block (idempotent)
3. **Block là 1 chiều nhưng hiệu lực 2 chiều** (plan2_final §1.5): A block B →
   `isBlockedEitherDirection(A, B)` true — B không thao tác gì với A được

#### Scenario: Block idempotent

- **GIVEN** A đã block B
- **WHEN** A block B lần nữa
- **THEN** HTTP 200 `{ data: { blocked: true } }`, vẫn 1 row blocks

#### Scenario: Unblock chưa từng block

- **WHEN** A gọi `DELETE /blocks/<B>`
- **THEN** HTTP 200 `{ data: { blocked: false } }` — không lỗi

#### Scenario: Tự chặn chính mình

- **WHEN** `POST /blocks` với `target_user_id` = mình
- **THEN** HTTP 400 `INVALID_TARGET` ("Không thể chặn chính mình")

### Requirement: Block enforce thật ở mọi business operation

Block 2 chiều **PHẢI** được enforce server-side ở các điểm (không chỉ ẩn UI):

1. **Matching pre-filter SQL** (capability `trip-matching`): `corridorFilter` có
   `NOT EXISTS (SELECT 1 FROM blocks WHERE (2 chiều))` — đơn của user đã block
   bị loại ngay ở query (`worker/src/services/matching.ts:243-252`)
2. **Contact**: `requireNotBlockedEitherDirection(driver, customer)` trước khi cấp
   SĐT → 403 `USER_BLOCKED` (`worker/src/services/contacts.ts:79`,
   `authorization.ts:44-53`)
3. **Accept**: cùng guard trước atomic UPDATE → 403 `USER_BLOCKED`
   (`worker/src/services/accept.ts:61-63`)

#### Scenario: Block chặn matching

- **GIVEN** customer A block driver B, A có đơn `posted` trên tuyến của B
- **WHEN** B quét radar
- **THEN** đơn của A không xuất hiện trong kết quả

#### Scenario: Block chặn accept

- **GIVEN** driver B tìm cách accept đơn của A qua API trực tiếp (không qua radar)
- **WHEN** `POST /orders/<id>/accept`
- **THEN** HTTP 403 `USER_BLOCKED` ("Bạn không thể giao dịch với người dùng này")

#### Scenario: Bỏ block mở lại giao dịch

- **GIVEN** A unblock B
- **WHEN** B quét radar / contact / accept
- **THEN** hoạt động bình thường trở lại

### Requirement: Audit logs — bằng chứng mọi hành động quan trọng

`writeAuditLog` (`worker/src/services/audit.ts:14-40`) **PHẢI**:

1. INSERT `audit_logs` với `actor_id`, `entity_type`, `entity_id`, `action`,
   `metadata` (JSON), `ip` (từ `CF-Connecting-IP`), timestamp DB
2. Được gọi ở: legal consent, accept, contact, report, block, admin
   suspend/ban/resolve, trip start/end, mọi order lifecycle transition
3. **Không bao giờ làm hỏng luồng chính**: lỗi ghi audit chỉ `console.error` và
   tiếp tục (`audit.ts:36-38`) — trade-off 0đ cost: mất 1 log không được phép
   hỏng business
4. Ghi chọn lọc các action quan trọng (không log mọi request — bảo vệ quota D1)

#### Scenario: Consent lưu bằng chứng pháp lý

- **GIVEN** user tick disclaimer lần đầu
- **WHEN** `POST /me/legal-consent`
- **THEN** audit_logs có dòng `action='legal_consent'`, metadata
  `{ consented_at, text: 'disclaimer_v1' }`, IP requester

#### Scenario: Audit fail không chặn business

- **GIVEN** D1 tạm lỗi statement INSERT audit
- **WHEN** driver accept đơn
- **THEN** accept vẫn thành công, lỗi chỉ xuất hiện trong console

### Requirement: Admin moderation (role 'admin')

`worker/src/routes/admin.ts` — mọi endpoint qua `requireAdmin` (role ≠ admin →
403 `FORBIDDEN` — `admin.ts:24-28`) **PHẢI**:

1. `GET /admin/reports?status=<s>`: danh sách report theo status (default `open`),
   mới nhất trước, tối đa 100 — `admin.ts:30-45`
2. `POST /admin/reports/:id/resolve`: UPDATE `status='resolved'` + audit
   `report_resolve` — `admin.ts:47-60`
3. `POST /admin/users/:id/suspend`: UPDATE `users.status='suspended'` + audit
   `suspend`; target không tồn tại → 404 `USER_NOT_FOUND` — `admin.ts:62-79`
4. `POST /admin/users/:id/ban`: UPDATE `users.status='banned'` + audit `ban` —
   `admin.ts:81-97`
5. Tác dụng của suspend/ban: auth middleware đọc `users.status` từ DB mỗi request —
   user `banned` (và `suspended` theo logic middleware) mất quyền gọi API ngay cả
   khi JWT còn hạn (chi tiết trong spec `auth-otp`)

#### Scenario: Admin resolve report

- **GIVEN** report `open`, admin đã đăng nhập
- **WHEN** `POST /admin/reports/<id>/resolve`
- **THEN** report chuyển `resolved`, audit log `report_resolve`

#### Scenario: Customer gọi admin API

- **WHEN** user role customer gọi `GET /admin/reports`
- **THEN** HTTP 403 `FORBIDDEN` ("Chỉ admin mới được dùng chức năng này")

#### Scenario: Ban user có hiệu lực tức thì

- **GIVEN** admin ban user B (token B còn hạn 30 ngày)
- **WHEN** B gọi bất kỳ API nào
- **THEN** bị từ chối 401 (middleware đọc status từ DB, không tin JWT)

### Requirement: Legal consent — enforce server-side

`requireLegalConsent` (`worker/src/services/authorization.ts:55-64`) **PHẢI** được
enforce ở mọi action tốn resource/rủi ro pháp lý (client checkbox chỉ là UX —
plan2_final §1.4): tạo đơn, contact, accept, mọi trip action non-GET, geocode,
mọi lifecycle transition. Chưa consent → HTTP 403 `LEGAL_CONSENT_REQUIRED`
("Bạn cần đồng ý điều khoản sử dụng..."). Ghi nhận consent: chỉ qua
`POST /me/legal-consent` (chi tiết thuộc `user-identity-vehicle`).

#### Scenario: Consent thiếu chặn tạo đơn

- **GIVEN** customer chưa tick disclaimer
- **WHEN** `POST /orders`
- **THEN** HTTP 403 `LEGAL_CONSENT_REQUIRED` — client checkbox không phải security boundary

### Requirement: Mobile — report/block từ chi tiết đơn

1. Customer xem đơn có tài xế → nút "Báo cáo / Chặn tài xế" mở bottom sheet 2 lựa
   chọn ("Báo cáo tài xế" / "Chặn tài xế") —
   `mobile/lib/feature/order/presentation/screens/order_detail_screen.dart:87-108`
2. Chọn report → dialog chọn lý do từ `reportReasonLabels` (5 lý do khớp enum
   backend, nhãn tiếng Việt) → `SafetyRepository.reportUser` (`POST /reports` với
   `target_user_id`, `reason`, `order_id`) — `safety_models.dart:3-9`,
   `order_detail_screen.dart:117-135`
3. Chọn block → `SafetyRepository.blockUser` (`POST /blocks`) — không có dialog
   xác nhận riêng
4. Kết quả: SnackBar "Đã gửi báo cáo, admin sẽ xem xét" / "Đã chặn tài xế"; lỗi →
   SnackBar message VN — `order_detail_screen.dart:139-146`
5. `SafetyRepository` có đủ 3 method report/block/unblock (unblock chưa có UI —
   API sẵn sàng) — `mobile/lib/feature/safety/data/safety_repository.dart:12-40`

#### Scenario: Customer report tài xế từ app

- **GIVEN** đơn `accepted` có tài xế, customer mở chi tiết
- **WHEN** chọn "Báo cáo tài xế" → chọn lý do "Quấy rối"
- **THEN** `POST /reports` với reason `harassment` + order_id; SnackBar xác nhận

#### Scenario: Customer chặn tài xế

- **WHEN** chọn "Chặn tài xế"
- **THEN** `POST /blocks`; về sau tài xế đó không match/contact được với customer

## Cần làm rõ

1. **`GET /admin/reports` không enforce consent, không phân trang thực sự** — LIMIT
   100 cứng, không cursor; đủ cho P0. Chấp nhận?
2. **Admin resolve không set `reviewing`/`dismissed`** — schema cho phép 4 status
   (`open/reviewing/resolved/dismissed` — migration 0005) nhưng route chỉ có
   resolve → `resolved`. 2 status còn lại là dead enum cho P0 — giữ cho tương lai
   hay đơn giản hóa schema?
3. **`createReport` rate limit chạy SAU các check quan hệ** — user dò nhiều order_id
   để thăm dò quan hệ không bị limit cho đến khi vượt qua các check (thông tin leak
   chỉ là tồn tại/không tồn tại qua mã lỗi khác nhau: 404 vs 403). Mức độ thấp,
   ghi nhận có chủ đích hay cần đưa rate limit lên trước?
4. **Mobile unblock chưa có UI** — backend `DELETE /blocks/:userId` đã xong, mobile
   có method nhưng không màn hình nào gọi. Đúng phạm vi P0 (user liên hệ hỗ trợ
   qua kênh ngoài) hay cần thêm trong pilot?
5. **Suspend không có cơ chế un-suspend qua API** — admin có thể suspend/ban nhưng
   không có endpoint khôi phục `status='active'` (phải sửa DB tay). Chủ đích P0?

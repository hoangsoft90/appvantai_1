# RESULT — Review kỹ thuật độc lập toàn bộ phase 0→8

- **Ngày:** 2026-09-11
- **Loại công việc:** Audit + báo cáo thuần (không sửa code)
- **Đối chiếu:** `.plan/production_roadmap.md` + `.plan/phase1..phase8*.md` (SSOT) với code thật `worker/src/**`, `mobile/lib/**`, `worker/scripts/**`, `docs/**`
- **Phạm vi:** Phase 0–8 + foundation/auth; cross-cutting invariants; regression check

---

## A. Tổng quan — verdict từng phase

| Phase | Thiết kế | % khớp code | GO/NO-GO |
|---|---|---|---|
| 0 Foundation | Flutter+Worker+D1/KV, error envelope | ~95% | **GO** |
| 1 Identity | Role, vehicle 1-1, consent+audit, role lock | ~95% | **GO** |
| 2 Marketplace | Order CRUD, grid, rate/active limit atomic | ~90% | **GO** (1 🟡 dead code) |
| 3 Matching | Pipeline 6 bước, hard reject, reasons | ~90% | **GO** (2 🟡 logic edge) |
| 4 GPS | Active-only, KV throttle, privacy, resume | ~95% | **GO** |
| 5 Safety+Lifecycle | Atomic accept, cancel siết, report/block/admin | ~95% | **GO** |
| 6 Pilot | Seed idempotent, smoke, metrics, checklist | ~85% | **GO tooling / NO-GO "đã pilot thật"** |
| 7 Hardening | Auth prod, guard fail-fast, release config | ~85% | **GO** (sau fix_p7_1) |
| 8 Store | Signing, in-app version/legal, soft launch docs | ~85% | **GO** (code sẵn, ops Play chưa làm) |

**Phase yếu nhất — top 3 vấn đề (P0/P1):**
1. **P1: `trip_type='return'` không truyền được từ UI** — `mobile/lib/feature/trip/presentation/screens/trip_form_screen.dart:146` chỉ có segment `one_way` trong `ButtonSegment`.
2. **P1: `verify_all.sh` E2E suite phụ thuộc `/tmp/e2e_phase*.sh` không có trong repo** — suite tổng không tái lập được từ checkout sạch.
3. **P2: `android:label="appvantai_mobile"`** — tên app hiển thị chưa phải tên thương mại.

---

## B. Chi tiết từng phase

### Phase 0 — Foundation
- **Đạt:** Hono app (`worker/src/index.ts`): middleware guard → request-id → access-log; error envelope `{error:{code,message,status}}` nhất quán qua `onError` + `ApiError`; config dart-define tập trung (`app_config.dart`); Dio timeout 10s/20s; AsyncView loading/empty/retry dùng xuyên suốt.
- **Lệch/thiếu:** không thấy.

### Phase 1 — Identity
- **Đạt:**
  - Users + phone unique + role CHECK 3 giá trị (`worker/migrations/0001_init.sql:10`); status active/suspended/banned (`users.ts:5`).
  - Vehicle 1-1 qua `driver_profiles` (`/me/vehicle` GET/PATCH) — đúng non-goal fleet (plan §25).
  - Consent: `POST /me/legal-consent` + audit + IP (`routes/me.ts:130`); `requireLegalConsent` enforce server-side ở mọi nghiệp vụ.
  - **Role lock đúng plan3_final Mục 1 + plan4 §3** (`routes/me.ts:28-58`): HARD `('accepted','pickup','in_transit','delivered')` không nhìn expiry; SOFT `(posted,matched,contacted)` có `expires_at > now`; trips planned/active chặn; gọi trong `PATCH /me` (`me.ts:95`). Evidence: e2e_plan4_m3 9/9.
  - Không fleet/KYC ✅
- **Lệch/thiếu:** none.

### Phase 2 — Marketplace
- **Đạt:**
  - Grid `FLOOR(lat/0.05)` + index `(grid_lat,grid_lng,status,expires_at)`; `corridorFilter` dùng BETWEEN → index-backed.
  - Rate limit **atomic D1 UPSERT RETURNING** (`services/rate_limit.ts:33-48`) — anti-TOCTOU.
  - POST /orders: role → consent → rate limit → active limit (`routes/orders.ts:42-50`); active-order limit INSERT→COUNT→DELETE-guard (`rate_limit.ts:70-119`).
  - Cancel qua `transitionOrder('cancel')` + `CUSTOMER_CANCELLABLE` = posted/matched/contacted (`order_state_machine.ts:56`).
  - Form geocode, không nhập lat/lng tay + invalidate điểm khi sửa text (plan4 §4.2) (`order_form_screen.dart:15-16,53`).
  - List chỉ `customer_id = ?` (`orders.ts:332`); view access 404 không leak (`assertOrderViewAccess:398-410`).
- **Lệch/thiếu:**
  - 🟡 P2 dead code: `cancelOrder()` + `ACTIVE_STATUSES` cũ (`orders.ts:411-427`) không còn ai gọi; logic cũ chỉ cancel posted/matched — **mâu thuẫn** `CUSTOMER_CANCELLABLE` (có contacted). Không active nhưng là bẫy dev.

### Phase 3 — Matching (core)
- **Đạt:**
  - Pipeline đúng 6 bước + đủ hard reject: pre-filter (status/expiry/vehicle/capacity/grid/block NOT EXISTS — `matching.ts:185-220`), pickup>10km, angle>135°, hết khung, feasibility 40km/h+30min, detour>15km chỉ tính Top-5 (`matching.ts:96-152`).
  - Return trip: bearing đảo B→A + feasibility/detour từ destination (`matching.ts:70-76,120-124,139-144`); migration 0008.
  - Score 110+15 → /125 normalize; reasons tiếng Việt (`buildReasons:264`).
  - Route cache D1 TTL 30 ngày + geocode KV TTL 30 ngày (`route_cache.ts:10-11`); OSRM/Nominatim timeout 10s + circuit breaker (`maps/resilience.ts`); matching catch lỗi routing → detour=null vẫn trả kết quả (`matching.ts:145-149`).
  - Match card đủ score/pickup_km/detour/reasons (pickupKm nullable — không fake 0.0); empty state 3 gợi ý (`trip_matches_screen.dart:44-77`).
  - Persist matches `db.batch` atomic (DELETE trước) (`matching.ts:280-305`).
- **Lệch/thiếu:**
  - 🟡 **P1 — Return trip chết ở UI:** `trip_form_screen.dart:146` chỉ có `ButtonSegment(value: 'one_way')` — không có nút 'return'. Backend đầy đủ nhưng user không tạo được trip return; empty state gợi ý "Khai báo chiều về" đẩy vào dead-end. (E2E tạo return bằng API nên không bắt được.)

### Phase 4 — GPS
- **Đạt:**
  - Active-only: planned → `TRIP_NOT_ACTIVE` message riêng "hãy start trước"; ended/cancelled → reject (`routes/trips.ts:113-120`); start/end ownership + audit.
  - KV `loc:` TTL 2h + throttle 30s `loclast:` (`gps.ts:23-26,46-66`); end xóa cả 2 key (`gps.ts:129-130`).
  - Privacy: `driverDistanceForOrder` chỉ trả `distance_km` (0.1km), chỉ customer của đơn có driver (`gps.ts:71-93`).
  - Mobile `reconcile()` 5 kết quả; activeNoPermission không crash; resume gửi ngay + timer lại (`trip_run_controller.dart:118-147`); geolocator timeLimit 10s.
  - Không background tracking/ETA/live map ✅ đúng non-goal.
- **Lệch/thiếu:** none — phase sạch nhất.

### Phase 5 — Safety + Lifecycle
- **Đạt:**
  - State machine tập trung + terminal không resurrect (`order_state_machine.ts:23-53`); transition WHERE status + actor bind (`lifecycle.ts:158+`).
  - **Atomic accept chuẩn plan §10:** `UPDATE ... WHERE status IN (...) AND driver_id IS NULL` + `changes===0` → 409; idempotent với chính driver (`accept.ts:78-98`).
  - Cancel sau accept → 409 `CANCEL_NOT_ALLOWED` riêng, check trước canTransition (`lifecycle.ts:144-151`) — plan4 §1.
  - Contact: rate limit 20/h atomic, block 2 chiều, consent, phone chỉ trả sau contact OK, batch re-check IN(posted,matched) (`contacts.ts:91-99`).
  - Report/block: reason enum, rate limit, admin reports/resolve/suspend/ban có audit; suspended/banned chặn ở auth middleware (`middleware/auth.ts:30`).
  - Double-tap: `_processing` flag (`order_detail_screen.dart:37,58`); menu report/block từ order detail khi có tài xế.
- **Lệch/thiếu:**
  - 🟡 P2: driver chưa có UI report/block phía trip/matches (chỉ customer) — plan §18 không bắt buộc 2 chiều UI ở P0.

### Phase 6 — Pilot
- **Đạt:**
  - `seed_pilot.sh` idempotent thật (DELETE scoped `notes='pilot'` + phone `0983%`, `--reset-seed`, khung giờ động +2h→+12h); `pilot_smoke.sh` 14/14 PASS; `pilot_metrics.sql` 4 nhóm; `docs/pilot_checklist.md` đủ 11 bước khớp §6.2 từng dòng.
  - Admin verify sẵn (`/admin/reports`, suspend/ban).
- **Lệch/thiếu:**
  - 🟡 **P1 — ranh giới tooling vs vận hành:** chưa có pilot người thật (không có `result_pilot.txt`, không có số liệu funnel thật). Phase 7 yêu cầu "Phase 6 DoD đã đạt" làm tiền đề — thực tế 7/8 đã làm trước pilot thật → **lệch trình tự roadmap**, cần ops đóng vòng.
  - 🟡 P2: metrics chỉ đáng tin trên DB sạch/remote (residue local đã ghi note trong header SQL).

### Phase 7 — Hardening
- **Đạt (sau fix_p7_1):**
  - `/auth/firebase`: verify RS256 WebCrypto + JWKS Google cache 1h; claims đủ (aud/iss/sub/phone); **exp không cộng clock-skew** (fix_p7_1 #5) + thêm nbf; `setFirebaseUid` batch "login mới thắng" tránh UNIQUE 500 (`users.ts:45-52`).
  - Dev OTP: `allowDev = APP_ENV==='dev' && ALLOW_DEV_OTP==='true'` — không echo ở env khác (`auth.ts:38-39`); OTP rate limit 5/15ph.
  - Guard fail-fast: production sai cấu hình → **503 PRODUCTION_MISCONFIGURED mọi request** (`env_guard.ts`); JWKS chỉ cho localhost; `verify_deploy_config.mjs` chặn placeholder D1/KV + JWT_SECRET trong vars; `npm run deploy` tự verify.
  - JWT 30 ngày; role đọc DB mỗi request — không stale role (`middleware/auth.ts:28-35`).
  - Mobile: strategy dev-OTP ↔ Firebase qua dart-define; `kReleaseMode` invariant + Gradle fail-fast thiếu APP_ENV; Firebase bắt buộc ở production (`app_config.dart`).
  - Terms/Privacy in-app (public pre-login, link từ login/onboarding/profile); evidence e2e_phase7_m1 6/6, m2 11/11, m5 11/11.
- **Lệch/thiếu:**
  - 🟡 P1: OTP KV rate-limit vẫn TOCTOU (`otp.ts:20-27` GET→check→PUT) — khác chuẩn atomic D1 của contact/report. Impact thấp (dev OTP chỉ chạy dev, KV vốn eventual-consistency).
  - 🟡 P2: guard chỉ chạy khi có request (giới hạn platform, không fail-boot) — đã ghi comment; `/health` cũng 503 khi misconfigured → monitor thấy được.

### Phase 8 — Store / soft launch
- **Đạt:**
  - Signing: `key.properties.example` + keystore gitignored; fallback debug chỉ test; Gradle fail-fast APP_ENV (fix_p7_1 #4).
  - In-app: tile "Phiên bản" (package_info_plus 8.3.1) + link Terms/Privacy; có test (`identity_flow_test.dart:70`).
  - `docs/legal/*.md` public host Pages; README Phase 8: checklist AAB 7 dart-define, Play Internal→Closed, listing tối thiểu, rollback `wrangler rollback`, "không force-update lần đầu", verify release config.
  - Manifest: chỉ INTERNET + 2 location, không background; iOS `NSLocationWhenInUseUsageDescription` tiếng Việt đúng ý ("chỉ khi chuyến đang chạy").
- **Lệch/thiếu:**
  - 🟡 P2: `android:label="appvantai_mobile"` — chưa phải tên thương mại (plan §8.3 hướng "radar tìm mối").
  - 🟡 P2: Android-first ghi đúng trong README (chưa có Apple account) — khớp điều kiện plan.
  - Ops chưa làm (đúng ranh giới): Play Console, upload AAB, Data safety.

---

## C. Cross-cutting

| Invariant | Nơi enforce | Trạng thái |
|---|---|---|
| Atomic accept | `accept.ts:78-88` UPDATE có điều kiện + changes check | ✅ |
| Cancel chỉ posted/matched/contacted | `order_state_machine.ts:56` + check trước canTransition | ✅ (dead code cũ mâu thuẫn nhưng không active) |
| GPS active-only + xóa KV khi end | `routes/trips.ts:113-120`, `gps.ts:129` | ✅ |
| Role lock hard/soft | `routes/me.ts:28-58` | ✅ |
| Phone chỉ lộ sau contact; GPS chỉ khoảng cách | `contacts.ts:100-108`, `gps.ts:71-93` | ✅ |
| Consent trước mọi nghiệp vụ | orders/accept/contact/lifecycle/trips | ✅ |
| dev_otp chỉ dev | `auth.ts:38` + guard 503 | ✅ |

**Regression:** mobile 50/50 test + `pilot:smoke` 14/14 + e2e_phase7 m1/m2/m5 + e2e_plan4_m1 đều GREEN ở phiên Phase 8 → lifecycle accept→complete xuyên suốt không vỡ. Lệch duy nhất là **trình tự**: Phase 7/8 đi trước pilot thật (xem P6).

**Điểm cộng vượt thiết kế:** suite e2e random-phone (`run_e2e_suite.sh` — không nhiễu run trước); guard 503 mạnh hơn yêu cầu plan (plan chỉ cần log); `verify_deploy_config` chặn pre-deploy.

---

## D. Hành động đề xuất (P0→P1, không feature mới)

### Code — P1 (nên sửa trước khi có user thật)
1. Thêm `ButtonSegment(value: 'return', label: Text('Có chiều về'))` vào `trip_form_screen.dart:144-148` (submit đã truyền `tripType` — chỉ thiếu segment). Mở đúng tính năng backend đã có + hết dead-end empty-state.
2. Đặt suite scripts (`e2e_phaseA...E`) vào `worker/scripts/e2e/` thay vì phụ thuộc `/tmp` — hiện `verify_all.sh` fail trên checkout sạch.
3. (Tùy chọn, ~10 dòng) OTP rate limit chuyển sang D1 atomic `consumeRateLimit` như contact/report, hoặc ghi chú chấp nhận KV trong `otp.ts`.

### Code — P2 (dọn khi rảnh, không chặn)
4. Xóa dead code `cancelOrder` + `ACTIVE_STATUSES` cũ (`orders.ts:411-427`).
5. `android:label` → "App Vận Tải".
6. Comment `otp.ts` ghi rõ KV-limit là best-effort (nếu không làm mục 3).

### Ops (người vận hành, không phải code)
7. **Chạy pilot thật 1 corridor** theo `docs/pilot_checklist.md` (11 bước) + ghi `pilot_metrics.sql` → `result_pilot.txt` — điều kiện roadmap trước khi mở rộng track.
8. Play Console: tạo app, Data safety (location when-in-use + phone), upload AAB internal track — checklist từng bước có sẵn trong README Phase 8.
9. Firebase project thật (Blaze cho SMS +84) + điền dart-define/secret; keystore release; `npm run verify:deploy` trước deploy đầu tiên.

### Kết luận
Code bám thiết kế tốt; invariants core đều đúng và có evidence E2E/widget test; **không có P0 mới** ngoài những gì fix_p7_1 đã xử lý. Hai việc đáng làm ngay: **mục 1 + 2 (P1)** và **mục 7 (ops pilot)** để roadmap trở lại đúng trình tự.

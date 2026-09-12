# App Vận Tải — "Tìm Mối Tiện Đường" (Cargo Radar)

MVP tìm hàng phù hợp với tuyến đường đang chạy của tài xế.
**SSOT:** `.plan/plan_final_v2.md` (MVP) + `.plan/plan2_final.md` (Hardening & Release Gate).

## Tech stack (theo plan §15, §27 — mục tiêu 0đ vận hành)

| Thành phần | Công nghệ |
|---|---|
| Mobile | Flutter (iOS + Android) |
| Backend | Cloudflare Worker (Hono) + D1 + KV |
| Maps | OSRM (primary) + Nominatim + Haversine local (Phase 3) |
| Auth | Dev OTP skeleton (Phase 0) → gắn Zalo/Firebase sau (không đổi API) |
| State | Riverpod 3 (codegen) + GoRouter + Feature-First |

## Cấu trúc

```
appvantai_1/
├── .plan/plan_final_v2.md   # SSOT — đọc trước khi viết code
├── worker/                  # Cloudflare Worker backend
│   ├── wrangler.toml        # bindings: D1 (DB), KV (APP_KV)
│   ├── migrations/          # SQL migrations (theo từng phase)
│   └── src/
│       ├── index.ts         # router + error handler thống nhất
│       ├── env.ts           # typed bindings
│       ├── lib/             # errors, logger, phone utils
│       ├── middleware/      # request-id, auth (JWT HS256)
│       ├── maps/            # MapsProvider: mock | OSRM | Nominatim (plan §14)
│       ├── services/        # otp, users, profiles, orders, trips, matching, route_cache
│       └── routes/          # /auth/*, /me, /orders, /trips
└── mobile/                  # Flutter app
    └── lib/
        ├── app/             # router (GoRouter + auth redirect), theme
        ├── core/            # config (--dart-define), utils
        ├── shared/          # services (API client, token, logger), widgets (AsyncView…)
        └── feature/         # auth/, home/, identity/, order/, trip/ — mỗi feature: data/domain/application/presentation
```

## Chạy backend (local)

```bash
cd worker
npm install
npm run typecheck
npx wrangler d1 migrations apply appvantai --local   # tạo local D1
npm run dev                                           # http://localhost:8787
```

Test nhanh luồng auth (dev OTP):

```bash
curl -X POST localhost:8787/auth/request-otp -H 'content-type: application/json' \
  -d '{"phone":"0912345678"}'          # → { "ok": true, "dev_otp": "123456" }
curl -X POST localhost:8787/auth/verify-otp -H 'content-type: application/json' \
  -d '{"phone":"0912345678","otp":"123456"}'   # → { "token": "...", "user": {...} }
curl localhost:8787/me -H 'Authorization: Bearer <token>'
```

## Chạy Flutter

```bash
cd mobile
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # sinh *.g.dart (Riverpod codegen)
flutter run --dart-define=API_BASE_URL=http://localhost:8787
# Android emulator: API_BASE_URL=http://10.0.2.2:8787
flutter analyze && flutter test
```

Dev OTP được hiển thị trong SnackBar khi backend ở dev mode (`ALLOW_DEV_OTP=true`),
không cần SMS thật.

## Quyết định kỹ thuật

### Phase 4 — GPS
- **Chỉ GPS khi active trip** (plan §13): không track toàn bộ users. `POST /trips/:id/start` → planned→active; `POST /trips/:id/end` → active→ended + xóa loc.
- **Vị trí lưu KV** `loc:<driver_id>` (TTL 2h) — KHÔNG ghi D1 realtime (D1 giới hạn 100k writes/ngày). Chỉ D1 write ở start/end trip (1 lần mỗi cái).
- **Throttle 30s** giữa 2 lần update (KV `loclast:`), foreground — plan §13.
- **Privacy (§13, §18):** `GET /orders/:id/driver-location` chỉ trả **khoảng cách làm tròn 0.1km từ điểm lấy** (haversine), KHÔNG bao giờ trả lat/lng chính xác. Chỉ chủ hàng của đơn đã accept gọi được; driver khác → ORDER_NOT_FOUND.
- **Flutter:** `geolocator` qua abstraction `LocationService` (fake trong test). `TripRunController` (AsyncNotifier): start → xin quyền → gửi vị trí ngay + Timer.periodic 30s → end. **Bắt buộc watch controller trong build** — nếu chỉ `ref.read`, Riverpod dispose provider → "Ref disposed" khi gọi.

### Phase 5 — Safety/Admin
- **Atomic Accept** (plan §10 — business invariant quan trọng nhất): 2 driver cùng accept một đơn → chỉ 1 người thắng. Không dùng "SELECT rồi client tự accept" — dùng `UPDATE cargo_orders SET driver_id=?, status='accepted' WHERE id=? AND status IN ('posted','matched','contacted') AND driver_id IS NULL` rồi check affected rows (D1 single-writer nên UPDATE nguyên tử).
- **State machine** (plan §9): chỉ cho transition hợp lệ (posted/matched/contacted → accepted; cancel chỉ khi posted/matched). Driver accept lại đơn của mình → idempotent success.
- **Contact** (plan §17): `POST /orders/:id/contact` → ghi `contacts` + chuyển đơn contacted, trả số điện thoại chủ hàng CHO DRIVER — không public trước khi contact (privacy §18). Rate limit 20/giờ (KV).
- **Legal disclaimer** (plan §18): checkbox bắt buộc ở onboarding + form tạo đơn; `POST /me/legal-consent` lưu `legal_consent_at` (users) + ghi `audit_logs` kèm IP (`CF-Connecting-IP`). Client đọc `legal_consent_at` từ response /me để gate form.
- **Report/Block** (plan §18): `POST /reports` (rate limit 10/giờ, reason enum), `POST/DELETE /blocks/:userId`. Admin (role='admin' — seed trực tiếp D1, KHÔNG cho tự phong qua API): GET /admin/reports, resolve, suspend/ban user.
- **Role đọc từ DB mỗi request** (auth middleware): user bị ban → token cũ lập tức vô hiệu (401 USER_NOT_FOUND).

### Phase 3 — Maps + Matching (core value)
- **MapsProvider abstraction** (plan §14): `MAPS_PROVIDER` env (`osrm` default | `mock`).
  - OSRM route: `router.project-osrm.org`, kết quả cache vào D1 `route_cache` (key = tọa độ làm tròn ~11m, TTL 30 ngày).
  - Nominatim geocode: throttle 1.1s giữa request (usage policy), cache vào KV `geo:<query>`.
  - Mock provider: deterministic (bảng địa danh VN + route 3 điểm) — dùng cho test local không cần network.
  - Lưu ý: OSRM public server trả 403 khi fetch từ Worker mà không có `User-Agent` rõ ràng.
- **Matching pipeline** (plan §5):
  1. Pre-filter bằng Grid Index (§12): quét corridor bbox ±1 ô, lọc status/expiry/vehicle/capacity — 1 query.
  2. Corridor check: pickup cách polyline (resample 300m) > 10km → hard reject (Haversine + point-to-line, không gọi API).
  3. Direction: chênh lệch bearing > 135° → hard reject.
  4. Time: hết khung giờ lấy (pickup_to < now) → hard reject.
  5. **Top-5 detour verification**: chỉ 5 mối điểm cao nhất gọi OSRM (cached) tính detour = (A→P + P→D + D→B) − A→B; > 15km hard reject (§5.3).
  6. Score 6 thành phần (125 subtotal → normalize 100): distance 20, route 30, direction 25, vehicle 15, capacity 10, time 10 + detour bonus 15/10/5.
- **Match reasons** (plan §7): mỗi match kèm danh sách lý do tiếng Việt (khoảng cách, hướng, xe, tải, thời gian, detour) — không trả số mà không giải thích.
- **Role đọc từ DB, không từ JWT**: user đổi role qua PATCH /me → token cũ vẫn còn hiệu lực nhưng role phải tươi (auth middleware query users mỗi request). Bug stale-role đã bắt được khi test.
- **Trips**: POST /trips (rate limit 20/giờ) → geocode+route (cached) → lưu polyline. POST /trips/:id/matches chạy pipeline trên. GET /trips chỉ trả chuyến của chính driver.

### Phase 2 — Marketplace
- **Grid Index** (plan §12): `grid_lat/lng = FLOOR(pickup/0.05)` tính lúc tạo đơn, index `(grid_lat, grid_lng, status, expires_at)` — Phase 3 pre-filter chỉ quét 9 ô lân cận.
- **Lazy expiry** (plan §19): không background job — đơn `expires_at < now` được trả về với status `expired` khi query. Mặc định `expires_at = pickup_to`.
- **Anti-spam** (plan §19): rate limit tạo đơn 10/giờ (KV) + tối đa 5 đơn active (posted/matched) mỗi customer.
- **P0 giới hạn:** `GET /orders` trả đơn của chính user (driver xem mối hàng qua matching Phase 3, không browse toàn bộ). Lat/lng nhập tay — Phase 3 thay bằng map picker + geocoding.

### Phase 1 — Identity
- **1 tài xế = 1 xe** (driver_profiles chứa luôn thông tin xe) — plan §11, không fleet (non-goal §2.2).
  Do đó dùng `GET/PATCH /me/vehicle` thay cho `/vehicles/:id` trong plan §25 (deviation có chủ đích).
- Chọn vai trò driver khi PATCH /me → backend auto-tạo driver_profile rỗng; bắt buộc khai xe trước khi vào home (router gate).
- Router: KHÔNG refresh GoRouter trên mọi auth change — chỉ khi "landing" thay đổi (login/logout/onboarding/xe đầu tiên).
  Lý do: `GoRouter.refresh()` (go_router 16) re-parse theo URL và xóa stack push → pop() fail.
  VehicleFormScreen không nhận vehicle qua `state.extra` (đọc từ AuthController) để tránh cast lỗi tương tự.

### Phase 0

- **Auth:** Dev OTP skeleton — Worker tự sinh OTP 6 số lưu KV (TTL 5 phút,
  rate limit 5 lần/15 phút, anti-spam plan §19). Trả `dev_otp` chỉ khi
  `ALLOW_DEV_OTP=true`. JWT HS256 do Worker ký (30 ngày). Khi gắn
  Firebase Phone Auth / Zalo (plan §16): thay `services/otp.ts` + phần verify,
  **API surface không đổi**.
- **KV dùng cho:** OTP (`otp:<phone>`), rate limit (`otprl:<phone>`), và GPS
  active trip (`loc:<driver_id>`) từ Phase 4. Không ghi GPS realtime vào D1
  (plan §13).
- **Token storage:** `shared_preferences` (đã chốt với user). Interface
  `TokenStorage` để sau đổi `flutter_secure_storage` không đụng call-site.
- **Error handling:** envelope thống nhất `{ error: { code, message, status } }`
  cả 2 phía; Flutter map về `ApiException` với message tiếng Việt; mọi async
  đều có Loading/Error/Retry/Empty qua `AsyncView` (plan §26).
- **Riverpod codegen:** `@riverpod` + build_runner. Lưu ý: cần Riverpod 3.x
  (flutter_riverpod ≥ 3.4) vì analyzer 7.x cũ không hỗ trợ Dart 3.13.

## Phase 6 — Pilot (corridor HN → Hưng Yên → Hải Dương → HP)

> **Đây là pilot 1 corridor, chạy bằng dev OTP nội bộ — CHƯA production auth, CHƯA
> store** (auth thật + hardening ở Phase 7, phân phối ở Phase 8).

Không thêm feature — chỉ seed dữ liệu + đo funnel để kiểm chứng **liquidity**
(plan §28) trước khi đưa app lên thật.

### Chạy seed + matching

```bash
cd worker
npm run typecheck
npx wrangler d1 migrations apply appvantai --local
npm run seed:pilot    # tự start wrangler dev (mock), seed, chạy matching, dừng server
```

**Seed là IDEMPOTENT**: mỗi lần chạy, data seed cũ (đơn `notes='pilot'` + trip của
tài xế seed `0983xxxxxx`) bị xóa rồi tạo lại — chạy nhiều lần không nhân đôi,
không đụng data user thật. Xóa data seed: `bash scripts/seed_pilot.sh --reset-seed`.
Khung giờ lấy hàng tính động (+2h → +12h) nên đơn seed không bao giờ hết hạn.

Kết quả verify (local, MAPS_PROVIDER=mock):

```
Tài xế có ≥1 match: 4/4 (truck 4 match, van/pickup 2 match — lọc đúng vehicle_requirement)
Tổng match: 12, score 100/100/90/61… — 2 đơn nhiễu (Quảng Ninh, Thanh Hóa) bị pre-filter loại đúng
```

### Smoke test 1 vòng lặp đầy đủ (trên data seed)

```bash
npm run seed:pilot && npm run pilot:smoke
# → PASS=14 FAIL=0: match (radar thấy đơn seed, reasons) → contact (nhận SĐT)
#   → accept → cancel-sau-accept BỊ CHẶN (409 CANCEL_NOT_ALLOWED)
#   → GPS planned-reject/active-OK/end-dừng → pickup → in-transit → delivered
#   → customer complete → COMPLETED
```

Chọn động 1 đơn seed còn `posted` nên chạy lại nhiều lần không cần re-seed.

### Test tay theo checklist + metrics

- Checklist 11 bước (login 2 vai, tạo đơn, radar, contact, accept, lifecycle,
  cancel, GPS, empty state, role lock): `docs/pilot_checklist.md`
- **Hướng dẫn sử dụng cho người dùng cuối** (chủ cửa hàng · tài xế · admin, kèm
  xử lý sự cố theo đúng thông báo trên app): `guide.md`
- **Bản public gửi cho tài xế / chủ cửa hàng** (đã lọc toàn bộ chi tiết vận hành
  admin, SQL, số điện thoại): `guide_public.md` → https://share.jotbird.com/soft-steady-prickly-pear
  (JotBird, hết hạn 11/12/2026 — sửa xong chạy lại lệnh publish trong `README` mục
  deploy docs hoặc skill `jotbird-publish` để cập nhật cùng slug).
- Tài khoản seed: driver `0983500001–04`, customer `0983600001–08` (dev OTP).

```bash
npm run pilot:metrics   # = wrangler d1 execute appvantai --local --file scripts/pilot_metrics.sql
```

Funnel (plan §29): `matches_shown → contacts_made → accepts → completed` + phân bố
score + reject heuristics. Kỳ vọng trước khi mở rộng: **≥70% trip có ≥1 match,
contact rate ≥ 30% số match, accept rate ≥ 50% số contact, cancel sau accept = 0**.

> **Lưu ý (bug đã bắt khi viết script):** user mới mặc định `role=customer`;
> nếu script không `PATCH /me` set `role=driver` thì `POST /trips` trả **403
> FORBIDDEN** và matching không bao giờ chạy ("0 match" nhưng không phải lỗi
> matching). `login()` trong script phải set role+name đúng như onboarding thật.

- [ ] Corridor: tọa độ điểm lấy/giao của đơn mẫu nằm sát QL5 (pickup cách tuyến ≤ 10km)
- [ ] `ALLOW_DEV_OTP=false` — tắt dev OTP; gắn Firebase/Zalo Phone Auth (§16)
- [ ] `JWT_SECRET` đổi thành secret thật (không phải dev value)
- [ ] Seed admin: `UPDATE users SET role='admin' WHERE id='...'` (không tự phong qua API)
- [ ] Test thật: login → tạo đơn → driver radar → contact → accept → GPS → end
- [ ] Theo dõi `pilot_metrics.sql` mỗi ngày; dừng nếu match rate < 50%

## Trạng thái phase

- [x] **Phase 0 — Foundation** (backend auth + Flutter skeleton) — xong, verified
- [x] **Phase 1 — Identity** (user name/role + driver profile + vehicle) — xong, verified
- [x] **Phase 2 — Marketplace** (cargo create/list/detail/cancel/expiry + grid index) — xong, verified
- [x] **Phase 3 — Maps + Matching** (OSRM/Nominatim + corridor/direction/time scoring + Top-N detour + radar UI) — xong, verified
- [x] **Phase 4 — GPS** (KV `loc:<driver_id>` + throttle 30s + privacy distance, start/end trip) — xong, verified
- [x] **Phase 5 — Safety/Admin** (contact + atomic accept + report/block + admin moderation + legal disclaimer + audit) — xong, verified
- [x] **plan2_final Phase A–I — Hardening & Release Gate** (xem dưới)
- [ ] Phase 6 — Pilot (corridor HN → HP) — **tooling xong, chờ pilot thật**
  - [x] Seed idempotent (`npm run seed:pilot`) — 4 tài xế + 8 đơn, match 4/4
  - [x] Smoke 1 vòng lặp (`npm run pilot:smoke`) — 14/14 PASS
  - [x] Metrics SQL (`npm run pilot:metrics`) + checklist `docs/pilot_checklist.md`
  - [ ] Chạy tay 11 bước checklist + ghi funnel (pilot thật/semi-thật)

## plan2_final — Hardening & Release Gate (đã thực thi, evidence kèm từng phase)

| Phase | Nội dung | Evidence |
|---|---|---|
| A — Security | role enforcement server-side, ownership mọi GET/PATCH/cancel, contact privacy (phone chỉ sau contact), legal consent enforce DB, block chặn matching/contact/accept, report validate order/participant | 21/21 E2E |
| B — State Machine | `order_state_machine.ts` centralized, lifecycle APIs `pickup/in-transit/delivered/complete/cancel`, actor rules, timestamps per transition, no-resurrect terminal | 28/28 E2E |
| C — Concurrency | atomic accept race (8 driver → 1 winner), active-order limit atomic (insert→count→rollback), rate limit atomic D1 (`rate_limits` UPSERT RETURNING), match persistence `db.batch` atomic | 12/12 E2E |
| D — Matching | Return Trip (`trip_type=return`, bearing/detour theo chiều về), pickup feasibility (travel time + 30min buffer), hard rejects: capacity/vehicle/expired/accepted/detour | 16/16 E2E |
| E — Maps | `GET /maps/geocode` + Flutter trip form search địa chỉ (không còn nhập lat/lng), OSRM/Nominatim timeout + circuit breaker (`maps/resilience.ts`), cache không ghi invalid response | 8/8 E2E + 21/21 Flutter |
| F — GPS | end-trip fail → giữ pending "chưa sync" + banner + retry (không silently swallow), app reopen `reconcile()` với server, backend chặn location sau terminal trip | test failure-injection pass |
| G — Production | `env_guard.ts` (production chặn dev OTP/dev secret), Flutter `assertReleaseConfig()` fail-fast localhost/HTTP, Android manifest INTERNET+LOCATION ở main, iOS `NSLocationWhenInUseUsageDescription` | analyze + tests green |
| H — Tests | Consolidated suite: `bash worker/scripts/verify_all.sh` = typecheck + 85 E2E + analyze + tests | **85/85 E2E + 21/21 Flutter** |

### Verification toàn diện (chạy 1 lệnh)

```bash
cd worker && bash scripts/verify_all.sh
# → [1/3] tsc clean · [2/3] E2E suite 85/85 · [3/3] flutter analyze + tests
```

### Deployment procedure (production) — Phase 7 §7.2 + fix_p7_1.md #1

```bash
# 1. Tạo resources thật, điền id vào [env.production] của worker/wrangler.toml
wrangler d1 create appvantai && wrangler kv namespace create APP_KV
#    (thay REPLACE_WITH_REAL_D1_ID / REPLACE_WITH_REAL_KV_ID trong wrangler.toml)
# 2. Kiểm tra cấu hình production TRƯỚC khi deploy (chặn nếu còn placeholder/dev secret)
npm run verify:deploy
# 3. Secrets (KHÔNG commit, KHÔNG truyền qua --var/command line)
wrangler secret put JWT_SECRET --env production
wrangler secret list --env production   # xác nhận JWT_SECRET + FIREBASE_PROJECT_ID? tồn tại
# 4. Migrations vào D1 production
wrangler d1 migrations apply appvantai --remote --env production
# 5. Deploy bằng cấu hình [env.production] (APP_ENV=production, ALLOW_DEV_OTP=false)
#    (npm run deploy tự chạy verify:deploy trước)
npm run deploy
# 6. Seed admin sau khi tạo user đầu tiên
wrangler d1 execute appvantai --remote --env production --command \
  "UPDATE users SET role='admin' WHERE phone='<số-admin>'"
# 7. Xác minh sau deploy:
#    - curl https://<worker>/health → phải trả "env":"production"
#    - Mọi request → không được là 503 PRODUCTION_MISCONFIGURED (guard fail-fast:
#      còn dev secret/thiếu FIREBASE_PROJECT_ID thì CẢ server chặn, không chỉ log)
#    - POST /auth/request-otp → response KHÔNG chứa dev_otp
#    - wrangler tail → không được có log PRODUCTION_ENV_GUARD
```

**Lưu ý guard (fix_p7_1.md #1):** production cấu hình sai (dev JWT secret,
ALLOW_DEV_OTP=true, thiếu FIREBASE_PROJECT_ID, JWKS ngoài localhost) → **mọi
request nhận 503 PRODUCTION_MISCONFIGURED** — sai cấu hình không thể âm thầm
chạy. Dev (APP_ENV=dev) không bị ảnh hưởng.

**As-built (đã deploy thật 2026-09-11):**

- URL: `https://appvantai-api.testhoangweb.workers.dev` (account Cloudflare của
  chủ dự án — `npx wrangler login`; version `5c3285ce`)
  ▸ **Repo này public** — không ghi email/token vào tài liệu trong repo.
- D1 `appvantai` = `99b06c30-…` · KV `APP_KV` = `cab09561-…` (đã điền vào
  wrangler.toml cả dev lẫn [env.production]; id đọc lại bằng
  `wrangler d1 list` / `wrangler kv namespace list`)
- Secrets: `JWT_SECRET` (openssl rand) + `FIREBASE_PROJECT_ID=appvantai1`
- Migrations 0001→0009 đã apply `--remote` (9/9 ✅)
- Smoke xác minh: request-otp không trả `dev_otp` (`{"ok":true}`),
  `/auth/firebase` thiếu token → 400 hợp lệ, không còn 503 guard

**Seed production (2026-09-11):**

- Script: `worker/scripts/seed_pilot_prod.sql` — SQL-only qua
  `wrangler d1 execute appvantai --remote --file ...` (production không có dev
  OTP nên không seed qua API được như `seed_pilot.sh` local)
- Đã seed: 1 admin (`0363930250`, login Firebase lần đầu tự nhận role admin —
  upsert không ghi đè role) + 4 tài xế + 8 chủ hàng + 4 driver_profiles +
  8 đơn corridor HN→HP (6 thật + 2 nhiễu, `notes='pilot'` để dọn được)
- User seed SQL-only = token của họ chưa từng tồn tại (an toàn hơn seed API)
- Matching verify E2E trên production: tạo trip thật → OSRM polyline thật →
  3 match đúng (score 100/100/70, detour 0/−3.7km), 2 đơn nhiễu bị pre-filter;
  trip+match test đã xoá, JWT_SECRET đã rotate sau verify (token test chết)

**Firebase Phone Auth production (2026-09-11):**

- `mobile/android/app/google-services.json` (project `appvantai1`, package
  `vn.appvantai.appvantai_mobile`) commit trong repo — CI đọc file này sinh
  dart-defines `FIREBASE_*` + `USE_FIREBASE_AUTH=true` lúc build (cơ chế
  dart-define của phase 7, KHÔNG cần gradle plugin google-services)
- `mobile/android/app/debug.keystore` commit cố ý (password chuẩn `android`,
  không phải secret) — SHA-1/SHA-256 cố định phải được đăng ký trên Firebase
  console (Authentication → Sign-in method → Phone → Domains/fingerprints) else
  SMS bị chặn `API restriction`; keystore debug random mỗi CI build là nguyên
  nhân phổ biến khiến SMS hỏng không đều
- Worker `/auth/firebase` chuẩn hoá `phone_number` E.164 (+84xxx) từ ID token
  về 0xxx (identity duy nhất) — khớp user seed/admin đã tạo từ trước
- Mobile `FirebaseAuthStrategy.toE164`: 0xxx → +84xxx trước khi gọi
  `verifyPhoneNumber` (Firebase bắt buộc E.164)
- User seed `legal_consent_at` để TRỐNG — consent §18 sinh từ audit log khi
  user tick disclaimer in-app lần đầu login (không set thẳng SQL nữa)

**Mobile release (fix_p7_1.md #2):** build APK release không truyền
`--dart-define=APP_ENV=production` (hoặc staging) sẽ **fail ngay lúc build**
(Gradle check). APP_ENV=production bắt buộc thêm: API HTTPS non-local,
`USE_FIREBASE_AUTH=true` + đủ 4 dart-define Firebase — thiếu là crash khi mở app
(assertReleaseConfig), không thể chạy nhầm auth dev.

**Rollback:** `wrangler rollback` (Worker versions); D1 time-travel cho data
(`wrangler d1 time-travel restore appvantai --timestamp=<ISO>`).

---

## Phase 8 — Store / phân phối (xuất bản mềm)

Chiến lược: **Soft launch** — Internal testing → Closed testing (10–30 user).
Không nhảy thẳng Production store trong vòng này.

### Checklist build release Android (người vận hành chạy)

```bash
# 0. (Một lần) Tạo keystore — KHÔNG commit file keystore/key.properties
cd mobile/android && cp key.properties.example key.properties
cd mobile && flutter pub get  # if not already
keytool -genkey -v -keystore ~/appvantai-release.jks -keyalg RSA \
  -keysize 2048 -validity 10000 -alias appvantai
# → điền path/alias/password vào mobile/android/key.properties (đã gitignore)

# 1. Build AAB (Play) — dart-define PRODUCTION: API https + Firebase auth bật.
#    Thiếu APP_ENV=production → Gradle FAIL-FAST (fix_p7_1 #2). Thiếu Firebase
#    config → app crash khi mở (assertReleaseConfig).
flutter build appbundle --release \
  --dart-define=APP_ENV=production \
  --dart-define=API_BASE_URL=https://<prod-worker>.workers.dev \
  --dart-define=USE_FIREBASE_AUTH=true \
  --dart-define=FIREBASE_API_KEY=<key> \
  --dart-define=FIREBASE_PROJECT_ID=<id> \
  --dart-define=FIREBASE_APP_ID=<id> \
  --dart-define=FIREBASE_MSG_SENDER_ID=<sender>
# → build/app/outputs/bundle/release/app-release.aab (version 1.0.0+1)

# 1b. (Optional, APK phân phối trực tiếp group tài xế — closed test)
flutter build apk --release <cùng các dart-define như trên>

# 2. Kiểm tra AAB trước khi upload (không quyền thừa, không debug-sign):
#    - Manifest: chỉ INTERNET + ACCESS_COARSE/FINE_LOCATION (không background)
#    - Data safety form (Play): location — chỉ thu khi dùng app (trip active);
#      phone number — thu, không chia sẻ ngoài đối tác đã liên hệ
#    - Content rating: trả lời form, Business/Maps & Navigation category
```

### Play Console — soft launch track

1. Tạo app → **Internal testing** (tối đa 100 tester, lên store trong vài phút)
2. Upload AAB → mời tester qua email list
3. Sau Internal ổn → **Closed testing** (10–30 user thật: tài xế + chủ hàng quen)
4. Đo 1–2 tuần: completion rate, crash, report → sửa P0 → mở dần
5. **Không** mở Production store khi còn P0 (theo production_roadmap cổng cuối)

### Store listing tối thiểu

- **Tên:** App Vận Tải — radar tìm mối tiện đường (KHÔNG claim "Grab vận tải")
- **Mô tả ngắn:** Tài xế đang chạy tuyến → tìm hàng cùng hướng; chủ hàng tìm xe
  rảnh theo tuyến đi qua.
- **Screenshot gợi ý (3–5):** radar match card (score + reasons), tạo chuyến,
  lifecycle đơn (pickup → in-transit → delivered), màn liên hệ.
- **Category:** Business hoặc Maps & Navigation (chọn 1)
- **Privacy Policy URL:** host `docs/legal/` lên Cloudflare Pages (xem
  `docs/legal/README.md`) — Terms + Privacy đã có bản public + in-app.
- **Support:** email/Zalo OA (điền khi tạo listing) + Báo cáo in-app đã hoạt động.

### iOS (P1 — Android-first)

Project hiện **chưa có cấu hình Apple Developer** (chưa có certificates/Bundle
ID đăng ký) → launch 1 là **Android-first**. Khi có tài khoản Apple: thêm
`NSLocationWhenInUseUsageDescription` tiếng Việt (đã có sẵn trong
`ios/Runner/Info.plist`) → TestFlight internal → review notes nêu rõ mô hình
"trung gian kết nối, không phải hãng vận tải".

### Rollback & support sau launch

- **Worker:** `wrangler rollback` — API giữ backward compatible với build cũ
  trong closed test (không xóa field response).
- **Mobile:** KHÔNG force-update lần đầu — closed test dùng build cũ vẫn chạy.
- **Support:** in-app Báo cáo → admin xử lý (`GET /admin/reports`) + kênh Zalo/email.

### Verify release config (trước khi upload)

- [ ] AAB không trỏ localhost: decompile nhẹ —
      `unzip -p app-release.aab base/AndroidManifest.xml | strings | grep -c localhost` = 0
      (dart-define được bake vào libapp.so — check thêm log khi chạy bản release)
- [ ] Dev OTP path tắt: bản production chỉ login Firebase (`USE_FIREBASE_AUTH=true`),
      server production không trả `dev_otp` (đã verify bằng e2e_phase7_m1 1.2)
- [ ] Quyền: chỉ INTERNET + location when-in-use (đã rà trong AndroidManifest.xml)
- [ ] Version: `1.0.0+1` rõ ràng, bump `+N` mỗi build upload (+minor cho feature)
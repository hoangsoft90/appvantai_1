# openspec.md — Tiến độ, bug, todo

> Cập nhật 2026-09-10 (sau Phase 6).

## Baseline spec (openspec/specs/) — 11 capability, khớp code ĐÃ IMPLEMENT

`auth-otp` · `user-identity-vehicle` · `order-marketplace` · `order-lifecycle` ·
`driver-engagement` · `trip-matching` · `trip-gps` · `maps-geocoding` ·
`safety-moderation` · `platform-core` · `app-shell-navigation`

- Mỗi spec có mục "Cần làm rõ" — các mục đã chốt ghi inline "→ Chốt/ĐÃ GIẢI
  QUYẾT"; chưa chốt phải hỏi user trước khi code quanh nó.
- 2026-09-10: `trip-matching` + scenario vehicle_requirement pre-filter + mục
  "Verification evidence — Phase 6"; `platform-core` + requirement "Pilot tooling"
  (seed idempotent, smoke 14/14, metrics SQL) + scenario /health gate.

## Trạng thái phase (theo .plan/production_roadmap.md)

| Phase | Trạng thái |
|---|---|
| 0–5 Foundation → Safety/Lifecycle | ✅ Xong + verified (verify_all: tsc clean, 85/85 E2E, analyze + 34 Flutter tests) |
| plan2_final A–I hardening | ✅ Xong |
| plan3_final 6 mục (role lock, GPS active-only, lifecycle UI, match card, maps, production) | ✅ Xong |
| plan4_final (cancel siết, production guard, role lock business-state, polish 4.1–4.4) | ✅ Xong |
| **6 — Pilot** | 🟡 **Tooling xong** (seed idempotent 4/4 match, smoke 14/14 PASS, metrics SQL, checklist `docs/pilot_checklist.md`) — **chờ pilot thật** 1 corridor HN→HP |
| 7 — Production hardening (auth thật, secrets, observability) | ⬜ Sau pilot |
| 8 — Store / phân phối | ⬜ Cuối |

## Bug đã biết (chưa fix — user chốt fix sau baseline)

1. **`GET /me` trả `driver_profile` rỗng non-null cho driver mới** → mobile parse
   non-null → router gate không giữ driver ở `/vehicle` sau reload app.
   (user-identity-vehicle "Cần làm rõ" #3 — user chốt LÀ BUG CẦN FIX.)
2. **`AsyncView._messageOf` dùng `error.toString()`** → UI hiện `ApiException(...): msg`
   thay vì message trần (app-shell-navigation "Cần làm rõ").

## Ghi nhận quirks (chưa quyết — trong "Cần làm rõ" của spec)

- `trips.direction` dead column (hardcode 'one_way', mọi logic đọc `trip_type`).
- Trip rate limit vẫn KV TOCTOU (orders/contact đã D1 atomic).
- Comment "active first" của GET /trips lệch ORDER BY created_at DESC.
- `_intOf` form xe chặn ô chiều rỗng với message lỗi chung ("không hợp lệ").

## Việc tiếp theo (thứ tự)

1. **Pilot thật** (người/semi-thật): chạy tay 11 bước `docs/pilot_checklist.md`,
   ghi funnel `npm run pilot:metrics` vào `result_pilot.txt`. Ngưỡng: ≥70% trip
   có match, contact ≥30%, accept ≥50%, cancel-sau-accept = 0.
2. Fix bug #1 (driver_profile rỗng) + #2 (messageOf) — nhỏ, trước hoặc song song pilot.
3. Phase 7 khi pilot đạt: `.plan/phase7_production_hardening.md` (auth production,
   secrets, observability).
4. Phase 8: store/pipeline release (`.plan/phase8_store_release.md`).

## Không làm (frozen — anti-overengineering)

Push, chat, rating, payment, map picker, multi-corridor, AI/ML — tới khi pilot
pass (plan §2.2, operating_rules §2).

# context.md — Project state snapshot

> Update this file at the END of any session that changes code. Goal: next agent opens it and knows exactly where we are.

Last updated: 2026-09-10 (Phase 6 pilot tooling done; plan3+plan4 shipped)

## One-liner

Cargo marketplace MVP: customers post orders, drivers post trips, a route-aware
matching engine ("Cargo Radar") pairs them by corridor/direction/detour. Target 0đ
operating cost. Backend = Cloudflare Worker; app = Flutter.

## Status: PILOT-READY (Phase 6 tooling done, awaiting real pilot run)

- **Done & verified:** Phase 0–5 + plan2_final A–I + plan3_final (6 mục) +
  plan4_final (cancel siết, production guard, role lock business-state, polish
  4.1–4.4) + **Phase 6 pilot tooling** (seed idempotent corridor HN→HP — 4/4
  driver có match; smoke full loop 14/14 PASS; metrics SQL; checklist
  `docs/pilot_checklist.md`).
- **Pilot evidence (2026-09-10, mock maps):** `npm run seed:pilot` → 12 match
  (truck 100/100/90/61, van 2, pickup 2; 2 đơn nhiễu bị pre-filter loại);
  `npm run pilot:smoke` → 14/14 PASS (match→contact→accept→cancel-blocked→GPS→
  lifecycle→completed).
- **Next:** real pilot run (11 bước checklist + funnel) → Phase 7 hardening
  (`.plan/phase7_production_hardening.md`).

## What exists now

### Backend (`worker/`)
- Auth: OTP flow (KV, 5/15min rate limit), JWT HS256 30d, role read from DB every request.
- Orders: create/list/detail/cancel + lifecycle `pickup / in-transit / delivered / complete`
  via centralized state machine (`services/order_state_machine.ts`).
- Trips: create (with `trip_type` one_way|return), start/end, matches (`/trips/:id/matches`).
- Matching pipeline: grid pre-filter → corridor (point-to-line ≤10km) → bearing (≤135°)
  → time → top-5 OSRM detour (≤15km) → 6-component score + reasons (VN text).
- Safety: contact (privacy: phone only after contact), atomic accept, reports, blocks,
  legal consent, audit logs, admin moderation.
- Concurrency: atomic rate limits in D1 (`rate_limits` UPSERT RETURNING), atomic
  active-order limit (insert→count→rollback), `db.batch` match persistence.
- Maps: `maps/` providers mock|osrm|nominatim + `resilience.ts` (timeout + circuit breaker),
  `GET /maps/geocode` with KV cache.
- GPS: KV `loc:<driver_id>` TTL 2h, throttle 30s, only during active trip; privacy —
  order detail returns rounded distance only, never raw lat/lng.
- Env guard (`lib/env_guard.ts`): production refuses dev OTP / dev JWT secret.

### Mobile (`mobile/lib/`, Feature-First)
- `feature/auth` — OTP login (dev OTP shown in SnackBar), `feature/identity` — role choice,
  vehicle form (1 driver = 1 vehicle), profile.
- `feature/order` — order form (geocode address search), list/detail/cancel, driver distance.
- `feature/trip` — trip form (geocode search for both points), radar matches screen,
  trip run screen (GPS, end-trip with offline-safe retry + "chưa sync" banner + reconcile).
- `feature/safety` — report/block.
- `shared/` — api_client (Dio), token storage (shared_preferences behind interface),
  `AsyncView` (Loading/Error/Retry/Empty), `ApiException` (VN messages).
- `core/config/app_config.dart` — `--dart-define` API_BASE_URL, `assertReleaseConfig()` fail-fast.

### Migrations 0001–0008 (D1)
init → identity → cargo → route_matching → safety → lifecycle → rate_limits → trip_type.

## Key design decisions (why)

1. **Atomic Accept via single UPDATE … WHERE status IN (…) AND driver_id IS NULL** —
   D1 is single-writer; affected-rows check gives race-free accept without transactions.
2. **Role from DB per request, not JWT claim** — ban/role-change takes effect immediately
   (stale-role bug found in Phase 3 testing).
3. **GPS in KV, not D1** — D1 free tier = 100k writes/day; realtime writes would burn it.
   D1 only on trip start/end.
4. **Lazy expiry, no cron** — orders past `expires_at` are shown as `expired` at read time.
5. **MapsProvider abstraction** — `mock` provider (deterministic VN landmark table) makes
   E2E tests network-free; OSRM/Nominatim only in matching and geocode.
6. **Riverpod 3 codegen + watch-in-build rule** — controllers that only `ref.read` get
   disposed → "Ref disposed" error; always watch in build.
7. **GoRouter refresh only on landing change** — refresh() re-parses URL and drops the
   push stack in go_router 16 (pop() breaks).
8. **shared_preferences token storage behind interface** — swap to secure storage later
   without touching call-sites (P1 item).

## Known bugs / gotchas (all fixed, keep in mind)

- Seed scripts must `PATCH /me` to set role=driver — new users default to customer,
  so POST /trips 403s (this caused a fake "0 match").
- OTP request rate limit (5/15min per phone) is exhausted quickly by retry loops —
  retries should re-verify, not re-request OTP.
- OSRM public server returns 403 without an explicit User-Agent.
- E2E leftover data breaks reruns (active-order limit, rate limits) — the suite runner
  patches unique phone numbers per run.
- `pkill -f "wrangler dev"` matches its own command line — use `[d]`-class patterns.

## Not yet done (deliberate, per plan §10/§15 — P1, do NOT add before pilot)

- Push notifications, order/trip history screens, ratings/reviews, secure token storage
  (flutter_secure_storage), real SMS provider (Firebase/Zalo), map picker UI.
- Phase 6 Pilot **tooling** — DONE (seed/smoke/metrics/checklist). Real pilot
  run (người thật/semi-thật, funnel thật) — requires user-side execution;
  metrics chỉ chuẩn trên DB sạch (working.md trap 10).
- Phase 7 Production hardening — auth thật (Firebase/Zalo), secrets, observability.

## Deployment state

- wrangler.toml holds placeholder D1/KV IDs (local dev only). Production steps are in
  README "Deployment procedure". No production deployment yet.

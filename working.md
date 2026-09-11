# working.md — How to work in this repo

> Commands, verification workflow, and environment traps. Read once, follow always.

## Current state (2026-09-11)

Phase 0–8 done (review result.md: all GO). Release ops 2026-09-11: targetSdk/compileSdk
**36**, cleartext HTTP allowed, app icon (mipmap+adaptive+store 512, generator
`mobile/tool/gen_icons.py`), Sentry (`sentry_flutter`, DSN qua dart-define `SENTRY_DSN`),
GH Actions debug-APK workflow `.github/workflows/android-debug-apk.yml` (Flutter 3.47.2,
JDK 17, AGP 9.1, gradle trực tiếp) — **GREEN, artifact `appvantai-debug-apk` ~84MB**
(run 34584725090; run AdMob 34587277648 cũng success). **AdMob tích hợp xong** —
flag TEST_ADS (dart-define, mặc định true = test IDs Google), banner Home +
interstitial sau tạo đơn + App Open (cold start/resume ≥30s); chi tiết
`.project/modules/ads.md`. Repo pushed to `github.com/hoangsoft90/appvantai_1`
(master); token live trong `.secrets/gh_token` (gitignored). 3 bài học CI đã fix
lần lượt: Groovy-trong-.kts, guard release eagerly-evaluated, thiếu build_runner
codegen trên CI (chi tiết trong skill `gh-debug-apk`).
Local Android SDK/gradle DELETED (2026-09-11) — APK chỉ build trên GH Actions.
**Backend LIVE trên Cloudflare (2026-09-11)**: `https://appvantai-api.testhoangweb.workers.dev`
— D1 `appvantai` + KV `APP_KV` thật (id trong wrangler.toml), migrations 0001→0009
applied `--remote`, secrets `JWT_SECRET` + `FIREBASE_PROJECT_ID=appvantai1`, guard
503 verified. Deploy lại: `cd worker && npm run deploy` (as-built trong README §Deployment).
Project knowledge base lives in `.project/` (update it + context.md at session end
per `.project/ai-rules.md` §2).

## OpenSpec baseline (2026-09-09, updated 2026-09-10)

`openspec/specs/` now has **11 capability specs** describing the code AS IMPLEMENTED
(not aspirational):
`auth-otp`, `user-identity-vehicle`, `order-marketplace`, `order-lifecycle`,
`driver-engagement`, `trip-matching`, `trip-gps`, `maps-geocoding`,
`safety-moderation`, `platform-core`, `app-shell-navigation`.

2026-09-10 (Phase 6 — Pilot tooling): `trip-matching` có thêm scenario
`vehicle_requirement` pre-filter + mục "Verification evidence — Phase 6 pilot
corridor"; `platform-core` có thêm requirement "Pilot tooling" (seed idempotent,
smoke full loop 14/14, metrics SQL) + scenario /health gate cho scripts. Specs
còn lại không đổi.

Rules when working against them:
- Each spec's "Cần làm rõ" section lists real ambiguities found while reading code.
  Several were answered by the user (2026-09-09) — answers are written inline as
  "→ Chốt:" / "→ ĐÃ GIẢI QUYẾT". Unresolved ones need an answer before coding around them.
- Known follow-up bug (user-confirmed, fix deferred): `GET /me` returns a non-null
  EMPTY `driver_profile` for new drivers → mobile parses it as non-null `VehicleProfile`
  → router gate `user.vehicle == null` does not hold a driver without vehicle on
  `/vehicle` after app reload. Fix AFTER baseline work, not during doc tasks.
- Spec coverage is both sides (Worker = canonical behavior, Flutter = consuming surface).

## Hard constraint (user directive)

**Do NOT build or run the Flutter app locally.** No `flutter run`, no `flutter build`,
no emulator. Local dev artifacts were deliberately deleted (disk-constrained).
Allowed: `flutter analyze`, `flutter test`, `dart run build_runner`. Real-device
verification is done by the user on request.

Backend (`wrangler dev`) + bash E2E scripts ARE allowed and are the standard way to
produce test evidence.

## Commands

### Worker (backend)
```bash
cd worker
npm run typecheck                                  # tsc --noEmit — ALWAYS run after edits
npx wrangler d1 migrations apply appvantai --local # after adding a migration
npm run dev                                        # http://localhost:8787 (dev OTP enabled)
npx wrangler d1 execute appvantai --local --command "SELECT ..."  # inspect local D1
```

### Flutter (analyze/test only — no build!)
```bash
cd mobile
dart run build_runner build --delete-conflicting-outputs  # after changing @riverpod providers
flutter analyze --no-pub
flutter test
```
Note: analyze/test need `.dart_tool` (first run re-creates it via `flutter pub get`).

### Full verification (the "done" gate)
```bash
cd worker && bash scripts/verify_all.sh
# [1/3] tsc clean · [2/3] E2E suite 85 checks · [3/3] flutter analyze + tests
```

### Phase 6 — Pilot tooling (seed/smoke/metrics)
```bash
cd worker
npm run seed:pilot     # seed idempotent corridor HN→HP + matching (4/4 driver có match, 12 match)
npm run pilot:smoke    # 1 vòng lặp đầy đủ trên data seed — 14/14 PASS (expect ALL GREEN)
npm run pilot:metrics  # 4 nhóm SQL funnel (chỉ chuẩn trên DB sạch — xem trap 10)
bash scripts/seed_pilot.sh --reset-seed   # xóa data seed, không tạo lại
```
Manual checklist cho pilot thật: `docs/pilot_checklist.md` (11 bước + tài khoản
seed `0983500001–04` driver / `0983600001–08` customer, dev OTP).

### E2E evidence scripts (backend)
Per-phase scripts in `worker/scripts/` (`run_e2e_suite.sh` runs all):
each prints `PASS:`/`FAIL:` lines. A task is done only when its new/changed behavior
appears as PASS in a real run.

Pattern used for E2E runs (server dies when the tool call ends → server + tests in ONE command):
```bash
cd worker && timeout 280 bash -c '
(npx wrangler dev --port 8787 --var MAPS_PROVIDER:mock >/tmp/wr.log 2>&1) &
for i in $(seq 1 40); do curl -sf localhost:8787/health && break; sleep 1; done
bash /tmp/e2e_phaseX.sh
pkill -f "worker[d]" 2>/dev/null; true'
```
Kill patterns: use `worker[d]` / `wrangl[e]r` character classes so the pattern never
matches the shell command itself (self-kill trap).

## Conventions

- **Backend:** Hono routes in `src/routes/`, logic in `src/services/`, all errors via
  `lib/errors.ts` envelope `{ error: { code, message, status } }`. New D1 objects need a
  numbered migration in `migrations/` (next: 0009). VN user-facing messages.
- **Flutter:** Feature-First `lib/feature/<name>/{data,domain,application,presentation}`;
  Riverpod codegen (`@riverpod`, never manual providers); GoRouter in
  `lib/app/router/app_router.dart`; VN UI text; shared widgets in `lib/shared/widgets/`
  (`AsyncView` for every async surface).
- **Tests:** backend E2E scripts must patch UNIQUE phone numbers per run (leftover
  rate limits / active orders from previous runs otherwise poison results).
  Flutter tests use fakes in `test/helpers/`.

## Known traps (encountered for real — don't rediscover them)

1. **Wrangler dev dies when the tool call ends** → run server+tests in one `bash -c`.
2. **"Address already in use"** → a stale workerd from a previous run is still bound;
   `pkill -f "worker[d]"` before starting.
3. **Rate limits persist in local D1/KV** across runs → unique phones per run, or
   execute SQL to clear `rate_limits`.
4. **OTP limit 5/15min per phone** → retry logic must re-verify only, never re-request.
5. **Local D1 was wiped** when `.wrangler/` was deleted → re-apply migrations before testing.
6. **Riverpod "Ref disposed"** → controllers must be watched in build, not only read.
7. **OSRM 403** without explicit `User-Agent` header.
8. **go_router 16**: `GoRouter.refresh()` drops the push stack — only refresh on landing change.
9. **Old `posted` orders in local D1 poison matching E2E** — stale orders fill Top-5
   then get detour-rejected → `data: []`. Wipe `cargo_orders` or use unique coords
   before matching tests (real incident while testing plan3 Mục 4).
10. **Local D1 residue pollutes pilot metrics** — `pilot_metrics.sql` counts
   ALL users/contacts/matches, and the local DB accumulates E2E leftovers
   (e.g. 88 users, contacts not from seed). Numbers are only meaningful on a
   clean DB (fresh DB or wipe before the real pilot) — noted in the SQL header
   too (Phase 6 session).
11. **`.project/` and root doc files are volatile** — lost once in a disk
   cleanup (2026-09-10). Before recreating, `ls` first; `.project/ai-rules.md`
   §2 defines the update protocol.

## Definition of done (per task)

1. Code change committed to the working tree (no "verbal" completions).
2. `npm run typecheck` (worker) and/or `flutter analyze` (mobile) clean.
3. Behavior proven: E2E PASS lines / unit tests pass / curl transcript.
4. If the change adds migration or env var → README + context.md updated.
5. Report: what changed (files), what was run, actual output summary — even for partial work.

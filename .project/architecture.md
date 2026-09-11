# architecture.md — Kiến trúc code

> Cập nhật 2026-09-10. Chi tiết hành vi từng feature: `modules/*.md`;
> spec chuẩn: `openspec/specs/`.

## Cấu trúc thư mục

```
worker/                          # Cloudflare Worker (Hono + TS)
├── src/
│   ├── index.ts                 # app assembly + onError/onNotFound (envelope)
│   ├── env.ts                   # typed bindings DB/APP_KV + vars
│   ├── lib/                     # errors (envelope), env_guard, geo, logger, phone
│   ├── middleware/              # request-id, auth (JWT + role từ DB mỗi request)
│   ├── maps/                    # provider.ts (mock|osrm), nominatim, resilience (timeout + circuit breaker)
│   ├── services/                # business logic thuần (otp, users, profiles, orders,
│   │                            # order_state_machine, lifecycle, trips, matching,
│   │                            # accept, contacts, gps, safety, audit, rate_limit…)
│   └── routes/                  # auth, me, orders, trips, maps, safety, admin (mỏng: parse + gate)
├── migrations/                  # 0001 init → 0008 trip_type (D1)
└── scripts/                     # E2E evidence + pilot tooling (seed_pilot, pilot_smoke, pilot_metrics.sql)

mobile/                          # Flutter — Feature-First
├── lib/
│   ├── app/                     # app.dart, router/app_router.dart, theme/app_theme.dart
│   ├── core/config/             # app_config.dart (--dart-define, assertReleaseConfig)
│   ├── shared/
│   │   ├── services/            # api_client (Dio), api_exception, token_storage, location_service
│   │   └── widgets/             # async_view, error_view, empty_view, loading_view, splash
│   └── feature/<name>/          # auth, home, identity, order, safety, trip
│       ├── data/                # repository (Dio calls) + DTO parse
│       ├── domain/              # models + rules thuần (ví dụ nextLifecycleAction)
│       ├── application/         # Riverpod controllers/providers (@riverpod codegen)
│       └── presentation/        # screens + widgets
└── test/                        # widget/unit test + test/helpers/ (fake repositories)
```

## Data flow (chuẩn mỗi feature)

```
UI (Screen/Widget)
  → ref.watch(controllerProvider)            # application/ — AsyncNotifier (@riverpod)
    → Repository (data/)                     # Dio qua ApiClient (tự gắn Bearer)
      → Worker route (thin: parse + role gate + consent)
        → Service (business logic + D1/KV, state machine, audit)
      ← { data } hoặc { error: { code, message, status } }
    ← ApiException (map envelope → message VN, isNetworkError)
  ← AsyncValue → AsyncView (Loading/Error/Retry/Empty)
```

Invariant đáng nhớ:
- **State machine đơn nguồn**: mọi đổi status đơn qua `order_state_machine.ts`
  + UPDATE có điều kiện (WHERE status IN…) — client không bao giờ tự đặt status.
- **Role/consent/ownership check ở Worker mỗi request**; client chỉ ẩn/hiện nút.
- **Matching đọc polyline trip** (encode 1e6) — pipeline 6 bước trong
  `services/matching.ts`, chi tiết trong `openspec/specs/trip-matching/spec.md`.
- **GPS chỉ KV** (`loc:<driver_id>` TTL 2h, throttle 30s) — D1 chỉ ghi ở start/end.

## Backend error contract

`{ "error": { "code": "STABLE_CODE", "message": "tiếng Việt", "status": 4xx } }`
— client parse đúng shape này; mã ổn định quan trọng: `CANCEL_NOT_ALLOWED`,
`ROLE_LOCKED`, `TRIP_NOT_ACTIVE`, `ORDER_ALREADY_ACCEPTED`, `POST_RATE_LIMITED`.

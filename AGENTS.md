# AGENTS.md — App Vận Tải (Cargo Radar)

> Read this file FIRST, every session. It tells you where the truth lives and what you must not break.

## What this project is

MVP marketplace connecting cargo owners (customer) with truck drivers (driver) via
**Route-aware matching ("Cargo Radar")**: a driver posts their trip, the engine finds
orders whose pickup point lies near the driver's actual route (corridor + direction +
detour verification), instead of plain location browsing.

Operational cost target: **0đ/month** (Cloudflare free tier + OSRM/Nominatim public servers).

## Single Source of Truth (SSOT)

| Doc | Role |
|---|---|
| `.plan/plan_final_v2.md` | Product thesis, matching pipeline, data model, P0/P1 scope |
| `.plan/plan2_final.md` | Hardening plan A→I (security, state machine, concurrency, release gate) |
| `README.md` | Phase status, technical decisions per phase, deployment procedure |
| `.project/` (if present) | Feature-level knowledge base (modules, integrations, design system) |

If code and plan disagree → **the plan wins**; fix the code or raise the conflict to the user.
Do not invent features outside P0 scope (§2.2 non-goals).

## Repository layout

```
worker/    Cloudflare Worker (Hono + TypeScript) + D1 migrations + scripts/
mobile/    Flutter app (iOS + Android), Feature-First
.plan/     SSOT documents (do not edit without user approval)
```

## Stack (chốt, không đổi khi chưa hỏi)

- **Backend:** Hono on Cloudflare Workers, D1 (SQLite), KV. No other infra.
- **Mobile:** Flutter (Dart SDK ^3.13), Riverpod 3 + riverpod codegen, GoRouter 16, Dio.
- **Maps:** OSRM (routing) + Nominatim (geocode) + local Haversine/point-to-line. No Google Maps.
- **Auth:** Dev OTP (JWT HS256 signed by Worker). Swap point for Zalo/Firebase later — API surface must not change.
- **Token storage:** `shared_preferences` behind `TokenStorage` interface (swap to secure storage later without touching call-sites).

## Non-negotiable working rules (details in operating_rules.md)

1. **Priority order:** 0đ cost → matching quality → reliability → no over-engineering.
2. **Evidence before "done":** every task needs code change + passing verification (see working.md commands). Never claim completion without real tool output.
3. **Backend checks are authority:** role/ownership/consent/rate-limit/state-machine all enforced server-side; client validation is UX only.
4. **Never build/run the Flutter app locally** (user directive: local dev has been removed, disk-constrained). Write code + run `flutter analyze`/`flutter test` only; real verification happens on the user's side.
5. Match to the plan's state machine — do not add transitions or client-side "convenience" states.
6. Respond in Vietnamese when the user writes Vietnamese (default working language of this repo).

## Quick orientation (who to read next)

- Commands & pitfalls → `working.md`
- Full state snapshot & known bugs → `context.md`
- Priority principles & anti-overengineering rules → `operating_rules.md`
- Architecture deep-dive → `README.md` (Quyết định kỹ thuật) and `.plan/` docs

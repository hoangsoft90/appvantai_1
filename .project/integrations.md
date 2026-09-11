# integrations.md — Tích hợp 3rd party & cấu hình hệ thống

> Cập nhật 2026-09-10. Nguyên tắc: 0đ — mọi dịch vụ dùng free tier/public.

## Maps (không Google Maps)

| Dịch vụ | Dùng cho | Cache | Lưu ý |
|---|---|---|---|
| OSRM `router.project-osrm.org` | route A→B (polyline 1e6, distance, duration) | D1 `route_cache` (key tọa độ làm tròn ~11m, TTL 30 ngày) | **403 nếu không có User-Agent**; timeout 10s + circuit breaker (`maps/resilience.ts`) |
| Nominatim | geocode search (order + trip form) | KV `geo:<query>` | Throttle 1.1s giữa 2 request (usage policy) |
| Mock provider (`MAPS_PROVIDER=mock`) | E2E/test local | — | Bảng địa danh VN deterministic (có đủ corridor HN→HP) |

## Auth (hiện tại = Dev OTP)

- Worker tự sinh OTP 6 số lưu KV (TTL 5 phút, rate limit 5/15 phút), echo
  `dev_otp` **chỉ khi** `APP_ENV=dev` && `ALLOW_DEV_OTP=true` (plan4 §2: env khác
  dev bị ép tắt, response không bao giờ chứa mã).
- JWT HS256 30 ngày, ký bằng `JWT_SECRET`; role đọc từ DB mỗi request.
- **Phase 7** sẽ gắn Firebase Phone Auth hoặc Zalo Login — thay `services/otp.ts`,
  API surface không đổi.

## Hạ tầng Cloudflare

- D1 `appvantai` (binding `DB`) — migrations 0001–0008.
- KV binding `APP_KV` — OTP `otp:<phone>`, `otprl:<phone>`, trip rate `triprl:<driverId>`,
  GPS `loc:<driver_id>` + `loclast:<driverId>` (throttle 30s), geocode cache.
- `wrangler.toml` đang giữ **placeholder ID** (chỉ chạy local). Production:
  `wrangler d1 create` + `kv namespace create` rồi thay ID, secrets qua
  `wrangler secret put JWT_SECRET` (README có đủ deployment procedure).

## Push notification / Payment / Chat

Chưa có — P1 frozen (anti-overengineering, plan §2.2). Không tích hợp gì thêm
trước khi pilot pass.

## CI/CD

Chưa có pipeline. Verify thủ công:
- `cd worker && bash scripts/verify_all.sh` → tsc + 85 E2E + Flutter analyze/test.
- Pilot: `npm run seed:pilot` → `npm run pilot:smoke` → `npm run pilot:metrics`.
- Build release: **cấm build Flutter local** (disk-constrained) — user tự build
  khi cần; Phase 8 (store) sẽ cần pipeline riêng.

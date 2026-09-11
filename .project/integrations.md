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

## AdMob (quảng cáo — thêm 2026-09-11)

- Package `google_mobile_ads ^8.0.0`; chi tiết module: `.project/modules/ads.md`.
- Flag `TEST_ADS` (dart-define, mặc định `true`) → test IDs Google (luôn fill,
  không bị AdMob giới hạn); `false` → ID thật app `ca-app-pub-6917313063209470~9914050394`.
- App ID khai báo trong `AndroidManifest.xml` (`GADApplicationIdentifier`); unit IDs
  chọn trong `lib/core/config/admob_config.dart` (fail-fast khi production thiếu ID).

## Monitoring — Sentry (Phase 7)

- `sentry_flutter ^9.x`, init trong `main()`; DSN qua dart-define `SENTRY_DSN`
  (không truyền → tự tắt, dev không gửi). Environment theo `APP_ENV`, release
  `appvantai_mobile@<APP_VERSION>`.

## Push notification / Payment / Chat

Chưa có — P1 frozen (anti-overengineering, plan §2.2). Không tích hợp gì thêm
trước khi pilot pass.

## CI/CD — GitHub Actions (2026-09-11)

- **Build debug APK trên CI** (không EAS, không keystore, gradle trực tiếp):
  `.github/workflows/android-debug-apk.yml` — trigger push vào `master` khi
  `mobile/**` đổi; artifact `appvantai-debug-apk` (~84MB, giữ 14 ngày).
- Toolchain pinned: Flutter 3.47.2, JDK 17 temurin, AGP 9.1.0, Kotlin 2.4.0,
  Gradle wrapper 9.3.1, compileSdk/targetSdk **36**.
- CI PHẢI chạy `dart run build_runner build` sau `pub get` (`*.g.dart` gitignored).
- Repo: `github.com/hoangsoft90/appvantai_1` (master); token trong
  `.secrets/gh_token` (gitignored — không commit). Quy trình đầy đủ + bài học:
  skill `.opencode/skills/gh-debug-apk/SKILL.md`.
- Verify vẫn giữ chuẩn local (không build APK): `verify_all.sh`, `pilot:smoke`,
  `flutter analyze/test`. Build release: cấm local — thêm workflow riêng khi ship.

# modules/ads.md — Quảng cáo AdMob (kiếm tiền trên store)

> Thêm 2026-09-11. Nguyên tắc: ads là **phụ trợ** — mọi lỗi ads không được chặn
> app chính; dev/test luôn dùng test ads để không bị AdMob giới hạn tài khoản.

## Cấu hình & flag TEST_ADS

`mobile/lib/core/config/admob_config.dart` — 1 file duy nhất giữ mọi ID:

| `TEST_ADS` (dart-define, mặc định `true`) | Unit IDs | Ý nghĩa |
|---|---|---|
| `true` (mặc định) | Test IDs chính thức Google `ca-app-pub-3940256099942544/…` | Luôn fill, không đếm vào tài khoản, không bị limit |
| `false` | ID thật (đã điền đủ, AdMob app `ca-app-pub-6917313063209470~9914050394`) | Kiếm tiền thật trên Play/App Store |

- Real IDs: app-open `…/8101063820`, banner `…/4489121877`, interstitial `…/3040308832`, rewarded `…/9414145495`.
- **App ID khai báo platform-level** (không qua dart-define): `AndroidManifest.xml`
  meta-data `GADApplicationIdentifier` — thiếu là crash khi init SDK.
- Fail-fast: `TEST_ADS=false` mà thiếu ID thật → `AdmobConfig.assertProductionConfig()`
  chặn ở `main()`.
- iOS: chưa có unit thật (Android-first) — điền thêm vào config khi đăng ký.

## Kiến trúc

| File | Vai trò |
|---|---|
| `lib/shared/services/ads_service.dart` | Singleton `AdsService.instance`: init SDK 1 lần ở `main()`, preload + show interstitial/app-open; **no-op khi `kDebugMode`/web** (test env an toàn) |
| `lib/shared/services/app_open_policy.dart` | Hàm thuần quyết định hiện App Open (unit test được, không đụng SDK) |
| `lib/shared/widgets/banner_ad_widget.dart` | Banner tái dùng, ẩn khi chưa load |
| `lib/shared/widgets/app_open_ad_listener.dart` | Vòng đời app (cold start + resume); **AppLifecycleListener là object tạo ở `initState`+`dispose`, KHÔNG phải widget** (lỗi compile nếu return từ build) |

## Điểm đặt (placements)

1. **Banner** — `HomeScreen.bottomNavigationBar` (không che nội dung).
2. **Interstitial** — sau **tạo đơn thành công** (`order_form_screen._submit`),
   fire-and-forget trước `context.go('/orders')` — navigation không bao giờ chờ ad.
3. **App Open** — cold start (frame đầu) + resume sau background **≥ 30s**
   (`AppOpenPolicy`, tránh spam khi bật/tắt liên tục).

## Bằng chứng test (2026-09-11)

- `test/core/admob_config_test.dart` 4/4: mặc định TEST_ADS=true, test IDs Google,
  validate production PASS với ID thật đã điền.
- `test/core/app_open_policy_test.dart` 4/4: cold start hiện, 10s không hiện,
  45s hiện, resume không qua paused không hiện.
- Full suite **58/58 PASS** + analyze sạch (ads no-op trong `flutter test`).

## Vận hành (từ skill `admob-ads-diagnosis`)

- **NO_FILL (error code 3) khi TEST_ADS=false = chuyện tài khoản AdMob** (duyệt
  24h–2 tuần), KHÔNG phải bug code. Test ads luôn fill là bằng chứng pipeline đúng.
- Bật ads thật: build với `--dart-define=TEST_ADS=false` (workflow CI hiện NHÚNG
  dart-define base64 trong file yml — thêm `VGVTVF9BRFM9ZmFsc2U=` vào mảng khi ship).
- Play Console Data safety sẽ cần khai báo "Advertising ID" (thu thập bởi AdMob SDK).

# .project/ — Knowledge base dự án App Vận Tải (Cargo Radar)

> Tái tạo 2026-09-10 (bản cũ mất khi dọn disk). Cập nhật mỗi phiên có thay đổi
> theo `.project/ai-rules.md` §2.

## Tổng quan

MVP marketplace chở hàng: **chủ hàng đăng đơn, tài xế đăng chuyến, engine
"Cargo Radar" ghép theo tuyến đường thật** (corridor ≤10km + cùng hướng ≤135° +
detour OSRM ≤15km) thay vì tìm theo bán kính. Chi phí vận hành mục tiêu **0đ/tháng**
(Cloudflare free tier + OSRM/Nominatim public).

- **Trạng thái (2026-09-11):** Phase 0–8 xong (review result.md: all GO; P7 audit
  fix_p7_1 đã sửa đủ blocker). **Release ops:** CI build debug APK trên GH Actions
  (GREEN, artifact ~84MB), Sentry + AdMob tích hợp (module `modules/ads.md`).
  Đang chờ: pilot thật 1 corridor HN→HP + ops Play Console (người vận hành).
- **Backend:** Cloudflare Worker (Hono + TS) + D1 (migrations 0001–0009) + KV.
- **Mobile:** Flutter, Riverpod 3 codegen + GoRouter 16, Feature-First;
  Sentry + AdMob (`google_mobile_ads`), flag TEST_ADS mặc định true.

## Điều hướng

| File | Nội dung |
|---|---|
| `ai-rules.md` | Quy tắc AI: SSOT, protocol cập nhật, bằng chứng trước "done" |
| `overview.md` | Ứng dụng: mục tiêu, người dùng, tech stack chi tiết |
| `architecture.md` | Kiến trúc code, data flow, thư mục |
| `state-routing.md` | Riverpod + GoRouter + deep link |
| `modules/<feature>.md` | Mỗi feature 1 file: API endpoints, storage |
| `integrations.md` | 3rd party + CI/CD + cấu hình hệ thống |
| `design-system.md` | Màu/spacing/typography + shared widgets |
| `patterns.md` | Pattern code đang dùng + lý do |
| `openspec.md` | Tiến độ, spec status, bug đã biết, TODO |

## Liên kết nhanh ngoài .project

- Lệnh + trap: `working.md` · Snapshot: `context.md` · Entry: `AGENTS.md`
- SSOT: `.plan/plan_final_v2.md`, `.plan/plan2_final.md`, `.plan/phase6_pilot.md`,
  `.plan/production_roadmap.md`, `.plan/phase7_production_hardening.md`
- Baseline hành vi: `openspec/specs/` (11 capability specs)

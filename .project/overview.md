# overview.md — Tổng quan ứng dụng

> Cập nhật 2026-09-10 (Phase 6 pilot tooling xong).

## Mục tiêu

Cho chủ hàng (customer) đăng đơn chở, tài xế (driver) đăng chuyến đang chạy;
engine **Cargo Radar** ghép đơn với chuyến **theo tuyến đường thật** — điểm lấy
hàng nằm gần polyline của chuyến, cùng hướng, detour nhỏ, kịp khung giờ — thay
vì tìm theo bán kính điểm-blank. Value cốt lõi: tài xế giảm chuyến rỗng, chủ
hàng tìm xe giá hợp lý trên đúng tuyến.

## Đối tượng người dùng

| Ai | Làm gì trong app |
|---|---|
| Chủ hàng nhỏ / shop (customer) | Đăng đơn (geocode 2 điểm, khung giờ, tải trọng, giá), theo dõi trạng thái, xác nhận hoàn tất, hủy theo rule, báo cáo/chặn |
| Tài xế tải nhỏ/van (driver) | Khai chuyến A→B (1 chiều/chiều về), quét radar thấy mối tiện đường, liên hệ (nhận SĐT), nhận đơn, chạy lifecycle pickup→in_transit→delivered, GPS khi chuyến active |

Pilot nhắm **1 corridor: Hà Nội → Hưng Yên → Hải Dương → Hải Phòng** (+ chiều về).

## Tech stack chính

| Lớp | Công nghệ | Ghi chú |
|---|---|---|
| Backend | Cloudflare Workers + Hono 4 + TypeScript | Free tier, không server riêng |
| DB | Cloudflare D1 (SQLite) | Migrations 0001–0008, next 0009 |
| Cache/KV | Cloudflare KV | OTP, rate limit OTP/trip, GPS `loc:<driver_id>` TTL 2h |
| Maps | OSRM (route) + Nominatim (geocode) + Haversine/point-to-line local | Mock provider deterministic cho test; KHÔNG Google Maps |
| Auth | Dev OTP (Worker tự sinh 6 số, JWT HS256 30 ngày) | Swap Zalo/Firebase ở Phase 7, API không đổi |
| Mobile | Flutter 3.x (Dart ^3.13), Material 3 | iOS + Android |
| State | Riverpod 3 + riverpod_annotation (codegen) | Watch-in-build bắt buộc |
| Router | GoRouter 16 | Refresh chỉ khi landing đổi |
| HTTP | Dio 5 | Interceptor gắn Bearer, map envelope lỗi |
| Token | shared_preferences qua `TokenStorage` interface | Swap secure storage sau, không đụng call-site |
| GPS | geolocator 14 qua `LocationService` abstraction | Fake trong test |

## SDK / môi trường

- Min/target SDK Android do Flutter default (không chỉnh riêng); iOS usage
  description `NSLocationWhenInUseUsageDescription` đã có.
- Mobile config qua `--dart-define`: `APP_ENV` (dev|production), `API_BASE_URL`
  (default `http://localhost:8787`); release fail-fast nếu trỏ localhost.
- Chi phí vận hành hiện tại: **0đ** (public OSRM/Nominatim + CF free tier).

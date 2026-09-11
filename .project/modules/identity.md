# modules/identity.md — Hồ sơ vai trò + xe

## Làm gì

Chọn vai trò 1 lần (customer/driver); driver khai 1 xe duy nhất (P0 không fleet):
loại xe, biển số, tải trọng, kích thước — bắt buộc trước khi vào home (router gate
`user.vehicle == null` → `/vehicle`).

## API endpoints

| Endpoint | Dùng |
|---|---|
| `GET /me/vehicle` | đọc xe (404 `NO_DRIVER_PROFILE` nếu chưa có) |
| `PATCH /me/vehicle` | upsert xe — validate `vehicle_type ∈ van|pickup|truck|container`, biển số `^[A-Za-z0-9.\- ]{4,12}$`, số nguyên dương |

Role lock business-state (plan4 §3): đổi role bị chặn 409 `ROLE_LOCKED` khi có
đơn `accepted|pickup|in_transit|delivered` (không phụ thuộc expires_at) hoặc đơn
`posted|matched|contacted` còn hạn, hoặc trip `planned|active`.

## Local storage

Không — luôn đọc từ /me.

## Files

`feature/identity/{data,domain,presentation}` (role choice + vehicle form) ·
backend `worker/src/routes/me.ts`, `services/profiles.ts`.

## Lỗi đáng nhớ

- **BUG ĐÃ BIẾT (chưa fix):** `GET /me` trả `driver_profile` `{}` non-null cho
  driver mới → gate không giữ ở `/vehicle` sau reload (fix sau baseline).
- Driver chưa khai xe → capacity 0 → matching trả rỗng (không phải bug engine).

## Spec

`openspec/specs/user-identity-vehicle/spec.md`

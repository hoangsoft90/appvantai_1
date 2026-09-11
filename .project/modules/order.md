# modules/order.md — Đơn hàng + vòng đời

## Làm gì

Customer đăng đơn (geocode search 2 điểm — không nhập tọa độ tay), quản lý đơn,
chạy vòng đời với driver; driver thao tác lifecycle trên đơn được gán.

## API endpoints

| Endpoint | Ai | Ghi chú |
|---|---|---|
| `POST /orders` | customer | rate limit 10/h + tối đa 5 đơn active (atomic D1); `expires_at` default = pickup_to |
| `GET /orders` | customer | đơn của chính mình |
| `GET /orders/:id` | chủ đơn / driver được gán / driver đã contact / admin | khác → 404 (không leak) |
| `PATCH /orders/:id` | customer | chỉ khi status posted |
| `POST /orders/:id/cancel` | customer | **chỉ** posted/matched/contacted → 409 `CANCEL_NOT_ALLOWED` từ accepted trở đi (plan4 §1) |
| `POST /orders/:id/accept` | driver | Atomic Accept: UPDATE WHERE driver_id IS NULL — 2 driver 1 winner |
| `POST /orders/:id/contact` | driver | mở khóa SĐT chủ hàng; đơn → contacted; 20/h |
| `POST /orders/:id/pickup|in-transit|delivered` | driver được gán | lifecycle, timestamps per transition |
| `POST /orders/:id/complete` | customer | delivered → completed |
| `GET /orders/:id/driver-location` | chủ đơn đã accept | chỉ khoảng cách làm tròn 0.1km — KHÔNG tọa độ |

## Local storage

Không cache — list/detail luôn fetch; sau mutation invalidate provider.

## Files

`feature/order/…` (form geocode có sync text↔tọa độ: sửa text → clear point,
chặn submit; detail có nút lifecycle đúng 1 cái/state + double-tap lock) ·
backend `routes/orders.ts`, `services/orders.ts`, `order_state_machine.ts`,
`lifecycle.ts`, `accept.ts`, `contacts.ts`, `gps.ts`.

## Trạng thái đơn

`posted → matched → contacted → accepted → pickup → in_transit → delivered →
completed` (+ `cancelled/expired/rejected` terminal, lazy expiry lúc đọc).

## Spec

`openspec/specs/order-marketplace/spec.md` · `order-lifecycle/spec.md` ·
`driver-engagement/spec.md`

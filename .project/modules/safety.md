# modules/safety.md — An toàn: report / block / admin

## Làm gì

User báo cáo (report) và chặn (block) user khác; admin duyệt report, suspend/ban.

## API endpoints

| Endpoint | Ghi chú |
|---|---|
| `POST /reports` | rate limit 10/h; reason enum; target phải có quan hệ (order liên quan / đã contact / đã block) |
| `POST /blocks` · `DELETE /blocks/:userId` | block 2 chiều enforce THẬT: chặn matching SQL (NOT EXISTS), contact, accept |
| `GET /admin/reports` · `POST /admin/reports/:id/resolve` | role admin (seed trực tiếp D1, không tự phong qua API) |
| `POST /admin/users/:id/suspend` · `/ban` | ban → token cũ chết ngay (role/status đọc DB mỗi request) |

Audit: mọi hành động quan trọng (accept, contact, report, block, consent, admin)
ghi `audit_logs` kèm IP `CF-Connecting-IP`.

## Local storage

Không.

## Files

`feature/safety/{data,domain,presentation}` (report screen; entry từ order detail) ·
backend `routes/safety.ts`, `routes/admin.ts`, `services/safety.ts`, `audit.ts`,
`migrations/0005_safety.sql`.

## Privacy (plan §18, bất biến)

- SĐT chủ hàng chỉ trả cho driver SAU khi contact thành công.
- GPS driver không bao giờ trả tọa độ — chỉ khoảng cách làm tròn.
- GPS chỉ tồn tại khi trip active; end → xóa KV.

## Spec

`openspec/specs/safety-moderation/spec.md`

# patterns.md — Pattern code đang dùng & lý do

> Cập nhật 2026-09-10.

## Danh sách pattern

| Pattern | Ở đâu | Lý do |
|---|---|---|
| **Repository Pattern** | `feature/*/data/*_repository.dart` | Tách Dio/parse khỏi controller; fake cho test cùng interface |
| **Riverpod 3 codegen (`@riverpod`)** | toàn bộ provider | Compile-safe, không provider thủ công; watch-in-build |
| **AsyncNotifier + AsyncValue** | per-id detail/list controllers | Chuẩn hóa Loading/Error/Refresh; `invalidate` sau mutation |
| **Feature-First** | `lib/feature/<name>/{data,domain,application,presentation}` | Feature tự trọn, xóa 1 feature không rách feature khác |
| **State Machine tập trung** | `worker/src/services/order_state_machine.ts` + `lifecycle.ts` RULES | Mọi transition qua 1 bảng RULES + UPDATE có điều kiện — không ad-hoc status write |
| **Conditional UPDATE (atomic)** | accept, cancel, rate limit D1 | D1 single-writer: `UPDATE … WHERE status IN (…) AND driver_id IS NULL` + check `meta.changes` = race-free, không cần transaction |
| **db.batch atomic** | match persistence, contact | DELETE cũ + INSERT mới trong 1 transaction; batch rỗng vẫn DELETE (không partial) |
| **Provider abstraction** | `worker/src/maps/provider.ts` (mock\|osrm) | E2E network-free; chỉ seam được phép (cùng `TokenStorage`) |
| **Env guard 2 chiều** | `env_guard.ts` (Worker fail-loud) + `assertReleaseConfig()` (Flutter fail-fast) | Không bao giờ chạy production với dev OTP/dev secret/localhost |
| **Role từ DB mỗi request** | `middleware/auth.ts` | Ban/đổi role có hiệu lực tức thì, không stale token |
| **Lazy expiry** | `effectiveOrder()` | Không cron; đơn quá `expires_at` hiện `expired` lúc đọc — 0đ |
| **KV cho hot data, D1 cho durable** | GPS, OTP, rate limit OTP/trip | D1 free 100k writes/ngày — không ghi realtime vào D1 |
| **Fake repositories trong test** | `mobile/test/helpers/` | Widget test không cần server; fake bắt "slow gate" để chứng minh double-tap lock |
| **E2E bash = bằng chứng** | `worker/scripts/*.sh` | "Done" = PASS in ra thật; server + test trong 1 bash -c (wrangler chết khi tool call kết thúc) |

## Chống-pattern (cấm)

- Abstraction "cho sau này" ngoài 2 seam đã sanctioned (MapsProvider, TokenStorage).
- Thêm dependency mà không hỏi (`operating_rules.md` §2).
- Background job/cron khi lazy làm được.
- Client-side trust: mọi check quyền phải ở Worker.

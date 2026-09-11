# ai-rules.md — Quy tắc AI khi làm việc với repo này

> Nguồn gốc: directive của user + `operating_rules.md` + `AGENTS.md`. File này
> tái tạo sau khi thư mục `.project/` bị mất trong đợt dọn disk (2026-09-10).

## 1. Nguồn sự thật (SSOT) — thứ tự ưu tiên

1. `.plan/*.md` — kế hoạch sản phẩm. Code trái plan → code sai, trừ khi user
   đã chốt deviation (ghi vào README "Quyết định kỹ thuật").
2. `openspec/specs/*.md` — mô tả hành vi ĐÃ IMPLEMENT (baseline). Sửa hành vi
   → phải update spec tương ứng trong cùng phiên.
3. README.md — trạng thái phase + quyết định kỹ thuật.
4. Memory files: `context.md` (snapshot), `working.md` (cách làm việc), 
   `AGENTS.md` (entry point), `operating_rules.md` (quy tắc bất biến).
5. `.project/` — knowledge base chi tiết (này): overview, architecture, modules.

## 2. Cập nhật sau mỗi phiên (protocol)

Cuối mỗi phiên có thay đổi code/docs, agent PHẢI:

1. Update `.project/` theo thay đổi (module liên quan + `openspec.md`).
2. Update `context.md` (snapshot trạng thái) + `working.md` (lệnh/trap mới).
3. Không tự sửa `.plan/*.md` — chỉ user mới được chốt plan.
4. Spec trái code → sửa spec; code trái plan → hỏi user.

## 3. Bằng chứng trước khi nói "xong" (user directive)

- "Done" = code diff + output test thật in ra trong phiên. Không nhận báo cáo suông.
- Không build/run Flutter local (disk-constrained): chỉ `flutter analyze` /
  `flutter test` / `dart run build_runner`. Backend `wrangler dev` + E2E bash
  scripts là chuẩn để tạo bằng chứng.
- Sau mỗi phase/task: liệt kê so với DoD checklist, HỎI trước khi sang phase mới.

## 4. Ràng buộc scope

- Ưu tiên: 0đ cost → matching quality → reliability → không over-engineer.
- Không thêm feature ngoài plan (P1 frozen tới khi pilot pass — phase 6 tooling
  là giới hạn hiện tại; Phase 7 = production hardening, Phase 8 = store).
- Không AI/ML, payment, chat realtime, WebSocket, background daemon.

## 5. Kiến trúc bất biến

- Backend: Hono routes `src/routes/`, logic `src/services/`, error envelope
  `{ error: { code, message, status } }`, migration D1 đánh số (next: 0009).
- Mobile: Feature-First `lib/feature/<name>/{data,domain,application,presentation}`,
  Riverpod 3 codegen (`@riverpod`, watch-in-build), GoRouter 16 (refresh chỉ khi
  landing đổi), token qua `TokenStorage` interface.
- Server-side authority: mọi check role/ownership/consent/block/rate-limit/
  state machine ở Worker; client check chỉ là UX.

## 6. Giao tiếp

- Ngôn ngữ làm việc: tiếng Việt (user viết tiếng Việt). Code/identifier giữ tiếng Anh.
- Trả lời ngắn, bảng cho checklist, luôn kèm lệnh chạy để user tự verify.

# Pilot Checklist — test tay end-to-end (Phase 6, phase6_pilot §6.2)

> Corridor: **Hà Nội → Hưng Yên → Hải Dương → Hải Phòng** (+ chiều về).
> Auth pilot = dev OTP (chưa production auth — Phase 7 mới làm).
> Chạy seed trước: `cd worker && npm run seed:pilot` (server tự start/stop).
> Ghi kết quả từng bước vào cột **Kết quả** — để trống nghĩa là chưa test.

## Chuẩn bị

- [ ] `npm run seed:pilot` chạy xong, in `Tài xế có ≥1 match: 4/4`
- [ ] Backend local chạy: `cd worker && npx wrangler dev --port 8787 --var MAPS_PROVIDER:mock`
- [ ] App chạy: `cd mobile && flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8787` (emulator)
      hoặc `http://<IP-lan>:8787` cho máy thật.

## Tài khoản seed (dev OTP hiện ngay trên màn hình login)

| Vai trò | SĐT | Ghi chú |
|---|---|---|
| Tài xế 1 | `0983500001` | truck 5 tấn |
| Tài xế 2 | `0983500002` | truck 8 tấn |
| Tài xế 3 | `0983500003` | van 1.5 tấn |
| Tài xế 4 | `0983500004` | pickup 1.2 tấn |
| Chủ hàng 1–8 | `0983600001` → `0983600008` | 8 đơn đã đăng sẵn |

## 11 bước test tay

| # | Bước | Kỳ vọng | Kết quả |
|---|------|---------|---------|
| 1 | Login **customer** (dev OTP) → tạo đơn trên tuyến (search địa chỉ geocode, ví dụ "Hà Nội" → "Hải Phòng", khung giờ hôm nay) | Đơn tạo thành công, hiện trong "Đơn của tôi" với chip Đang chờ | |
| 2 | Login **driver** (khác browser/device hoặc logout) → tạo trip Hà Nội → Hải Phòng → bấm **Quét radar** | Match card hiện đơn vừa tạo + đơn seed | |
| 3 | Xem match card | Có: score, **Khỏi tuyến (pickup_km)**, **Độ lệch (detour)**, khối lượng, giá, reasons tiếng Việt | |
| 4 | Bấm **Liên hệ** → bấm vào **số điện thoại** (hoặc nút **Gọi**) trong dialog | Hiện SĐT chủ hàng (không có SĐT trước khi contact); bấm số mở **app điện thoại** với đúng số đã phím sẵn | |
| 5 | Accept đơn; cho tài xế thứ 2 accept cùng đơn | Tài xế 1 thành công; tài xế 2 lỗi "Đơn đã được tài xế khác nhận" (atomic) | |
| 6 | Driver: **Đã lấy hàng → Bắt đầu giao → Đã giao hàng** | Mỗi bước đúng 1 nút, chip trạng thái đổi đúng, nút cũ biến mất | |
| 7 | Customer: **Xác nhận hoàn tất** | Đơn → Hoàn thành | |
| 8 | Customer tạo đơn khác, để driver accept xong thử **Hủy** | Bị chặn: "Không thể hủy đơn sau khi tài xế đã nhận" (cancel chỉ khi Đang chờ/Đã ghép/Đã liên hệ) | |
| 9 | GPS: bấm gửi vị trí khi trip **chưa start** → phải báo lỗi; **Start chuyến** → gửi vị trí OK (30s/lần); **Kết thúc** → dừng track | planned → TRIP_NOT_ACTIVE; active → OK; ended → không nhận nữa | |
| 10 | Tạo trip hướng không có hàng (ví dụ Thanh Hóa → Vinh) → quét radar | **Empty state** với 3 gợi ý: khai báo chiều về / về trang chủ / quét lại radar — bấm từng cái **không ra màn "Không tìm thấy trang"** | |
| 11 | Đang có đơn/truyền active, vào hồ sơ thử **đổi vai trò** | Bị chặn ROLE_LOCKED; sau khi hủy/kết thúc thì đổi được | |

## Sau khi xong 11 bước

```bash
cd worker && npx wrangler d1 execute appvantai --local --file scripts/pilot_metrics.sql
```

Ghi lại 4 bảng kết quả vào `result_pilot.txt` (funnel + phân bố score + reject
heuristics). Đối chiếu mục tiêu: **≥70% trip có ≥1 match; contact ≥30% match;
accept ≥50% contact; cancel sau accept = 0**.

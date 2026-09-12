# Hướng dẫn sử dụng App Vận Tải

> Version app: **1.0.0+1** · Cập nhật tài liệu: **12/09/2026** · Nền tảng: **Android**
> (iOS cùng mã nguồn nhưng chưa phát hành) · Backend: `https://appvantai-api.testhoangweb.workers.dev`

Tài liệu này viết cho **3 nhóm người dùng thật**: Chủ cửa hàng (đăng hàng), Tài xế
(chạy tuyến – bắt mối) và Admin (xử lý vi phạm). Mọi mô tả ở đây **khớp với app đang
chạy**, không bao gồm tính năng chưa làm (danh sách hạn chế ở §7).

**Mục lục**

1. [Tổng quan & quy tắc chung](#1-tổng-quan--quy-tắc-chung)
2. [Dùng chung: đăng nhập, hồ sơ, trạng thái đơn](#2-dùng-chung-đăng-nhập-hồ-sơ-trạng-thái-đơn)
3. [Dành cho CHỦ CỬA HÀNG](#3-dành-cho-chủ-cửa-hàng)
4. [Dành cho TÀI XẾ](#4-dành-cho-tài-xế)
5. [Dành cho ADMIN (quản trị)](#5-dành-cho-admin-quản-trị)
6. [Quảng cáo, dữ liệu & quyền riêng tư](#6-quảng-cáo-dữ-liệu--quyền-riêng-tư)
7. [Xử lý sự cố — tra theo đúng thông báo trên app](#7-xử-lý-sự-cố--tra-theo-đúng-thông-báo-trên-app)
8. [Hạn chế đã biết (P0)](#8-hạn-chế-đã-biết-p0)
9. [Phụ lục kỹ thuật](#9-phụ-lục-kỹ-thuật)

---

## 1. Tổng quan & quy tắc chung

**App Vận Tải** là nền tảng **trung gian kết nối thông tin**: người có hàng cần vận
chuyển (Chủ cửa hàng) và người có xe (Tài xế). App **không** vận chuyển, **không**
thu tiền hộ, **không** xử lý thanh toán, **không** chịu trách nhiệm hàng hóa.

**Giá trị cốt lõi — “Radar mối hàng tiện đường”:** tài xế khai tuyến đang chạy, hệ
thống quét các đơn hàng **nằm trên tuyến đó** và xếp hạng theo mức độ tiện đường
(ít lệch tuyến, đúng tải trọng/loại xe, kịp giờ lấy hàng).

### Quy tắc chung phải nhớ

| Quy tắc | Chi tiết |
|---|---|
| **1 tài khoản = 1 vai trò** | Chọn **1 lần duy nhất** ở lần đăng nhập đầu (`Hoàn tất hồ sơ`). **App chưa có màn đổi vai trò** — muốn đổi phải nhờ quản trị (§5.4), và điều kiện là **không còn đơn/chuyến đang hoạt động** (nếu còn, hệ thống trả *“Không thể đổi vai trò khi đang có đơn/chuyến đang hoạt động”*). |
| **Tick điều khoản 1 lần** | Bắt buộc ở bước hoàn tất hồ sơ và ở form đăng đơn. App chỉ là trung gian — mọi giao dịch hai bên tự thỏa thuận. |
| **Tài xế phải khai xe** | Chưa khai xe thì app giữ ở màn `Thông tin xe`, không vào được Radar. |
| **Số điện thoại chỉ lộ khi bấm “Liên hệ”** | Không ai xem được số của đối tác trước đó. |
| **Không dùng GPS để bắt mối** | Radar chạy trên **tuyến tài xế khai**, không cần GPS. GPS chỉ dùng khi tài xế bấm **Bắt đầu chuyến** (§4.5). |
| **Đơn hết hạn theo khung giờ lấy hàng** | Đơn tự chuyển `Hết hạn` khi quá “Đến” của khung giờ lấy hàng. |

---

## 2. Dùng chung: đăng nhập, hồ sơ, trạng thái đơn

### 2.1 Đăng nhập

1. Mở app → màn **đăng nhập**: nhập **số điện thoại** (dạng `0912345678` hoặc `+84912345678` đều được).
2. Bấm **`Gửi mã OTP`** → app chuyển sang màn **`Xác thực OTP`**.
3. Nhập **6 chữ số** nhận qua SMS (không nhận được thì bấm **`Gửi lại mã`**).
4. Bấm **`Xác nhận`**.

> **Số điện thoại test (khi chưa dùng SMS thật):** dùng đúng cặp *số test + OTP test* đã
> khai trong Firebase Console → nhập OTP đó là vào được, **không tính phí SMS**.

**Lần đầu đăng nhập — màn `Hoàn tất hồ sơ`:**
- Nhập **Họ và tên** (2–100 ký tự).
- Chọn vai trò: **`Chủ hàng`** hoặc **`Tài xế`**.
- Tick ô xác nhận điều khoản → bấm **`Tiếp tục`**.
- Chọn **Tài xế** → app tự chuyển sang màn khai xe (bắt buộc).
- Chọn **Chủ hàng** → vào thẳng trang chủ.

### 2.2 Khai / sửa thông tin xe (chỉ Tài xế)

| Trường | Ghi chú |
|---|---|
| `Loại xe` | Xe van · Xe bán tải · Xe tải · Xe container |
| `Biển số xe` | 4–12 ký tự, ví dụ `29C-123.45` |
| `Tải trọng (kg)` | Bắt buộc > 0 — hệ thống dùng để lọc đơn quá nặng |
| `Dài` / `Rộng` / `Cao (cm)` | Không bắt buộc, dùng để đối chiếu kích thước hàng |
| `Khu vực hoạt động` | Tự do, ví dụ `Hà Nội – Hải Phòng` |

Bấm **`Hoàn tất`** (lần đầu) hoặc **`Lưu thay đổi`** (khi sửa từ `Hồ sơ`).

> **Khai tải trọng thật quan trọng:** khai thấp hơn thực tế → radar sẽ bỏ qua các đơn
> nặng mà xe bạn chở được; khai cao hơn thực tế → bạn thấy đơn không chở được.

### 2.3 Hồ sơ (`Hồ sơ của tôi`)

Vào bằng icon **người** ở góc phải trang chủ. Trong hồ sơ có:
- **Tên + số điện thoại** (bút chì ✏️ để sửa tên).
- **Vai trò** hiển thị đúng: `Chủ hàng` / `Tài xế` / `Quản trị`.
- **Phiên bản** app (dùng khi cần báo lỗi).
- **`Điều khoản sử dụng`** và **`Chính sách riêng tư`** (đọc được cả khi chưa đăng nhập).
- Tài xế: khối **Thông tin xe** + nút **`Cập nhật thông tin xe`**.
- **Đăng xuất**: icon ở góc phải trang chủ.

### 2.4 Ý nghĩa 11 trạng thái đơn

| Trạng thái trên app | Nghĩa | Ai làm gì tiếp |
|---|---|---|
| `Đang chờ` | Đơn vừa đăng, chưa ai liên hệ | Tài xế có thể liên hệ/ nhận; chủ hàng hủy được |
| `Đã ghép` | Hệ thống đã ghép vào radar của tài xế | như trên |
| `Đã liên hệ` | Tài xế đã bấm “Liên hệ” (số đã lộ) | chủ hàng hủy được |
| `Đã nhận` | Tài xế đã nhận chuyến | chủ hàng **không hủy được nữa** |
| `Đang lấy hàng` | Tài xế đã đến lấy hàng | |
| `Đang vận chuyển` | Hàng đang trên đường | |
| `Đã giao` | Tài xế báo đã giao | **Chủ hàng bấm `Xác nhận hoàn tất`** |
| `Hoàn thành` | Xong | — (không còn nút nào) |
| `Đã hủy` | Chủ hàng đã hủy (trước khi tài xế nhận) | — |
| `Hết hạn` | Quá khung giờ lấy hàng mà chưa có tài xế | Đăng đơn mới |
| `Từ chối` | Trạng thái dự phòng | — |

---

## 3. Dành cho CHỦ CỬA HÀNG

### 3.1 Đăng đơn hàng (5 phút)

1. Trang chủ → bấm **`Đơn hàng của tôi`** → nút **`Tạo đơn`** (hoặc nút **`Tạo đơn`** ở màn danh sách trống).
2. **Điểm lấy hàng:** gõ địa chỉ (≥ 3 ký tự) → bấm **icon kính lúp 🔍** → app hiện dòng xác nhận địa chỉ đã chọn.
   ▸ Làm tương tự cho **Điểm giao hàng**.
   ▸ **Sau khi đã chọn điểm mà bạn sửa lại chữ trong ô địa chỉ, điểm đó bị hủy** — phải bấm tìm lại (tránh “địa chỉ A + toạ độ B”).
3. **Hàng hóa:** `Loại hàng` (Hàng thường / Thực phẩm / Hàng dễ vỡ / Nội thất / Điện tử / Vật liệu xây dựng / Khác), `Khối lượng (kg)` (số nguyên > 0), kích thước `Dài/Rộng/Cao (cm)` nếu cần, `Yêu cầu xe` (Xe bất kỳ / van / bán tải / tải / container).
4. **Thời gian & giá:** bấm 2 nút **`Từ:`** và **`Đến:`** để chọn **khung giờ lấy hàng**; nhập `Giá (đ)` (ví dụ `2500000`), `Ghi chú` (tối đa 500 ký tự).
5. Tick ô xác nhận điều khoản → bấm **`Đăng đơn hàng`**.

> ⚠️ **Khung giờ lấy hàng = thời hạn sống của đơn.** Quá mốc `Đến:` mà chưa có tài xế
> nhận, đơn tự chuyển `Hết hạn` và biến khỏi radar. Muốn giữ đơn lâu hơn → chọn `Đến:`
> xa hơn (hệ thống cho tối đa 1 năm).

**Giới hạn cần biết**

| Giới hạn | Con số | Thông báo khi vượt |
|---|---|---|
| Đơn đang hoạt động cùng lúc | **5** | *“Bạn đang có 5 đơn hàng đang hoạt động, vui lòng hủy hoặc chờ hoàn thành trước khi tạo mới”* |
| Tốc độ tạo đơn | **10 đơn/giờ** | *“Bạn đã tạo quá nhiều đơn hàng trong thời gian ngắn, vui lòng thử lại sau”* |

### 3.2 Theo dõi đơn

- **`Đơn hàng của tôi`** = danh sách đơn của bạn; kéo xuống để làm mới. Chạm vào đơn để mở chi tiết.
- Chi tiết đơn hiển thị: trạng thái, giá, điểm lấy/giao, hàng hóa, yêu cầu xe, khung giờ, ghi chú.

### 3.3 Biết tài xế đang tới đâu?

Khi tài xế đã nhận (`Đã nhận`) **và** đã bật GPS cho chuyến, chi tiết đơn hiện dòng:

> *“Tài xế đang cách điểm lấy khoảng 2.3 km”* — kèm ghi chú *“Vị trí ẩn danh — bảo mật theo chính sách”*.

Bạn **không bao giờ** thấy toạ độ GPS của tài xế. Nếu tài xế chưa bật GPS, app ghi
*“Tài xế chưa bật định vị”*. Không thấy vị trí? Bấm icon **làm mới ↻** trên dòng đó.

### 3.4 Hủy đơn — khi nào được?

Được hủy khi đơn còn ở: `Đang chờ`, `Đã ghép`, `Đã liên hệ`.
Cách làm: mở chi tiết đơn → **`Hủy đơn hàng`** → xác nhận **`Hủy đơn`**.

Từ `Đã nhận` trở đi, nút hủy **không còn hiện**; nếu cố hủy qua hệ thống, server trả:
*“Không thể hủy đơn sau khi tài xế đã nhận. Hãy liên hệ hoặc báo cáo sự cố.”* →
khi đó hãy **gọi tài xế** (số đã lộ khi họ bấm “Liên hệ”) để thống nhất.

### 3.5 Kết thúc đơn

Khi tài xế báo **`Đã giao hàng`** (đơn hiện `Đã giao`), mở chi tiết đơn và bấm
**`Xác nhận hoàn tất`** → đơn chuyển `Hoàn thành`. **Chỉ chủ hàng bấm được bước này.**

### 3.6 Báo cáo / Chặn tài xế

Đơn đã có tài xế → trong chi tiết đơn có nút **`Báo cáo / Chặn tài xế`**:
- **Báo cáo tài xế** → chọn lý do (Spam / Thông tin giả / Quấy rối / Lừa đảo / Khác) → admin xem xét.
- **Chặn tài xế** → hai bên không còn thấy nhau trên app.

Giới hạn: **10 báo cáo/giờ** (*“Bạn đã báo cáo quá nhiều trong thời gian ngắn…”*).

### 3.7 Checklist nhanh cho chủ cửa hàng

- [ ] Đã ghi tên thật + tick điều khoản (lần đầu)
- [ ] Đã chọn **đúng khung giờ lấy hàng** (đơn không sống quá mốc này)
- [ ] Đã bấm 🔍 để xác nhận **cả 2 điểm** trước khi đăng
- [ ] Giá + khối lượng đã nhập đúng (tài xế quyết định nhận dựa vào 2 số này)
- [ ] Theo dõi danh sách đơn; tài xế nhận → chuẩn bị hàng; tài xế báo “Đã giao” → **Xác nhận hoàn tất**

---

## 4. Dành cho TÀI XẾ

### 4.1 Tạo chuyến (bắt đầu ca chạy)

1. Trang chủ → nút **`Tôi đang chạy — quét radar`** → màn **`Tạo chuyến đi`**.
2. Chọn chiều chuyến: **`Đi 1 chiều`** hoặc **`Có chiều về`** (chọn “Có chiều về” nếu bạn
   sẽ chạy xe rỗng về — hệ thống ưu tiên tìm hàng cho cả chặng về).
3. **Điểm đi:** gõ địa chỉ → bấm **🔍** → chọn điểm. Làm tương tự **Điểm đến**.
   ▸ Sửa chữ sau khi đã chọn → phải tìm lại (giống bên đơn hàng).
4. Bấm **`Tạo chuyến & quét radar`** → vào thẳng màn radar.

> **Tuyến phải thật:** radar chỉ quét đơn trong hành lang ±10 km quanh tuyến bạn khai.
> Khai tuyến “cho rộng” (ví dụ Hà Nội → Cà Mau khi thực tế chỉ chạy Hà Nội → Hải Phòng)
> sẽ làm điểm tiện đường sai và bạn nhận đơn không chạy nổi.

### 4.2 Đọc màn Radar (`Mối hàng tiện đường`)

Mỗi thẻ mối hàng hiển thị:

| Thành phần | Ý nghĩa |
|---|---|
| **Vòng tròn số (điểm)** | Điểm tiện đường 0–100. **≥ 85 xanh** (rất tiện), **≥ 70 cam** (tiện), còn lại xám (cân nhắc). |
| `Khỏi tuyến` | Điểm lấy hàng cách tuyến bao nhiêu km (nhỏ = đỡ phải vòng). |
| `Độ lệch` | Chênh lệch tổng quãng đường khi ghé đơn này (âm = tuyến gần như không đổi hoặc ngắn hơn). Hiện `—` nếu hệ thống không tính được. |
| `Khối lượng` | Khối lượng hàng so với tải trọng xe bạn đã khai. |
| **Danh sách lý do ✅** | Vì sao hệ thống coi đây là mối tốt (cùng hướng, đủ tải, kịp giờ…). |
| `Liên hệ chủ hàng` / `Nhận chuyến` | 2 hành động chính. |
| `Xem chi tiết đơn hàng` | Xem đầy đủ điểm lấy/giao, giờ, ghi chú. |

**Vì sao có đơn không xuất hiện?** Hệ thống tự loại các đơn:
- Nằm ngoài hành lang tuyến, hoặc đi **ngược hướng** quá 135°;
- **Quá tải trọng**/ sai **loại xe** yêu cầu;
- **Không kịp giờ lấy hàng** (thời gian di chuyển tới điểm lấy + biên 30 phút);
- Làm tuyến bạn lệch quá **15 km**;
- Đã **hết hạn**, đã có tài xế khác nhận, hoặc đang bị chặn hai chiều.

Radar chỉ hiện **top 5 mối tốt nhất** — danh sách ngắn là bình thường, không phải lỗi.

### 4.3 Liên hệ chủ hàng

Bấm **`Liên hệ chủ hàng`** → hộp thoại hiện **tên + số điện thoại** chủ hàng:

- **Bấm vào chính số điện thoại** (hoặc nút **`Gọi`**) → app mở **trình gọi điện** với số đã phím sẵn → bạn chỉ cần bấm nút gọi của điện thoại.
- Số vẫn **bôi đen/ copy** được nếu muốn nhắn tin.
- Nút trên thẻ đổi thành `Đã liên hệ (09xx…)` → bấm lại **mở thẳng hộp thoại**, không gọi lại API.

Giới hạn: **20 lần liên hệ/giờ** (*“Bạn đã liên hệ quá nhiều trong thời gian ngắn…”*).

### 4.4 Nhận chuyến (2 tài xế cùng bấm thì sao?)

Bấm **`Nhận chuyến`**. Hệ thống dùng khóa nguyên tử — **chỉ 1 tài xế thắng**, người
còn lại nhận *“Đơn đã được tài xế khác nhận”*. Nhận xong, thẻ hiện `Đã nhận`.

> Nếu bạn đã nhận đơn này trước đó, bấm lại **không lỗi** (idempotent) — an toàn khi mạng chập chờn.

### 4.5 Chạy chuyến & GPS

Mở chuyến đang chạy: trên màn radar bấm **icon ▶ (`Bắt đầu chuyến (GPS)`)** ở góc phải trên → màn **`Chuyến của tôi`**.

| Bước | Việc app làm |
|---|---|
| Bấm **`Bắt đầu chuyến`** | Xin quyền vị trí → báo server chuyến `active` → gửi vị trí **ngay** rồi **mỗi 30 giây**. |
| Chip trên màn hình | `Đang chạy — GPS bật (30s/lần)` hoặc `Chưa bắt đầu — GPS tắt`. |
| Bấm **`Kết thúc chuyến`** | Dừng gửi vị trí, báo server chuyến `ended`, xoá vị trí đã lưu, quay về trang chủ. |

**Để GPS làm việc đúng:**
- Phải **giữ app mở ở màn `Chuyến của tôi`** trong lúc chạy — GPS **không chạy nền**
  (app không xin quyền định vị nền). Máy khoá màn hình thì việc gửi có thể dừng lại.
- Nếu bạn **từ chối quyền vị trí**, app báo *“Cần quyền truy cập vị trí để chạy chuyến”*
  và **chuyến không bắt đầu** (mọi thứ khác vẫn dùng bình thường).
- Nếu chuyến đã `active` trên server mà máy thiếu quyền, app hiện băng đỏ
  *“Chuyến đang chạy nhưng thiếu quyền vị trí — cấp quyền để GPS tiếp tục”*.
- Nếu server không nhận được lệnh kết thúc (mất mạng), app **vẫn ở lại màn hình** và hiện
  *“Chuyến chưa được kết thúc trên máy chủ — bấm ‘Kết thúc chuyến’ để thử lại”*. Bấm lại
  khi có mạng.

**GPS dùng để làm gì?** Chỉ để chủ hàng thấy **“tài xế cách ~X km”** (khoảng cách ẩn
danh, không lộ toạ độ) → tăng tin cậy khi chờ lấy hàng. GPS **không** dùng để tìm mối.

### 4.6 Cập nhật tiến độ giao hàng

Mở **chi tiết đơn hàng** (từ thẻ mối hàng → `Xem chi tiết đơn hàng`). Mỗi lúc **chỉ có
đúng 1 nút** đúng với trạng thái:

`Đã nhận` → bấm **`Đã lấy hàng`** → `Đang lấy hàng` → **`Bắt đầu giao`** → `Đang vận chuyển`
→ **`Đã giao hàng`** → `Đã giao`. Sau đó **chủ hàng** bấm `Xác nhận hoàn tất` → `Hoàn thành`.

Nút có chống bấm liên tục (đang gửi thì nút mờ + xoay) — cứ bấm 1 lần rồi chờ.

### 4.7 Khi radar không có mối nào

Màn hình gợi ý 3 hành động (bấm được):
- **`Khai báo chiều về`** → tạo chuyến ngược chiều để bắt hàng chiều về.
- **`Về trang chủ`** → tạm nghỉ, quay lại sau.
- **`Quét lại radar`** → đơn mới có thể vừa được đăng.

### 4.8 ⚠️ Quy tắc sống còn khi chạy chuyến

> **Đừng tắt/ đóng app khi chuyến đang `Đang chạy`.** Hiện app **chưa có màn “chuyến
> của tôi”** để vào lại chuyến cũ, nên sau khi đóng app bạn sẽ **không còn đường quay
> lại màn chạy chuyến** (GPS dừng, và không tự bấm “Kết thúc chuyến” được). Xem §8 để
> biết cách xử lý nếu lỡ gặp.

### 4.9 Checklist nhanh cho tài xế

- [ ] Đã khai **loại xe + tải trọng thật**
- [ ] Mỗi ca: tạo chuyến **đúng tuyến thật**, chọn **chiều về** nếu có
- [ ] Đọc **danh sách lý do ✅** trên thẻ trước khi nhận (không chỉ nhìn giá)
- [ ] Bấm **Liên hệ** → gọi chủ hàng để chốt trước khi tới
- [ ] Nhận xong: cập nhật **Đã lấy hàng → Bắt đầu giao → Đã giao hàng**
- [ ] Bấm **Kết thúc chuyến** ở cuối ca (đừng chỉ thoát app)

---

## 5. Dành cho ADMIN (quản trị)

### 5.1 Trạng thái hiện tại — đọc kỹ trước

**App chưa có màn quản trị.** Đăng nhập bằng tài khoản `admin` sẽ thấy chip
**`Quản trị`** và một thẻ thông báo: *“Màn quản trị trong app chưa có ở giai đoạn này
— báo cáo vi phạm được xử lý qua công cụ quản trị (xem README §Admin).”*

Tài khoản admin **không** có màn “Đơn hàng của tôi” (danh sách đơn là của chủ hàng).
Admin **vẫn mở được chi tiết một đơn** nếu có link/ID (ví dụ để kiểm tra nội dung báo cáo).

Trong giai đoạn pilot, **xử lý vi phạm bằng 1 trong 2 cách dưới đây**.

### 5.2 Cách A — SQL trực tiếp (khuyến nghị cho pilot)

```bash
cd worker

# 1) Danh sách báo cáo đang mở (mới nhất trước)
npx wrangler d1 execute appvantai --remote --command \
 "SELECT id, reporter_id, target_user_id, order_id, reason, description, created_at \
  FROM reports WHERE status='open' ORDER BY created_at DESC LIMIT 100"

# 2) Tra ai là ai (đọc số điện thoại thay vì UUID)
npx wrangler d1 execute appvantai --remote --command \
 "SELECT id, phone, name, role, status FROM users \
  WHERE id IN ('<reporter_id>','<target_user_id>')"

# 3) Đóng báo cáo sau khi xử lý
npx wrangler d1 execute appvantai --remote --command \
 "UPDATE reports SET status='resolved' WHERE id='<report_id>'"

# 4) Treo tài khoản (tạm thời) hoặc cấm (vĩnh viễn)
npx wrangler d1 execute appvantai --remote --command \
 "UPDATE users SET status='suspended', updated_at=strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE id='<user_id>'"
#   → hoặc status='banned'
```

**Lý do báo cáo (`reason`)**: `spam` (Spam) · `fake_info` (Thông tin giả) ·
`harassment` (Quấy rối) · `fraud` (Lừa đảo) · `other` (Khác).

> ⚠️ **Cách A không ghi audit trail.** Nếu bạn cần bằng chứng xử lý, dùng Cách B (API)
> hoặc tự ghi lại (ngày/giờ, ai báo, ai bị xử lý, căn cứ).

### 5.3 Cách B — API admin (có ghi audit log)

Yêu cầu: một **JWT của tài khoản admin**. Lấy token bằng cách đăng nhập app rồi trích
`Authorization: Bearer <token>` (xem Phụ lục §9.3). Sau đó:

```bash
BASE="https://appvantai-api.testhoangweb.workers.dev"
T="<JWT_của_admin>"

curl -s "$BASE/admin/reports?status=open" -H "Authorization: Bearer $T"
curl -s -X POST "$BASE/admin/reports/<report_id>/resolve" -H "Authorization: Bearer $T"
curl -s -X POST "$BASE/admin/users/<user_id>/suspend"      -H "Authorization: Bearer $T"
curl -s -X POST "$BASE/admin/users/<user_id>/ban"          -H "Authorization: Bearer $T"
```

Mọi lệnh qua API đều ghi vào `audit_logs` (ai làm, lúc nào, IP). Người không phải
`admin` gọi sẽ nhận `403 FORBIDDEN`.

### 5.3b Hiệu lực của `suspend` / `banned`

Mọi request của người bị `suspended`/`banned` đều bị từ chối ngay ở tầng xác thực:
`401 – “Người dùng không tồn tại hoặc đã bị khoá”`. App nhận 401 → xoá phiên → đẩy về
màn đăng nhập; đăng nhập lại cũng chỉ về màn đăng nhập (không tải được dữ liệu).

👉 **Kết quả thực tế: tài khoản bị vô hiệu**, dù SMS OTP vẫn gửi được. Đây là cách duy
nhất "khoá" tài khoản ở giai đoạn pilot (chưa có màn quản trị trong app). Người bị khoá
muốn khiếu nại thì liên hệ kênh hỗ trợ; admin mở lại bằng
`UPDATE users SET status='active' …`.

### 5.4 Cấp/ thu hồi quyền admin

```bash
cd worker
# Cấp admin cho 1 số điện thoại đã từng đăng nhập
npx wrangler d1 execute appvantai --remote --command \
 "UPDATE users SET role='admin' WHERE phone='0363930250'"
# Thu hồi về chủ hàng
npx wrangler d1 execute appvantai --remote --command \
 "UPDATE users SET role='customer' WHERE phone='0363930250'"
```

> **Không thể tự phong admin qua app/API** (đúng thiết kế — `PATCH /me` chỉ nhận
> `driver|customer`). Sau khi đổi role bằng SQL, người đó cần **đăng xuất/ đăng nhập lại**
> để app nhận vai trò mới.

### 5.5 Theo dõi sức khỏe pilot

```bash
cd worker
npm run pilot:metrics     # funnel: matches → contacts → accepts → completed/cancelled + phân bố score
```

Chỉ số cần nhìn: **≥ 70% chuyến có ≥ 1 mối**, **≥ 30% mối được liên hệ**,
**≥ 50% liên hệ được nhận**, **hủy sau khi nhận = 0**. (Chi tiết: `docs/pilot_checklist.md`.)

### 5.6 Cứu chuyến bị “kẹt” đang chạy

Nếu tài xế lỡ thoát app khi chuyến `active` (xem §4.8), chuyến sẽ nằm `active` mãi và
**chặn tài xế đổi vai trò**. Cách xử lý:

```bash
cd worker
# 1) Xem chuyến đang treo
npx wrangler d1 execute appvantai --remote --command \
 "SELECT t.id, t.status, t.created_at, u.phone FROM trips t JOIN users u ON u.id=t.driver_id \
  WHERE t.status IN ('active','planned') ORDER BY t.created_at DESC"

# 2) Xác nhận KHÔNG còn phiên chạy thật (tài xế đã tắt app) rồi mới đóng
npx wrangler d1 execute appvantai --remote --command \
 "UPDATE trips SET status='ended', ended_at=strftime('%Y-%m-%dT%H:%M:%fZ','now'), \
  updated_at=strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE id='<trip_id>'"
```

> Không xoá dữ liệu đơn/ chuyến đang có giao dịch thật — chỉ **đóng** chuyến treo.

---

## 6. Quảng cáo, dữ liệu & quyền riêng tư

**Quảng cáo (AdMob):** app có 3 vị trí — **banner** ở đáy trang chủ, **quảng cáo xen kẽ**
hiện sau khi **đăng đơn thành công**, và **quảng cáo khi mở app**. Quảng cáo **không bao
giờ chặn** thao tác chính (lỗi quảng cáo không làm app kẹt). Khi đang thử nghiệm, app
dùng quảng cáo **test** của Google; muốn thấy quảng cáo thật phải phát hành bản production.

**Dữ liệu app thu thập:**

| Dữ liệu | Khi nào |
|---|---|
| Số điện thoại, họ tên, vai trò | Khi đăng ký/ đăng nhập |
| Thông tin xe (tài xế) | Khi khai xe/ sửa xe |
| Đơn hàng/ chuyến (điểm đi–đến, loại hàng, khối lượng, giờ, giá) | Khi đăng/ tạo |
| **Vị trí GPS** | **Chỉ khi tài xế đang chạy chuyến** (bật/ tắt ở màn `Chuyến của tôi`); lưu tối đa ~2 giờ, xoá khi kết thúc chuyến |

**Không thu thập:** danh bạ, tin nhắn, ảnh; **không** theo dõi khi không có chuyến;
**không** xử lý thanh toán. **Không bán dữ liệu.**

**Số điện thoại** chỉ hiện cho đối tác **sau khi một bên bấm “Liên hệ”** cho đúng đơn đó.
**Vị trí** chỉ hiện dưới dạng **khoảng cách ước lượng**, không hiện toạ độ.

---

## 7. Xử lý sự cố — tra theo đúng thông báo trên app

| Thông báo bạn thấy | Nguyên nhân | Cách xử lý |
|---|---|---|
| *“Chưa gửi mã xác minh, vui lòng thử lại”* | Firebase từ chối gửi SMS (chưa đăng ký vân tay keystore, hoặc chưa cho phép khu vực Việt Nam) | Đã có thông báo cụ thể hơn ở các bản sau; nếu vẫn gặp: kiểm tra Firebase → `Authentication` → `Sign-in method` → Phone; **`Settings` → `User actions` → `SMS region allowlist` cho phép Vietnam (+84)**; và đã thêm SHA-1/SHA-256 của keystore vào app Android |
| *“Phone Auth chưa được bật trên Firebase console…”* | Firebase trả `operation-not-allowed` — thường là **chưa allowlist khu vực SMS**, không phải chưa bật Phone | Như trên (bật allowlist Vietnam) |
| *“Số điện thoại không hợp lệ”* | Nhập thiếu số | Nhập 10 số `09xxxxxxxx` hoặc `+849xxxxxxxx` |
| *“Vui lòng nhập đủ 6 chữ số”* | OTP nhập thiếu | Nhập đúng 6 số |
| *“Không thể kết nối máy chủ, vui lòng kiểm tra mạng”* | Mất mạng/ server không tới | Kiểm tra 3G/ WiFi rồi thử lại |
| *“Nhập địa chỉ ít nhất 3 ký tự”* | Từ khoá tìm quá ngắn | Gõ rõ hơn, ví dụ `KCN Thăng Long, Hà Nội` |
| *“Không tìm thấy địa chỉ, vui lòng thử từ khóa khác”* | Dịch vụ geocode không nhận ra địa chỉ | Ghi kèm tỉnh/ thành phố; tránh viết tắt lạ |
| *“Vui lòng tìm và chọn điểm lấy + điểm giao (địa chỉ vừa sửa cần tìm lại)”* | Đã chọn điểm rồi sửa lại chữ trong ô địa chỉ | Bấm **🔍** để tìm lại cho **cả 2 điểm** rồi mới đăng/ tạo |
| *“Khối lượng phải là số nguyên > 0”* / *“Giá không hợp lệ”* | Để trống hoặc nhập chữ | Nhập số, ví dụ `800` và `2500000` |
| *“Vui lòng tick xác nhận điều khoản để đăng hàng”* | Chưa tick ô xác nhận cuối form | Tick rồi bấm `Đăng đơn hàng` |
| *“Bạn đang có 5 đơn hàng đang hoạt động…”* | Vượt giới hạn 5 đơn hoạt động | Hủy bớt hoặc chờ đơn cũ `Hoàn thành`/`Hết hạn` |
| *“Bạn đã tạo quá nhiều đơn hàng trong thời gian ngắn…”* | Vượt 10 đơn/giờ | Chờ bớt rồi đăng lại |
| *“Bạn đã liên hệ quá nhiều trong thời gian ngắn…”* | Tài xế vượt 20 lần liên hệ/giờ | Chờ bớt |
| *“Đơn đã được tài xế khác nhận”* | 2 tài xế cùng nhận, hệ thống chỉ cho 1 người | Quét lại radar tìm mối khác |
| *“Không thể hủy đơn sau khi tài xế đã nhận…”* | Đơn đã `Đã nhận` | Gọi tài xế thống nhất; nếu cần thì `Báo cáo / Chặn tài xế` |
| *“Không thể đổi vai trò khi đang có đơn/chuyến đang hoạt động”* | (Chỉ gặp khi quản trị/hệ thống đổi vai trò) còn đơn `Đang chờ`/`Đã nhận`… hoặc chuyến `đang chạy` | Kết thúc/ hủy cho xong rồi đổi — hoặc nhờ admin đóng chuyến treo (§5.6) |
| *“Cần quyền truy cập vị trí để chạy chuyến”* | Từ chối quyền định vị | Cài đặt Android → App Vận Tải → Quyền → **Vị trí: Cho phép khi đang dùng app** |
| Băng đỏ *“Chuyến đang chạy nhưng thiếu quyền vị trí…”* | Chuyến đã `active` nhưng máy thiếu quyền | Cấp quyền rồi mở lại màn `Chuyến của tôi` |
| *“Chưa sync được với máy chủ — GPS đã tắt, vui lòng thử lại”* | Mất mạng lúc bấm kết thúc chuyến | Có mạng lại rồi bấm **`Kết thúc chuyến`** lần nữa |
| *“Chuyến chưa được kết thúc trên máy chủ…”* | Như trên (băng đỏ trên màn) | Bấm lại **`Kết thúc chuyến`** khi có mạng |
| *“Đường dẫn này không còn tồn tại hoặc đã được thay đổi.”* | Mở link cũ/ sai | Bấm **`Về trang chủ`** |
| Không thấy quảng cáo | Đang dùng quảng cáo test, hoặc tài khoản AdMob chưa được duyệt | Bình thường khi thử nghiệm; không ảnh hưởng chức năng |
| Radar trắng, không có mối | Không có đơn nào khớp tuyến/ tải trọng/ giờ | Dùng 3 gợi ý ở §4.7, hoặc đợi đơn mới |
| App treo ở màn xoay tròn | Mạng chậm khi tải dữ liệu | Chờ vài giây; nếu kẹt, thoát và mở lại (trừ khi đang chạy chuyến — xem §4.8) |

---

## 8. Hạn chế đã biết (P0)

| # | Hạn chế | Ảnh hưởng | Cách xử lý tạm |
|---|---|---|---|
| 1 | **Không có màn “chuyến của tôi”** — thoát app khi đang chạy chuyến thì **không vào lại được** màn chạy chuyến (không có nút vào) | GPS dừng; không bấm được `Kết thúc chuyến`; chuyến treo `active`; tài xế bị chặn đổi vai trò | Nhắc tài xế **không thoát app** trong ca chạy; nếu lỡ: admin đóng chuyến treo bằng SQL (§5.6) |
| 2 | **Không có màn sửa đơn** | Đăng sai giá/ khối lượng/ giờ thì không sửa tại chỗ | Hủy đơn (khi còn `Đang chờ`) rồi đăng lại |
| 3 | **Chưa có màn quản trị admin trong app** | Admin xử lý báo cáo qua SQL/ API | §5.2 / §5.3 |
| 4 | **Không có chat/ thông báo đẩy** | Hai bên liên hệ bằng **gọi điện** | Bấm số trong hộp thoại `Liên hệ chủ hàng` |
| 5 | **Không có thanh toán trong app** (đúng thiết kế) | Giá chỉ là thông tin tham khảo; hai bên tự thỏa thuận | Thỏa thuận ngoài app |
| 6 | **Chưa phát hành iOS** | Chỉ có bản Android | — |
| 7 | **Radar giới hạn top 5** | Không xem được danh sách dài | Quét lại sau, hoặc tạo chuyến khác |
| 8 | **Chưa có tìm kiếm/ lọc đơn cho chủ hàng** | Chỉ xem được đơn của mình | — |

> **Ưu tiên sửa tiếp:** #1 là hạn chế ảnh hưởng vận hành nhiều nhất (đã gây 2 chuyến
> treo trong đợt thử nghiệm 11–12/09).

---

## 9. Phụ lục kỹ thuật

### 9.1 Địa chỉ hệ thống

| Thành phần | Giá trị |
|---|---|
| Backend production | `https://appvantai-api.testhoangweb.workers.dev` |
| Cloudflare Workers + D1 + KV | worker `appvantai-api` (tài khoản Cloudflare của chủ dự án — đăng nhập bằng `npx wrangler login`) |
| Kho mã nguồn | `github.com/hoangsoft90/appvantai_1` (nhánh `master`, **public** — đừng đưa token/ mã khoá vào tài liệu) |
| APK test | GitHub → **Actions** → run mới nhất → **Artifacts** → `appvantai-debug-apk` |

### 9.2 Bản APK test trỏ vào đâu?

Bản debug trên CI được build sẵn với `API_BASE_URL` = **server production**, nên cài là
dùng được ngay (không cần cấu hình). Đăng nhập bằng số thật (Firebase SMS) hoặc số test.

### 9.3 Cách lấy JWT của tài khoản (chỉ khi cần dùng API admin)

App **không** hiển thị token cho người dùng (đúng thiết kế bảo mật), nên trong pilot
**hãy dùng Cách A — SQL (§5.2)** cho mọi việc xử lý vi phạm; nó không cần token.

Chỉ khi thật cần audit trail qua API (§5.3) mới cần JWT, và lúc đó cần kỹ thuật hỗ trợ
lấy token từ một phiên đăng nhập thật trên production (JWT được ký bằng `JWT_SECRET`
của Worker — token ở môi trường local **không** dùng được cho production).

### 9.4 Giới hạn & tham số hệ thống (tham chiếu nhanh)

| Tham số | Giá trị |
|---|---|
| OTP: hiệu lực / số lần gửi | 5 phút · tối đa **5 lần / 15 phút** / số điện thoại |
| Tạo đơn | **10/giờ** · tối đa **5 đơn hoạt động** cùng lúc |
| Liên hệ chủ hàng | **20 giờ/ tài xế** |
| Báo cáo vi phạm | **10/giờ** |
| Đơn hết hạn | = mốc `Đến:` của khung giờ lấy hàng |
| Vị trí GPS | gửi mỗi **30 giây** · lưu KV **~2 giờ** · xoá khi kết thúc chuyến |
| Hành lang radar | ±**10 km** quanh tuyến · ngược hướng tối đa **135°** · lệch thêm tối đa **15 km** · top **5** |
| JWT phiên đăng nhập | 30 ngày |

### 9.5 Tài liệu liên quan trong repo

| File | Nội dung |
|---|---|
| `docs/pilot_checklist.md` | 11 bước kiểm thử pilot + cách ghi kết quả |
| `README.md` | Kiến trúc, API, quy trình build/ deploy |
| `openspec/specs/*` | Đặc tả hành vi từng capability (nguồn sự thật của code) |
| `.project/modules/*.md` | Ghi chú kỹ thuật theo module (ads, auth, order, trip…) |
| `mobile/lib/feature/legal/…/legal_docs.dart` | Nội dung Điều khoản & Chính sách trong app |

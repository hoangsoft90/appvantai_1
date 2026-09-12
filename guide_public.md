# Hướng dẫn sử dụng App Vận Tải

> Bản dành cho **chủ cửa hàng** và **tài xế** · Cập nhật: 12/09/2026 · Nền tảng: Android

**App Vận Tải** giúp bạn tìm **mối hàng tiện đường**: tài xế khai tuyến đang chạy, hệ
thống tự quét các đơn hàng nằm trên tuyến đó và xếp hạng theo mức độ tiện đường; chủ
cửa hàng đăng hàng và nhận liên hệ từ tài xế chạy đúng tuyến.

Ứng dụng chỉ là **trung gian kết nối thông tin** — không vận chuyển, **không** thu tiền
hộ/thanh toán, không chịu trách nhiệm hàng hóa. Mọi thỏa thuận là giữa hai bên.

**Mục lục**

1. [Quy tắc chung cần biết](#1-quy-tắc-chung-cần-biết)
2. [Đăng nhập, hồ sơ, trạng thái đơn](#2-đăng-nhập-hồ-sơ-trạng-thái-đơn)
3. [Dành cho CHỦ CỬA HÀNG](#3-dành-cho-chủ-cửa-hàng)
4. [Dành cho TÀI XẾ](#4-dành-cho-tài-xế)
5. [Quảng cáo & quyền riêng tư](#5-quảng-cáo--quyền-riêng-tư)
6. [Xử lý sự cố — tra theo thông báo trên app](#6-xử-lý-sự-cố--tra-theo-thông-báo-trên-app)
7. [Hạn chế đã biết](#7-hạn-chế-đã-biết)
8. [Giới hạn hệ thống & hỗ trợ](#8-giới-hạn-hệ-thống--hỗ-trợ)

---

## 1. Quy tắc chung cần biết

| Quy tắc | Chi tiết |
|---|---|
| **1 tài khoản = 1 vai trò** | Chọn **một lần** ở bước “Hoàn tất hồ sơ” đầu tiên. Cần đổi vai trò → liên hệ ban quản trị, và chỉ đổi được khi **không còn đơn/chuyến đang hoạt động**. |
| **Tick điều khoản 1 lần** | Bắt buộc ở bước hoàn tất hồ sơ và ở form đăng đơn. |
| **Tài xế phải khai xe** | Chưa khai xe thì app giữ ở màn `Thông tin xe`, chưa vào được Radar. |
| **Số điện thoại chỉ lộ khi bấm “Liên hệ”** | Không ai xem được số của đối tác trước đó. |
| **GPS không dùng để bắt mối** | Radar chạy trên **tuyến tài xế khai**; GPS chỉ dùng khi tài xế bấm **Bắt đầu chuyến**. |
| **Đơn hết hạn theo khung giờ lấy hàng** | Quá mốc “Đến” của khung giờ lấy hàng mà chưa có tài xế nhận → đơn chuyển `Hết hạn` và biến khỏi radar. |

---

## 2. Đăng nhập, hồ sơ, trạng thái đơn

### 2.1 Đăng nhập

1. Mở app → nhập **số điện thoại** (dạng `0912345678` hoặc `+84912345678` đều được).
2. Bấm **`Gửi mã OTP`** → nhập **6 chữ số** nhận qua SMS (không thấy tin nhắn thì bấm **`Gửi lại mã`**) → **`Xác nhận`**.
3. Không nhận được SMS: kiểm tra số đã đúng chưa, thử **`Gửi lại mã`**; vẫn không được thì báo ban quản trị.

**Lần đầu đăng nhập — màn `Hoàn tất hồ sơ`:**
- Nhập **Họ và tên** (2–100 ký tự).
- Chọn vai trò: **`Chủ hàng`** (có hàng cần chở) hoặc **`Tài xế`** (có xe).
- Tick ô xác nhận điều khoản → bấm **`Tiếp tục`** → chọn Tài xế thì khai xe ở bước kế tiếp.

### 2.2 Khai / sửa thông tin xe (chỉ Tài xế)

| Trường | Ghi chú |
|---|---|
| `Loại xe` | Xe van · Xe bán tải · Xe tải · Xe container |
| `Biển số xe` | 4–12 ký tự, ví dụ `29C-123.45` |
| `Tải trọng (kg)` | Bắt buộc > 0 |
| `Dài` / `Rộng` / `Cao (cm)` | Không bắt buộc |
| `Khu vực hoạt động` | Tự do, ví dụ `Hà Nội – Hải Phòng` |

Bấm **`Hoàn tất`** (lần đầu) hoặc **`Lưu thay đổi`** (khi sửa từ Hồ sơ).

> **Khai tải trọng thật quan trọng:** khai thấp hơn thực tế → radar bỏ qua đơn nặng mà
> xe bạn chở được; khai cao hơn thực tế → bạn thấy đơn không chở được.

### 2.3 Hồ sơ (`Hồ sơ của tôi`)

Vào bằng icon **người** ở góc phải trang chủ: xem/sửa tên (bút chì ✏️), xem vai trò,
xem **phiên bản** app, đọc **`Điều khoản sử dụng`** và **`Chính sách riêng tư`**
(đọc được cả khi chưa đăng nhập). Tài xế còn có khối **Thông tin xe** +
**`Cập nhật thông tin xe`**. **Đăng xuất**: icon ở góc phải trang chủ.

### 2.4 Ý nghĩa 11 trạng thái đơn

| Trạng thái | Nghĩa | Ai làm gì tiếp |
|---|---|---|
| `Đang chờ` | Đơn vừa đăng, chưa ai liên hệ | Tài xế liên hệ/ nhận; chủ hàng hủy được |
| `Đã ghép` | Hệ thống đã ghép vào radar của tài xế | như trên |
| `Đã liên hệ` | Tài xế đã bấm “Liên hệ” (số đã lộ) | chủ hàng hủy được |
| `Đã nhận` | Tài xế đã nhận chuyến | chủ hàng **không hủy được nữa** |
| `Đang lấy hàng` | Tài xế đã đến lấy hàng | |
| `Đang vận chuyển` | Hàng đang trên đường | |
| `Đã giao` | Tài xế báo đã giao | **Chủ hàng bấm `Xác nhận hoàn tất`** |
| `Hoàn thành` | Xong | — |
| `Đã hủy` | Chủ hàng đã hủy (trước khi tài xế nhận) | — |
| `Hết hạn` | Quá khung giờ lấy hàng mà chưa có tài xế | Đăng đơn mới |
| `Từ chối` | Trạng thái dự phòng | — |

---

## 3. Dành cho CHỦ CỬA HÀNG

### 3.1 Đăng đơn hàng (khoảng 5 phút)

1. Trang chủ → **`Đơn hàng của tôi`** → nút **`Tạo đơn`**.
2. **Điểm lấy hàng:** gõ địa chỉ (≥ 3 ký tự) → bấm **icon kính lúp 🔍** → app hiện dòng xác nhận địa chỉ đã chọn. Làm tương tự cho **Điểm giao hàng**.
   ▸ **Đã chọn điểm mà còn sửa chữ trong ô địa chỉ thì điểm đó bị hủy** — phải bấm 🔍 tìm lại (tránh “địa chỉ A + toạ độ B”).
3. **Hàng hóa:** `Loại hàng` (Hàng thường / Thực phẩm / Hàng dễ vỡ / Nội thất / Điện tử / Vật liệu xây dựng / Khác), `Khối lượng (kg)` (số nguyên > 0), kích thước `Dài/Rộng/Cao (cm)` nếu cần, `Yêu cầu xe` (Xe bất kỳ / van / bán tải / tải / container).
4. **Thời gian & giá:** bấm **`Từ:`** và **`Đến:`** để chọn **khung giờ lấy hàng**; nhập `Giá (đ)` (ví dụ `2500000`) và `Ghi chú` (tối đa 500 ký tự).
5. Tick ô xác nhận điều khoản → **`Đăng đơn hàng`**.

> ⚠️ **Khung giờ lấy hàng = thời hạn sống của đơn.** Quá mốc `Đến:` mà chưa có tài xế
> nhận, đơn tự `Hết hạn`. Muốn giữ đơn lâu hơn → chọn `Đến:` xa hơn.

**Giới hạn:** tối đa **5 đơn hoạt động** cùng lúc (*“Bạn đang có 5 đơn hàng đang hoạt
động, vui lòng hủy hoặc chờ hoàn thành trước khi tạo mới”*) và **10 đơn/giờ**
(*“Bạn đã tạo quá nhiều đơn hàng trong thời gian ngắn, vui lòng thử lại sau”*).

### 3.2 Theo dõi đơn

**`Đơn hàng của tôi`** = danh sách đơn của bạn (kéo xuống để làm mới); chạm vào đơn để
mở chi tiết: trạng thái, giá, điểm lấy/giao, hàng hóa, yêu cầu xe, khung giờ, ghi chú.

### 3.3 Biết tài xế đang tới đâu?

Khi tài xế đã nhận (`Đã nhận`) **và** đã bật GPS cho chuyến, chi tiết đơn hiện:

> *“Tài xế đang cách điểm lấy khoảng 2.3 km”* — kèm ghi chú *“Vị trí ẩn danh — bảo mật theo chính sách”*.

Bạn **không bao giờ** thấy toạ độ GPS của tài xế. Nếu tài xế chưa bật vị trí, app ghi
*“Tài xế chưa bật định vị”* — bấm icon **làm mới ↻** trên dòng đó để cập nhật.

### 3.4 Hủy đơn — khi nào được?

Được hủy khi đơn còn ở `Đang chờ`, `Đã ghép`, `Đã liên hệ`: mở chi tiết đơn →
**`Hủy đơn hàng`** → **`Hủy đơn`**.

Từ `Đã nhận` trở đi nút hủy **không còn hiện**; hệ thống cũng chặn và báo *“Không thể hủy
đơn sau khi tài xế đã nhận. Hãy liên hệ hoặc báo cáo sự cố.”* → hãy **gọi tài xế** để
thống nhất.

### 3.5 Kết thúc đơn

Khi tài xế báo **`Đã giao hàng`** (đơn hiện `Đã giao`), mở chi tiết đơn → bấm
**`Xác nhận hoàn tất`** → đơn chuyển `Hoàn thành`. **Chỉ chủ hàng bấm được bước này.**

### 3.6 Báo cáo / Chặn tài xế

Đơn đã có tài xế → trong chi tiết đơn có **`Báo cáo / Chặn tài xế`**:
- **Báo cáo tài xế** → chọn lý do (Spam / Thông tin giả / Quấy rối / Lừa đảo / Khác).
- **Chặn tài xế** → hai bên không còn thấy nhau trên app.

Giới hạn: **10 báo cáo/giờ**.

### 3.7 Checklist nhanh

- [ ] Đã ghi tên thật + tick điều khoản (lần đầu)
- [ ] Chọn **đúng khung giờ lấy hàng** (đơn không sống quá mốc này)
- [ ] Bấm 🔍 xác nhận **cả 2 điểm** trước khi đăng
- [ ] Giá + khối lượng đã đúng (tài xế quyết định nhận dựa vào 2 số này)
- [ ] Tài xế báo “Đã giao” → **Xác nhận hoàn tất**

---

## 4. Dành cho TÀI XẾ

### 4.1 Tạo chuyến (bắt đầu ca chạy)

1. Trang chủ → **`Tôi đang chạy — quét radar`** → màn **`Tạo chuyến đi`**.
2. Chọn **`Đi 1 chiều`** hoặc **`Có chiều về`** (chọn “Có chiều về” nếu sẽ chạy xe rỗng về — hệ thống ưu tiên tìm hàng cho cả chặng về).
3. **Điểm đi:** gõ địa chỉ → bấm **🔍** → chọn điểm. Làm tương tự **Điểm đến**.
   ▸ Sửa chữ sau khi đã chọn → phải tìm lại.
4. Bấm **`Tạo chuyến & quét radar`** → vào thẳng màn radar.

> **Khai tuyến phải thật:** radar chỉ quét đơn trong hành lang ±10 km quanh tuyến bạn
> khai. Khai tuyến “cho rộng” sẽ làm điểm tiện đường sai và bạn nhận đơn không chạy nổi.

### 4.2 Đọc màn Radar (`Mối hàng tiện đường`)

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
- **Quá tải trọng** hoặc sai **loại xe** yêu cầu;
- **Không kịp giờ lấy hàng** (thời gian di chuyển tới điểm lấy + biên 30 phút);
- Làm tuyến bạn lệch quá **15 km**;
- Đã **hết hạn**, đã có tài xế khác nhận, hoặc đang bị chặn hai chiều.

Radar chỉ hiện **top 5 mối tốt nhất** — danh sách ngắn là bình thường, không phải lỗi.

### 4.3 Liên hệ chủ hàng

Bấm **`Liên hệ chủ hàng`** → hộp thoại hiện **tên + số điện thoại** chủ hàng:
- **Bấm vào chính số điện thoại** (hoặc nút **`Gọi`**) → app mở **trình gọi điện** với số đã phím sẵn.
- Số vẫn bôi đen/ copy được nếu muốn nhắn tin.
- Nút trên thẻ đổi thành `Đã liên hệ (09xx…)` → bấm lại **mở thẳng hộp thoại**.

Giới hạn: **20 lần liên hệ/giờ**.

### 4.4 Nhận chuyến (2 tài xế cùng bấm thì sao?)

Bấm **`Nhận chuyến`**. Hệ thống dùng khoá nguyên tử — **chỉ 1 tài xế thắng**, người còn
lại nhận *“Đơn đã được tài xế khác nhận”*. Nhận xong thẻ hiện `Đã nhận`.

> Nếu bạn đã nhận đơn này trước đó, bấm lại **không lỗi** — an toàn khi mạng chập chờn.

### 4.5 Chạy chuyến & GPS

Trên màn radar bấm **icon ▶ (`Bắt đầu chuyến (GPS)`)** ở góc phải trên → màn **`Chuyến của tôi`**.

| Bước | Việc app làm |
|---|---|
| Bấm **`Bắt đầu chuyến`** | Xin quyền vị trí → báo server chuyến đang chạy → gửi vị trí **ngay** rồi **mỗi 30 giây**. |
| Chip trên màn hình | `Đang chạy — GPS bật (30s/lần)` hoặc `Chưa bắt đầu — GPS tắt`. |
| Bấm **`Kết thúc chuyến`** | Ngừng gửi vị trí, kết thúc chuyến trên server, xoá vị trí đã lưu, quay về trang chủ. |

**Để GPS làm việc đúng:**
- **Giữ app mở ở màn `Chuyến của tôi`** trong lúc chạy — GPS **không chạy nền**.
- Từ chối quyền vị trí → app báo *“Cần quyền truy cập vị trí để chạy chuyến”* và **chuyến không bắt đầu** (mọi thứ khác vẫn dùng bình thường).
- Chuyến đã chạy trên server mà máy thiếu quyền → hiện băng đỏ *“Chuyến đang chạy nhưng thiếu quyền vị trí — cấp quyền để GPS tiếp tục”*.
- Mất mạng khi kết thúc → app ở lại màn hình, báo *“Chuyến chưa được kết thúc trên máy chủ — bấm ‘Kết thúc chuyến’ để thử lại”*. Bấm lại khi có mạng.

**GPS dùng để làm gì?** Chỉ để chủ hàng thấy **“tài xế cách ~X km”** (khoảng cách ẩn danh,
không lộ toạ độ). GPS **không** dùng để tìm mối.

### 4.6 Cập nhật tiến độ giao hàng

Mở **chi tiết đơn hàng** (từ thẻ mối hàng → `Xem chi tiết đơn hàng`). Mỗi lúc **chỉ có
đúng 1 nút** đúng với trạng thái:

`Đã nhận` → **`Đã lấy hàng`** → `Đang lấy hàng` → **`Bắt đầu giao`** → `Đang vận chuyển`
→ **`Đã giao hàng`** → `Đã giao`. Sau đó **chủ hàng** bấm `Xác nhận hoàn tất`.

Nút có chống bấm liên tục (đang gửi thì nút mờ + xoay) — bấm 1 lần rồi chờ.

### 4.7 Khi radar không có mối nào

Màn hình gợi ý 3 hành động (bấm được):
- **`Khai báo chiều về`** → tạo chuyến ngược chiều để bắt hàng chiều về.
- **`Về trang chủ`** → tạm nghỉ, quay lại sau.
- **`Quét lại radar`** → đơn mới có thể vừa được đăng.

### 4.8 ⚠️ Quy tắc sống còn khi chạy chuyến

> **Đừng tắt/ đóng app khi chuyến đang chạy.** App chưa có màn “chuyến của tôi” để vào
> lại chuyến cũ, nên nếu đóng app giữa ca bạn sẽ **không quay lại được màn chạy chuyến**
> (GPS dừng và không bấm được `Kết thúc chuyến`). Nếu lỡ gặp → **báo ban quản trị** để
> đóng chuyến treo.

### 4.9 Checklist nhanh

- [ ] Đã khai **loại xe + tải trọng thật**
- [ ] Mỗi ca: tạo chuyến **đúng tuyến thật**, chọn **chiều về** nếu có
- [ ] Đọc **danh sách lý do ✅** trên thẻ trước khi nhận (không chỉ nhìn giá)
- [ ] Bấm **Liên hệ** → gọi chủ hàng để chốt trước khi tới
- [ ] Nhận xong: **Đã lấy hàng → Bắt đầu giao → Đã giao hàng**
- [ ] Bấm **Kết thúc chuyến** ở cuối ca (đừng chỉ thoát app)

---

## 5. Quảng cáo & quyền riêng tư

**Quảng cáo:** app có quảng cáo ở đáy trang chủ, sau khi đăng đơn thành công và khi mở
app. Quảng cáo **không bao giờ chặn** thao tác chính.

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

## 6. Xử lý sự cố — tra theo thông báo trên app

| Thông báo bạn thấy | Nguyên nhân | Cách xử lý |
|---|---|---|
| *“Chưa gửi mã xác minh, vui lòng thử lại”* | Không gửi được SMS xác minh | Thử lại sau vài phút; vẫn lỗi → báo ban quản trị |
| *“Số điện thoại không hợp lệ”* | Nhập thiếu số | Nhập 10 số `09xxxxxxxx` hoặc `+849xxxxxxxx` |
| *“Vui lòng nhập đủ 6 chữ số”* | OTP nhập thiếu | Nhập đúng 6 số |
| *“Không thể kết nối máy chủ, vui lòng kiểm tra mạng”* | Mất mạng/ server không tới | Kiểm tra 3G/ WiFi rồi thử lại |
| *“Nhập địa chỉ ít nhất 3 ký tự”* | Từ khoá tìm quá ngắn | Gõ rõ hơn, ví dụ `KCN Thăng Long, Hà Nội` |
| *“Không tìm thấy địa chỉ, vui lòng thử từ khóa khác”* | Không nhận ra địa chỉ | Ghi kèm tỉnh/ thành phố; tránh viết tắt lạ |
| *“Vui lòng tìm và chọn điểm lấy + điểm giao (địa chỉ vừa sửa cần tìm lại)”* | Đã chọn điểm rồi sửa lại chữ trong ô địa chỉ | Bấm **🔍** tìm lại cho **cả 2 điểm** |
| *“Khối lượng phải là số nguyên > 0”* / *“Giá không hợp lệ”* | Để trống hoặc nhập chữ | Nhập số, ví dụ `800` và `2500000` |
| *“Vui lòng tick xác nhận điều khoản để đăng hàng”* | Chưa tick ô xác nhận | Tick rồi bấm `Đăng đơn hàng` |
| *“Bạn đang có 5 đơn hàng đang hoạt động…”* | Vượt giới hạn đơn hoạt động | Hủy bớt hoặc chờ đơn cũ `Hoàn thành`/`Hết hạn` |
| *“Bạn đã tạo quá nhiều đơn hàng trong thời gian ngắn…”* | Vượt 10 đơn/giờ | Chờ bớt rồi đăng lại |
| *“Bạn đã liên hệ quá nhiều trong thời gian ngắn…”* | Tài xế vượt 20 lần liên hệ/giờ | Chờ bớt |
| *“Đơn đã được tài xế khác nhận”* | 2 tài xế cùng nhận, chỉ 1 người thắng | Quét lại radar tìm mối khác |
| *“Không thể hủy đơn sau khi tài xế đã nhận…”* | Đơn đã `Đã nhận` | Gọi tài xế thống nhất; cần thì `Báo cáo / Chặn tài xế` |
| *“Cần quyền truy cập vị trí để chạy chuyến”* | Từ chối quyền định vị | Cài đặt Android → App Vận Tải → Quyền → **Vị trí: Cho phép khi đang dùng app** |
| Băng đỏ *“Chuyến đang chạy nhưng thiếu quyền vị trí…”* | Chuyến đã chạy nhưng máy thiếu quyền | Cấp quyền rồi mở lại màn `Chuyến của tôi` |
| *“Chưa sync được với máy chủ — GPS đã tắt, vui lòng thử lại”* | Mất mạng lúc kết thúc chuyến | Có mạng lại rồi bấm **`Kết thúc chuyến`** lần nữa |
| *“Chuyến chưa được kết thúc trên máy chủ…”* | Như trên (băng đỏ trên màn) | Bấm lại **`Kết thúc chuyến`** khi có mạng |
| *“Đường dẫn này không còn tồn tại hoặc đã được thay đổi.”* | Mở link cũ/ sai | Bấm **`Về trang chủ`** |
| Radar trắng, không có mối | Không có đơn nào khớp tuyến/ tải trọng/ giờ | Dùng 3 gợi ý ở §4.7, hoặc đợi đơn mới |
| App xoay tròn mãi | Mạng chậm khi tải dữ liệu | Chờ vài giây; nếu kẹt, thoát và mở lại (**trừ khi đang chạy chuyến** — xem §4.8) |

---

## 7. Hạn chế đã biết

| # | Hạn chế | Cách xử lý tạm |
|---|---|---|
| 1 | **Đóng app khi đang chạy chuyến thì không vào lại được** màn chạy chuyến (chưa có màn danh sách chuyến) | Đừng thoát app trong ca; nếu lỡ → báo ban quản trị đóng chuyến treo |
| 2 | **Không sửa được đơn đã đăng** (chưa có màn sửa) | Hủy đơn (khi còn `Đang chờ`) rồi đăng lại |
| 3 | **Không có chat/ thông báo đẩy** | Hai bên liên hệ bằng **gọi điện** |
| 4 | **Không có thanh toán trong app** (đúng thiết kế) | Giá chỉ là thông tin tham khảo; hai bên tự thỏa thuận |
| 5 | Chỉ có bản **Android** | — |
| 6 | Radar chỉ hiện **top 5** mối | Quét lại sau, hoặc tạo chuyến khác |
| 7 | Chủ cửa hàng chưa **tìm/ lọc đơn** | Chỉ xem được danh sách đơn của mình |

---

## 8. Giới hạn hệ thống & hỗ trợ

| Tham số | Giá trị |
|---|---|
| OTP: hiệu lực / số lần gửi | 5 phút · tối đa **5 lần / 15 phút** mỗi số |
| Tạo đơn hàng | **10/giờ** · tối đa **5 đơn hoạt động** cùng lúc |
| Liên hệ chủ hàng | **20 lần/giờ** mỗi tài xế |
| Báo cáo vi phạm | **10/giờ** |
| Đơn hết hạn | = mốc `Đến:` của khung giờ lấy hàng |
| Vị trí GPS | gửi mỗi **30 giây** · lưu **~2 giờ** · xoá khi kết thúc chuyến |
| Bán kính radar | ±**10 km** quanh tuyến · ngược hướng tối đa **135°** · lệch thêm tối đa **15 km** · top **5** |

**Cần hỗ trợ?** Liên hệ ban quản trị App Vận Tải (Zalo/ điện thoại của người phụ trách
pilot). Nói rõ: **số điện thoại đăng nhập**, **màn hình đang gặp lỗi** và **nguyên văn
thông báo trên app** để được xử lý nhanh nhất.

_Ứng dụng chỉ là trung gian kết nối thông tin. Mọi giao dịch, chất lượng hàng hóa,
thanh toán và trách nhiệm pháp lý do hai bên tự thỏa thuận và chịu trách nhiệm._

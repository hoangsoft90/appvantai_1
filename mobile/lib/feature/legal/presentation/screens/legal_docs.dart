import 'package:flutter/material.dart';

import '../../../../app/router/safe_nav.dart';

/// Phase 7 §7.5 — Điều khoản sử dụng & Chính sách riêng tư (nội dung tối thiểu).
/// Nội dung tĩnh trong app (không cần server/Pages) — 0đ, hoạt động offline.
/// Render mini: '# ' → heading lớn, '## ' → heading vừa, còn lại là đoạn văn
/// (không thêm package markdown — anti-overengineering).
///
/// Điểm pháp lý bắt buộc theo plan:
///  - App chỉ trung gian kết nối thông tin, không tham gia vận chuyển
///  - Không chịu trách nhiệm hàng hóa/thanh toán/trách nhiệm pháp lý 2 bên
///  - Dữ liệu vị trí chỉ thu khi có chuyến active, chỉ hiện khoảng cách
class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  static const String body = '''
# Điều khoản sử dụng

_Cập nhật: 09/2026_

## 1. Vai trò của ứng dụng

App Vận Tải ("Ứng dụng") CHỈ là nền tảng trung gian kết nối thông tin giữa
người có hàng cần vận chuyển ("Chủ hàng") và người có phương tiện vận tải
("Tài xế"). Ứng dụng không phải bên vận chuyển, không sở hữu phương tiện,
không nhận ký gửi hàng hóa.

## 2. Trách nhiệm của các bên

- Hợp đồng vận chuyển (nếu có) được xác lập trực tiếp giữa Chủ hàng và Tài xế.
- Ứng dụng không chịu trách nhiệm về chất lượng hàng hóa, thời gian giao,
  an toàn hàng hóa, tai nạn, thiệt hại phát sinh, hoặc các vấn đề thanh toán
  giữa hai bên.
- Giá cước hiển thị (nếu có) chỉ mang tính tham khảo, hai bên tự thỏa thuận.

## 3. Điều kiện sử dụng

- Bạn phải đủ 18 tuổi, sử dụng thông tin thật khi đăng ký.
- Tài xế chịu trách nhiệm về tính pháp lý của phương tiện, giấy phép lái xe
  và các giấy tờ liên quan.
- Không sử dụng Ứng dụng cho hàng cấm, hàng giả, chất cấm, động vật hoang dã
  hoặc bất kỳ hàng hóa vi phạm pháp luật Việt Nam.
- Gian lận, giả mạo, quấy rối người dùng khác có thể bị khóa tài khoản.

## 4. Chức năng định vị

- Vị trí GPS chỉ được thu khi bạn có chuyến đang chạy (active) và bạn đã
  cấp quyền.
- Đối tác của bạn chỉ thấy khoảng cách ước lượng, không thấy tọa độ chi
  tiết của bạn theo thời gian thực.

## 5. Thay đổi điều khoản

Chúng tôi có thể cập nhật điều khoản này. Việc tiếp tục sử dụng Ứng dụng sau
khi cập nhật đồng nghĩa với việc bạn chấp nhận điều khoản mới.

## 6. Liên hệ

Mọi khiếu nại/vi phạm: dùng chức năng Báo cáo trong Ứng dụng hoặc liên hệ
đội ngũ hỗ trợ qua kênh chính thức được công bố.
''';

  @override
  Widget build(BuildContext context) {
    return const LegalDocScaffold(
      title: 'Điều khoản sử dụng',
      body: body,
    );
  }
}

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const String body = '''
# Chính sách riêng tư

_Cập nhật: 09/2026_

## 1. Dữ liệu chúng tôi thu thập

- Tài khoản: số điện thoại (xác thực), họ tên, vai trò (Chủ hàng/Tài xế).
- Tài xế: thông tin phương tiện (loại xe, biển số, tải trọng, kích thước).
- Đơn hàng / Chuyến xe: điểm đi — điểm đến, loại hàng, khối lượng, thời gian.
- Vị trí GPS: chỉ khi chuyến đang chạy (active) và bạn đã cấp quyền.
  Khi chuyến kết thúc, ứng dụng ngừng gửi vị trí.

## 2. Chúng tôi KHÔNG thu thập

- Không đọc danh bạ, tin nhắn, ảnh trên thiết bị của bạn.
- Không theo dõi vị trí khi không có chuyến active.
- Không thu thập dữ liệu thanh toán (Ứng dụng không xử lý thanh toán).

## 3. Dữ liệu được dùng để làm gì

- Ghép nối đơn hàng — chuyến xe tiện đường ("radar tìm mối").
- Cho đối tác của bạn thấy khoảng cách ước lượng đến điểm nhận/giao
  (không hiển thị tọa độ chi tiết theo thời gian thực).
- Xử lý báo cáo vi phạm, ngăn chặn gian lận và chặn người dùng xấu.

## 4. Chia sẻ dữ liệu

- Số điện thoại của bạn chỉ hiển thị cho đối tác sau khi một trong hai bên
  bấm "Liên hệ" cho một đơn hàng cụ thể.
- Không bán dữ liệu cho bên thứ ba. Không dùng cho quảng cáo.

## 5. Lưu trữ & xóa dữ liệu

- Dữ liệu lưu trên máy chủ của Ứng dụng, được bảo vệ bằng kiểm soát truy cập.
- Vị trí chuyến cũ được tự động xóa khỏi bộ nhớ tạm trong vòng ~2 giờ sau
  khi chuyến kết thúc.
- Bạn có thể yêu cầu xóa tài khoản bằng cách liên hệ hỗ trợ.

## 6. Quyền của bạn

- Xem, sửa thông tin hồ sơ bất cứ lúc nào trong màn "Hồ sơ".
- Từ chối quyền định vị: Ứng dụng vẫn hoạt động (xem mối, liên hệ, nhận đơn)
  nhưng không thể chia sẻ vị trí khi chuyến chạy.
- Báo cáo người dùng khác — đội ngũ vận hành xử lý trực tiếp.
''';

  @override
  Widget build(BuildContext context) {
    return const LegalDocScaffold(
      title: 'Chính sách riêng tư',
      body: body,
    );
  }
}

/// Scaffold chung cho 2 màn legal — render văn bản dạng heading/đoạn.
class LegalDocScaffold extends StatelessWidget {
  const LegalDocScaffold({super.key, required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        // Legal docs là trang public: mở bằng deep link (stack rỗng) vẫn phải có
        // đường ra → /login (router tự đưa user đã đăng nhập về landing).
        leading: const SafeBackButton(fallback: '/login'),
        title: Text(title),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final line in body.split('\n'))
            _line(context, theme, line),
        ],
      ),
    );
  }

  Widget _line(BuildContext context, ThemeData theme, String raw) {
    final line = raw.trim();
    if (line.isEmpty) return const SizedBox(height: 8);
    if (line.startsWith('## ')) {
      return Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 4),
        child: Text(
          line.substring(3),
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
      );
    }
    if (line.startsWith('# ')) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          line.substring(2),
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
      );
    }
    if (line.startsWith('_') && line.endsWith('_')) {
      return Text(
        line.substring(1, line.length - 1),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.outline,
          fontStyle: FontStyle.italic,
        ),
      );
    }
    return Text(line, style: theme.textTheme.bodyMedium);
  }
}

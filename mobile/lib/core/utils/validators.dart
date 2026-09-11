/// Chuẩn hóa + validate số điện thoại Việt Nam (giống worker/src/lib/phone.ts).
class PhoneValidator {
  PhoneValidator._();

  /// Trả về số đã chuẩn hóa (0xxxxxxxxx) hoặc null nếu không hợp lệ.
  static String? normalize(String raw) {
    var p = raw.trim().replaceAll(RegExp(r'[\s-]'), '');
    if (p.startsWith('+')) p = p.substring(1);
    if (p.startsWith('84')) p = '0${p.substring(2)}';
    if (!RegExp(r'^0(3|5|7|8|9)\d{8}$').hasMatch(p)) return null;
    return p;
  }

  /// Message lỗi hiển thị cho TextField validator.
  static String? validate(String? raw) {
    if (raw == null || raw.trim().isEmpty) return 'Vui lòng nhập số điện thoại';
    if (normalize(raw) == null) return 'Số điện thoại không hợp lệ';
    return null;
  }
}
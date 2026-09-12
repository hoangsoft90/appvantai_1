import 'package:appvantai_mobile/core/utils/phone_dialer.dart';
import 'package:flutter_test/flutter_test.dart';

/// Nav audit 2026-09-12: nút \"Gọi\" phải mở dialer với ĐÚNG số đã lộ từ
/// `POST /orders/:id/contact`. URI `tel:` sai định dạng sẽ im lặng không làm gì
/// trên máy thật → khóa hành vi chuẩn hoá bằng unit test (không cần device).
void main() {
  test('số nội địa → URI tel: đúng', () {
    expect(telUri('0912000001').toString(), 'tel:0912000001');
  });

  test('số có space/gạch/chấm (backend hay trả) → strip hết', () {
    expect(telUri('0912 000 001').toString(), 'tel:0912000001');
    expect(telUri('0912-000-001').toString(), 'tel:0912000001');
    expect(telUri('0912.000.001').toString(), 'tel:0912000001');
    expect(telUri('(0912) 000-001').toString(), 'tel:0912000001');
  });

  test('số E.164 (+84) giữ dấu + — dialer quốc tế cần', () {
    expect(telUri('+84912000001').toString(), 'tel:+84912000001');
    expect(telUri('+84 912 000 001').toString(), 'tel:+84912000001');
  });

  test('chuỗi rỗng / toàn ký tự lạ → URI rỗng để caller bỏ qua (không mở dialer)', () {
    expect(telUri('').path, isEmpty);
    expect(telUri('   ').path, isEmpty);
    expect(telUri('abc').path, isEmpty);
  });
}

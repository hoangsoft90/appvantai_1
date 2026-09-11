import 'package:appvantai_mobile/core/utils/validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PhoneValidator.normalize', () {
    test('chuẩn hóa định dạng phổ biến về 0xxxxxxxxx', () {
      expect(PhoneValidator.normalize('0912345678'), '0912345678');
      expect(PhoneValidator.normalize('+84912345678'), '0912345678');
      expect(PhoneValidator.normalize('84912345678'), '0912345678');
      expect(PhoneValidator.normalize('0912 345 678'), '0912345678');
    });

    test('số không hợp lệ → null', () {
      expect(PhoneValidator.normalize('123'), isNull);
      expect(PhoneValidator.normalize('012345678'), isNull); // thiếu 1 số
      expect(PhoneValidator.normalize('0112345678'), isNull); // đầu 01
      expect(PhoneValidator.normalize(''), isNull);
      expect(PhoneValidator.normalize('abcdefghij'), isNull);
    });
  });

  group('PhoneValidator.validate', () {
    test('trả message khi rỗng', () {
      expect(PhoneValidator.validate(null), isNotNull);
      expect(PhoneValidator.validate(''), isNotNull);
    });

    test('trả message khi sai định dạng', () {
      expect(PhoneValidator.validate('123'), isNotNull);
    });

    test('null khi hợp lệ', () {
      expect(PhoneValidator.validate('0912345678'), isNull);
    });
  });
}
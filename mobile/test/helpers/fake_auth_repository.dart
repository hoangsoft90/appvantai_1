import 'package:appvantai_mobile/feature/auth/data/auth_repository.dart';
import 'package:appvantai_mobile/feature/auth/domain/auth_models.dart';
import 'package:appvantai_mobile/shared/services/api_exception.dart';

/// Fake repository — không cần network/Dio trong widget test.
/// Hành vi:
///  - requestOtp trả '123456' (dev OTP) hoặc ném lỗi mạng khi [failRequestOtp]
///  - verifyOtp chỉ chấp nhận '123456'
///  - updateMe/saveVehicle cập nhật [currentUser] và trả về
class FakeAuthRepository implements AuthRepository {
  final requestedPhones = <String>[];
  bool failRequestOtp = false;

  AuthUser currentUser = const AuthUser(
    id: 'u1',
    name: '',
    phone: '0912345678',
    role: 'customer',
    status: 'active',
  );

  @override
  Future<String> requestOtp(String phone) async {
    if (failRequestOtp) {
      throw const ApiException(
        statusCode: null,
        code: 'NETWORK_ERROR',
        message: 'Không thể kết nối máy chủ, vui lòng kiểm tra mạng',
      );
    }
    requestedPhones.add(phone);
    return '123456';
  }

  @override
  Future<AuthSession> loginWithFirebaseIdToken(String idToken) async {
    // Widget test chạy strategy dev nên method này thường không chạm;
    // nếu bị gọi (strategy Firebase) trả session thành công như verifyOtp.
    return AuthSession(token: 'jwt-firebase-test', user: currentUser);
  }

  @override
  Future<AuthSession> verifyOtp(String phone, String otp) async {
    if (otp != '123456') {
      throw const ApiException(
        statusCode: 400,
        code: 'INVALID_OTP',
        message: 'Mã OTP không đúng hoặc đã hết hạn',
      );
    }
    return AuthSession(token: 'fake-token', user: currentUser);
  }

  @override
  Future<AuthUser> me() async => throw UnimplementedError();

  @override
  Future<AuthUser> updateMe({String? name, String? role}) async {
    currentUser = currentUser.copyWith(name: name, role: role);
    return currentUser;
  }

  @override
  Future<VehicleProfile> saveVehicle(VehicleProfile vehicle) async {
    currentUser = currentUser.copyWith(vehicle: vehicle);
    return vehicle;
  }

  @override
  Future<AuthUser> giveLegalConsent() async {
    currentUser = currentUser.copyWith(legalConsentAt: DateTime.now());
    return currentUser;
  }
}
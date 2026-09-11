import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/services/api_client.dart';
import '../../../shared/services/api_exception.dart';
import '../domain/auth_models.dart';

/// Repository auth — gọi API worker (/auth/*, /me, /me/vehicle).
/// Mọi DioException đều map sang ApiException để UI hiển thị message thân thiện.
class AuthRepository {
  AuthRepository(this._api);

  final ApiClient _api;

  /// Trả dev_otp nếu backend đang ở dev mode (ALLOW_DEV_OTP=true),
  /// ngược lại chuỗi rỗng. Dùng để hiện gợi ý OTP khi test pilot.
  Future<String> requestOtp(String phone) async {
    try {
      final res = await _api.dio.post('/auth/request-otp', data: {'phone': phone});
      final data = (res.data as Map<String, dynamic>?) ?? const {};
      return (data['dev_otp'] as String?) ?? '';
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<AuthSession> verifyOtp(String phone, String otp) async {
    try {
      final res = await _api.dio.post('/auth/verify-otp', data: {'phone': phone, 'otp': otp});
      final data = (res.data as Map<String, dynamic>?) ?? const {};
      return AuthSession(
        token: (data['token'] as String?) ?? '',
        user: AuthUser.fromJson((data['user'] as Map<String, dynamic>?) ?? const {}),
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Phase 7 §7.1 — Đổi Firebase ID token lấy JWT app (POST /auth/firebase).
  /// Worker verify chữ ký RS256 + claims server-side; response contract
  /// giống verify-otp → mobile lưu token như cũ.
  Future<AuthSession> loginWithFirebaseIdToken(String idToken) async {
    try {
      final res = await _api.dio.post('/auth/firebase', data: {'id_token': idToken});
      final data = (res.data as Map<String, dynamic>?) ?? const {};
      return AuthSession(
        token: (data['token'] as String?) ?? '',
        user: AuthUser.fromJson((data['user'] as Map<String, dynamic>?) ?? const {}),
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// GET /me — trả user kèm driver_profile (nếu role=driver).
  Future<AuthUser> me() async {
    try {
      final res = await _api.dio.get('/me');
      return _parseUserResponse(res.data);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// PATCH /me — cập nhật name/role (Phase 1 Identity).
  Future<AuthUser> updateMe({String? name, String? role}) async {
    try {
      final res = await _api.dio.patch('/me', data: {
        'name': ?name,
        'role': ?role,
      });
      return _parseUserResponse(res.data);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// PATCH /me/vehicle — lưu/cập nhật xe của tài xế (upsert).
  Future<VehicleProfile> saveVehicle(VehicleProfile vehicle) async {
    try {
      final res = await _api.dio.patch('/me/vehicle', data: vehicle.toJson());
      final data = (res.data as Map<String, dynamic>?) ?? const {};
      return VehicleProfile.fromJson(
        (data['driver_profile'] as Map<String, dynamic>?) ?? const {},
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// POST /me/legal-consent — tick disclaimer (Phase 5, §18).
  /// Trả user mới kèm legal_consent_at.
  Future<AuthUser> giveLegalConsent() async {
    try {
      final res = await _api.dio.post('/me/legal-consent');
      final data = (res.data as Map<String, dynamic>?) ?? const {};
      final user = AuthUser.fromJson(
        (data['user'] as Map<String, dynamic>?) ?? const {},
      );
      return AuthUser(
        id: user.id,
        name: user.name,
        phone: user.phone,
        role: user.role,
        status: user.status,
        vehicle: user.vehicle,
        legalConsentAt: DateTime.tryParse(data['legal_consent_at'] as String? ?? '') ??
            user.legalConsentAt,
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  AuthUser _parseUserResponse(dynamic raw) {
    final data = (raw as Map<String, dynamic>?) ?? const {};
    final profileRaw = data['driver_profile'];
    final user = AuthUser.fromJson(
      (data['user'] as Map<String, dynamic>?) ?? const {},
      vehicle: profileRaw is Map<String, dynamic> ? VehicleProfile.fromJson(profileRaw) : null,
    );
    // legal_consent_at nằm ở top-level response /me (không trong user object)
    final consentRaw = data['legal_consent_at'];
    if (consentRaw is String && consentRaw.isNotEmpty && user.legalConsentAt == null) {
      return AuthUser(
        id: user.id,
        name: user.name,
        phone: user.phone,
        role: user.role,
        status: user.status,
        vehicle: user.vehicle,
        legalConsentAt: DateTime.tryParse(consentRaw),
      );
    }
    return user;
  }
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(apiClientProvider)),
);
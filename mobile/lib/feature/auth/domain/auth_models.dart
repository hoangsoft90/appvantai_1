// Domain entities cho auth.

/// Trạng thái xác thực của app (single source of truth cho routing).
sealed class AuthState {
  const AuthState();
}

class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

class AuthAuthenticated extends AuthState {
  const AuthAuthenticated({required this.user});

  final AuthUser user;
}

/// Thông tin xe của tài xế (Phase 1 — 1 tài xế = 1 xe, plan §11).
class VehicleProfile {
  const VehicleProfile({
    required this.vehicleType,
    required this.licensePlate,
    required this.capacityKg,
    required this.lengthCm,
    required this.widthCm,
    required this.heightCm,
    required this.operatingArea,
  });

  factory VehicleProfile.fromJson(Map<String, dynamic> json) => VehicleProfile(
        vehicleType: (json['vehicle_type'] as String?) ?? 'van',
        licensePlate: (json['license_plate'] as String?) ?? '',
        capacityKg: (json['capacity_kg'] as num?)?.toInt() ?? 0,
        lengthCm: (json['vehicle_length_cm'] as num?)?.toInt() ?? 0,
        widthCm: (json['vehicle_width_cm'] as num?)?.toInt() ?? 0,
        heightCm: (json['vehicle_height_cm'] as num?)?.toInt() ?? 0,
        operatingArea: (json['operating_area'] as String?) ?? '',
      );

  final String vehicleType;
  final String licensePlate;
  final int capacityKg;
  final int lengthCm;
  final int widthCm;
  final int heightCm;
  final String operatingArea;

  bool get isEmpty =>
      licensePlate.isEmpty && capacityKg == 0 && lengthCm == 0;

  Map<String, dynamic> toJson() => {
        'vehicle_type': vehicleType,
        'license_plate': licensePlate,
        'capacity_kg': capacityKg,
        'vehicle_length_cm': lengthCm,
        'vehicle_width_cm': widthCm,
        'vehicle_height_cm': heightCm,
        'operating_area': operatingArea,
      };
}

class AuthUser {
  const AuthUser({
    required this.id,
    required this.name,
    required this.phone,
    required this.role,
    required this.status,
    this.vehicle,
    this.legalConsentAt,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json, {VehicleProfile? vehicle}) =>
      AuthUser(
        id: (json['id'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
        phone: (json['phone'] as String?) ?? '',
        role: (json['role'] as String?) ?? 'customer',
        status: (json['status'] as String?) ?? 'active',
        vehicle: vehicle,
        legalConsentAt: DateTime.tryParse(json['legal_consent_at'] as String? ?? ''),
      );

  final String id;
  final String name;
  final String phone;

  /// 'driver' | 'customer' | 'admin'
  final String role;

  /// 'active' | 'suspended' | 'banned'
  final String status;

  /// Chỉ có khi role = driver và đã tạo profile (Phase 1).
  final VehicleProfile? vehicle;

  /// Thời điểm tick legal disclaimer (§18) — null nếu chưa consent.
  final DateTime? legalConsentAt;

  bool get isActive => status == 'active';
  bool get isDriver => role == 'driver';
  bool get needsOnboarding => name.trim().isEmpty;
  bool get hasLegalConsent => legalConsentAt != null;

  AuthUser copyWith({String? name, String? role, VehicleProfile? vehicle, DateTime? legalConsentAt}) => AuthUser(
        id: id,
        name: name ?? this.name,
        phone: phone,
        role: role ?? this.role,
        status: status,
        vehicle: vehicle ?? this.vehicle,
        legalConsentAt: legalConsentAt ?? this.legalConsentAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'role': role,
        'status': status,
      };
}

class AuthSession {
  const AuthSession({required this.token, required this.user});

  final String token;
  final AuthUser user;
}
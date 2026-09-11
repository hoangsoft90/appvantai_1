import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lưu token auth (đã chốt: shared_preferences cho pilot).
/// Interface nhỏ để sau đổi sang flutter_secure_storage không đụng call-site.
class TokenStorage {
  static const _tokenKey = 'auth_token';

  Future<String?> readToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }
}

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());
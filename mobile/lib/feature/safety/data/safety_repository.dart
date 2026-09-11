import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/services/api_client.dart';
import '../../../shared/services/api_exception.dart';

/// Repository trust layer (Phase 5 — plan §18): report + block.
class SafetyRepository {
  SafetyRepository(this._api);

  final ApiClient _api;

  Future<void> reportUser({
    required String targetUserId,
    required String reason,
    String? orderId,
    String description = '',
  }) async {
    try {
      await _api.dio.post('/reports', data: {
        'target_user_id': targetUserId,
        'reason': reason,
        'order_id': ?orderId,
        'description': description,
      });
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<void> blockUser(String targetUserId) async {
    try {
      await _api.dio.post('/blocks', data: {'target_user_id': targetUserId});
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<void> unblockUser(String targetUserId) async {
    try {
      await _api.dio.delete('/blocks/$targetUserId');
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

final safetyRepositoryProvider = Provider<SafetyRepository>(
  (ref) => SafetyRepository(ref.watch(apiClientProvider)),
);
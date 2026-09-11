import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import 'logger.dart';
import 'token_storage.dart';

/// API client dùng chung. Single source of truth cho mọi request:
///  - baseUrl + timeout từ AppConfig
///  - tự gắn `Authorization: Bearer <token>` từ TokenStorage
///  - log request/response khi dev (không log header để tránh lộ token)
class ApiClient {
  ApiClient({required this.tokenStorage, String? baseUrl})
      : _dio = Dio(
          BaseOptions(
            baseUrl: baseUrl ?? AppConfig.apiBaseUrl,
            connectTimeout: AppConfig.connectTimeout,
            receiveTimeout: AppConfig.receiveTimeout,
            contentType: 'application/json',
          ),
        ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await tokenStorage.readToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
      ),
    );
    if (AppConfig.isDev) {
      _dio.interceptors.add(
        LogInterceptor(
          request: true,
          requestHeader: false, // tránh log token
          requestBody: true,
          responseHeader: false,
          responseBody: true,
          logPrint: (o) => AppLogger.debug('[dio] $o'),
        ),
      );
    }
  }

  final TokenStorage tokenStorage;
  final Dio _dio;

  Dio get dio => _dio;
}

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(tokenStorage: ref.watch(tokenStorageProvider)),
);
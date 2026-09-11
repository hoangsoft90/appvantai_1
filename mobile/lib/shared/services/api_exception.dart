import 'package:dio/dio.dart';

/// Lỗi API thống nhất (plan §26): mọi network operation đều map về đây,
/// mang message tiếng Việt thân thiện để UI hiển thị trực tiếp.
class ApiException implements Exception {
  const ApiException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  /// null = lỗi mạng/timeout (không có response từ server).
  final int? statusCode;
  final String code;
  final String message;

  bool get isNetworkError => statusCode == null;
  bool get isUnauthorized => statusCode == 401;

  static ApiException fromDio(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return const ApiException(
          statusCode: null,
          code: 'TIMEOUT',
          message: 'Kết nối quá chậm, vui lòng thử lại',
        );
      case DioExceptionType.connectionError:
        return const ApiException(
          statusCode: null,
          code: 'NETWORK_ERROR',
          message: 'Không thể kết nối máy chủ, vui lòng kiểm tra mạng',
        );
      case DioExceptionType.cancel:
        return const ApiException(
          statusCode: null,
          code: 'CANCELLED',
          message: 'Yêu cầu đã bị hủy',
        );
      case DioExceptionType.badCertificate:
        return const ApiException(
          statusCode: null,
          code: 'BAD_CERTIFICATE',
          message: 'Kết nối không an toàn',
        );
      case DioExceptionType.badResponse:
      case DioExceptionType.unknown:
        break;
    }

    // Parse envelope thống nhất từ worker: { error: { code, message, status } }
    final data = e.response?.data;
    if (data is Map<String, dynamic>) {
      final err = data['error'];
      if (err is Map<String, dynamic>) {
        return ApiException(
          statusCode: e.response?.statusCode,
          code: (err['code'] as String?) ?? 'UNKNOWN',
          message: (err['message'] as String?) ?? 'Có lỗi xảy ra, vui lòng thử lại',
        );
      }
    }
    return ApiException(
      statusCode: e.response?.statusCode,
      code: 'UNKNOWN',
      message: 'Có lỗi xảy ra (${e.response?.statusCode ?? 'unknown'})',
    );
  }

  @override
  String toString() => 'ApiException($statusCode, $code): $message';
}
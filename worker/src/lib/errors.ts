/**
 * Unified API error. Mọi handler ném ApiError; error handler middleware
 * chuyển thành JSON envelope thống nhất:
 *   { "error": { "code": "...", "message": "...", "status": 400 } }
 */
export class ApiError extends Error {
  readonly status: number;
  readonly code: string;
  readonly details?: unknown;

  constructor(status: number, code: string, message: string, details?: unknown) {
    super(message);
    this.name = 'ApiError';
    this.status = status;
    this.code = code;
    this.details = details;
  }
}

export const Errors = {
  badRequest: (code: string, message: string, details?: unknown) =>
    new ApiError(400, code, message, details),
  unauthorized: (code = 'UNAUTHORIZED', message = 'Chưa đăng nhập hoặc phiên đã hết hạn') =>
    new ApiError(401, code, message),
  forbidden: (code = 'FORBIDDEN', message = 'Bạn không có quyền thực hiện thao tác này') =>
    new ApiError(403, code, message),
  notFound: (code = 'NOT_FOUND', message = 'Không tìm thấy') =>
    new ApiError(404, code, message),
  conflict: (code: string, message: string, details?: unknown) =>
    new ApiError(409, code, message, details),
  tooManyRequests: (code = 'RATE_LIMITED', message: string = 'Quá nhiều yêu cầu, vui lòng thử lại sau') =>
    new ApiError(429, code, message),
  // fix_p7_1 #1 — cấu hình production sai phải là lỗi rõ ràng, không âm thầm chạy dev secret.
  serviceUnavailable: (code: string, message: string) => new ApiError(503, code, message),
  internal: (message = 'Lỗi hệ thống, vui lòng thử lại') =>
    new ApiError(500, 'INTERNAL_ERROR', message),
};

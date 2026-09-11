/**
 * Structured logging đơn giản (JSON lines). Mọi log đều kèm requestId
 * để trace một request từ đầu đến cuối. P0 không cần hệ thống log ngoài.
 */
export type LogLevel = 'debug' | 'info' | 'warn' | 'error';

export function log(level: LogLevel, message: string, meta: Record<string, unknown> = {}): void {
  const line = JSON.stringify({
    time: new Date().toISOString(),
    level,
    msg: message,
    ...meta,
  });
  if (level === 'error') {
    console.error(line);
  } else {
    console.log(line);
  }
}
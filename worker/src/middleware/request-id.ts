import type { Context, Next } from 'hono';
import { log } from '../lib/logger';

/**
 * Gán requestId cho mỗi request (header x-request-id nếu client gửi,
 * ngược lại tự sinh). Dùng cho log correlation và debug.
 */
export async function requestIdMiddleware(c: Context, next: Next): Promise<void> {
  const incoming = c.req.header('x-request-id');
  const requestId = incoming && /^[A-Za-z0-9-]{8,64}$/.test(incoming) ? incoming : crypto.randomUUID();
  c.set('requestId', requestId);
  c.header('x-request-id', requestId);
  await next();
}

/** Log method/path/status của mọi request (debug level). */
export async function accessLogMiddleware(c: Context, next: Next): Promise<void> {
  const start = Date.now();
  await next();
  log('debug', 'request', {
    requestId: c.get('requestId'),
    method: c.req.method,
    path: c.req.path,
    status: c.res.status,
    durationMs: Date.now() - start,
  });
}
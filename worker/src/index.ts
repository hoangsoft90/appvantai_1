import { Hono } from 'hono';
import type { ContentfulStatusCode } from 'hono/utils/http-status';
import type { AppEnv } from './env';
import { ApiError, Errors } from './lib/errors';
import { assertProductionEnv } from './lib/env_guard';
import { log } from './lib/logger';
import { accessLogMiddleware, requestIdMiddleware } from './middleware/request-id';
import { adminRoutes } from './routes/admin';
import { authRoutes } from './routes/auth';
import { mapsRoutes } from './routes/maps';
import { meRoutes } from './routes/me';
import { orderRoutes } from './routes/orders';
import { blockRoutes, reportRoutes } from './routes/safety';
import { trips } from './routes/trips';

const app = new Hono<AppEnv>();

// --- Middleware toàn cục ---
app.use('*', async (c, next) => {
  assertProductionEnv(c.env); // plan2_final §7.1 — no-op trừ khi APP_ENV=production
  await next();
});
app.use('*', requestIdMiddleware);
app.use('*', accessLogMiddleware);

// --- Health check ---
app.get('/health', (c) => {
  return c.json({ ok: true, env: c.env.APP_ENV, time: new Date().toISOString() });
});

// --- Routes ---
app.route('/auth', authRoutes);
app.route('/maps', mapsRoutes);
app.route('/me', meRoutes);
app.route('/orders', orderRoutes);
app.route('/trips', trips);
app.route('/reports', reportRoutes);
app.route('/blocks', blockRoutes);
app.route('/admin', adminRoutes);

// --- Unified error handling (plan §26: mọi lỗi đều có envelope JSON) ---
app.onError((err, c) => {
  const requestId = c.get('requestId');
  if (err instanceof ApiError) {
    if (err.status >= 500) {
      log('error', 'api_error', { requestId, code: err.code, message: err.message });
    } else {
      log('info', 'api_error', { requestId, code: err.code, status: err.status });
    }
    return c.json(
      { error: { code: err.code, message: err.message, status: err.status } },
      err.status as ContentfulStatusCode,
    );
  }
  const wrapped = Errors.internal();
  log('error', 'unhandled_error', {
    requestId,
    error: err instanceof Error ? err.message : String(err),
    stack: err instanceof Error ? err.stack : undefined,
  });
  return c.json(
    { error: { code: wrapped.code, message: wrapped.message, status: wrapped.status } },
    wrapped.status as ContentfulStatusCode,
  );
});

app.notFound((c) => {
  return c.json(
    { error: { code: 'NOT_FOUND', message: 'Endpoint không tồn tại', status: 404 } },
    404,
  );
});

export default app;
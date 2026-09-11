import { Hono } from 'hono';
import type { AppEnv } from '../env';
import { Errors } from '../lib/errors';
import { log } from '../lib/logger';
import { authMiddleware } from '../middleware/auth';
import { atomicAccept } from '../services/accept';
import { contactDriverToCustomer } from '../services/contacts';
import { driverDistanceForOrder } from '../services/gps';
import { requireLegalConsent, requireRole } from '../services/authorization';
import { transitionOrder } from '../services/lifecycle';
import { enforceRateLimit } from '../services/rate_limit';
import { assertOrderViewAccess, createOrderChecked } from '../services/orders';
import {
  cancelOrder,
  createOrder,
  enforceActiveOrderLimit,
  enforcePostRateLimit,
  getOrderById,
  listOrdersByCustomer,
  updateOrder,
  validateOrderInput,
  type OrderInput,
} from '../services/orders';

/**
 * /orders (Phase 2 — Marketplace, plan §25).
 * P0: customer tạo/lấy/sửa/hủy đơn của chính mình.
 * Driver xem mối hàng qua matching (Phase 3), không browse toàn bộ ở P0.
 */
export const orderRoutes = new Hono<AppEnv>();

orderRoutes.use('*', authMiddleware);

// plan2_final §1.1: chỉ customer được tạo đơn — driver bypass UI bằng API bị chặn.
// plan2_final §1.4: legal consent enforce server-side (client checkbox chỉ là UX).
// plan2_final §3.3/§3.4: rate limit + active-order limit ATOMIC (D1), không KV GET/PUT.
orderRoutes.post('/', async (c) => {
  requireRole(c.get('userRole'), 'customer');
  await requireLegalConsent(c.env.DB, c.get('userId'));
  const body = await c.req.json().catch(() => null);
  const input = validateOrderInput(body) as OrderInput;
  await enforceRateLimit(c.env.DB, `postrl:${c.get('userId')}`, 10, 3600, 'POST_RATE_LIMITED',
    'Bạn đã tạo quá nhiều đơn hàng trong thời gian ngắn, vui lòng thử lại sau');
  const order = await createOrderChecked(c.env.DB, c.get('userId'), input, 5);
  log('info', 'order_created', { requestId: c.get('requestId'), orderId: order.id });
  return c.json({ order }, 201);
});

orderRoutes.get('/', async (c) => {
  const orders = await listOrdersByCustomer(c.env.DB, c.get('userId'));
  return c.json({ orders });
});

// plan2_final §1.2: chỉ chủ đơn / tài xế được gán / tài xế đã liên hệ / admin được xem.
orderRoutes.get('/:id', async (c) => {
  const order = await getOrderById(c.env.DB, c.req.param('id'));
  if (!order) {
    throw Errors.notFound('ORDER_NOT_FOUND', 'Không tìm thấy đơn hàng');
  }
  await assertOrderViewAccess(c.env.DB, order, c.get('userId'), c.get('userRole'));
  return c.json({ order });
});

orderRoutes.patch('/:id', async (c) => {
  const body = await c.req.json().catch(() => null);
  const input = validateOrderInput(body, { partial: true });
  const order = await updateOrder(c.env.DB, c.req.param('id'), c.get('userId'), input);
  return c.json({ order });
});

// POST /orders/:id/cancel — customer hủy (plan2_final §2.3, state machine §9)
// plan2_final §2.4: chỉ customer (chủ đơn) cancel — driver cancel là P1.
// Ownership check trong transitionOrder (customer_id !== actorId → 404).
orderRoutes.post('/:id/cancel', async (c) => {
  requireRole(c.get('userRole'), 'customer');
  const result = await transitionOrder(c.env, 'cancel', c.req.param('id'), c.get('userId'), c.req.header('CF-Connecting-IP') ?? '');
  return c.json({ order: result.order });
});

// POST /orders/:id/contact — driver liên hệ chủ hàng (Phase 5, plan §17)
// plan2_final §1.1: chỉ driver đủ điều kiện; §1.3: check eligibility trước khi cấp phone.
orderRoutes.post('/:id/contact', async (c) => {
  requireRole(c.get('userRole'), 'driver');
  const ip = c.req.header('CF-Connecting-IP') ?? '';
  const result = await contactDriverToCustomer(
    c.env,
    c.get('userId'),
    c.req.param('id'),
    ip,
  );
  log('info', 'order_contacted', {
    requestId: c.get('requestId'),
    orderId: result.order_id,
    driverId: c.get('userId'),
  });
  return c.json({ data: result });
});

// POST /orders/:id/accept — Atomic Accept (Phase 5, plan §10)
orderRoutes.post('/:id/accept', async (c) => {
  requireRole(c.get('userRole'), 'driver');
  const ip = c.req.header('CF-Connecting-IP') ?? '';
  const result = await atomicAccept(c.env, c.get('userId'), c.req.param('id'), ip);
  log('info', 'order_accepted', {
    requestId: c.get('requestId'),
    orderId: c.req.param('id'),
    driverId: c.get('userId'),
  });
  return c.json({ data: result });
});

// GET /orders/:id/driver-location — khoảng cách ẩn danh (privacy §13),
// chỉ chủ hàng của đơn đã accept thấy; KHÔNG trả tọa độ chính xác.
orderRoutes.get('/:id/driver-location', async (c) => {
  const result = await driverDistanceForOrder(
    c.env,
    c.req.param('id'),
    c.get('userId'),
  );
  return c.json({ data: result });
});

// ---- Order Lifecycle (plan2_final §2.3/§2.4) ----
// POST /orders/:id/pickup — driver xác nhận đã đến lấy hàng (accepted → pickup)
orderRoutes.post('/:id/pickup', async (c) => {
  requireRole(c.get('userRole'), 'driver');
  const result = await transitionOrder(c.env, 'pickup', c.req.param('id'), c.get('userId'), c.req.header('CF-Connecting-IP') ?? '');
  return c.json({ data: { order: result.order, status: result.status } });
});

// POST /orders/:id/in-transit — driver bắt đầu vận chuyển (pickup → in_transit)
orderRoutes.post('/:id/in-transit', async (c) => {
  requireRole(c.get('userRole'), 'driver');
  const result = await transitionOrder(c.env, 'in_transit', c.req.param('id'), c.get('userId'), c.req.header('CF-Connecting-IP') ?? '');
  return c.json({ data: { order: result.order, status: result.status } });
});

// POST /orders/:id/delivered — driver giao hàng (in_transit → delivered)
orderRoutes.post('/:id/delivered', async (c) => {
  requireRole(c.get('userRole'), 'driver');
  const result = await transitionOrder(c.env, 'delivered', c.req.param('id'), c.get('userId'), c.req.header('CF-Connecting-IP') ?? '');
  return c.json({ data: { order: result.order, status: result.status } });
});

// POST /orders/:id/complete — customer xác nhận hoàn thành (delivered → completed)
orderRoutes.post('/:id/complete', async (c) => {
  requireRole(c.get('userRole'), 'customer');
  const result = await transitionOrder(c.env, 'complete', c.req.param('id'), c.get('userId'), c.req.header('CF-Connecting-IP') ?? '');
  return c.json({ data: { order: result.order, status: result.status } });
});
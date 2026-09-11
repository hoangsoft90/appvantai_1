/**
 * Routing resilience (plan2_final §5.2) — timeout + simple circuit breaker.
 *
 * Circuit breaker: nếu provider liên tục lỗi (≥ OPEN_THRESHOLD lỗi liên tiếp),
 * OPEN mạch trong COOLDOWN_MS → mọi call fail ngay (fail-fast) thay vì chờ
 * timeout 10s mỗi request. Sau cooldown → HALF-OPEN cho 1 request thử lại.
 * Provider failure KHÔNG corrupt business data — caller (matching) đã có
 * fallback bỏ qua detour khi route() throw.
 */

const OPEN_THRESHOLD = 3; // 3 lỗi liên tiếp → OPEN
const COOLDOWN_MS = 30_000; // 30s trước khi thử lại

interface BreakerState {
  consecutiveFailures: number;
  openedAt: number | null;
}

const breaker: BreakerState = { consecutiveFailures: 0, openedAt: null };

function isOpen(): boolean {
  if (breaker.openedAt === null) return false;
  if (Date.now() - breaker.openedAt >= COOLDOWN_MS) {
    // Cooldown hết → HALF-OPEN: cho thử lại
    breaker.openedAt = null;
    breaker.consecutiveFailures = OPEN_THRESHOLD - 1; // 1 lỗi nữa sẽ OPEN lại
    return false;
  }
  return true;
}

/** Bọc 1 async operation với timeout riêng + circuit breaker. */
export async function withResilience<T>(
  op: (timeoutMs: number) => Promise<T>,
  timeoutMs = 10_000,
): Promise<T> {
  if (isOpen()) {
    throw new Error('ROUTING_BREAKER_OPEN');
  }
  try {
    const result = await op(timeoutMs);
    breaker.consecutiveFailures = 0; // thành công → reset
    breaker.openedAt = null;
    return result;
  } catch (e) {
    breaker.consecutiveFailures += 1;
    if (breaker.consecutiveFailures >= OPEN_THRESHOLD) {
      breaker.openedAt = Date.now();
    }
    throw e;
  }
}

/** Tạo AbortController với timeout (dùng trong osrm/nominatim). */
export function makeTimeoutSignal(timeoutMs: number): {
  signal: AbortSignal;
  done: () => void;
} {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  return { signal: controller.signal, done: () => clearTimeout(timer) };
}

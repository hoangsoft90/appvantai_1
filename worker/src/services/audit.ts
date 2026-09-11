import type { Env } from '../env';

/**
 * Audit log (plan §18, §11): ghi lại hành động quan trọng kèm actor + IP.
 * Dùng cho:
 *  - Legal disclaimer tick (bằng chứng pháp lý — thời gian + IP)
 *  - Accept / Contact / Report / Block
 *  - Admin moderation (suspend/ban)
 *
 * Lưu ý 0đ cost: mỗi lần ghi là 1 D1 write. Chỉ ghi hành động quan trọng,
 * không ghi mọi request (access log đã có qua middleware, không vào D1).
 */
export async function writeAuditLog(
  env: Env,
  input: {
    actorId: string | null;
    entityType: string;
    entityId?: string;
    action: string;
    metadata?: Record<string, unknown>;
    ip?: string;
  },
): Promise<void> {
  try {
    await env.DB.prepare(
      `INSERT INTO audit_logs (id, actor_id, entity_type, entity_id, action, metadata, ip)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
    )
      .bind(
        crypto.randomUUID(),
        input.actorId,
        input.entityType,
        input.entityId ?? null,
        input.action,
        JSON.stringify(input.metadata ?? {}),
        input.ip ?? '',
      )
      .run();
  } catch (e) {
    // Audit không được phép làm hỏng luồng chính — log lỗi và tiếp tục.
    console.error('audit_log_failed', e);
  }
}
import { Errors } from '../lib/errors';

/**
 * OTP service (Phase 0 — dev provider).
 *
 * Lưu OTP vào KV (không phải D1) vì:
 *  - OTP là dữ liệu session ngắn hạn, không cần lịch sử
 *  - Tiết kiệm D1 writes quota (plan §13: D1 giới hạn 100k writes/ngày)
 *
 * Provider abstraction: khi gắn Firebase Phone Auth / Zalo (plan §16),
 * chỉ cần thay hàm này — requestOtp/verifyOtp vẫn giữ chữ ký, API không đổi.
 */

const OTP_TTL_SECONDS = 300; // 5 phút
const OTP_RATE_LIMIT = 5; // tối đa 5 lần request OTP
const OTP_RATE_WINDOW_SECONDS = 900; // trong 15 phút
const OTP_CODE_LENGTH = 6;

export function generateOtpCode(): string {
  const n = Math.floor(Math.random() * 10 ** OTP_CODE_LENGTH);
  return String(n).padStart(OTP_CODE_LENGTH, '0');
}

export async function requestOtp(kv: KVNamespace, phone: string): Promise<string> {
  // Rate limit theo số điện thoại (anti-spam, plan §19)
  const rlKey = `otprl:${phone}`;
  const count = Number((await kv.get(rlKey)) ?? '0');
  if (count >= OTP_RATE_LIMIT) {
    throw Errors.tooManyRequests();
  }
  await kv.put(rlKey, String(count + 1), { expirationTtl: OTP_RATE_WINDOW_SECONDS });

  const code = generateOtpCode();
  await kv.put(`otp:${phone}`, JSON.stringify({ code }), { expirationTtl: OTP_TTL_SECONDS });
  // Provider thật sẽ gửi SMS tại đây. Route chỉ echo code về client khi ALLOW_DEV_OTP=true.
  return code;
}

export async function verifyOtp(kv: KVNamespace, phone: string, code: string): Promise<void> {
  const raw = await kv.get(`otp:${phone}`);
  if (!raw) {
    throw Errors.badRequest('INVALID_OTP', 'Mã OTP không đúng hoặc đã hết hạn');
  }
  let expected: string;
  try {
    expected = (JSON.parse(raw) as { code: string }).code;
  } catch {
    await kv.delete(`otp:${phone}`);
    throw Errors.badRequest('INVALID_OTP', 'Mã OTP không đúng hoặc đã hết hạn');
  }
  if (expected !== code) {
    throw Errors.badRequest('INVALID_OTP', 'Mã OTP không đúng hoặc đã hết hạn');
  }
  // OTP dùng 1 lần: xóa ngay sau khi verify thành công
  await kv.delete(`otp:${phone}`);
}
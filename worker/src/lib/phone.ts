/**
 * Chuẩn hóa số điện thoại Việt Nam về dạng 0xxxxxxxxx (10 chữ số).
 * Chấp nhận: 0912345678, +84912345678, 84912345678, có space/dash.
 * Trả về null nếu không hợp lệ.
 */
export function normalizePhone(raw: string): string | null {
  let p = String(raw ?? '').trim().replace(/[\s-]/g, '');
  if (p.startsWith('+')) p = p.slice(1);
  if (p.startsWith('84')) p = '0' + p.slice(2);
  if (!/^0(3|5|7|8|9)\d{8}$/.test(p)) return null;
  return p;
}
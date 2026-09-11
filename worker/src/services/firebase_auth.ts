import { Errors } from '../lib/errors';

/**
 * Firebase Phone Auth — verify ID token server-side (phase7 §7.1).
 *
 * KHÔNG dùng firebase-admin SDK (không tương thích Workers runtime).
 * Thay thế: tự verify RS256 bằng WebCrypto + public key Google:
 *  1. Fetch JWKs công khai: https://www.googleapis.com/service_accounts/v1/jwk/
 *     securetoken@system.gserviceaccount.com (cache in-memory theo TTL)
 *  2. Verify signature (crypto.subtle.verify RS256)
 *  3. Validate claims theo docs Google:
 *     - exp > now, iat <= now (skew 5 phút)
 *     - aud === FIREBASE_PROJECT_ID
 *     - iss === https://securetoken.google.com/<PROJECT_ID>
 *     - sub (uid) là string non-empty
 *  4. Lấy phone_number (E.164) từ payload — Phone Auth luôn gắn claim này.
 *
 * FIREBASE_JWKS_URL: CHỈ dùng cho test (trỏ JWKS local để test signature).
 * Production KHÔNG BAO GIỜ set var này — env_guard sẽ log ERROR nếu phát hiện.
 */

const GOOGLE_JWKS_URL =
  'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com';

const JWKS_CACHE_TTL_MS = 60 * 60 * 1000; // 1 giờ
const CLOCK_SKEW_SECONDS = 300; // 5 phút

interface Jwk {
  kty: string;
  kid: string;
  n: string;
  e: string;
  alg?: string;
  use?: string;
}

interface Jwks {
  keys: Jwk[];
}

export interface FirebaseTokenPayload {
  uid: string;
  phone: string;
}

// --- In-memory JWKS cache (mỗi isolate) ---
let cachedJwks: { keys: Jwk[]; fetchedAt: number } | null = null;

async function fetchJwks(url: string): Promise<Jwk[]> {
  if (cachedJwks && Date.now() - cachedJwks.fetchedAt < JWKS_CACHE_TTL_MS) {
    return cachedJwks.keys;
  }
  const res = await fetch(url, { cf: { cacheTtl: 3600, cacheEverything: true } });
  if (!res.ok) {
    throw Errors.internal('Không tải được public key Firebase (JWKS)');
  }
  const jwks = (await res.json()) as Jwks;
  if (!Array.isArray(jwks.keys) || jwks.keys.length === 0) {
    throw Errors.internal('JWKS Firebase không hợp lệ');
  }
  cachedJwks = { keys: jwks.keys, fetchedAt: Date.now() };
  return jwks.keys;
}

function base64UrlDecode(segment: string): Uint8Array {
  const b64 = segment.replace(/-/g, '+').replace(/_/g, '/');
  const padded = b64 + '='.repeat((4 - (b64.length % 4)) % 4);
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

async function importVerifyKey(jwk: Jwk): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    'jwk',
    { kty: jwk.kty, n: jwk.n, e: jwk.e, alg: 'RS256', ext: true },
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['verify'],
  );
}

/**
 * Verify Firebase ID token. Ném 401 INVALID_ID_TOKEN khi token sai/hết hạn.
 * Trả về { uid, phone } khi hợp lệ.
 */
export async function verifyFirebaseIdToken(
  token: string,
  opts: { projectId: string; jwksUrl?: string },
): Promise<FirebaseTokenPayload> {
  const parts = token.split('.');
  if (parts.length !== 3) {
    throw Errors.unauthorized('INVALID_ID_TOKEN', 'ID token Firebase không hợp lệ');
  }
  let header: { kid?: string; alg?: string };
  let payload: Record<string, unknown>;
  try {
    header = JSON.parse(new TextDecoder().decode(base64UrlDecode(parts[0]))) as typeof header;
    payload = JSON.parse(new TextDecoder().decode(base64UrlDecode(parts[1]))) as typeof payload;
  } catch {
    throw Errors.unauthorized('INVALID_ID_TOKEN', 'ID token Firebase không giải mã được');
  }
  if (header.alg !== 'RS256' || !header.kid) {
    throw Errors.unauthorized('INVALID_ID_TOKEN', 'ID token Firebase sai thuật toán/thiếu kid');
  }

  const keys = await fetchJwks(opts.jwksUrl ?? GOOGLE_JWKS_URL);
  const jwk = keys.find((k) => k.kid === header.kid);
  if (!jwk) {
    throw Errors.unauthorized('INVALID_ID_TOKEN', 'ID token Firebase ký bởi key không rõ nguồn');
  }

  const key = await importVerifyKey(jwk);
  const valid = await crypto.subtle.verify(
    'RSASSA-PKCS1-v1_5',
    key,
    base64UrlDecode(parts[2]) as BufferSource,
    new TextEncoder().encode(`${parts[0]}.${parts[1]}`),
  );
  if (!valid) {
    throw Errors.unauthorized('INVALID_ID_TOKEN', 'Chữ ký ID token Firebase không hợp lệ');
  }

  // --- Claims validation (docs.google.com/documents/d/1y8yPSYi1vIXUKO_tM6QHScBkURYAoNc73RTJmlih7zc) ---
  // fix_p7_1.md #5: exp KHÔNG được nới bởi clock-skew — token hết hạn 1 giây
  // trước là hết hạn (401). Skew chỉ áp dụng cho iat/nbf (timestamp phía emitter).
  const now = Math.floor(Date.now() / 1000);
  const exp = Number(payload.exp);
  const iat = Number(payload.iat);
  const aud = payload.aud;
  const iss = payload.iss;
  const sub = payload.sub;
  const phone = typeof payload.phone_number === 'string' ? payload.phone_number : '';
  const expectedIss = `https://securetoken.google.com/${opts.projectId}`;

  if (!Number.isFinite(exp) || exp <= now) {
    throw Errors.unauthorized('INVALID_ID_TOKEN', 'ID token Firebase đã hết hạn');
  }
  if (Number.isFinite(iat) && iat > now + CLOCK_SKEW_SECONDS) {
    throw Errors.unauthorized('INVALID_ID_TOKEN', 'ID token Firebase có iat trong tương lai');
  }
  // fix_p7_1.md #5 — nbf (nếu có): sau skew, không trước now - skew.
  const nbf = Number(payload.nbf);
  if (Number.isFinite(nbf) && nbf > now + CLOCK_SKEW_SECONDS) {
    throw Errors.unauthorized('INVALID_ID_TOKEN', 'ID token Firebase chưa có hiệu lực');
  }
  if (aud !== opts.projectId || iss !== expectedIss) {
    throw Errors.unauthorized('INVALID_ID_TOKEN', 'ID token Firebase không thuộc project này');
  }
  if (typeof sub !== 'string' || sub.length === 0 || sub.length > 128) {
    throw Errors.unauthorized('INVALID_ID_TOKEN', 'ID token Firebase thiếu uid');
  }
  if (!phone) {
    throw Errors.unauthorized('INVALID_ID_TOKEN', 'ID token Firebase thiếu phone_number');
  }

  return { uid: sub, phone };
}

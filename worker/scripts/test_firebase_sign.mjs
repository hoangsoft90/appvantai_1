// Helper test cho Phase 7 Mục 2 — mô phỏng Firebase ID token KHÔNG cần project thật.
// Dùng RSA keypair local + JWKS server localhost; Worker verify qua FIREBASE_JWKS_URL.
// KHÔNG dùng ở production — chỉ phục vụ e2e_phase7_m2.sh (env_guard cấm JWKS_URL ở prod).
//
// Cách dùng:
//   node scripts/test_firebase_sign.mjs setup            → tạo keypair + JWKS, in kid
//   node scripts/test_firebase_sign.mjs token <aud> <iss> <exp> <phone> [sub]
//   node scripts/test_firebase_sign.mjs serve [port]     → JWKS server (mặc định 8788)
//
// State (keypair + kid) lưu /tmp/p7_fb_key.json giữa các lần gọi.

import { generateKeyPairSync, createSign, createHash } from 'node:crypto';
import { readFileSync, writeFileSync, existsSync } from 'node:fs';

const KEY_FILE = '/tmp/p7_fb_key.json';

function ensureKeys() {
  if (existsSync(KEY_FILE)) return JSON.parse(readFileSync(KEY_FILE, 'utf8'));
  const { publicKey, privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
  const kid = createHash('sha256').update(publicKey.export({ type: 'spki', format: 'der' })).digest('base64url');
  const state = {
    kid,
    private_pem: privateKey.export({ type: 'pkcs1', format: 'pem' }).toString(),
    n: publicKey.export({ type: 'spki', format: 'jwk' }).n,
    e: publicKey.export({ type: 'spki', format: 'jwk' }).e,
  };
  writeFileSync(KEY_FILE, JSON.stringify(state));
  return state;
}

function b64url(buf) {
  return Buffer.from(buf).toString('base64url');
}

function signToken(state, { aud, iss, exp, phone, sub }) {
  const header = b64url(JSON.stringify({ alg: 'RS256', kid: state.kid, typ: 'JWT' }));
  const payload = b64url(JSON.stringify({
    aud, iss, sub, phone_number: phone,
    exp, iat: Math.floor(Date.now() / 1000),
    firebase: { sign_in_provider: 'phone' },
  }));
  const signer = createSign('RSA-SHA256');
  signer.update(`${header}.${payload}`);
  const sig = signer.sign(state.private_pem, 'base64url');
  return `${header}.${payload}.${sig}`;
}

const [cmd, ...args] = process.argv.slice(2);

if (cmd === 'setup') {
  const s = ensureKeys();
  console.log(s.kid);
} else if (cmd === 'token') {
  const [aud, iss, exp, phone, sub = 'test-fb-uid-' + Date.now()] = args;
  if (!aud || !iss || !exp || !phone) {
    console.error('usage: token <aud> <iss> <exp> <phone> [sub]');
    process.exit(1);
  }
  console.log(signToken(ensureKeys(), { aud, iss, exp: Number(exp), phone, sub }));
} else if (cmd === 'serve') {
  const port = Number(args[0] ?? 8788);
  const s = ensureKeys();
  const jwks = { keys: [{ kty: 'RSA', kid: s.kid, n: s.n, e: s.e, alg: 'RS256', use: 'sig' }] };
  const { createServer } = await import('node:http');
  const server = createServer((_, res) => {
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify(jwks));
  });
  server.listen(port); // bind cả :: và 127.0.0.1 (workerd có thể resolve localhost → ::1)
  console.log(`JWKS test server on :${port}`);
  process.on('SIGTERM', () => server.close());
} else {
  console.error('usage: setup | token <aud> <iss> <exp> <phone> [sub] | serve [port]');
  process.exit(1);
}

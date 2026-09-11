#!/usr/bin/env node
/**
 * Predeploy check (fix_p7_1.md #1) — chạy TRƯỚC `wrangler deploy --env production`.
 *
 * Đọc wrangler.toml scope [env.production] và chặn (exit 1) khi:
 *  - D1/KV còn placeholder REPLACE_WITH_REAL_*_ID
 *  - ALLOW_DEV_OTP=true trong [env.production.vars]
 *  - có JWT_SECRET trong [env.production.vars] (secret phải đặt bằng
 *    `wrangler secret put JWT_SECRET --env production`, không commit vào repo)
 *
 * Cách chạy: node scripts/verify_deploy_config.mjs  (npm run verify:deploy)
 * Lưu ý: check tĩnh — JWT_SECRET có tồn tại trên Cloudflare hay không phải xem
 * trên dashboard/`wrangler secret list`; runtime guard (env_guard.ts) là lớp
 * chặn cuối với 503 PRODUCTION_MISCONFIGURED.
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const toml = readFileSync(join(here, '..', 'wrangler.toml'), 'utf8');

// Cắt scope [env.production] (từ dòng [env.production] tới EOF — các block
// [[env.production.*]] và [env.production.vars] đều nằm trong khoảng này).
const start = toml.indexOf('[env.production]');
const scope = start >= 0 ? toml.slice(start) : '';
const problems = [];

const check = (label, re, line) => {
  const m = line.match(re);
  if (!m) problems.push(`${label}: không tìm thấy trong [env.production]`);
  return m?.[1]?.trim() ?? '';
};

if (!scope) {
  console.error('FAIL: không tìm thấy [env.production] trong wrangler.toml');
  process.exit(1);
}

const d1Line = scope.split('\n').find((l) => l.includes('database_id')) ?? '';
const d1Id = check('D1 database_id', /database_id\s*=\s*"([^"]*)"/, d1Line);
if (!d1Id || d1Id.startsWith('REPLACE_') || d1Id === '00000000-0000-0000-0000-000000000000') {
  problems.push(`D1 database_id chưa là id production thật: "${d1Id}" — chạy \`wrangler d1 create appvantai\` rồi điền vào wrangler.toml`);
}

// KV: lấy id trong block [[env.production.kv_namespaces]] (đơn giản, tránh precedence ??/&&)
const kvBlock = scope.slice(scope.indexOf('[[env.production.kv_namespaces]]'));
const kvId = (kvBlock.match(/id\s*=\s*"([^"]*)"/) ?? [])[1] ?? '';
if (!kvId || kvId.startsWith('REPLACE_') || kvId === '00000000-0000-0000-0000-000000000000') {
  problems.push(`KV namespace id chưa là id production thật: "${kvId}" — chạy \`wrangler kv namespace create APP_KV\` rồi điền vào wrangler.toml`);
}

const varsScope = scope.slice(scope.indexOf('[env.production.vars]'));
const allowDev = (varsScope.match(/ALLOW_DEV_OTP\s*=\s*"([^"]*)"/) ?? [])[1];
if (allowDev !== 'false') {
  problems.push(`ALLOW_DEV_OTP phải là "false" ở production (thấy: "${allowDev}")`);
}
if (/JWT_SECRET\s*=/.test(varsScope)) {
  problems.push('JWT_SECRET không được nằm trong [env.production.vars] — dùng `wrangler secret put JWT_SECRET --env production`');
}

if (problems.length > 0) {
  console.error('✗ CHƯA ĐỦ ĐIỀU KIỆN DEPLOY PRODUCTION:');
  for (const p of problems) console.error(`  - ${p}`);
  process.exit(1);
}
console.log('✓ [env.production] đủ điều kiện deploy: D1/KV id thật, ALLOW_DEV_OTP=false, JWT_SECRET qua secret.');
console.log('  (Kiểm tra secret đã tồn tại: `wrangler secret list --env production`)');

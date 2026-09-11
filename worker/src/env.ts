export interface Env {
  DB: D1Database;
  APP_KV: KVNamespace;
  JWT_SECRET: string;
  /** "true" khi cho phép trả OTP trong response (dev only) */
  ALLOW_DEV_OTP: string;
  APP_ENV: string;
  /** Maps provider: "osrm" (default) | "mock" — plan §14 */
  MAPS_PROVIDER: string;
  /** Phase 7 §7.1 — Firebase Phone Auth: project id để verify ID token (aud/iss) */
  FIREBASE_PROJECT_ID?: string;
  /** CHỈ cho test: override JWKS URL. Production KHÔNG BAO GIỜ set (env_guard log ERROR) */
  FIREBASE_JWKS_URL?: string;
}

export type Variables = {
  userId: string;
  userRole: string;
  requestId: string;
};

export type AppEnv = { Bindings: Env; Variables: Variables };
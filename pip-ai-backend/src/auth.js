// Verifies a Firebase Auth ID token with the Web Crypto API, so only people
// signed in to FocusForge can spend the AI quota. No SDK is needed: an ID
// token is an RS256 JWT signed by Google's secure-token service.
//
// https://firebase.google.com/docs/auth/admin/verify-id-tokens#verify_id_tokens_using_a_third-party_jwt_library

export const JWKS_URL =
  'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com';

/** Seconds of clock difference tolerated between Google and the worker. */
const SKEW = 60;

/** Why a token was refused. Never shown to the user. */
export class AuthError extends Error {}

/**
 * Least time between signing-key downloads made for an unknown key ID.
 * Google publishes a new key hours before signing with it, so a kid the
 * cache has never seen right after a download is a forged one, and a
 * stream of them must not turn into a stream of downloads.
 */
export const REFRESH_COOLDOWN_MS = 60 * 1000;

let cachedKeys = null;
let cachedUntil = 0;
let fetchedAt = -Infinity;
let inFlight = null;

/** Clears the signing-key cache. For tests. */
export function resetKeyCache() {
  cachedKeys = null;
  cachedUntil = 0;
  fetchedAt = -Infinity;
  inFlight = null;
}

async function downloadKeys(fetchImpl, nowMs) {
  const response = await fetchImpl(JWKS_URL, {redirect: 'error', signal: AbortSignal.timeout(5000)});
  if (!response.ok) throw new AuthError(`signing keys: HTTP ${response.status}`);
  const body = await response.json();
  if (!Array.isArray(body?.keys)) throw new AuthError('signing keys: bad body');
  const maxAge = /max-age=(\d+)/.exec(response.headers.get('cache-control') ?? '');
  cachedKeys = new Map(body.keys.map((key) => [key.kid, key]));
  cachedUntil = nowMs + Math.min(Number(maxAge?.[1] ?? 3600), 6 * 3600) * 1000;
  return cachedKeys;
}

/**
 * The signing keys, downloaded when the cache has expired, or when
 * [refresh] asks and none was downloaded in the last [REFRESH_COOLDOWN_MS].
 * Requests arriving while a download runs share it.
 */
async function signingKeys(fetchImpl, nowMs, refresh) {
  const stale = !cachedKeys || nowMs >= cachedUntil;
  if (!stale && !(refresh && nowMs - fetchedAt >= REFRESH_COOLDOWN_MS)) return cachedKeys;
  if (!inFlight) {
    fetchedAt = nowMs;
    inFlight = downloadKeys(fetchImpl, nowMs).finally(() => {
      inFlight = null;
    });
  }
  return inFlight;
}

function base64UrlBytes(segment) {
  const base64 = segment.replace(/-/g, '+').replace(/_/g, '/');
  const binary = atob(base64 + '='.repeat((4 - (base64.length % 4)) % 4));
  return Uint8Array.from(binary, (char) => char.charCodeAt(0));
}

function base64UrlJson(segment) {
  try {
    return JSON.parse(new TextDecoder().decode(base64UrlBytes(segment)));
  } catch {
    throw new AuthError('malformed token');
  }
}

/**
 * Checks [token] for Firebase project [projectId] and returns `{uid}`.
 * Throws [AuthError] for anything that is not a live, verified, non-guest
 * sign-in of that project.
 */
export async function verifyIdToken(token, projectId, {fetchImpl = fetch, nowMs = Date.now()} = {}) {
  if (typeof token !== 'string' || token.length > 4096) throw new AuthError('no token');
  const parts = token.split('.');
  if (parts.length !== 3) throw new AuthError('malformed token');
  const header = base64UrlJson(parts[0]);
  const claims = base64UrlJson(parts[1]);

  if (header?.alg !== 'RS256' || typeof header.kid !== 'string') throw new AuthError('wrong algorithm');
  const now = Math.floor(nowMs / 1000);
  if (claims?.aud !== projectId) throw new AuthError('wrong audience');
  if (claims.iss !== `https://securetoken.google.com/${projectId}`) throw new AuthError('wrong issuer');
  if (typeof claims.sub !== 'string' || !claims.sub || claims.sub.length > 128) {
    throw new AuthError('no subject');
  }
  if (!Number.isFinite(claims.exp) || claims.exp <= now - SKEW) throw new AuthError('expired');
  if (!Number.isFinite(claims.iat) || claims.iat > now + SKEW) throw new AuthError('issued in the future');
  if (Number.isFinite(claims.auth_time) && claims.auth_time > now + SKEW) {
    throw new AuthError('signed in in the future');
  }
  // FocusForge guests stay on the device and never hold a Firebase account,
  // so an anonymous token can only come from outside the app. Email
  // accounts must be verified, as the app itself requires.
  const provider = claims.firebase?.sign_in_provider;
  if (provider === 'anonymous') throw new AuthError('anonymous');
  if (provider === 'password' && claims.email_verified !== true) throw new AuthError('unverified email');

  let jwk = (await signingKeys(fetchImpl, nowMs, false)).get(header.kid);
  // Google rotates keys; an unknown kid may be a key newer than the cache.
  jwk ??= (await signingKeys(fetchImpl, nowMs, true)).get(header.kid);
  if (!jwk) throw new AuthError('unknown key');

  const key = await crypto.subtle.importKey(
    'jwk',
    {kty: jwk.kty, n: jwk.n, e: jwk.e, alg: 'RS256', ext: true},
    {name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256'},
    false,
    ['verify'],
  );
  const valid = await crypto.subtle.verify(
    'RSASSA-PKCS1-v1_5',
    key,
    base64UrlBytes(parts[2]),
    new TextEncoder().encode(`${parts[0]}.${parts[1]}`),
  );
  if (!valid) throw new AuthError('bad signature');
  return {uid: claims.sub};
}

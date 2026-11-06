// Test helpers: a throwaway RS256 key standing in for Google's signer, and
// tokens shaped like Firebase ID tokens.
import {JWKS_URL} from '../src/auth.js';

export const PROJECT = 'focusforge-1edf7';
export const KID = 'test-key';

const encoder = new TextEncoder();

function base64Url(bytes) {
  return Buffer.from(bytes).toString('base64url');
}

export async function makeSigner() {
  const pair = await crypto.subtle.generateKey(
    {name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256'},
    true,
    ['sign', 'verify'],
  );
  const publicJwk = await crypto.subtle.exportKey('jwk', pair.publicKey);
  return {
    jwks: {keys: [{...publicJwk, kid: KID, alg: 'RS256', use: 'sig'}]},
    /** A token for [claims] over sensible defaults, signed by this key. */
    async token(claims = {}, header = {}) {
      const now = Math.floor(Date.now() / 1000);
      const body = {
        iss: `https://securetoken.google.com/${PROJECT}`,
        aud: PROJECT,
        sub: 'user-123',
        iat: now - 10,
        exp: now + 3600,
        auth_time: now - 10,
        email_verified: true,
        firebase: {sign_in_provider: 'google.com'},
        ...claims,
      };
      const head = base64Url(encoder.encode(JSON.stringify({alg: 'RS256', kid: KID, typ: 'JWT', ...header})));
      const payload = base64Url(encoder.encode(JSON.stringify(body)));
      const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', pair.privateKey, encoder.encode(`${head}.${payload}`));
      return `${head}.${payload}.${base64Url(new Uint8Array(signature))}`;
    },
  };
}

/**
 * A fetch that serves the signing keys and hands any other URL to
 * [route], recording every call.
 */
export function fakeFetch(jwks, route = () => new Response('not found', {status: 404})) {
  const calls = [];
  const impl = async (url, init = {}) => {
    calls.push({url: String(url), init});
    if (String(url) === JWKS_URL) {
      return new Response(JSON.stringify(jwks), {headers: {'cache-control': 'public, max-age=3600'}});
    }
    return route(String(url), init);
  };
  impl.calls = calls;
  return impl;
}

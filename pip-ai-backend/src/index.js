// Pip's AI proxy: a Cloudflare Worker between the FocusForge app and the
// model providers. The app sends a Firebase ID token and one question; the
// worker checks the token, bounds the request, holds each user to a rate
// limit and asks Gemini, falling back to Groq when Gemini is down or out of
// quota. The provider keys live only in Worker secrets.
//
// POST /  Authorization: Bearer <Firebase ID token>
//   {message, locale?, context?, history?}
// 200 {reply, provider}
// 4xx/5xx {error, window?} where error is a Firebase-style code the app maps.

import {AuthError, verifyIdToken} from './auth.js';
import {drainResetEmails} from './reset-delivery.js';
import {
  InputError,
  isInstructionAttack,
  LIMITS,
  buildGeminiRequest,
  buildGroqRequest,
  parseReport,
  parseRequest,
  readGeminiReply,
  readGroqReply,
} from './pip.js';

const CORS = {
  'access-control-allow-methods': 'POST, OPTIONS',
  'access-control-allow-headers': 'authorization, content-type, x-firebase-appcheck',
  'access-control-max-age': '86400',
};

const BROWSER_ORIGINS = new Set([
  'https://www.focus-forge.in',
  'https://focus-forge.in',
  'https://focusforgeorg.vercel.app',
  'https://focusforge-1edf7.web.app',
  'https://focusforge-1edf7.firebaseapp.com',
]);

function secureResponse(response, origin) {
  response.headers.set('vary', 'Origin');
  response.headers.set('x-content-type-options', 'nosniff');
  response.headers.set('referrer-policy', 'no-referrer');
  response.headers.set('strict-transport-security', 'max-age=31536000');
  response.headers.set('content-security-policy', "default-src 'none'; frame-ancestors 'none'");
  response.headers.set('cache-control', 'no-store');
  if (BROWSER_ORIGINS.has(origin)) response.headers.set('access-control-allow-origin', origin);
  return response;
}

/** Time allowed for each provider, so a full fallback fits the app's 25 s. */
const PROVIDER_TIMEOUT_MS = 9000;

function json(status, body, extra = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...CORS,
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
      ...extra,
    },
  });
}

/** One provider's outcome: `{text}`, `{blocked}`, or `{failed, timedOut?, status?}`. */
async function callProvider(name, url, init, read, fetchImpl) {
  try {
    const response = await fetchImpl(url, {...init, redirect: 'error', signal: AbortSignal.timeout(PROVIDER_TIMEOUT_MS)});
    if (!response.ok) {
      console.warn(JSON.stringify({event: 'provider_error', provider: name, status: response.status}));
      return {failed: true, status: response.status};
    }
    const reply = read(await response.json());
    if (reply.empty) {
      console.warn(JSON.stringify({event: 'provider_empty', provider: name}));
      return {failed: true};
    }
    return reply;
  } catch (error) {
    const timedOut = error?.name === 'TimeoutError' || error?.name === 'AbortError';
    console.warn(JSON.stringify({event: timedOut ? 'provider_timeout' : 'provider_network', provider: name}));
    return {failed: true, timedOut};
  }
}

function askGemini(request, env, fetchImpl) {
  const model = env.GEMINI_MODEL || 'gemini-flash-lite-latest';
  return callProvider(
    'gemini',
    `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`,
    {
      method: 'POST',
      // The key goes in a header, never the URL, so it stays out of logs.
      headers: {'content-type': 'application/json', 'x-goog-api-key': env.GEMINI_API_KEY},
      body: JSON.stringify(buildGeminiRequest(request)),
    },
    readGeminiReply,
    fetchImpl,
  );
}

function askGroq(request, env, fetchImpl) {
  return callProvider(
    'groq',
    'https://api.groq.com/openai/v1/chat/completions',
    {
      method: 'POST',
      headers: {'content-type': 'application/json', authorization: `Bearer ${env.GROQ_API_KEY}`},
      body: JSON.stringify(buildGroqRequest(request, env.GROQ_MODEL || 'openai/gpt-oss-20b')),
    },
    readGroqReply,
    fetchImpl,
  );
}

/**
 * Asks Gemini first. Any failure other than a safety block (quota, 5xx,
 * timeout, network, a bad key or a retired model) is retried on Groq with
 * the same conversation. A safety block is final: another model is not
 * asked to answer what the first one refused.
 */
export async function answer(request, env, fetchImpl = fetch) {
  const attempts = [];
  if (env.GEMINI_API_KEY) attempts.push(['gemini', askGemini]);
  if (env.GROQ_API_KEY) attempts.push(['groq', askGroq]);
  let timedOut = attempts.length > 0;
  for (const [provider, ask] of attempts) {
    const result = await ask(request, env, fetchImpl);
    if (result.text) return {reply: result.text, provider};
    if (result.blocked) return {blocked: true};
    timedOut &&= result.timedOut === true;
  }
  return {failed: true, timedOut};
}

async function handle(request, env, fetchImpl) {
  if (request.method === 'OPTIONS') return new Response(null, {status: 204, headers: CORS});
  const path = new URL(request.url).pathname;
  if (path !== '/' && path !== '/report' && path !== '/data') return json(404, {error: 'not-found'});
  if (request.method !== 'POST') return json(405, {error: 'method-not-allowed'}, {allow: 'POST, OPTIONS'});

  // Checking a token can mean downloading Google's signing keys, so callers
  // are limited before it, by address, as well as per account after it.
  const caller = request.headers.get('cf-connecting-ip') ?? 'unknown';
  if (!(await env.CALLER_LIMIT.limit({key: caller})).success) {
    return json(429, {error: 'resource-exhausted', window: 'minute'}, {'retry-after': '60'});
  }

  const bearer = /^Bearer (.+)$/.exec(request.headers.get('authorization') ?? '')?.[1];
  let uid;
  try {
    ({uid} = await verifyIdToken(bearer, env.FIREBASE_PROJECT_ID, {fetchImpl}));
  } catch (error) {
    if (!(error instanceof AuthError)) throw error;
    return json(401, {error: 'unauthenticated'});
  }

  if (Number(request.headers.get('content-length') ?? 0) > LIMITS.bodyBytes) {
    return json(413, {error: 'invalid-argument'});
  }
  const raw = await readBounded(request, LIMITS.bodyBytes);
  if (raw === null) return json(413, {error: 'invalid-argument'});
  if (path === '/data') return legacyData(raw, uid, env, request, fetchImpl);
  if (path === '/report') return report(raw, uid, env, request, fetchImpl);
  let parsed;
  try {
    parsed = parseRequest(JSON.parse(raw));
  } catch (error) {
    if (error instanceof SyntaxError || error instanceof InputError) {
      return json(400, {error: 'invalid-argument'});
    }
    throw error;
  }

  // Per person first, then a ceiling for everyone that keeps a burst of new
  // accounts from draining the free provider quotas.
  const perUser = await env.PER_USER_LIMIT.limit({key: uid});
  const everyone = perUser.success ? await env.ALL_USERS_LIMIT.limit({key: 'all'}) : perUser;
  if (!perUser.success || !everyone.success) {
    return json(429, {error: 'resource-exhausted', window: 'minute'}, {'retry-after': '60'});
  }

  if (isInstructionAttack(parsed.message) || parsed.history.some(t => isInstructionAttack(t.text))) {
    return json(422, {error: 'failed-precondition', blocked: true});
  }

  const authorization = await authorize(request, uid, 'answer', fetchImpl);
  if (authorization) return authorization;

  const started = Date.now();
  const result = await answer(parsed, env, fetchImpl);
  if (result.reply) {
    console.log(JSON.stringify({event: 'answered', provider: result.provider, ms: Date.now() - started}));
    return json(200, {reply: result.reply, provider: result.provider});
  }
  if (result.blocked) return json(422, {error: 'failed-precondition', blocked: true});
  return result.timedOut
    ? json(504, {error: 'deadline-exceeded'})
    : json(503, {error: 'unavailable'}, {'retry-after': '30'});
}

/** New reports use a transactional account-deletion fence in Firestore.
 * Legacy KV reports are read-only and remain exportable/erasable below. */
async function report(raw, uid, env, request, fetchImpl) {
  let parsed;
  try { parsed = parseReport(JSON.parse(raw)); }
  catch { return json(400, {error: 'invalid-argument'}); }
  if (!(await env.PER_USER_LIMIT.limit({key: `report:${uid}`})).success) {
    return json(429, {error: 'resource-exhausted', window: 'minute'});
  }
  try {
    const response = await fetchImpl('https://www.focus-forge.in/api/account-data', {
      method: 'POST', redirect: 'error', signal: AbortSignal.timeout(9000),
      headers: forwardingHeaders(request), body: JSON.stringify({operation: 'report', ...parsed}),
    });
    if (response.status === 200 && (await response.json()).ok === true) return json(200, {ok: true});
    if (response.status === 429) return json(429, {error: 'resource-exhausted', window: 'day'});
    if ([401, 403].includes(response.status)) return json(401, {error: 'unauthenticated'});
  } catch { /* No provider details or credentials in errors. */ }
  return json(503, {error: 'unavailable'});
}

function forwardingHeaders(request) {
  const headers = {'content-type': 'application/json', authorization: request.headers.get('authorization')};
  const attestation = request.headers.get('x-firebase-appcheck');
  if (attestation) headers['x-firebase-appcheck'] = attestation;
  return headers;
}

/** Paged, owner-filtered access to historical KV reports. Cursors identify a
 * scan position, never an account. No cross-account contents are returned. */
async function legacyData(raw, uid, env, request, fetchImpl) {
  let body;
  try {
    body = JSON.parse(raw);
    if (!body || Array.isArray(body) || Object.keys(body).some(k => !['operation', 'cursor'].includes(k)) ||
        !['export', 'delete'].includes(body.operation) ||
        (body.cursor !== undefined && (typeof body.cursor !== 'string' || body.cursor.length > 1024))) throw Error();
  } catch { return json(400, {error: 'invalid-argument'}); }
  if (!(await env.PER_USER_LIMIT.limit({key: `privacy:${uid}`})).success) {
    return json(429, {error: 'resource-exhausted', window: 'minute'});
  }
  const denied = await authorize(request, uid, `privacy-${body.operation}`, fetchImpl);
  if (denied) return denied;
  // Listing and ownership checks include the original time-based keys.
  const page = await env.REPORTS.list({limit: 100, ...(body.cursor ? {cursor: body.cursor} : {})});
  const records = [];
  for (let start = 0; start < page.keys.length; start += 10) {
    const rows = await Promise.all(page.keys.slice(start, start + 10).map(async ({name}) => {
      const value = await env.REPORTS.get(name, {type: 'json'});
      if (value?.uid !== uid) return null;
      if (body.operation === 'delete') await env.REPORTS.delete(name);
      return {key: name, data: value};
    }));
    if (body.operation === 'export') records.push(...rows.filter(Boolean));
  }
  return json(200, {records, cursor: page.list_complete ? null : page.cursor});
}

/** Current account status and a globally shared daily quota, both fail closed. */
async function authorize(request, uid, operation, fetchImpl) {
  const headers = {'content-type': 'application/json', authorization: request.headers.get('authorization')};
  const attestation = request.headers.get('x-firebase-appcheck');
  if (attestation) headers['x-firebase-appcheck'] = attestation;
  try {
    const response = await fetchImpl('https://www.focus-forge.in/api/ai-authorize', {
      method: 'POST', headers, body: JSON.stringify({operation}),
      signal: AbortSignal.timeout(5000), redirect: 'error',
    });
    const body = await response.json();
    if (response.status === 200 && body.uid === uid) return null;
    if (response.status === 429) return json(429, {error: 'resource-exhausted', window: 'day'});
    if (response.status === 401 || response.status === 403) return json(401, {error: 'unauthenticated'});
  } catch {
    // No token, provider error body, or account detail is logged.
  }
  return json(503, {error: 'unavailable'}, {'retry-after': '30'});
}

export default {
  async scheduled(_controller, env, ctx) {
    ctx.waitUntil(drainResetEmails(env).catch(() => {
      console.error(JSON.stringify({event: 'reset_scheduler_failed'}));
    }));
  },
  /** The Workers entry point. [fetchImpl] is swapped out in tests. */
  async fetch(request, env, _ctx, fetchImpl = fetch) {
    const origin = request.headers.get('origin');
    try {
      // Native clients have no Origin; they still need verified Firebase auth
      // and every quota check. CORS is browser defence, never authentication.
      const response = origin !== null && !BROWSER_ORIGINS.has(origin)
        ? json(403, {error: 'permission-denied'})
        : await handle(request, env, fetchImpl);
      return secureResponse(response, origin);
    } catch (error) {
      console.error(JSON.stringify({event: 'crash'}));
      return secureResponse(json(500, {error: 'internal'}), origin);
    }
  },
};

/**
 * The request body as text, or null once it passes [limit] bytes. Reads the
 * stream as it arrives, so a body with no or a false Content-Length is never
 * held whole, and the limit is in bytes, as declared, not in characters.
 */
async function readBounded(request, limit) {
  if (!request.body) return '';
  const reader = request.body.getReader();
  const chunks = [];
  let size = 0;
  for (;;) {
    const {done, value} = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > limit) {
      await reader.cancel();
      return null;
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(size);
  let at = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, at);
    at += chunk.byteLength;
  }
  return new TextDecoder().decode(bytes);
}

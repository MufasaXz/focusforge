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
import {
  InputError,
  LIMITS,
  buildGeminiRequest,
  buildGroqRequest,
  parseReport,
  parseRequest,
  readGeminiReply,
  readGroqReply,
} from './pip.js';

const CORS = {
  'access-control-allow-origin': '*',
  'access-control-allow-methods': 'POST, OPTIONS',
  'access-control-allow-headers': 'authorization, content-type',
  'access-control-max-age': '86400',
};

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
    const response = await fetchImpl(url, {...init, signal: AbortSignal.timeout(PROVIDER_TIMEOUT_MS)});
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
  if (path !== '/' && path !== '/report') return json(404, {error: 'not-found'});
  if (request.method !== 'POST') return json(405, {error: 'method-not-allowed'}, {allow: 'POST, OPTIONS'});

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
  const raw = await request.text();
  if (raw.length > LIMITS.bodyBytes) return json(413, {error: 'invalid-argument'});
  if (path === '/report') return report(raw, uid, env);
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

/** How long a report is kept for review. */
const REPORT_TTL_SECONDS = 90 * 24 * 60 * 60;

/**
 * Keeps a user's report of an answer for review, as Google Play asks of
 * apps with generated content. Stored in KV for 90 days under a key that
 * sorts by time; review with `wrangler kv key list --binding REPORTS`.
 */
async function report(raw, uid, env) {
  let parsed;
  try {
    parsed = parseReport(JSON.parse(raw));
  } catch (error) {
    if (error instanceof SyntaxError || error instanceof InputError) {
      return json(400, {error: 'invalid-argument'});
    }
    throw error;
  }
  const limit = await env.PER_USER_LIMIT.limit({key: `report:${uid}`});
  if (!limit.success) return json(429, {error: 'resource-exhausted', window: 'minute'});
  const at = new Date().toISOString();
  await env.REPORTS.put(
    `${at}:${crypto.randomUUID()}`,
    JSON.stringify({...parsed, uid, at}),
    {expirationTtl: REPORT_TTL_SECONDS},
  );
  console.log(JSON.stringify({event: 'reported', reason: parsed.reason}));
  return json(200, {ok: true});
}

export default {
  /** The Workers entry point. [fetchImpl] is swapped out in tests. */
  async fetch(request, env, _ctx, fetchImpl = fetch) {
    try {
      return await handle(request, env, fetchImpl);
    } catch (error) {
      console.error(JSON.stringify({event: 'crash', name: error?.name}));
      return json(500, {error: 'internal'});
    }
  },
};

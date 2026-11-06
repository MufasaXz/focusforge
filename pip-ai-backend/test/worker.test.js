// The worker end to end, with fake providers.
//
// WHAT INVARIANT: the worker answers only signed-in users, refuses bad input
// with 400, holds users to the rate limit, sends the keys only in headers,
// falls back from Gemini to Groq on quota, server and network failures, never
// falls back after a safety block, and reports total failure with a code the
// app can map.
import {beforeEach, test} from 'node:test';
import assert from 'node:assert/strict';

import worker from '../src/index.js';
import {resetKeyCache} from '../src/auth.js';
import {PROJECT, fakeFetch, makeSigner} from './support.js';

const signer = await makeSigner();
const URL = 'https://pip-ai-backend.example.workers.dev/';

function limiter(allowed = true) {
  const keys = [];
  return {keys, limit: async ({key}) => (keys.push(key), {success: allowed})};
}

function store() {
  const items = new Map();
  return {items, put: async (key, value, options) => items.set(key, {value, options})};
}

function env(overrides = {}) {
  return {
    FIREBASE_PROJECT_ID: PROJECT,
    GEMINI_API_KEY: 'gemini-secret',
    GROQ_API_KEY: 'groq-secret',
    GEMINI_MODEL: 'gemini-flash-lite-latest',
    GROQ_MODEL: 'openai/gpt-oss-20b',
    PER_USER_LIMIT: limiter(),
    ALL_USERS_LIMIT: limiter(),
    REPORTS: store(),
    ...overrides,
  };
}

const geminiOk = (text) =>
  new Response(JSON.stringify({candidates: [{finishReason: 'STOP', content: {parts: [{text}]}}]}));
const groqOk = (text) =>
  new Response(JSON.stringify({choices: [{finish_reason: 'stop', message: {content: text}}]}));

/** Routes provider URLs to [gemini] and [groq] handlers. */
function providers({gemini = () => geminiOk('Gemini says hi.'), groq = () => groqOk('Groq says hi.')} = {}) {
  return fakeFetch(signer.jwks, (url, init) => {
    if (url.startsWith('https://generativelanguage.googleapis.com/')) return gemini(url, init);
    if (url.startsWith('https://api.groq.com/')) return groq(url, init);
    throw new Error(`unexpected ${url}`);
  });
}

async function ask(body, {token, headers = {}, method = 'POST', vars = env(), fetchImpl = providers(), path = ''} = {}) {
  const request = new Request(URL + path, {
    method,
    headers: {
      'content-type': 'application/json',
      ...(token === null ? {} : {authorization: `Bearer ${token ?? (await signer.token())}`}),
      ...headers,
    },
    body: method === 'POST' ? (typeof body === 'string' ? body : JSON.stringify(body)) : undefined,
  });
  const response = await worker.fetch(request, vars, {}, fetchImpl);
  return {status: response.status, headers: response.headers, body: await response.json().catch(() => null)};
}

beforeEach(resetKeyCache);

test('a signed-in question is answered by Gemini, with the key only in a header', async () => {
  const fetchImpl = providers();
  const vars = env();
  const result = await ask({message: 'plan my evening', locale: 'en'}, {vars, fetchImpl});
  assert.equal(result.status, 200);
  assert.deepEqual(result.body, {reply: 'Gemini says hi.', provider: 'gemini'});
  assert.equal(result.headers.get('access-control-allow-origin'), '*');
  const call = fetchImpl.calls.find((c) => c.url.includes('generativelanguage'));
  assert.ok(call.url.endsWith('/models/gemini-flash-lite-latest:generateContent'));
  assert.ok(!call.url.includes('secret'));
  assert.equal(call.init.headers['x-goog-api-key'], 'gemini-secret');
  assert.deepEqual(vars.PER_USER_LIMIT.keys, ['user-123']);
});

test('preflight is answered with CORS headers', async () => {
  const response = await worker.fetch(new Request(URL, {method: 'OPTIONS'}), env(), {}, providers());
  assert.equal(response.status, 204);
  assert.match(response.headers.get('access-control-allow-headers'), /authorization/);
});

test('missing or bad sign-in is refused before any model is asked', async () => {
  const fetchImpl = providers();
  assert.equal((await ask({message: 'hi'}, {token: null, fetchImpl})).status, 401);
  assert.equal((await ask({message: 'hi'}, {token: 'nonsense', fetchImpl})).status, 401);
  const guest = await signer.token({firebase: {sign_in_provider: 'anonymous'}});
  assert.equal((await ask({message: 'hi'}, {token: guest, fetchImpl})).status, 401);
  assert.ok(fetchImpl.calls.every((c) => !c.url.includes('generativelanguage') && !c.url.includes('groq')));
});

test('bad input is refused with 400 and wrong methods with 405', async () => {
  assert.equal((await ask('{not json')).status, 400);
  assert.equal((await ask({message: '   '})).status, 400);
  assert.equal((await ask({})).status, 400);
  assert.equal((await ask({message: 'x'.repeat(20000)})).status, 413);
  assert.equal((await ask(null, {method: 'GET'})).status, 405);
});

test('a flood of text reaches the model as at most 300 characters', async () => {
  let sent;
  const fetchImpl = providers({gemini: (url, init) => ((sent = JSON.parse(init.body)), geminiOk('ok'))});
  await ask({message: 'a'.repeat(5000)}, {fetchImpl});
  assert.equal(sent.contents.at(-1).parts[0].text, `Student: ${'a'.repeat(300)}`);
});

test('a user over the limit gets 429 and no model is asked', async () => {
  const fetchImpl = providers();
  const result = await ask({message: 'hi'}, {vars: env({PER_USER_LIMIT: limiter(false)}), fetchImpl});
  assert.equal(result.status, 429);
  assert.deepEqual(result.body, {error: 'resource-exhausted', window: 'minute'});
  assert.equal(result.headers.get('retry-after'), '60');
  const busy = await ask({message: 'hi'}, {vars: env({ALL_USERS_LIMIT: limiter(false)}), fetchImpl});
  assert.equal(busy.status, 429);
  assert.ok(fetchImpl.calls.every((c) => !c.url.includes('generativelanguage')));
});

test('Gemini quota, server, key and network failures fall back to Groq', async () => {
  for (const gemini of [
    () => new Response('{}', {status: 429}),
    () => new Response('{}', {status: 503}),
    () => new Response('{}', {status: 403}),
    () => geminiOk('   '),
    () => {
      throw new TypeError('network down');
    },
  ]) {
    let groqBody;
    const fetchImpl = providers({
      gemini,
      groq: (url, init) => ((groqBody = JSON.parse(init.body)), groqOk('Groq says hi.')),
    });
    const result = await ask({message: 'motivate me'}, {fetchImpl});
    assert.equal(result.status, 200);
    assert.deepEqual(result.body, {reply: 'Groq says hi.', provider: 'groq'});
    assert.equal(groqBody.messages.at(-1).content, 'Student: motivate me');
    const call = fetchImpl.calls.find((c) => c.url.includes('groq'));
    assert.equal(call.init.headers.authorization, 'Bearer groq-secret');
  }
});

test('a safety block is final and is not retried on Groq', async () => {
  const fetchImpl = providers({
    gemini: () => new Response(JSON.stringify({promptFeedback: {blockReason: 'SAFETY'}})),
  });
  const result = await ask({message: 'something unsafe'}, {fetchImpl});
  assert.equal(result.status, 422);
  assert.deepEqual(result.body, {error: 'failed-precondition', blocked: true});
  assert.ok(!fetchImpl.calls.some((c) => c.url.includes('groq')));
});

test('when both providers fail the app gets a code it can map', async () => {
  const down = providers({
    gemini: () => new Response('{}', {status: 500}),
    groq: () => new Response('{}', {status: 502}),
  });
  const failed = await ask({message: 'hi'}, {fetchImpl: down});
  assert.equal(failed.status, 503);
  assert.deepEqual(failed.body, {error: 'unavailable'});

  const timeout = () => {
    throw new DOMException('slow', 'TimeoutError');
  };
  const slow = await ask({message: 'hi'}, {fetchImpl: providers({gemini: timeout, groq: timeout})});
  assert.equal(slow.status, 504);
  assert.deepEqual(slow.body, {error: 'deadline-exceeded'});

  const noKeys = await ask({message: 'hi'}, {vars: env({GEMINI_API_KEY: '', GROQ_API_KEY: ''})});
  assert.equal(noKeys.status, 503);
});

test('a signed-in report is kept for review, and nothing else is asked', async () => {
  const vars = env();
  const fetchImpl = providers();
  const result = await ask(
    {reason: 'harmful', reply: 'Some answer.', question: 'hi'},
    {vars, fetchImpl, path: 'report'},
  );
  assert.equal(result.status, 200);
  const [[key, {value, options}]] = [...vars.REPORTS.items];
  assert.match(key, /^\d{4}-\d{2}-\d{2}T/);
  assert.deepEqual(JSON.parse(value).reason, 'harmful');
  assert.equal(JSON.parse(value).uid, 'user-123');
  assert.equal(options.expirationTtl, 90 * 24 * 60 * 60);
  assert.ok(fetchImpl.calls.every((c) => !c.url.includes('generativelanguage')));

  assert.equal((await ask({reason: 'x', reply: 'y'}, {vars, path: 'report'})).status, 400);
  assert.equal((await ask({reason: 'hate', reply: 'y'}, {vars, path: 'report', token: null})).status, 401);
  assert.equal((await ask({}, {vars, path: 'elsewhere'})).status, 404);
});

import {test} from 'node:test';
import assert from 'node:assert/strict';
import {drainResetEmails} from '../src/reset-delivery.js';

test('scheduler signs a timestamp and sends no user data or signing key', async () => {
  const pair = await crypto.subtle.generateKey('Ed25519', true, ['sign', 'verify']);
  const privateKey = Buffer.from(await crypto.subtle.exportKey('pkcs8', pair.privateKey)).toString('base64');
  const now = Date.now();
  await drainResetEmails({RESET_DELIVERY_SIGNING_KEY: privateKey}, async (url, init) => {
    assert.equal(url, 'https://www.focus-forge.in/api/reset-delivery');
    assert.equal(init.redirect, 'error');
    assert.equal(init.method, 'POST');
    assert.equal(init.body, undefined);
    const [timestamp, signature] = init.headers.authorization.slice('ResetWorker '.length).split('.');
    assert.equal(timestamp, String(now));
    assert.ok(await crypto.subtle.verify('Ed25519', pair.publicKey, Buffer.from(signature, 'base64url'),
      new TextEncoder().encode('reset-delivery:' + timestamp)));
    assert.ok(!JSON.stringify(init).includes(privateKey));
    return Response.json({processed: 0, retry: 0});
  }, now);
});

test('scheduler fails closed without a secret or when delivery service rejects the request', async () => {
  let calls = 0;
  await assert.rejects(drainResetEmails({}, () => {calls++;}));
  assert.equal(calls, 0);
  const pair = await crypto.subtle.generateKey('Ed25519', true, ['sign', 'verify']);
  const key = Buffer.from(await crypto.subtle.exportKey('pkcs8', pair.privateKey)).toString('base64');
  await assert.rejects(drainResetEmails({RESET_DELIVERY_SIGNING_KEY: key}, async () => new Response('', {status: 401})));
});

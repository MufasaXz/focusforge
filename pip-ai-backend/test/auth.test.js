// Firebase ID token checks.
//
// WHAT INVARIANT: only a live token signed by Google's key for this project,
// from a real (non-guest, verified) account, yields a uid; every other token
// is refused with AuthError.
import {beforeEach, test} from 'node:test';
import assert from 'node:assert/strict';

import {AuthError, resetKeyCache, verifyIdToken} from '../src/auth.js';
import {PROJECT, fakeFetch, makeSigner} from './support.js';

const signer = await makeSigner();
const fetchImpl = fakeFetch(signer.jwks);
const verify = (token) => verifyIdToken(token, PROJECT, {fetchImpl});

beforeEach(resetKeyCache);

test('a valid token yields its uid', async () => {
  assert.deepEqual(await verify(await signer.token()), {uid: 'user-123'});
});

test('a verified email account is accepted', async () => {
  const token = await signer.token({firebase: {sign_in_provider: 'password'}, email_verified: true});
  assert.deepEqual(await verify(token), {uid: 'user-123'});
});

test('tokens for another project, issuer or time are refused', async () => {
  const now = Math.floor(Date.now() / 1000);
  for (const claims of [
    {aud: 'someone-else'},
    {iss: 'https://securetoken.google.com/someone-else'},
    {exp: now - 600},
    {iat: now + 600},
    {auth_time: now + 600},
    {sub: ''},
  ]) {
    await assert.rejects(verify(await signer.token(claims)), AuthError, JSON.stringify(claims));
  }
});

test('guest and unverified email tokens are refused', async () => {
  await assert.rejects(verify(await signer.token({firebase: {sign_in_provider: 'anonymous'}})), AuthError);
  await assert.rejects(
    verify(await signer.token({firebase: {sign_in_provider: 'password'}, email_verified: false})),
    AuthError,
  );
});

test('a forged, tampered or unknown-key token is refused', async () => {
  const other = await makeSigner();
  await assert.rejects(verify(await other.token()), AuthError);

  const [head, , signature] = (await signer.token()).split('.');
  const payload = Buffer.from(JSON.stringify({sub: 'admin'})).toString('base64url');
  await assert.rejects(verify(`${head}.${payload}.${signature}`), AuthError);

  await assert.rejects(verify(await signer.token({}, {kid: 'retired'})), AuthError);
  await assert.rejects(verify(await signer.token({}, {alg: 'none'})), AuthError);
  await assert.rejects(verify('not-a-token'), AuthError);
  await assert.rejects(verify(undefined), AuthError);
});

test('signing keys are cached between requests', async () => {
  const counting = fakeFetch(signer.jwks);
  for (let i = 0; i < 3; i++) await verifyIdToken(await signer.token(), PROJECT, {fetchImpl: counting});
  assert.equal(counting.calls.length, 1);
});

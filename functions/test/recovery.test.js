import {test, before, after, beforeEach} from 'node:test';
import assert from 'node:assert/strict';
import {initializeApp, deleteApp} from 'firebase-admin/app';
import {getFirestore, Timestamp} from 'firebase-admin/firestore';
import {beginRecovery, finishRecovery} from '../recover-client-account.js';

const enabled = !!process.env.FIRESTORE_EMULATOR_HOST;
let app, db, user, auth;
const uid = 'recovery-test-user';
before(() => {
  if (!enabled) return;
  app = initializeApp({projectId:'demo-focusforge'}, 'recovery-tests');
  db = getFirestore(app);
});
after(async () => { if (app) await deleteApp(app); });
beforeEach(async () => {
  if (!enabled) return;
  await db.doc('_accountRecoveries/'+uid).delete();
  await db.doc('accountDeletions/'+uid).set({requestedAt:Timestamp.fromMillis(1)});
  await db.doc('users/'+uid+'/preferences/studyBackup').set({keep:true});
  user = {disabled:false, tokensValidAfterTime:new Date(0).toISOString(),
    metadata:{creationTime:new Date(1).toISOString()}};
  auth = {
    async getUser() { if (!user) throw Error('user-not-found'); return structuredClone(user); },
    async updateUser(_uid, patch) { Object.assign(user, patch); },
    async revokeRefreshTokens() { user.tokensValidAfterTime = new Date().toISOString(); },
  };
});
async function ageWaitingPeriod() {
  // Only the trusted test Admin can move server time backwards.
  const at = Date.now() - 66 * 60 * 1000;
  user.tokensValidAfterTime = new Date(at-1000).toISOString();
  await db.doc('_accountRecoveries/'+uid).update({blockedAt:Timestamp.fromMillis(at),
    tokensValidAfterTime:user.tokensValidAfterTime});
}

test('recovery waits for old tokens, then restores Auth without erasing remaining data', {skip:!enabled}, async () => {
  await beginRecovery(db, auth, uid);
  assert.equal(user.disabled, true);
  await assert.rejects(finishRecovery(db, auth, uid), /65 minutes/);
  assert.equal((await db.doc('accountDeletions/'+uid).get()).exists, true);
  await ageWaitingPeriod();
  const disabledAt = (await db.doc('_accountRecoveries/'+uid).get()).data().blockedAt.toMillis();
  await finishRecovery(db, auth, uid);
  assert.ok(Date.parse(user.tokensValidAfterTime) > disabledAt,
    'final revocation must cover every session created before disabling');
  assert.equal(user.disabled, false);
  assert.equal((await db.doc('accountDeletions/'+uid).get()).exists, false);
  assert.equal((await db.doc('_accountRecoveries/'+uid).get()).exists, false);
  assert.deepEqual((await db.doc('users/'+uid+'/preferences/studyBackup').get()).data(), {keep:true});
});

for (const skew of ['same-second', 'future']) test(skew+' revocation cannot release the fence', {skip:!enabled}, async () => {
  await beginRecovery(db, auth, uid);
  await ageWaitingPeriod();
  const blockedAt = (await db.doc('_accountRecoveries/'+uid).get()).data().blockedAt.toMillis();
  auth.revokeRefreshTokens = async () => {
    user.tokensValidAfterTime = new Date(skew === 'same-second' ? blockedAt : Date.now()+3600000).toISOString();
  };
  await assert.rejects(finishRecovery(db, auth, uid), /revocation cutoff/);
  assert.equal(user.disabled, true);
  assert.equal((await db.doc('accountDeletions/'+uid).get()).exists, true);
});

test('missing and disabled accounts and backend deletion jobs cannot start recovery', {skip:!enabled}, async () => {
  user.disabled = true;
  await assert.rejects(beginRecovery(db, auth, uid), /disabled/);
  user.disabled = false;
  for (const status of ['pending', 'complete']) {
    await db.doc('accountDeletions/'+uid).set({requestedAt:Timestamp.fromMillis(1), status});
    await assert.rejects(beginRecovery(db, auth, uid), /client deletion/);
    assert.equal(user.disabled, false);
  }
  user = null;
  await assert.rejects(beginRecovery(db, auth, uid), /user-not-found/);
});

test('a deletion completed during the wait leaves its fence intact', {skip:!enabled}, async () => {
  await beginRecovery(db, auth, uid);
  await ageWaitingPeriod();
  user = null;
  await assert.rejects(finishRecovery(db, auth, uid), /user-not-found/);
  assert.equal((await db.doc('accountDeletions/'+uid).get()).exists, true);
});

test('changed Auth identity, renewed sessions and changed fences stop recovery', {skip:!enabled}, async () => {
  await beginRecovery(db, auth, uid);
  await ageWaitingPeriod();
  const original = structuredClone(user);
  user.metadata.creationTime = new Date(2).toISOString();
  await assert.rejects(finishRecovery(db, auth, uid), /identity/);
  user = structuredClone(original);
  user.disabled = false;
  await assert.rejects(finishRecovery(db, auth, uid), /disabled/);
  user = structuredClone(original);
  user.metadata.lastRefreshTime = new Date().toISOString();
  await assert.rejects(finishRecovery(db, auth, uid), /session/);
  user = structuredClone(original);
  user.tokensValidAfterTime = new Date().toISOString();
  await assert.rejects(finishRecovery(db, auth, uid), /session/);
  user = structuredClone(original);
  await db.doc('accountDeletions/'+uid).set({requestedAt:Timestamp.now()});
  await assert.rejects(finishRecovery(db, auth, uid), /fence changed/);
  assert.equal((await db.doc('accountDeletions/'+uid).get()).exists, true);
});

test('interrupted disable and interrupted re-enable can be retried safely', {skip:!enabled}, async () => {
  const revoke = auth.revokeRefreshTokens;
  auth.revokeRefreshTokens = async () => { throw Error('temporary Auth error'); };
  await assert.rejects(beginRecovery(db, auth, uid), /temporary/);
  assert.equal(user.disabled, true);
  auth.revokeRefreshTokens = revoke;
  await beginRecovery(db, auth, uid);
  await ageWaitingPeriod();
  const update = auth.updateUser;
  auth.updateUser = async () => { throw Error('temporary Auth error'); };
  await assert.rejects(finishRecovery(db, auth, uid), /temporary/);
  assert.equal(user.disabled, true);
  assert.equal((await db.doc('_accountRecoveries/'+uid).get()).data().phase, 'released');
  auth.updateUser = update;
  await finishRecovery(db, auth, uid);
  assert.equal(user.disabled, false);
});

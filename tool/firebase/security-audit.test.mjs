import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {before, after, beforeEach, test} from 'node:test';
import {initializeTestEnvironment, assertFails, assertSucceeds} from '@firebase/rules-unit-testing';
import {collection, collectionGroup, deleteDoc, doc, getDoc, getDocs, query,
  serverTimestamp, setDoc, updateDoc, where, writeBatch} from 'firebase/firestore';

let env;
const db = uid => env.authenticatedContext(uid, {
  auth_time:Math.floor(Date.now()/1000),
  firebase:{sign_in_provider:'google.com'},
}).firestore();
const inviteCode = 'ABCD234567';
const row = uid => ({ownerUid:uid,name:'Student',joinedAt:Date.now(),inviteCode,
  week:'2026-10-19',minutes:0,focusUntil:0,updatedAt:serverTimestamp()});

before(async () => {
  env = await initializeTestEnvironment({projectId:'demo-focusforge-security-audit', firestore:{
    rules:readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8'),
    host:'127.0.0.1', port:Number(process.env.FIRESTORE_EMULATOR_HOST?.split(':').at(-1) || 8080),
  }});
});
after(async () => { await env?.cleanup(); });
beforeEach(async () => { await env.clearFirestore(); });

async function seedPrivateGroup() {
  const store = db('owner'), batch = writeBatch(store);
  batch.set(doc(store,'studyGroups/private'),{name:'Private',targetHours:10,createdAt:Date.now(),
    ownerUid:'owner',memberIds:['owner'],inviteCode});
  batch.set(doc(store,'groupInvites',inviteCode),{groupId:'private'});
  batch.set(doc(store,'studyGroups/private/members/owner'),row('owner'));
  await assertSucceeds(batch.commit());
}

// Catches a relaxed owner check on either private documents or social deletion paths.
test('security audit: a stranger cannot read private backups or delete another account records', async () => {
  await seedPrivateGroup();
  const paths = [
    'users/owner',
    'users/owner/preferences/studyBackup',
    'users/owner/sessionData/private-session',
    'users/owner/achievements/earned',
    'users/owner/archive/year/nested/private',
  ];
  await env.withSecurityRulesDisabled(async c => {
    for (const path of paths) await setDoc(doc(c.firestore(),path),{ownerUid:'owner',private:'private fixture'});
    await setDoc(doc(c.firestore(),'leaderboard/2026-10-19/entries/owner'),{ownerUid:'owner',name:'Owner',minutes:10});
  });
  const stranger = db('stranger');
  for (const path of paths) {
    await assertFails(getDoc(doc(stranger,path)));
    await assertFails(deleteDoc(doc(stranger,path)));
  }
  for (const path of ['leaderboard/2026-10-19/entries/owner','studyGroups/private/members/owner',
    'studyGroups/private','groupInvites/'+inviteCode]) {
    await assertFails(deleteDoc(doc(stranger,path)));
  }
  await assertFails(getDocs(query(collectionGroup(stranger,'members'),where('ownerUid','==','owner'))));
  await assertFails(getDocs(query(collectionGroup(stranger,'entries'),where('ownerUid','==','owner'))));
});

// Catches accidental OR-rule access from the recursive entries/members cleanup grants.
test('security audit: recursive cleanup reads cannot expose private member progress to an outsider', async () => {
  await seedPrivateGroup();
  const outsider = db('stranger');
  await assertFails(getDoc(doc(outsider,'studyGroups/private/members/owner')));
  await assertFails(getDocs(collection(outsider,'studyGroups/private/members')));
  await assertFails(getDocs(collectionGroup(outsider,'members')));
  const owned = await assertSucceeds(getDocs(query(collectionGroup(outsider,'members'),where('ownerUid','==','stranger'))));
  assert.equal(owned.size,0);
});

// Catches membership authorization based on knowledge of the group ID instead of the invite.
test('security audit: group ID alone cannot authorize joins, own progress rows or foreign member injection', async () => {
  await seedPrivateGroup();
  const outsider = db('stranger');
  await assertFails(setDoc(doc(outsider,'studyGroups/private/members/stranger'),row('stranger')));
  await assertFails(updateDoc(doc(outsider,'studyGroups/private'),{memberIds:['owner','stranger']}));
  for (const candidate of [
    {...row('stranger'),inviteCode:'WRONG23456'},
    {...row('victim'),inviteCode},
  ]) {
    const batch = writeBatch(outsider);
    batch.update(doc(outsider,'studyGroups/private'),{memberIds:['owner','stranger']});
    batch.set(doc(outsider,'studyGroups/private/members/stranger'),candidate);
    await assertFails(batch.commit());
  }
  await assertFails(setDoc(doc(outsider,'groupInvites/'+inviteCode),{groupId:'attacker'}));
  await assertFails(deleteDoc(doc(outsider,'groupInvites/'+inviteCode)));
});

// Catches a relaxed departure condition that lets a member remove the group or another member.
test('security audit: a member may leave only itself and cannot remove a peer in the same batch', async () => {
  await seedPrivateGroup();
  const friend = db('friend'), join = writeBatch(friend);
  join.update(doc(friend,'studyGroups/private'),{memberIds:['owner','friend']});
  join.set(doc(friend,'studyGroups/private/members/friend'),row('friend'));
  await assertSucceeds(join.commit());
  const attack = writeBatch(friend);
  attack.update(doc(friend,'studyGroups/private'),{memberIds:['friend'],ownerUid:'friend'});
  attack.delete(doc(friend,'studyGroups/private/members/owner'));
  await assertFails(attack.commit());
  const destroy = writeBatch(friend);
  destroy.delete(doc(friend,'studyGroups/private'));
  destroy.delete(doc(friend,'groupInvites/'+inviteCode));
  destroy.delete(doc(friend,'studyGroups/private/members/friend'));
  await assertFails(destroy.commit());
  await assertFails(updateDoc(doc(friend,'studyGroups/private'),{inviteCode:'OTHER23456'}));
});

// Catches new broad matches that expose credentials/private records without an ID token.
test('security audit: unauthenticated requests have no Firestore document access', async () => {
  await seedPrivateGroup();
  const paths = ['users/owner','users/owner/preferences/studyBackup','users/owner/sessionData/private-session',
    'users/owner/achievements/earned','leaderboard/2026-10-19/entries/owner',
    'studyGroups/private','studyGroups/private/members/owner','groupInvites/'+inviteCode,
    'accountCleanup/schema','accountDeletions/owner','pairCodes/old'];
  const anonymous = env.unauthenticatedContext().firestore();
  for (const path of paths) {
    await assertFails(getDoc(doc(anonymous,path)));
    await assertFails(setDoc(doc(anonymous,path),{ownerUid:'owner'}));
    await assertFails(deleteDoc(doc(anonymous,path)));
  }
});

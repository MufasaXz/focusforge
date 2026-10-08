import { readFileSync } from 'node:fs';
import { before, after, beforeEach, test } from 'node:test';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, getDoc, getDocs, collection, query, where, setDoc, updateDoc,
  deleteDoc, writeBatch, serverTimestamp, arrayUnion } from 'firebase/firestore';
let env;
const db = (uid, anonymous = false) => env.authenticatedContext(uid, {
  firebase: { sign_in_provider: anonymous ? 'anonymous' : 'google.com' },
}).firestore();
before(async () => {
  env = await initializeTestEnvironment({projectId:'demo-focusforge', firestore: {
    rules: readFileSync('../../firestore.rules', 'utf8'), host:'127.0.0.1', port:8080,
  }});
});
after(async () => { await env?.cleanup(); });
beforeEach(async () => { await env.clearFirestore(); });
const now = () => Date.now();
async function seedCode(code = '123456', expiresAt = now() + 900000) {
  await assertSucceeds(setDoc(doc(db('child'), 'pairCodes', code), {
    childUid:'child', childName:'Alex', createdAt:now(), expiresAt,
  }));
}
function pair(parent, code = '123456') {
  const store = db(parent), batch = writeBatch(store), linkedAt = now();
  batch.set(doc(store,'users/child/guardian/link'), {
    parentUid:parent, parentName:'Sam', linkedAt, pairCode:code,
  });
  batch.set(doc(store, 'users', parent, 'children/child'), {name:'Alex',linkedAt});
  batch.update(doc(store, 'pairCodes', code), {claimedBy:parent});
  return batch.commit();
}
async function seedGroup() {
  const store = db('owner'), batch = writeBatch(store);
  const code = 'ABCD234567';
  batch.set(doc(store, 'studyGroups/group'), {name:'Study circle',targetHours:10,
    createdAt:now(),ownerUid:'owner',memberIds:['owner'],inviteCode:code});
  batch.set(doc(store,'groupInvites',code), {groupId:'group'});
  batch.set(doc(store,'studyGroups/group/members/owner'), row(code));
  await assertSucceeds(batch.commit());
}
function row(code = 'ABCD234567') {
  return {name:'Alex',joinedAt:now(),inviteCode:code,week:'2026-10-05',minutes:30,
    focusUntil:0,updatedAt:serverTimestamp()};
}
function join(uid, code = 'ABCD234567') {
  const store = db(uid), batch = writeBatch(store);
  batch.update(doc(store,'studyGroups/group'), {memberIds:arrayUnion(uid)});
  batch.set(doc(store,'studyGroups/group/members', uid), row(code));
  return batch.commit();
}
test('pairing requires a live code and an atomic two-sided link', async () => {
  await seedCode();
  await assertFails(setDoc(doc(db('attacker'),'users/child/guardian/link'), {
    parentUid:'attacker',parentName:'Sam',linkedAt:now(),pairCode:'123456'}));
  await assertFails(setDoc(doc(db('attacker'),'users/attacker/children/child'), {name:'Alex',linkedAt:now()}));
  await assertSucceeds(pair('parent'));
  await assertFails(pair('attacker'));
  await assertSucceeds(getDoc(doc(db('parent'), 'users/child/guardian/link')));
  await assertFails(getDoc(doc(db('stranger'), 'users/child/guardian/link')));
  await assertFails(getDocs(collection(db('parent'), 'pairCodes')));
});
test('expired and self-pairing are rejected on the server', async () => {
  await env.withSecurityRulesDisabled(async c => setDoc(doc(c.firestore(),'pairCodes/123456'), {
    childUid:'child',childName:'Alex',createdAt:now()-1000000,expiresAt:now()-1000}));
  await assertFails(pair('parent'));
  await assertFails(pair('child'));
});
test('unlink cleans the parent list and remote rules atomically', async () => {
  await seedCode(); await assertSucceeds(pair('parent'));
  await assertSucceeds(setDoc(doc(db('parent'),'users/child/remoteRules/current'), {watchingOnly:false}));
  await assertFails(deleteDoc(doc(db('child'),'users/child/guardian/link')));
  const store = db('child'), batch = writeBatch(store);
  batch.delete(doc(store,'users/child/guardian/link'));
  batch.delete(doc(store,'users/parent/children/child'));
  batch.delete(doc(store,'users/child/remoteRules/current'));
  await assertSucceeds(batch.commit());
  await assertFails(getDoc(doc(db('parent'),'users/child/progress/current')));
  await assertFails(setDoc(doc(db('parent'),'users/child/remoteRules/current'), {watchingOnly:false}));
});
test('groups are private, invites cannot be enumerated, anonymous accounts cannot join', async () => {
  await seedGroup();
  await assertFails(getDoc(doc(db('stranger'),'studyGroups/group')));
  await assertFails(getDocs(collection(db('stranger'),'studyGroups/group/members')));
  await assertFails(getDocs(collection(db('stranger'),'groupInvites')));
  await assertSucceeds(getDoc(doc(db('friend'),'groupInvites/ABCD234567')));
  await assertFails(getDoc(doc(db('anon',true),'groupInvites/ABCD234567')));
  await assertFails(join('friend','WRONG23456'));
  await assertSucceeds(join('friend'));
  await assertSucceeds(getDocs(query(collection(db('friend'),'studyGroups'),where('memberIds','array-contains','friend'))));
  await assertSucceeds(getDocs(collection(db('friend'),'studyGroups/group/members')));
});
test('members can publish only their own progress and cannot change membership for others', async () => {
  await seedGroup(); await assertSucceeds(join('friend'));
  await assertSucceeds(updateDoc(doc(db('friend'),'studyGroups/group/members/friend'), {
    minutes:90,focusUntil:now()+1500000,updatedAt:serverTimestamp()}));
  await assertFails(updateDoc(doc(db('friend'),'studyGroups/group/members/owner'), {minutes:900,updatedAt:serverTimestamp()}));
  await assertFails(updateDoc(doc(db('friend'),'studyGroups/group'), {memberIds:['friend'],ownerUid:'friend'}));
  await assertFails(updateDoc(doc(db('friend'),'studyGroups/group'), {ownerUid:'friend'}));
  await assertFails(updateDoc(doc(db('friend'),'studyGroups/group/members/friend'), {minutes:-1,updatedAt:serverTimestamp()}));
});
test('owner departure transfers ownership; final departure closes group and invite', async () => {
  await seedGroup(); await assertSucceeds(join('friend'));
  const store = db('owner'), batch = writeBatch(store);
  batch.update(doc(store,'studyGroups/group'), {memberIds:['friend'],ownerUid:'friend'});
  batch.delete(doc(store,'studyGroups/group/members/owner'));
  await assertSucceeds(batch.commit());
  await assertFails(getDoc(doc(store,'studyGroups/group')));
  const friend = db('friend'), last = writeBatch(friend);
  last.delete(doc(friend,'studyGroups/group'));
  last.delete(doc(friend,'studyGroups/group/members/friend'));
  last.delete(doc(friend,'groupInvites/ABCD234567'));
  await assertSucceeds(last.commit());
});
test('two competing parents cannot both claim the same code', async () => {
  await seedCode();
  const attempts = await Promise.allSettled([pair('parent-a'),pair('parent-b')]);
  if (attempts.filter(a => a.status === 'fulfilled').length !== 1) throw Error('Exactly one claim must succeed');
});
test('group join cannot inject another member or create an invite for an existing group', async () => {
  await seedGroup();
  const store = db('friend'), batch = writeBatch(store);
  batch.update(doc(store,'studyGroups/group'), {memberIds:['owner','friend','victim']});
  batch.set(doc(store,'studyGroups/group/members/friend'), row());
  await assertFails(batch.commit());
  await assertFails(setDoc(doc(db('owner'),'groupInvites/OTHER23456'), {groupId:'group'}));
  await assertFails(setDoc(doc(db('anon',true),'studyGroups/group2'), {
    name:'Anon',targetHours:10,createdAt:now(),ownerUid:'anon',memberIds:['anon'],inviteCode:'OTHER23456'}));
});
test('linked parent can retire a device atomically; strangers cannot', async () => {
  await seedCode(); await assertSucceeds(pair('parent'));
  await assertFails(deleteDoc(doc(db('stranger'),'users/child/guardian/link')));
  const store = db('parent'), batch = writeBatch(store);
  batch.delete(doc(store,'users/child/guardian/link'));
  batch.delete(doc(store,'users/parent/children/child'));
  batch.delete(doc(store,'users/child/remoteRules/current'));
  await assertSucceeds(batch.commit());
});

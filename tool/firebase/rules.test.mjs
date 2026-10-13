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
    rules: readFileSync('../../firestore.rules', 'utf8'), host:'127.0.0.1',
    port: Number(process.env.FIRESTORE_EMULATOR_HOST?.split(':').at(-1) || 8080),
  }});
});
after(async () => { await env?.cleanup(); });
beforeEach(async () => { await env.clearFirestore(); });
const now = () => Date.now();
async function seedCode(code = 'ABCD2345EFGH6789', expiresAt = now() + 900000) {
  await assertSucceeds(setDoc(doc(db('child'), 'pairCodes', code), {
    childUid:'child', childName:'Alex', createdAt:now(), expiresAt,
  }));
}
function pair(parent, code = 'ABCD2345EFGH6789') {
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
    parentUid:'attacker',parentName:'Sam',linkedAt:now(),pairCode:'ABCD2345EFGH6789'}));
  await assertFails(setDoc(doc(db('attacker'),'users/attacker/children/child'), {name:'Alex',linkedAt:now()}));
  await assertSucceeds(pair('parent'));
  await assertFails(pair('attacker'));
  await assertSucceeds(getDoc(doc(db('parent'), 'users/child/guardian/link')));
  await assertFails(getDoc(doc(db('stranger'), 'users/child/guardian/link')));
  await assertFails(getDocs(collection(db('parent'), 'pairCodes')));
});
test('expired and self-pairing are rejected on the server', async () => {
  await env.withSecurityRulesDisabled(async c => setDoc(doc(c.firestore(),'pairCodes/ABCD2345EFGH6789'), {
    childUid:'child',childName:'Alex',createdAt:now()-1000000,expiresAt:now()-1000}));
  await assertFails(pair('parent'));
  await assertFails(pair('child'));
});
test('unlink cleans the parent list and remote rules atomically', async () => {
  await seedCode(); await assertSucceeds(pair('parent'));
  await assertSucceeds(setDoc(doc(db('parent'),'users/child/remoteRules/current'), {apps:[],youtube:{shorts:false,feed:false,focusOnly:false},enforced:true,updatedAt:now()}));
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
test('expired and claimed pairing records are private to owner and claimant', async () => {
  await env.withSecurityRulesDisabled(async c => {
    await setDoc(doc(c.firestore(),'pairCodes/123456'), {
      childUid:'child',childName:'Private',createdAt:now()-1000000,expiresAt:now()-1000});
    await setDoc(doc(c.firestore(),'pairCodes/234567'), {
      childUid:'child',childName:'Private',createdAt:now(),expiresAt:now()+900000,claimedBy:'parent'});
    await setDoc(doc(c.firestore(),'pairCodes/ABCD2345EFGH6789'), {
      childUid:'child',childName:'Private',createdAt:now()-1000000,expiresAt:now()-1000});
    await setDoc(doc(c.firestore(),'pairCodes/JKLM2345NPQR6789'), {
      childUid:'child',childName:'Private',createdAt:now(),expiresAt:now()+900000,claimedBy:'parent'});
  });
  await assertFails(getDoc(doc(db('stranger'),'pairCodes/123456')));
  await assertFails(getDoc(doc(db('stranger'),'pairCodes/234567')));
  await assertFails(getDoc(doc(db('stranger'),'pairCodes/ABCD2345EFGH6789')));
  await assertFails(getDoc(doc(db('stranger'),'pairCodes/JKLM2345NPQR6789')));
  await assertSucceeds(getDoc(doc(db('child'),'pairCodes/123456')));
  await assertSucceeds(getDoc(doc(db('parent'),'pairCodes/234567')));
});
test('a live strong token permits its bearer lookup while legacy short tokens cannot be claimed', async () => {
  await seedCode();
  await assertSucceeds(getDoc(doc(db('parent'),'pairCodes/ABCD2345EFGH6789')));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(),'pairCodes/ABCD2345EFGH6789')));
  await env.withSecurityRulesDisabled(c => setDoc(doc(c.firestore(),'pairCodes/123456'), {
    childUid:'child',childName:'Private',createdAt:now(),expiresAt:now()+900000}));
  await assertFails(getDoc(doc(db('stranger'),'pairCodes/123456')));
  await assertFails(pair('parent','123456'));
});
test('pairing mint requires high entropy token and allows missing-token uniqueness lookup', async () => {
  await assertFails(setDoc(doc(db('child'),'pairCodes/123456'), {
    childUid:'child',childName:'Alex',createdAt:now(),expiresAt:now()+900000}));
  await assertSucceeds(getDoc(doc(db('child'),'pairCodes/ABCD2345EFGH6789')));
  await assertFails(getDoc(doc(db('stranger'),'pairCodes/123456')));
});
test('guardian sees shared summaries but cannot read private root profile', async () => {
  await seedCode(); await assertSucceeds(pair('parent'));
  await assertSucceeds(setDoc(doc(db('child'),'users/child'), {privateProfile:'local identity'}));
  await assertFails(getDoc(doc(db('parent'),'users/child')));
  await assertSucceeds(getDoc(doc(db('child'),'users/child')));
});
function progress(overrides = {}) {
  return {minutes:30,sessions:1,goalMinutes:180,streak:2,day:'2026-10-12',updatedAt:now(),
    weekMinutes:90,weekSessions:3,weekDays:[0,0,0,30,0,30,30],...overrides};
}
test('parent summary schema rejects private fields, arbitrary records and invalid totals', async () => {
  await assertSucceeds(setDoc(doc(db('child'),'users/child/progress/current'),progress()));
  await assertFails(setDoc(doc(db('child'),'users/child/progress/current'),progress({email:'private@example.invalid'})));
  await assertFails(setDoc(doc(db('child'),'users/child/progress/logs'),progress()));
  await assertFails(setDoc(doc(db('child'),'users/child/progress/current'),progress({minutes:-1})));
  await assertFails(setDoc(doc(db('child'),'users/child/progress/current'),progress({weekDays:[0,0,0,0,0,0,999999]})));
});
test('parent catalog and remote rules reject undocumented top-level data', async () => {
  await seedCode(); await assertSucceeds(pair('parent'));
  await assertSucceeds(setDoc(doc(db('child'),'users/child/catalog/current'),{apps:[{packageId:'com.example.app',name:'Example'}],updatedAt:now()}));
  await assertFails(setDoc(doc(db('child'),'users/child/catalog/current'),{apps:[],updatedAt:now(),usageHistory:[]}));
  const rules={apps:[],youtube:{shorts:false,feed:false,focusOnly:false},enforced:true,updatedAt:now()};
  await assertSucceeds(setDoc(doc(db('parent'),'users/child/remoteRules/current'),rules));
  await assertFails(setDoc(doc(db('parent'),'users/child/remoteRules/current'),{...rules,email:'private@example.invalid'}));
  await assertFails(setDoc(doc(db('parent'),'users/child/remoteRules/other'),rules));
  await assertFails(setDoc(doc(db('parent'),'users/child/remoteRules/current'),{...rules,youtube:{shorts:false,feed:false,focusOnly:false,extra:'private'}}));
});
test('leaderboard accepts bounded weekly summary and rejects invalid timestamp or totals', async () => {
  const ref=doc(db('student'),'leaderboard/2026-10-12/entries/student');
  await assertSucceeds(setDoc(ref,{name:'Alex',minutes:10080,updatedAt:now()}));
  await assertFails(setDoc(ref,{name:'Alex',minutes:10081,updatedAt:now()}));
  await assertFails(setDoc(ref,{name:'Alex',minutes:30,updatedAt:'private'}));
  await assertFails(setDoc(doc(db('student'),'leaderboard/invalid-week/entries/student'),{name:'Alex',minutes:30,updatedAt:now()}));
});
test('legacy cloud records remain removable during account cleanup', async () => {
  await env.withSecurityRulesDisabled(async c => {
    const store=c.firestore();
    await setDoc(doc(store,'users/child/progress/legacy'),{old:'schema'});
    await setDoc(doc(store,'users/child/catalog/legacy'),{old:'schema'});
    await setDoc(doc(store,'leaderboard/legacy/entries/child'),{old:'schema'});
  });
  await assertSucceeds(deleteDoc(doc(db('child'),'users/child/progress/legacy')));
  await assertSucceeds(deleteDoc(doc(db('child'),'users/child/catalog/legacy')));
  await assertSucceeds(deleteDoc(doc(db('child'),'leaderboard/legacy/entries/child')));
});
test('legacy six-digit guardian links remain readable and can be unlinked atomically', async () => {
  await env.withSecurityRulesDisabled(async c => {
    const store=c.firestore();
    await setDoc(doc(store,'users/child/guardian/link'),{parentUid:'parent',parentName:'Parent',linkedAt:now(),pairCode:'123456'});
    await setDoc(doc(store,'users/parent/children/child'),{name:'Child',linkedAt:now()});
    await setDoc(doc(store,'users/child/remoteRules/current'),{old:'schema'});
    await setDoc(doc(store,'users/child/progress/legacy-log'),{privateEmail:'private@example.invalid'});
  });
  await assertSucceeds(getDoc(doc(db('parent'),'users/child/guardian/link')));
  await assertFails(getDoc(doc(db('parent'),'users/child/progress/legacy-log')));
  const store=db('child'), batch=writeBatch(store);
  batch.delete(doc(store,'users/child/guardian/link'));
  batch.delete(doc(store,'users/parent/children/child'));
  batch.delete(doc(store,'users/child/remoteRules/current'));
  await assertSucceeds(batch.commit());
});

const earnedBadgePath = 'users/student/achievements/earned';
function earnedBadges(unlockedAt = {first_focus: now() - 1000}) {
  return {version:1, unlockedAt};
}
test('earned badges are readable only by their linked account owner', async () => {
  const store = db('student');
  await assertSucceeds(setDoc(doc(store, earnedBadgePath), earnedBadges()));
  await assertSucceeds(getDoc(doc(store, earnedBadgePath)));
  await assertSucceeds(getDocs(collection(store, 'users/student/achievements')));
  await assertFails(getDoc(doc(db('stranger'), earnedBadgePath)));
  await assertFails(getDocs(collection(db('stranger'), 'users/student/achievements')));
  await assertFails(getDoc(doc(db('student', true), earnedBadgePath)));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), earnedBadgePath)));
});
test('guardians cannot read or modify a child achievement cabinet', async () => {
  await seedCode(); await assertSucceeds(pair('parent'));
  const path = 'users/child/achievements/earned';
  await assertSucceeds(setDoc(doc(db('child'), path), earnedBadges()));
  await assertFails(getDoc(doc(db('parent'), path)));
  await assertFails(setDoc(doc(db('parent'), path), earnedBadges({first_focus:0})));
  await assertFails(deleteDoc(doc(db('parent'), path)));
});
test('earned badge writes require an authenticated linked owner', async () => {
  await assertFails(setDoc(doc(db('stranger'), earnedBadgePath), earnedBadges()));
  await assertFails(setDoc(doc(db('student', true), earnedBadgePath), earnedBadges()));
  await assertFails(setDoc(doc(env.unauthenticatedContext().firestore(), earnedBadgePath), earnedBadges()));
  await assertSucceeds(setDoc(doc(db('student'), earnedBadgePath), earnedBadges()));
  await assertFails(deleteDoc(doc(db('stranger'), earnedBadgePath)));
  // Account cleanup can also remove legacy anonymous records owned by the UID.
  await assertSucceeds(deleteDoc(doc(db('student', true), earnedBadgePath)));
});
test('achievement backup rejects unknown badge IDs, private fields and invalid dates', async () => {
  const ref = doc(db('student'), earnedBadgePath);
  await assertFails(setDoc(ref, {version:1, unlockedAt:{first_focus:now()}, sessionLog:[]}));
  await assertFails(setDoc(ref, {version:2, unlockedAt:{first_focus:now()}}));
  await assertFails(setDoc(ref, {version:1}));
  await assertFails(setDoc(ref, {version:1, unlockedAt:[]}));
  await assertFails(setDoc(ref, earnedBadges({private_email:'private@example.invalid'})));
  await assertFails(setDoc(ref, earnedBadges({first_focus:'2026-01-01'})));
  await assertFails(setDoc(ref, earnedBadges({first_focus:-1})));
  await assertFails(setDoc(ref, earnedBadges({first_focus:now() + 86400000})));
  await assertFails(setDoc(doc(db('student'), 'users/student/achievements/other'), earnedBadges()));
  await assertSucceeds(setDoc(ref, earnedBadges({first_focus:0, week_warrior:now() - 1000})));
});
test('a complete achievement cabinet can preserve all fourteen earned badges', async () => {
  const ref = doc(db('student'), earnedBadgePath), earnedAt = now() - 1000;
  const unlockedAt = {
    first_focus:earnedAt, week_warrior:earnedAt, century_club:earnedAt,
    night_owl:earnedAt, early_bird:earnedAt, deep_diver:earnedAt,
    steady_hand:earnedAt, month_king:earnedAt, hundred_hours:earnedAt,
    marathon:earnedAt, perfectionist:earnedAt, subject_master:earnedAt,
    night_shift:earnedAt, breath_master:earnedAt,
  };
  await assertSucceeds(setDoc(ref, earnedBadges(unlockedAt)));
  await assertSucceeds(setDoc(ref, earnedBadges(unlockedAt)));
  for (const id of Object.keys(unlockedAt)) {
    await assertFails(setDoc(ref, earnedBadges({...unlockedAt, [id]:-1})));
    await assertFails(setDoc(ref, earnedBadges({...unlockedAt, [id]:earnedAt + 1})));
  }
});
test('achievement merge can add badges and refine their dates without losing past unlocks', async () => {
  const ref = doc(db('student'), earnedBadgePath), early = now() - 5000, late = now() - 1000;
  await assertSucceeds(setDoc(ref, earnedBadges({first_focus:late, night_owl:0})));
  await assertSucceeds(setDoc(ref, earnedBadges({first_focus:early, night_owl:late, early_bird:0})));
  await assertSucceeds(setDoc(ref, earnedBadges({first_focus:early, night_owl:late, early_bird:0})));
  await assertFails(setDoc(ref, earnedBadges({first_focus:early, night_owl:late})));
  await assertFails(setDoc(ref, earnedBadges({first_focus:late, night_owl:late, early_bird:0})));
  await assertFails(setDoc(ref, earnedBadges({first_focus:0, night_owl:late, early_bird:0})));
  await assertSucceeds(deleteDoc(ref));
});

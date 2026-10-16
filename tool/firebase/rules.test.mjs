import { readFileSync } from 'node:fs';
import { before, after, beforeEach, test } from 'node:test';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, getDoc, getDocs, collection, collectionGroup, query, where, setDoc, updateDoc,
  deleteDoc, writeBatch, serverTimestamp, arrayUnion } from 'firebase/firestore';
let env;
const db = (uid, anonymous = false) => env.authenticatedContext(uid, {
  auth_time: Math.floor(Date.now()/1000),
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
test('study backups are private, verified account only, bounded and fenced by deletion', async () => {
  const store=db('student');
  const settings={version:1,ownerUid:'student',data:JSON.stringify({subjects:[]}),modifiedAt:Date.now()};
  const session={ownerUid:'student',id:'s-1',subjectId:'math',label:'Math',startedAt:Date.now(),minutes:240,completed:true};
  await assertSucceeds(setDoc(doc(store,'users/student/preferences/studyBackup'),settings));
  await assertSucceeds(setDoc(doc(store,'users/student/sessionData/s-1'),session));
  await assertSucceeds(getDocs(collection(store,'users/student/sessionData')));
  await assertFails(getDoc(doc(db('other'),'users/student/preferences/studyBackup')));
  await assertFails(getDocs(collection(db('other'),'users/student/sessionData')));
  await assertFails(setDoc(doc(db('other'),'users/student/sessionData/s-2'),session));
  await assertFails(setDoc(doc(db('guest',true),'users/guest/preferences/studyBackup'),{...settings,ownerUid:'guest'}));
  await assertFails(setDoc(doc(store,'users/student/preferences/studyBackup'),{...settings,data:'x'.repeat(300001)}));
  await assertFails(setDoc(doc(store,'users/student/sessionData/s-1'),{...session,minutes:-1}));
  await assertFails(setDoc(doc(store,'users/student/sessionData/s-1'),{...session,ownerUid:'other'}));
  await assertSucceeds(setDoc(doc(store,'accountDeletions/student'),{requestedAt:serverTimestamp()}));
  await assertFails(setDoc(doc(store,'users/student/preferences/studyBackup'),settings));
  await assertFails(setDoc(doc(store,'users/student/sessionData/s-2'),session));
  await assertSucceeds(deleteDoc(doc(store,'users/student/preferences/studyBackup')));
  await assertSucceeds(deleteDoc(doc(store,'users/student/sessionData/s-1')));
});
const now = () => Date.now();
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
  return {ownerUid:'owner',name:'Alex',joinedAt:now(),inviteCode:code,week:'2026-10-05',minutes:30,
    focusUntil:0,updatedAt:serverTimestamp()};
}
function join(uid, code = 'ABCD234567') {
  const store = db(uid), batch = writeBatch(store);
  batch.update(doc(store,'studyGroups/group'), {memberIds:arrayUnion(uid)});
  batch.set(doc(store,'studyGroups/group/members', uid), {...row(code), ownerUid:uid});
  return batch.commit();
}

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

test('leaderboard accepts optional positive integer levels and preserves row ownership', async () => {
  const ref = doc(db('student'), 'leaderboard/2026-10-12/entries/student');
  const summary = {ownerUid:'student',name:'Alex',minutes:60,updatedAt:now()};
  await assertSucceeds(setDoc(ref, summary));
  await assertSucceeds(setDoc(ref, {...summary, level:7}));
  for (const level of [0, -1, 1.5, '7', null]) {
    await assertFails(setDoc(ref, {...summary, level}));
  }
  await assertFails(setDoc(doc(db('other'), 'leaderboard/2026-10-12/entries/student'), {...summary, level:7}));
});
test('leaderboard accepts bounded weekly summary and rejects invalid timestamp or totals', async () => {
  const ref=doc(db('student'),'leaderboard/2026-10-12/entries/student');
  await assertSucceeds(setDoc(ref,{ownerUid:'student',name:'Alex',minutes:10080,updatedAt:now()}));
  await assertFails(setDoc(ref,{ownerUid:'student',name:'Alex',minutes:10081,updatedAt:now()}));
  await assertFails(setDoc(ref,{ownerUid:'student',name:'Alex',minutes:30,updatedAt:'private'}));
  await assertFails(setDoc(doc(db('student'),'leaderboard/invalid-week/entries/student'),{ownerUid:'student',name:'Alex',minutes:30,updatedAt:now()}));
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
test('a complete achievement cabinet can preserve all eighteen earned badges', async () => {
  const ref = doc(db('student'), earnedBadgePath), earnedAt = now() - 1000;
  const unlockedAt = {
    first_focus:earnedAt, week_warrior:earnedAt, century_club:earnedAt,
    night_owl:earnedAt, early_bird:earnedAt, deep_diver:earnedAt,
    steady_hand:earnedAt, month_king:earnedAt, hundred_hours:earnedAt,
    marathon:earnedAt, perfectionist:earnedAt, subject_master:earnedAt,
    night_shift:earnedAt, breath_master:earnedAt,
    five_sessions:earnedAt, three_day_streak:earnedAt,
    five_hours:earnedAt, ten_hours:earnedAt,
  };
  await assertSucceeds(setDoc(ref, earnedBadges(unlockedAt)));
  await assertSucceeds(setDoc(ref, earnedBadges(unlockedAt)));
  for (const id of Object.keys(unlockedAt)) {
    await assertFails(setDoc(ref, earnedBadges({...unlockedAt, [id]:-1})));
    await assertFails(setDoc(ref, earnedBadges({...unlockedAt, [id]:earnedAt + 1})));
    await assertFails(setDoc(ref, earnedBadges({...unlockedAt, [id]:0})));
    const removed = {...unlockedAt};
    delete removed[id];
    await assertFails(setDoc(ref, earnedBadges(removed)));
  }
});
test('intermediate badges retain the same private ownership and date validation', async () => {
  const ref = doc(db('student'), earnedBadgePath), earnedAt = now() - 5000;
  await assertSucceeds(setDoc(ref, earnedBadges({five_sessions:0})));
  await assertSucceeds(setDoc(ref, earnedBadges({five_sessions:earnedAt, three_day_streak:earnedAt, five_hours:earnedAt, ten_hours:earnedAt})));
  for (const id of ['five_sessions','three_day_streak','five_hours','ten_hours']) {
    await assertFails(setDoc(doc(db('stranger'), earnedBadgePath), earnedBadges({[id]:earnedAt})));
    await assertFails(setDoc(doc(db('anon',true), 'users/anon/achievements/earned'), earnedBadges({[id]:earnedAt})));
    await assertFails(setDoc(doc(db('student'), 'users/student/achievements/invalid'), earnedBadges({[id]:earnedAt})));
    await assertFails(setDoc(ref, earnedBadges({five_sessions:earnedAt, three_day_streak:earnedAt, five_hours:earnedAt, ten_hours:earnedAt, [id]:now() + 86400000})));
  }
  await assertFails(getDoc(doc(db('stranger'), earnedBadgePath)));
  await assertSucceeds(deleteDoc(ref));
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

test('retired paths allow private owner cleanup but never new monitoring writes', async () => {
  const paths = ['users/child/guardian/link', 'users/child/catalog/current',
    'users/child/progress/current', 'users/child/remoteRules/current'];
  await env.withSecurityRulesDisabled(async c => {
    for (const path of paths) await setDoc(doc(c.firestore(), path), {parentUid:'parent',private:'legacy'});
  });
  for (const path of paths) {
    await assertSucceeds(getDoc(doc(db('child'), path)));
    await assertFails(getDoc(doc(db('parent'), path)));
    await assertFails(deleteDoc(doc(db('parent'), path)));
    await assertFails(setDoc(doc(db('child'), path), {parentUid:'parent'}));
    await assertSucceeds(deleteDoc(doc(db('child'), path)));
  }
  await assertFails(getDocs(collection(db('child'), 'pairCodes')));
  await assertFails(setDoc(doc(db('child'), 'pairCodes/NEW23456ABCDEFGH'), {childUid:'child'}));
});
test('an account being deleted cannot republish badges, board rows or join groups', async () => {
  await seedGroup();
  await env.withSecurityRulesDisabled(c => setDoc(doc(c.firestore(), 'accountDeletions/student'), {requestedAt:now()}));
  await assertFails(setDoc(doc(db('student'), earnedBadgePath), earnedBadges()));
  await assertFails(setDoc(doc(db('student'), 'leaderboard/2026-10-12/entries/student'), {ownerUid:'student',name:'Alex',minutes:30,updatedAt:now()}));
  await assertFails(join('student'));
  await assertSucceeds(getDoc(doc(db('student'), 'accountDeletions/student')));
  await assertFails(deleteDoc(doc(db('student'), 'accountDeletions/student')));
});


test('client deletion marker is owner-only, immutable and requires fresh authentication', async () => {
  const store = db('student');
  await assertFails(setDoc(doc(store, 'accountDeletions/stranger'), {requestedAt:serverTimestamp()}));
  const stale = env.authenticatedContext('student', {auth_time:1, firebase:{sign_in_provider:'google.com'}}).firestore();
  await assertFails(setDoc(doc(stale,'accountDeletions/student'), {requestedAt:serverTimestamp()}));
  await assertSucceeds(setDoc(doc(store,'accountDeletions/student'), {requestedAt:serverTimestamp()}));
  await assertFails(updateDoc(doc(store,'accountDeletions/student'), {requestedAt:serverTimestamp()}));
  await assertFails(deleteDoc(doc(store,'accountDeletions/student')));
  await assertFails(getDoc(doc(db('stranger'),'accountDeletions/student')));
});
test('deletion marker still permits owner cleanup and group departure', async () => {
  await seedGroup(); await assertSucceeds(join('friend'));
  const store = db('owner');
  await assertSucceeds(setDoc(doc(store,'users/owner/achievements/earned'),earnedBadges()));
  await assertSucceeds(setDoc(doc(store,'accountDeletions/owner'),{requestedAt:serverTimestamp()}));
  await assertSucceeds(getDoc(doc(store,'users/owner/achievements/earned')));
  await assertSucceeds(deleteDoc(doc(store,'users/owner/achievements/earned')));
  await assertFails(setDoc(doc(store,'users/owner'),{name:'Recreated'}));
  const batch = writeBatch(store);
  batch.update(doc(store,'studyGroups/group'),{memberIds:['friend'],ownerUid:'friend'});
  batch.delete(doc(store,'studyGroups/group/members/owner'));
  await assertSucceeds(batch.commit());
});
test('collection group cleanup sees only caller entries and orphaned members', async () => {
  await env.withSecurityRulesDisabled(async c => {
    const store = c.firestore();
    await setDoc(doc(store,'leaderboard/2024-01-01/entries/student'),{ownerUid:'student',name:'Alex',minutes:10,updatedAt:now()});
    await setDoc(doc(store,'leaderboard/2024-01-01/entries/other'),{ownerUid:'other',name:'Other',minutes:20,updatedAt:now()});
    await setDoc(doc(store,'studyGroups/missing/members/student'),{ownerUid:'student',name:'Alex'});
  });
  const store = db('student');
  const entries = await assertSucceeds(getDocs(query(collectionGroup(store,'entries'),where('ownerUid','==','student'))));
  if (entries.size !== 1) throw Error('Missing historical row');
  await assertFails(getDocs(query(collectionGroup(store,'members'),where('ownerUid','==','other'))));
  const members = await assertSucceeds(getDocs(query(collectionGroup(store,'members'),where('ownerUid','==','student'))));
  if (members.size !== 1) throw Error('Missing orphan member');
  await assertFails(deleteDoc(doc(store,'studyGroups/missing/members/student')));
  await assertSucceeds(setDoc(doc(store,'accountDeletions/student'),{requestedAt:serverTimestamp()}));
  await assertSucceeds(deleteDoc(doc(store,'studyGroups/missing/members/student')));
  await assertSucceeds(deleteDoc(doc(store,'leaderboard/2024-01-01/entries/student')));
  await assertFails(deleteDoc(doc(store,'leaderboard/2024-01-01/entries/other')));
});
test('nested owner cleanup and immutable inventory do not grant write or foreign access', async () => {
  await env.withSecurityRulesDisabled(async c => {
    await setDoc(doc(c.firestore(),'users/student/archive/year/nested/session'),{private:'value'});
    await setDoc(doc(c.firestore(),'users/student/deletionRefs/record'),{path:'users/student/archive/year/nested/session'});
    await setDoc(doc(c.firestore(),'accountCleanup/schema'),{version:2});
  });
  const store = db('student');
  await assertSucceeds(getDoc(doc(store,'accountCleanup/schema')));
  await assertFails(setDoc(doc(store,'accountCleanup/schema'),{version:2}));
  await assertSucceeds(getDocs(collection(store,'users/student/deletionRefs')));
  await assertFails(getDoc(doc(db('stranger'),'users/student/archive/year/nested/session')));
  await assertFails(setDoc(doc(store,'users/student/deletionRefs/fake'),{path:'users/other'}));
  await assertFails(setDoc(doc(store,'users/student/archive/year/nested/session'),{private:'modified'}));
  await assertSucceeds(deleteDoc(doc(store,'users/student/archive/year/nested/session')));
});
test('legacy anonymous credential can cleanup private records after confirming deletion', async () => {
  await env.withSecurityRulesDisabled(async c => {
    await setDoc(doc(c.firestore(),'users/anon/achievements/earned'),earnedBadges());
  });
  const store = db('anon',true);
  await assertSucceeds(setDoc(doc(store,'accountDeletions/anon'),{requestedAt:serverTimestamp()}));
  await assertSucceeds(getDocs(query(collection(store,'studyGroups'),where('memberIds','array-contains','anon'))));
  await assertSucceeds(getDoc(doc(store,'users/anon/achievements/earned')));
  await assertSucceeds(deleteDoc(doc(store,'users/anon/achievements/earned')));
});
test('orphan cleanup page fits security-call budget across eight different group parents', async () => {
  await env.withSecurityRulesDisabled(async c => {
    for (let i=0;i<8;i++) await setDoc(doc(c.firestore(),'studyGroups/missing-'+i+'/members/student'),{ownerUid:'student'});
  });
  const store = db('student');
  await assertSucceeds(setDoc(doc(store,'accountDeletions/student'),{requestedAt:serverTimestamp()}));
  const batch=writeBatch(store);
  for(let i=0;i<8;i++) batch.delete(doc(store,'studyGroups/missing-'+i+'/members/student'));
  await assertSucceeds(batch.commit());
});
test('paged orphan cleanup removes thirty groups without exceeding batch rule calls', async () => {
  await env.withSecurityRulesDisabled(async c => {
    for(let i=0;i<30;i++) await setDoc(doc(c.firestore(),'studyGroups/old-'+i+'/members/student'),{ownerUid:'student'});
  });
  const store=db('student');
  await assertSucceeds(setDoc(doc(store,'accountDeletions/student'),{requestedAt:serverTimestamp()}));
  let removed=0;
  while(true) {
    const snapshot=await getDocs(query(collectionGroup(store,'members'),where('ownerUid','==','student')));
    const page=snapshot.docs.slice(0,8);
    if(!page.length) break;
    const batch=writeBatch(store);
    for(const member of page) batch.delete(member.ref);
    await assertSucceeds(batch.commit());
    removed+=page.length;
  }
  if(removed!==30) throw Error('Missed orphan records');
});

test('unverified password credentials cannot create cloud profiles, badges or social data but retain owner cleanup', async () => {
  const uid = 'email-new';
  const unverified = env.authenticatedContext(uid, {
    email_verified:false,
    auth_time:Math.floor(Date.now()/1000),
    firebase:{sign_in_provider:'password'},
  }).firestore();
  await assertFails(setDoc(doc(unverified,'users',uid),{name:'Unverified'}));
  await assertFails(setDoc(doc(unverified,'users',uid,'achievements','earned'),earnedBadges()));
  await assertFails(setDoc(doc(unverified,'leaderboard/2026-10-12/entries',uid),{ownerUid:uid,name:'Unverified',minutes:10,updatedAt:now()}));
  await assertFails(getDoc(doc(unverified,'groupInvites/ABCD234567')));
  await env.withSecurityRulesDisabled(async context => {
    await setDoc(doc(context.firestore(),'users',uid),{name:'Legacy'});
    await setDoc(doc(context.firestore(),'users',uid,'achievements','earned'),earnedBadges());
  });
  await assertSucceeds(deleteDoc(doc(unverified,'users',uid,'achievements','earned')));
  await assertSucceeds(deleteDoc(doc(unverified,'users',uid)));
});

test('verified password credentials can save private profile and badges', async () => {
  const uid = 'email-verified';
  const verified = env.authenticatedContext(uid, {
    email_verified:true,
    firebase:{sign_in_provider:'password'},
  }).firestore();
  await assertSucceeds(setDoc(doc(verified,'users',uid),{name:'Verified'}));
  await assertSucceeds(setDoc(doc(verified,'users',uid,'achievements','earned'),earnedBadges()));
});

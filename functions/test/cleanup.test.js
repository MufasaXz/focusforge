import {test} from 'node:test';
import assert from 'node:assert/strict';
import {initializeApp, deleteApp} from 'firebase-admin/app';
import {getFirestore} from 'firebase-admin/firestore';
import {cleanupAccount, requireDeletionIdentity} from '../cleanup.js';

test('deletion requires verified caller identity and recent login, not a supplied UID', () => {
  const now = Date.now();
  assert.throws(() => requireDeletionIdentity(null, now), /authentication/);
  assert.throws(() => requireDeletionIdentity({uid:'victim',token:{auth_time:1}},now), /recent login/);
  assert.throws(() => requireDeletionIdentity({uid:'caller',token:{auth_time:now/1000 + 600}},now), /recent login/);
  assert.equal(requireDeletionIdentity({uid:'caller',token:{auth_time:now/1000}},now), 'caller');
});

test('cleanup removes historical rows and legacy links, transfers groups, preserves other users and is retryable', {skip:!process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  const app=initializeApp({projectId:'demo-focusforge'}, 'cleanup-tests');
  const db=getFirestore(app);
  const uid='cleanup-test-user', other='cleanup-survivor';
  const put=(path,data)=>db.doc(path).set(data);
  await put('users/'+uid,{name:'Delete'});
  await put('users/'+uid+'/achievements/earned',{version:1,unlockedAt:{first_focus:0}});
  await put('users/'+other+'/achievements/earned',{version:1,unlockedAt:{night_owl:0}});
  await put('users/'+uid+'/guardian/link',{parentUid:other});
  await put('users/'+other+'/children/'+uid,{name:'Delete'});
  await put('users/cleanup-former-parent/children/'+uid,{name:'Stale reverse link'});
  await put('users/cleanup-child/guardian/link',{parentUid:uid});
  await put('users/cleanup-child/remoteRules/current',{apps:['old']});
  await put('users/cleanup-child/progress/current',{minutes:12});
  await put('users/cleanup-child/catalog/current',{apps:['private']});
  await put('pairCodes/cleanup-unused',{childUid:uid});
  await put('pairCodes/cleanup-claimed',{childUid:'cleanup-child',claimedBy:uid});
  for(const week of ['1900-01-01','2026-10-12']) {
    await put('leaderboard/'+week+'/entries/'+uid,{name:'Delete'});
    await put('leaderboard/'+week+'/entries/'+other,{name:'Keep'});
  }
  await put('studyGroups/cleanup-shared',{ownerUid:uid,memberIds:[uid,other],inviteCode:'cleanup-invite'});
  await put('studyGroups/cleanup-shared/members/'+uid,{name:'Delete'});
  await put('studyGroups/cleanup-shared/members/'+other,{name:'Keep'});
  await put('studyGroups/cleanup-last',{ownerUid:uid,memberIds:[uid],inviteCode:'cleanup-last-invite'});
  await put('studyGroups/cleanup-last/members/'+uid,{name:'Delete'});
  await put('groupInvites/cleanup-last-invite',{groupId:'cleanup-last'});
  await put('studyGroups/cleanup-orphan/members/'+uid,{name:'Delete'});
  let failed=true, authDeleted=false;
  const removeAuth=async()=>{if(failed)throw Error('temporary Auth failure'); authDeleted=true;};
  await assert.rejects(cleanupAccount(db,uid,removeAuth), /temporary Auth failure/);
  assert.equal(authDeleted,false);
  assert.equal((await db.doc('accountDeletions/'+uid).get()).exists,true);
  assert.equal((await db.doc('users/'+uid+'/achievements/earned').get()).exists,false);
  failed=false;
  await cleanupAccount(db,uid,removeAuth);
  assert.equal(authDeleted,true);
  await cleanupAccount(db,uid,async()=>{throw Error('completed deletion must be a no-op');});
  assert.equal((await db.doc('accountDeletions/'+uid).get()).data().status,'complete');
  assert.ok((await db.doc('accountDeletions/'+uid).get()).data().expiresAt);
  for(const path of ['users/'+uid,'users/'+other+'/children/'+uid,'users/cleanup-former-parent/children/'+uid,'users/cleanup-child/guardian/link',
    'users/cleanup-child/remoteRules/current','users/cleanup-child/progress/current','users/cleanup-child/catalog/current',
    'pairCodes/cleanup-unused','pairCodes/cleanup-claimed','studyGroups/cleanup-last','groupInvites/cleanup-last-invite',
    'studyGroups/cleanup-orphan/members/'+uid]) {
    assert.equal((await db.doc(path).get()).exists,false,path);
  }
  assert.deepEqual((await db.doc('studyGroups/cleanup-shared').get()).data().memberIds,[other]);
  assert.equal((await db.doc('studyGroups/cleanup-shared').get()).data().ownerUid,other);
  assert.equal((await db.doc('users/'+other+'/achievements/earned').get()).exists,true);
  for(const week of ['1900-01-01','2026-10-12']) {
    assert.equal((await db.doc('leaderboard/'+week+'/entries/'+uid).get()).exists,false);
    assert.equal((await db.doc('leaderboard/'+week+'/entries/'+other).get()).exists,true);
  }
  await deleteApp(app);
});

import {FieldValue, Timestamp} from 'firebase-admin/firestore';

export function requireDeletionIdentity(auth, now=Date.now()) {
  if (!auth?.uid) throw Error('authentication required');
  if(auth.token?.firebase?.sign_in_provider==='anonymous') return auth.uid;
  const age=now/1000 - Number(auth.token?.auth_time);
  if (!Number.isFinite(age) || age < -60 || age > 300) throw Error('recent login required');
  return auth.uid;
}

async function deleteRefs(db, refs) {
  for(let start=0;start<refs.length;start+=400) {
    const batch=db.batch();
    for(const ref of refs.slice(start,start+400)) batch.delete(ref);
    await batch.commit();
  }
}
async function deleteMatching(db, query) {
  while(true) {
    const page=await query.limit(400).get();
    if(page.empty) return;
    await deleteRefs(db,page.docs.map(d=>d.ref));
  }
}

// Only the trusted backend calls this. Never accept a target UID from an app.
export async function cleanupAccount(db, uid, deleteAuth) {
  const marker=db.doc('accountDeletions/'+uid);
  // Rules stop stale sessions and older devices from recreating deleted data.
  const pending = await db.runTransaction(async tx => {
    const previous = await tx.get(marker);
    if (previous.data()?.status === 'complete') return false;
    tx.set(marker, {requestedAt:FieldValue.serverTimestamp(),status:'pending'});
    return true;
  });
  if (!pending) return;
  const groups=await db.collection('studyGroups').where('memberIds','array-contains',uid).get();
  for(const group of groups.docs) {
    await db.runTransaction(async tx=>{
      const latest=await tx.get(group.ref);
      if(!latest.exists) return;
      const data=latest.data(), ids=(data.memberIds ?? []).filter(id=>id!==uid);
      tx.delete(group.ref.collection('members').doc(uid));
      if(!ids.length) {
        tx.delete(group.ref);
        if(typeof data.inviteCode==='string') tx.delete(db.doc('groupInvites/'+data.inviteCode));
        return;
      }
      tx.update(group.ref,{memberIds:ids,ownerUid:data.ownerUid===uid ? ids[0] : data.ownerUid});
    });
  }
  // listDocuments includes missing parent docs with extant subcollections.
  // Legacy entries have no UID field, so query-by-UID would miss them.
  const weeks=await db.collection('leaderboard').listDocuments();
  await deleteRefs(db,weeks.map(week=>week.collection('entries').doc(uid)));
  const allGroups=await db.collection('studyGroups').listDocuments();
  await deleteRefs(db,allGroups.map(group=>group.collection('members').doc(uid)));
  await deleteMatching(db,db.collection('pairCodes').where('childUid','==',uid));
  await deleteMatching(db,db.collection('pairCodes').where('claimedBy','==',uid));
  // Reverse links may be orphaned after a changed or missing guardian link.
  const users = await db.collection('users').listDocuments();
  await deleteRefs(db,users.map(user=>user.collection('children').doc(uid)));
  const children=await db.collectionGroup('guardian').where('parentUid','==',uid).get();
  for(const link of children.docs) {
    const child=link.ref.parent.parent;
    if(!child || child.parent.id!=='users' || link.id!=='link') continue;
    for(const sub of ['remoteRules','progress','catalog']) await db.recursiveDelete(child.collection(sub));
    await link.ref.delete();
  }
  // Recursion covers achievements and unknown/old-schema account subcollections.
  await db.recursiveDelete(db.doc('users/'+uid));
  // Auth removal is last; any prior failure leaves a credential for retry.
  await deleteAuth(uid);
  // Retain only UID/time for 24h: revoked ID tokens remain usable for ~1h.
  // Enable Firestore TTL on expiresAt; no email/profile is retained here.
  await marker.set({status:'complete',completedAt:FieldValue.serverTimestamp(),
    expiresAt:Timestamp.fromMillis(Date.now()+24*60*60*1000)}, {merge:true});
}

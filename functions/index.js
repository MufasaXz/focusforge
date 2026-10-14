import {initializeApp} from 'firebase-admin/app';
import {getAuth} from 'firebase-admin/auth';
import {getFirestore} from 'firebase-admin/firestore';
import {onCall, HttpsError} from 'firebase-functions/v2/https';
import {onSchedule} from 'firebase-functions/v2/scheduler';
import {cleanupAccount, requireDeletionIdentity} from './cleanup.js';
initializeApp();
const db=getFirestore();
async function deleteAuth(uid) {
  try { await getAuth().deleteUser(uid); }
  catch(e) { if(e.code!=='auth/user-not-found') throw e; }
}
export const deleteFocusForgeAccount=onCall({region:'us-central1',timeoutSeconds:540,
  memory:'512MiB',maxInstances:3},async request=>{
  let uid;
  try { uid=requireDeletionIdentity(request.auth); }
  catch(e) { throw new HttpsError(request.auth ? 'failed-precondition' : 'unauthenticated',e.message); }
  try { await cleanupAccount(db,uid,deleteAuth); }
  catch { throw new HttpsError('unavailable','Cleanup is not finished. Retry deletion or contact support.'); }
  return {deleted:true};
});
// Resume a deletion interrupted after the user explicitly requested it.
export const retryAccountDeletions=onSchedule({schedule:'every 60 minutes',region:'us-central1',
  timeoutSeconds:540,memory:'512MiB',maxInstances:1},async()=>{
  const requests=await db.collection('accountDeletions').where('status','==','pending').limit(100).get();
  for(const request of requests.docs) {
    if(request.data().completedAt) continue;
    try { await cleanupAccount(db,request.id,deleteAuth); }
    catch { console.error('Account cleanup retry failed; pending job retained.'); }
  }
});

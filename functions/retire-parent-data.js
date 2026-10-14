// Run once with a project administrator AFTER publishing the retired rules.
// This removes only the explicitly retired monitoring paths, not study data.
import {initializeApp} from 'firebase-admin/app';
import {getFirestore} from 'firebase-admin/firestore';
const projectId=process.argv[2];
if(!projectId || process.argv[3]!=='--confirm-retire-parent-control') {
 throw Error('Usage: node retire-parent-data.js PROJECT --confirm-retire-parent-control');
}
initializeApp({projectId});
const db=getFirestore();
await db.recursiveDelete(db.collection('pairCodes'));
for(const user of await db.collection('users').listDocuments()) {
 for(const sub of ['guardian','children','remoteRules','progress','catalog']) {
  await db.recursiveDelete(user.collection(sub));
 }
}
console.log('Retired parent-control records removed. Study and achievement paths preserved.');

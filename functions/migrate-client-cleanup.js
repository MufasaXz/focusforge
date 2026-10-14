// One-time local administrator migration; no deployed backend or billing plan.
import {createHash} from 'node:crypto';
import {initializeApp} from 'firebase-admin/app';
import {getFirestore, FieldValue} from 'firebase-admin/firestore';
import {fileURLToPath} from 'node:url';
export async function migrateClientCleanup(db) {
  const schema = db.doc('accountCleanup/schema');
  await schema.set({version:1, startedAt:FieldValue.serverTimestamp()});
  await db.recursiveDelete(db.collection('pairCodes'));
  const users = await db.collection('users').listDocuments();
  for (const user of users) {
    for (const retired of ['guardian','children','remoteRules','progress','catalog']) {
      await db.recursiveDelete(user.collection(retired));
    }
    async function inventory(parent) {
      for (const collection of await parent.listCollections()) {
        if (collection.id === 'deletionRefs' && parent.path === user.path) continue;
        for (const doc of await collection.listDocuments()) {
          const key = createHash('sha256').update(doc.path).digest('hex');
          await user.collection('deletionRefs').doc(key).set({path:doc.path});
          await inventory(doc);
        }
      }
    }
    await inventory(user);
  }
  for (const week of await db.collection('leaderboard').listDocuments()) {
    const entries = await week.collection('entries').get();
    for (const entry of entries.docs) await entry.ref.update({ownerUid:entry.id});
  }
  for (const group of await db.collection('studyGroups').listDocuments()) {
    const members = await group.collection('members').get();
    for (const member of members.docs) await member.ref.update({ownerUid:member.id});
  }
  await schema.set({version:2, completedAt:FieldValue.serverTimestamp()});
}
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const project = process.argv[2];
  if (!project || process.argv[3] !== '--confirm-client-cleanup-migration') {
    throw Error('Usage: node functions/migrate-client-cleanup.js PROJECT --confirm-client-cleanup-migration');
  }
  initializeApp({projectId:project});
  await migrateClientCleanup(getFirestore());
  console.log('Client cleanup migration complete. No user profile data printed.');
}

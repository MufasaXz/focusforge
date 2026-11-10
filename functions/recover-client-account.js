// Local administrator recovery after the owner asks to keep an interrupted
// client-deletion account. Never deploy this as a callable client endpoint.
import {initializeApp} from 'firebase-admin/app';
import {getAuth} from 'firebase-admin/auth';
import {getFirestore, FieldValue, Timestamp} from 'firebase-admin/firestore';
import {fileURLToPath} from 'node:url';

const tokenWait = 65 * 60 * 1000;
function refs(db, uid) {
  if (!uid || uid.includes('/') || uid.length > 128) throw Error('Invalid UID');
  return {marker:db.doc('accountDeletions/'+uid), recovery:db.doc('_accountRecoveries/'+uid)};
}
function clientFence(snapshot) {
  const data = snapshot.data();
  if (!snapshot.exists || Object.keys(data).length !== 1 ||
      !(data.requestedAt instanceof Timestamp)) {
    throw Error('Only a timestamp-only client deletion fence can be recovered');
  }
}
function sameIdentity(user, operation) {
  if (!user.metadata.creationTime || user.metadata.creationTime !== operation.authCreatedAt) {
    throw Error('Auth identity changed; keep the fence and investigate');
  }
}
function sameFence(marker, operation) {
  clientFence(marker);
  if (!marker.updateTime.isEqual(operation.markerVersion)) throw Error('Deletion fence changed');
}

export async function beginRecovery(db, auth, uid) {
  const {marker, recovery} = refs(db, uid);
  const user = await auth.getUser(uid);
  if (!user.metadata.creationTime) throw Error('Missing Auth identity metadata');
  await db.runTransaction(async tx => {
    const fence = await tx.get(marker);
    const previous = await tx.get(recovery);
    clientFence(fence);
    if (previous.exists) {
      const operation = previous.data();
      sameIdentity(user, operation);
      sameFence(fence, operation);
      if (!['preparing','waiting'].includes(operation.phase)) throw Error('Finish the existing recovery');
    } else if (user.disabled) {
      throw Error('Account was already disabled; do not override another administrator');
    }
    tx.set(recovery, {phase:'preparing', authCreatedAt:user.metadata.creationTime,
      markerVersion:fence.updateTime});
  });
  // Keep the fence throughout the wait. Disabling stops new credentials;
  // revocation stops refresh tokens. Firestore ID tokens last up to an hour.
  await auth.updateUser(uid, {disabled:true});
  await auth.revokeRefreshTokens(uid);
  const blocked = await auth.getUser(uid);
  sameIdentity(blocked, {authCreatedAt:user.metadata.creationTime});
  if (!blocked.disabled || !Number.isFinite(Date.parse(blocked.tokensValidAfterTime))) {
    throw Error('Could not verify disabled Auth sessions');
  }
  await recovery.update({phase:'waiting', blockedAt:FieldValue.serverTimestamp(),
    tokensValidAfterTime:blocked.tokensValidAfterTime});
}

export async function finishRecovery(db, auth, uid) {
  const {marker, recovery} = refs(db, uid);
  let snapshot = await recovery.get();
  const operation = snapshot.data();
  if (!operation || !['waiting','released'].includes(operation.phase)) {
    throw Error('Begin recovery before finishing it');
  }
  const user = await auth.getUser(uid); // Deleted accounts must keep their fence.
  sameIdentity(user, operation);
  if (operation.phase === 'waiting') {
    if (!user.disabled) throw Error('Account must stay disabled throughout recovery');
    const blockedAt = operation.blockedAt;
    if (!(blockedAt instanceof Timestamp) || snapshot.readTime.toMillis()-blockedAt.toMillis() < tokenWait) {
      throw Error('Wait at least 65 minutes after begin before finishing recovery');
    }
    const sessionDates = [user.tokensValidAfterTime, user.metadata.lastSignInTime,
      user.metadata.lastRefreshTime].filter(value => value != null);
    if (user.tokensValidAfterTime !== operation.tokensValidAfterTime ||
        sessionDates.some(value => !Number.isFinite(Date.parse(value)) || Date.parse(value) > blockedAt.toMillis())) {
      throw Error('Auth session state changed; begin a new waiting period');
    }
    // The Admin SDK rounds revocation to seconds and uses the operator's
    // clock. Revoke again after the wait, then prove that the cutoff is past
    // every pre-disable session and is not ahead of Firestore's server clock.
    await auth.revokeRefreshTokens(uid);
    const revoked = await auth.getUser(uid);
    sameIdentity(revoked, operation);
    if (!revoked.disabled) throw Error('Account must stay disabled throughout recovery');
    const cutoff = Date.parse(revoked.tokensValidAfterTime);
    await db.runTransaction(async tx => {
      const current = await tx.get(recovery);
      const fence = await tx.get(marker);
      if (!current.updateTime?.isEqual(snapshot.updateTime)) throw Error('Recovery changed; retry');
      if (!Number.isFinite(cutoff) || cutoff <= blockedAt.toMillis() || cutoff > current.readTime.toMillis()) {
        throw Error('Unsafe revocation cutoff; check the administrator clock and begin again');
      }
      sameFence(fence, operation);
      tx.delete(marker);
      tx.update(recovery, {phase:'released'});
    });
    snapshot = await recovery.get();
  }
  // Persist the released phase first: a failed Auth update is retryable without
  // dropping any new fence that might be created after a successful sign-in.
  if (user.disabled) await auth.updateUser(uid, {disabled:false});
  await recovery.delete({lastUpdateTime:snapshot.updateTime});
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const [project, uid, action, confirm] = process.argv.slice(2);
  if (!project || !uid || !['inspect','begin','finish'].includes(action) ||
      (action !== 'inspect' && confirm !== '--confirm-account-recovery')) {
    throw Error('Usage: node functions/recover-client-account.js PROJECT UID inspect|begin|finish [--confirm-account-recovery]');
  }
  initializeApp({projectId:project});
  const db = getFirestore(), auth = getAuth();
  if (action === 'inspect') {
    const {marker, recovery} = refs(db, uid);
    const user = await auth.getUser(uid);
    const fence = await marker.get(), operation = await recovery.get();
    console.log({accountExists:true, disabled:user.disabled, deletionFence:fence.exists,
      recoveryPhase:operation.data()?.phase ?? 'not-started'});
  } else if (action === 'begin') {
    await beginRecovery(db, auth, uid);
    console.log('Account disabled; fence retained. Wait at least 65 minutes before finish.');
  } else {
    await finishRecovery(db, auth, uid);
    console.log('Recovery finished. Sign in again. Previously deleted cloud records are not restored.');
  }
}

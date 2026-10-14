# Firebase: first Play release candidate 1.0.0 (2022)

Firebase powers authentication, private earned-badge backups, private groups and
the optional weekly leaderboard. Parent control has been removed. Detailed
sessions, app usage and installed-app lists stay on the device. Supply the
ignored android/app/google-services.json locally. Client API keys remain visible
inside APKs; protect data with server rules and compatible API/app restrictions.

## Deploy before public distribution

The owner will publish Firestore rules. **No production rules, indexes or functions
were deployed here.** Project administrator access and Functions/Scheduler billing
are needed. From the repository root, use Node 22+; emulator checks need Java 21:

    npm ci --prefix tool/firebase
    npm ci --prefix functions
    tool/firebase/node_modules/.bin/firebase login
    tool/firebase/node_modules/.bin/firebase deploy --only firestore --project focusforge-1edf7
    tool/firebase/node_modules/.bin/firebase deploy --only functions:focusforge-account-cleanup --project focusforge-1edf7

Deploy both firestore.rules and firestore.indexes.json. If using the console
rules editor, also publish the indexes file. It adds collection-group indexing
on guardian.parentUid and TTL on accountDeletions.expiresAt. Wait for indexing
before public use. Callable deleteFocusForgeAccount is in us-central1, matching
the client's default region. Rules alone are insufficient for the delete button.

Revised rules deny retired pairing, guardian, children, catalog, progress and
remoteRules paths to all clients, including older APKs. Achievements remain
owner-private; groups remain member-only. Publishing rules does not physically
erase legacy records. Their cleanup requires trusted Admin SDK access.

This candidate adds four earned-badge IDs: five_sessions, three_day_streak,
five_hours and ten_hours. Publish the matching rules before distributing it.
Older rules reject these new IDs; the app retains earned badges locally and
shows pending backup until compatible rules are available. Existing badge IDs
and dates are preserved.

## Account cleanup and retries

The callable derives the target from Firebase's verified caller UID. It accepts
no supplied target UID. Linked accounts must authenticate within five minutes;
anonymous accounts may remove their own credential without a password.

A private deletion marker stops stale sessions/devices uploading more data.
Cleanup transfers group ownership to a remaining member, removes a last-member
group and invite, deletes member rows, walks every leaderboard week (including
weeks absent from local history), removes old pair codes and two-sided links,
and recursively deletes account subcollections including badges. Auth is last.

An hourly scheduler retries pending jobs; monitor failures. Success keeps only
UID/timestamps/status for 24 hours to block old ID tokens, then TTL deletes that
marker asynchronously. Physical deletion is not guaranteed at the exact expiry
instant. Local data clears only after the app receives a successful response.
A lost response or later scheduled completion can leave local history after
cloud deletion; support must confirm status and explain Android app-storage
clearing. Other devices' local history cannot be remotely erased.

Deleting Auth directly in Firebase Console does not invoke this callable. For
verified external requests, run cleanupAccount with Admin SDK and delete Auth
last. No live external-request fulfillment is claimed here.

Legacy board rows lack a UID field, so cleanup enumerates all week/group parents
rather than exposing a broad client query. Monitor reads/runtime at scale; an
indexed ownership ledger is needed if cleanup exceeds its 540-second limit.

## Production checks

- Register the Play App Signing certificate with Firebase and verify login.
- Earn a disposable badge, sign out/back in and verify private restoration.
  Backed-up badges have no inactivity expiry; detailed sessions remain local.
- Create a two-member group as owner, publish multiple board weeks and delete
  the disposable account. Verify Auth, subcollections, every board/member row,
  old pair codes, retry job status and TTL with administrator access.
- Confirm an old token cannot recreate records while the tombstone exists.
- Monitor the deletion inbox, scheduler and errors; safely verify ownership.

## Emulator evidence

    npm test --prefix tool/firebase
    npm run test:emulator --prefix functions

These test authorization and real Firestore cleanup locally, not production
configuration. No Firebase administrator is logged in here. Signing out retains
setup/history on the same installation; uninstalling loses unbacked local data.

## Retire stored monitoring records

After publishing the deny rules, a project administrator can remove retired
records without deleting study history or achievements. Review the script first:

    cd functions
    node retire-parent-data.js focusforge-1edf7 --confirm-retire-parent-control

It requires Application Default Credentials with Firestore administrator access.
It removes pairCodes and only guardian/children/remoteRules/progress/catalog
subcollections under users. It does not bypass deployment permissions or run in
this workspace. Keep older apps blocked by the new rules while it runs.

## Community reports

Community terms are shown before group creation/join and leaderboard opt-in.
Users can report a group or member by private email and hide a member's rows.
Local hide choices are account-scoped and removed with local account data.
There is no chat or media posting. The developer must monitor reports, review
reported names privately and remove prohibited content/disable abusive accounts
with administrator access. Email drafting alone does not prove moderation works.

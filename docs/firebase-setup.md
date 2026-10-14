# Firebase: FocusForge 1.0.0 (2024)

Deletion runs through the Firebase Auth and Firestore client SDKs. No Extension,
Cloud Function, Scheduler, Blaze plan or TTL is required. Spark's normal
storage/read/write/delete quotas still apply. Retired Functions code is not
deployed by firebase.json and is not called by the app.

Firebase stores credentials, private badges, private groups and the optional
weekly leaderboard. Detailed sessions, settings, app usage and installed-app
lists stay on device. Parent control is removed. API keys in APKs are public
client identifiers; server rules enforce ownership.

## Activate client deletion

The owner elected to run these steps themselves. Use a project administrator
with Node 22+ and Google Cloud CLI. From the repository root:

    npm ci --prefix tool/firebase
    npm ci --prefix functions
    tool/firebase/node_modules/.bin/firebase login
    tool/firebase/node_modules/.bin/firebase deploy --only firestore --project focusforge-1edf7
    gcloud auth application-default login
    node functions/migrate-client-cleanup.js focusforge-1edf7 --confirm-client-cleanup-migration

Deploy BOTH firestore.rules and firestore.indexes.json. Wait for the ascending
collection-group ownerUid indexes for entries and members to become ready. CLI
login and Application Default Credentials are separate sessions. Never place
admin credentials in the app/repo. This is a one-time LOCAL administrator script,
not a deployed backend. Do not loosen rules to resolve a permission error.

The migration removes explicitly retired pairCodes and guardian/children/
remoteRules/progress/catalog records, indexes historical leaderboard and member
rows (including missing parent documents), and inventories arbitrary legacy
nested user documents. It preserves study history and badges. Review it and
back up the database first. It is retryable; accountCleanup/schema version 2 is
written only when all steps finish. The app refuses cleanup until then. Do not
manually create that marker. Rules alone cannot inventory old data.

New app writes include ownerUid. Old app versions without that field cannot
create sharing rows under these rules; they must update. Future cloud schemas
must add cleanup support before release. A mobile SDK cannot enumerate unknown
subcollections; the migration makes old data discoverable privately.

## Account cleanup and retries

You → Account & privacy → Delete account shows the irreversible warning, then
linked users confirm their password or choose their Google account again.
Verification happens before any deletion. Pending writes must finish first.

An immutable owner-only deletion fence blocks stale devices from recreating
profile, badge, leaderboard or membership data. Owner reads/deletes and group
departure still work. The client transfers group ownership, removes final-member
groups/invites, deletes historical board/member rows with indexed owner queries,
and removes inventoried and known private documents in batches of at most 400
writes. Auth is deleted LAST. All cleanup reads use the server.

Rules/index/offline/quota errors preserve Auth and local history for retry;
some cloud records may already be removed. Long cleanup can expire verification;
the UI prompts again and retries once. Auth and Firestore are not atomic. If
the app closes midway, reopen and retry; no paid background job finishes it.
A pending fence keeps cloud sharing closed. Cleanup cannot be cancelled once
destructive writes begin.

Success clears preferences, achievements, providers, timer, widget state,
Google provider cache and Firestore cache, then opens Welcome. Other devices'
local history cannot be remotely erased. The UID-only fence and request time
remain in Firestore to block still-valid tokens; no profile/email/progress is
retained. TTL is not used. Administrators may remove completed fences after
verifying Auth is absent and tokens expired (allow at least 24 hours). Never
remove a pending fence.

## Email login configuration

The live Firebase password-sign-in endpoint returned PASSWORD_LOGIN_DISABLED
on October 14. Enable Authentication → Sign-in method → Email/Password in
Firebase Console. No real-user password or token was used for that check. A
successful production login still needs verification after enabling it.

## Verify before public distribution

- Register the Play signing certificate and test signed-release Email/Google login.
- Earn a disposable badge, publish old/new board weeks and create a two-member
  group. Delete as owner and inspect Auth/profile/badges/board/members/inventory.
- Test wrong password, cancelled Google, offline failure, restart/retry and an
  older signed-in device trying to republish.
- Verify strangers cannot read/delete private data. Monitor the external
  deletion inbox and fulfill verified requests with administrator access.

Local checks with Java 21 on PATH:

    npm test --prefix tool/firebase
    cd functions
    ../tool/firebase/node_modules/.bin/firebase emulators:exec --only firestore --project demo-focusforge --config ../firebase.json 'node --test test/migration.test.js'

For console-only rule deployment, paste the complete firestore.rules file into
Firestore → Rules → Publish. Also configure Firestore → Indexes → Single field
→ Add exemption for collection IDs entries and members, field ownerUid, with
Collection group scope and ascending index enabled. The CLI command deploys
both files together and is less error-prone. This setup uses no TTL policy.

Local tests do not activate production. No production migration or disposable
account deletion was performed here. Verify those before Play submission.

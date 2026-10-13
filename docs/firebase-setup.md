# Firebase: achievements, groups and parent control

The published Android APK uses the maintainer's Firebase project. Client configuration is supplied locally and is no longer tracked; download your Android app's google-services.json from Firebase Settings into android/app/ before building. A placeholder example is included, but cannot authenticate or be used unchanged. This release
uses Firestore directly; there is no Cloud Function to deploy and no new paid
service dependency. Web previews deliberately use the local auth backend.

## Publish the rules before testing the new APK

1. Open the Firebase console for focusforge-1edf7.
2. Ensure Cloud Firestore has a database in Native mode, and Authentication has
   your sign-in providers enabled: Anonymous for local/parent accounts, and
   Google and/or Email/Password for study groups.
3. Copy the complete root firestore.rules into **Firestore → Rules**, then
   select **Publish**. Keep the entire file together: it covers private earned
   achievements, parent control, groups and the existing public weekly board.
4. Alternatively, run these commands from the repository with an administrator login:

       npm ci --prefix tool/firebase
       tool/firebase/node_modules/.bin/firebase login
       tool/firebase/node_modules/.bin/firebase deploy --only firestore --project focusforge-1edf7

The memberIds array-contains query uses Firestore's automatic single-field
index. No composite index is required. Keep automatic indexing enabled for
studyGroups.memberIds. No Firebase administrator is logged in in the development
environment, so production rules have **not** been deployed by the coding agent.

## Test with two separate accounts

- Sign in, open Profile → Study groups, create a group and set a shared goal.
- Copy the ten-character invite and join from a second phone/account.
- Finish a focus session. Both phones should show the new shared total and
  standing. Start/pause a timer to check focus status.
- Leave from the owner account: ownership passes to a remaining member.
  Leaving as the final member deletes the group and its invite.
- Show a pairing code on a child's phone. Add the child from the parent's
  phone. A used or expired code must fail.
- Set a rule, then unlink from either phone. The parent list and source rules
  disappear together. The child's service updates when it receives the change.

Both devices need build 2018 and these revised rules before creating new parent links. New pairing uses sixteen random symbols, shown in four groups. Six-digit pairing is rejected after publishing these rules. Existing guardian links still work and can be removed atomically.
Local-only group entries were never shared and are not converted into real
memberships. Create a cloud group to get a valid invite.

## Keep earned achievements after signing out

The updated app backs up earned badges to the signed-in Firebase account at
`users/{uid}/achievements/earned`. Each record contains a schema version and a
small map of badge IDs to original earned dates. Older badges whose original
date was not recorded use zero and continue to show "Earned earlier". Names,
email addresses, session logs and detailed achievement progress are not sent
in this backup.

Publish the complete updated rules before checking cloud restore. Sign in with
a linked Google or email/password account, open Achievements while online and
allow the backup to finish. Signing out does not remove the backup. Signing
back into the same account months later restores the earned badges once
Firebase is reachable; there is no time-based expiry. The same backup can be
restored on another phone or after reinstalling. Badges earned before this
update must be synced from the device that still has them. An anonymous local
session cannot create or read an account backup.

Only the authenticated account owner can read or write this cabinet. Guardians,
group members and unrelated accounts have no access. Concurrent devices merge
their earned badge IDs, preserving the earliest known date instead of replacing
each other's cabinet. The rules reject unknown badge IDs, extra private fields,
invalid dates, removed unlocks and dates moved later. These are self-reported
badges; the rules do not establish proof that a focus session happened.

Offline badges remain on the device and sync when the app can reconnect. A new
installation cannot restore a badge that never reached Firebase. Deleting the
account removes its private achievement backup along with the local records.
The production rules are maintained by you and have not been deployed by the
coding agent.

## What is shared

- studyGroups: name, shared target, owner, member IDs, invite and creation time.
- Group member rows: name, UTC week, completed focus minutes, active timer
  deadline, join time and server update timestamp. No session log.
- groupInvites: group ID only. Exact-code reads need a linked account; listing
  is denied. Group details and standings require membership.
- Parent control: pairing proof, link, study summaries, installed app names,
  parent rules and optional salted local security-code digest.

Group totals are self-reported, not anti-cheat scores. They reflect this device's
session log; multiple devices using the same account can overwrite its row.
Focus status ends at its deadline and refreshes on a 30-second display clock.
It is not proof of online presence or a synchronised session. Weeks reset at
Monday 00:00 UTC. Only changed data is published; failures retry every 30 seconds.
The app must be running to send new summaries; Android suspension may delay sync.
The last confirmed parent rules are cached per account and restored before the
native service is updated on launch. Failed reads retain this protection; a
confirmed unlink clears it.

Groups are capped at 32 members. Invite codes use secure randomness and cannot
be enumerated through the rules. Parent tokens use 80 bits of secure randomness and expire in 15 minutes,
with one atomic claim. Security rules are not a rate limiter. For a large public
rollout, configure App Check and move claims behind a rate-limited backend before
promising abuse resistance. The four-digit parent code is a local commitment aid,
not Android device management or a server-enforced security boundary.

Account deletion removes group rows before deleting the credential and requires
a recent sign-in, confirmed in the app with the account password or Google.
Build 2018 also unlinks both sides of parent relationships, removes this user's
progress/catalog records, removes the linked pairing code and withdraws public
board entries for weeks found in this device's local session log (plus the
current week). Optional publishers pause during deletion. If cleanup fails
partway, the credential and local history remain so deletion can be retried;
already-removed shared records are not restored.

Complete erasure across devices needs a privileged backend deletion job. The
client cannot enumerate old pairing codes under the current rules, and boards
from another device may have no corresponding local history. The confirmation
discloses this limit. Configure your backend to delete those remaining records
when an Auth user is deleted; no such function or rule deployment is included
in this refresh. Rules remain under your control.

## Reproducible rules tests

Use Java 21+ and Node 22:

    npm ci --prefix tool/firebase
    npm test --prefix tool/firebase

Tests run against demo-focusforge in a local Firestore emulator, never production.
They cover valid/expired/competing pairing, atomic unlink, private group queries,
invite abuse, progress ownership, ownership transfer and private achievement
backups, including schema validation and preservation of earned badges.

## Repository and device privacy hardening (build 2018)

See [the security audit](security-audit-2026-10-12.md). Automatic Android cloud backups and device transfers are disabled, and shared Firestore records use memory-only caching after clearing old persistence at launch. Account changes clear retained private family/group views and reset leaderboard consent. Detailed setup/history remains device-local; it is not restored from Firebase after an uninstall or on a new phone. The newer private achievement backup described above restores earned badges only; it does not upload that detailed history.

The Firebase client API key remains public inside APKs and historical git commits. Configure API/application restrictions compatible with Firebase Authentication and rotate it in the project console if necessary. Removing the file from git does not revoke a key. Production key restrictions and rule deployment were not performed here.

Rules restrict shared top-level schemas and current records, foreign profile reads, and inactive pairing lookup. Variable app-list members are not deeply validated by Firestore Rules; a per-app document schema or backend validator would be needed for that.

Rules tooling now uses Firebase CLI 15.33.0, firebase 13.0.0 and rules-unit-testing 6.0.0. NPM development dependencies still report upstream advisories; they are not included in the APK. Avoid automated major downgrades from npm audit fix --force.

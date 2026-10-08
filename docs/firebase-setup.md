# Firebase: groups and parent control

FocusForge's Android configuration points to focusforge-1edf7. This release
uses Firestore directly; there is no Cloud Function to deploy and no new paid
service dependency. Web previews deliberately use the local auth backend.

## Publish the rules before testing the new APK

1. Open the Firebase console for focusforge-1edf7.
2. Ensure Cloud Firestore has a database in Native mode, and Authentication has
   your sign-in providers enabled: Anonymous for local/parent accounts, and
   Google and/or Email/Password for study groups.
3. Copy the complete root firestore.rules into **Firestore → Rules**, then
   select **Publish**. Keep the entire file together: it covers parent control,
   groups and the existing public weekly board.
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

Both devices need this release for strengthened pairing/unlink operations.
Existing guardian links still work. Older APKs must update before creating or
removing links: the new rules deliberately reject their non-atomic flow.
Local-only group entries were never shared and are not converted into real
memberships. Create a cloud group to get a valid invite.

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
be enumerated through the rules. Six-digit parent codes expire in 15 minutes,
with one atomic claim. Security rules are not a rate limiter. For a large public
rollout, configure App Check and move claims behind a rate-limited backend before
promising abuse resistance. The four-digit parent code is a local commitment aid,
not Android device management or a server-enforced security boundary.

Account deletion removes group rows before deleting the credential and requires
a recent sign-in. Older parent and public-board records are not automatically
purged: unlink and opt out first. If cloud cleanup fails partway, the local
account remains so deletion can be retried.

## Reproducible rules tests

Use Java 21+ and Node 22:

    npm ci --prefix tool/firebase
    npm test --prefix tool/firebase

Tests run against demo-focusforge in a local Firestore emulator, never production.
They cover valid/expired/competing pairing, atomic unlink, private group queries,
invite abuse, progress ownership and ownership transfer.

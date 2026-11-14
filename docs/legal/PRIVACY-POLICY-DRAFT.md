# FocusForge Privacy Policy

**Draft for owner and legal review — do not publish with unresolved placeholders.** This describes the accompanying source changes once deployed. Confirm provider eligibility, contracts, operating practices and Play Console declarations before publishing. A content rating or this document does not establish legal compliance.

Effective date: [FILL IN: effective date]. Last updated: [FILL IN: date].

## 1. Who we are and scope

FocusForge is a study companion with focus timers, study planning, progress records, optional app boundaries, and Pip, a study coach. The operator responsible for your personal data is [FILL IN: full legal name and trading name], at [FILL IN: postal address and country]. Contact us at [FILL IN: monitored privacy email]. This policy covers the FocusForge Android app, related account services and the website at https://www.focus-forge.in.

FocusForge is distributed internationally, including India, the European Union, the United Kingdom and the United States. Availability in 177 countries does not mean every feature is appropriate or legally available to every person in every country. Local rights and mandatory protections continue to apply.

You can use local study features without creating a linked account. Optional cloud coaching and account services have separate data flows, described below. Turning cloud coaching off does not sign you out or stop the account services you continue to use.

## 2. Data we collect and why

**Study and device settings.** On your device we store study sessions, subjects, focus goals, schedules, presets, progress totals, streaks, achievements and settings. Pip also stores your chosen exam and date, timetable, reminders and cloud-coaching choice. This supports timers, progress displays, local coaching and reminders. The ordinary chat conversation is held in app memory; a report you choose to submit is handled separately.

**Optional account details.** A linked account uses Firebase Authentication, with email/password or Google sign-in. These services process your account identifier, email, sign-in information and provider details. A profile may include a display name, an avatar and study preferences. Password entry goes to the authentication service; FocusForge's app preferences do not store the password. The Firebase SDK manages session credentials on the device.

Linked accounts privately back up profile and level/progress totals and earned achievements in Firestore. Current backup code excludes detailed study-session history, raw installed-app lists and app usage. Historical backups may contain older settings/session records until migrated or deleted. Signing out leaves your cloud account intact. Guest use has a local identifier and does not require a Firebase account.

**Optional sharing.** If you enable the leaderboard or join a study group, the service stores your chosen display name, membership and shared study totals/status. Group members or leaderboard viewers can see the information associated with that feature. Do not use your full real name if you do not want it displayed. Leaving a group or deleting your account removes your membership and own shared rows; a group used by others may continue under a different owner. Copies other people have already saved cannot be recalled from their devices.

**App boundaries and usage access.** If you choose these features, Android permissions let FocusForge read installed app/package names, usage events and durations, and the apps selected for local blocking. App labels, raw package lists, category choices, rule settings and detailed usage stay on your device in the inspected implementation. Categories help organise the focus controls; they are not an uploaded anonymous dataset. Android also retains its own system usage records, which FocusForge does not control.

The overlay permission displays a pause over an app you chose to restrict. An optional accessibility service supports YouTube filters using relevant screen events/content. These permissions can expose sensitive on-device information, so enable them only if you want the feature. FocusForge does not use them to collect account passwords, run advertisements or upload screen content. Notifications and alarms deliver timers and reminders. An optional photo picker lets you choose an avatar without requesting unrestricted access to your whole photo library.

**Security and operation.** Requests disclose network information such as an IP address to the service receiving them. Firebase, Google sign-in, Play Integrity/App Check, Cloudflare, Vercel and email delivery services may process technical request, integrity and security information according to their roles and contracts. We use authentication, abuse limits and brief error/operation events to operate the services. Our inspected application logs do not intentionally record chat text, passwords or bearer tokens. Hosting-provider access logs and retention must be confirmed separately: [FILL IN: provider logging settings, categories and retention].

**Support.** When you contact us, we receive what you send, including contact details and complaint information. Avoid sending passwords, sign-in tokens, private keys or unnecessary information about other people.

We found no integrated advertising SDK, Firebase Analytics or Crashlytics in the inspected runtime dependencies. Study progress and local usage statistics are functional records, rather than advertising profiles. We do not use these records for targeted advertising in this implementation. [FILL IN: confirm the operator's actual no-sale/no-sharing business practices, including the website and support tooling].

## 3. Children and student privacy

FocusForge has a Google Play content rating of 3+. This is a content classification, not age verification, a statement that children can enter contracts themselves, or proof of parental consent. [FILL IN: exact Play Console target audience age groups and child-access policy].

Local coaching and study tools remain available when cloud coaching is declined. The inspected implementation has no behavioural advertising, ad-ID collection or targeted-advertising feature. It does not implement verifiable parental consent or a reliable child/guardian account designation. An ordinary cloud opt-in is not verifiable parental consent.

For users under 18 in India, we must assess the DPDP Act's child-data requirements, applicable commencement dates, rules, exemptions and any requirement for verifiable parental consent. In the US, COPPA can require notice and verifiable parental consent before collecting covered information from children under 13, depending on whether the service is child-directed or has actual knowledge of age. For an online service relying on a child's own consent in the EEA, national thresholds range from 13 to 16; the UK threshold is 13. Other protections and legal bases may apply. These laws are not interchangeable.

[FILL IN: the lawful, implemented child-data procedure, including guardian verification, permissions, withdrawal, parental access/deletion and prevention of prohibited child tracking]. Do not publish a claim that these procedures exist until implemented and checked.

**Cloud-provider eligibility must be resolved before offering cloud coaching to children.** Gemini API terms reviewed for this build restrict clients directed toward or likely accessed by under-18s. A parent's agreement does not override those terms. [FILL IN: provider-approved age eligibility and how it is enforced, or removal/replacement of the affected provider].

A parent or guardian who believes a child provided personal data without the required authority can contact [FILL IN: children's privacy contact and procedure]. We will handle access, deletion and other requests after proportionate verification. [FILL IN: response periods and escalation arrangements required in the relevant jurisdiction].

## 4. How Pip processes data

**Offline Local Mode.** Until you agree to cloud coaching, Pip uses local rules and study records for planning, focus habits, subject progress, revision advice and reminders. This coaching engine makes no model API calls and does not download or train a model. It cannot answer every academic question. Account sync, sign-in and other features you independently use may still connect to their services.

**Optional Cloud Study Coach.** The first time you open Pip, you can agree or choose Offline Mode. Either choice is remembered locally. Settings → Account & privacy → Pip Cloud Study Coach lets you enable or withdraw consent. Cloud answers also require a linked, eligible account and a working backend. Withdrawal stops future coaching requests and discards pending replies in the app; it cannot recall a request already transmitted.

For an online answer, the app sends a redacted question, up to eight redacted recent chat turns, a language code, and a small numeric summary: today's focus minutes, daily goal, weekly minutes, comparable prior-week minutes, streak and days to your saved exam. Questions are capped at 300 characters. These go over HTTPS to our authenticated Cloudflare Worker, which checks your account and quotas and calls Google Gemini, or Groq if the primary service fails. A Gemini safety refusal is not retried with the fallback provider.

The authentication token identifies your account to our backend and Firebase/Vercel authorisation service. It is not included in the model prompt. Raw app/package lists, usage events, device IMEI/SSAID and profile fields are not selected as model context. The app removes your known profile name/identifier and common patterns such as emails, phone numbers and package names from outgoing text; the Worker repeats pattern-based redaction. **This reduces personal data but cannot guarantee anonymity.** An unfamiliar name, address or deliberately disguised detail can remain. Please leave personal and confidential information out of questions.

We do not operate an in-app sale of prompts or app lists. Do not interpret that as a verified promise about every processor's contractual use of data. **We cannot currently promise that all providers exclude inputs/outputs from model improvement or human review.** Provider use depends on the service tier, account settings and contract. [FILL IN: verified Gemini paid-service eligibility, data-use terms, retention, processing regions and DPA]. [FILL IN: verified Groq data-use/training policy, retention or zero-retention setting, regions and DPA]. Confirm these facts before replacing this disclosure with a no-training assurance.

Cloud replies are automated, may be wrong, and are not official exam or professional advice. Safety settings and instructions reduce inappropriate outputs; they cannot promise that every generated response is suitable for every age. Each cloud answer has a reporting control. A report includes the selected reason, the redacted answer/question, an account reference and timestamp so it can be reviewed and included in your export/deletion request. New reports are stored in Firestore; historical reports may be in Cloudflare KV. A local copy helps record the action.

## 5. Service providers and international transfers

We use Google/Firebase for account authentication, private Firestore records, Google sign-in and app integrity; Cloudflare for Pip request routing, historical feedback reports and scheduled delivery calls; Google Gemini and Groq for optional cloud coaching; and Vercel for website/account endpoints. Branded password-reset messages are delivered through the configured Gmail/SMTP service. Google Play and Android provide distribution, integrity and operating-system permission services. The app bundles its fonts/assets; no remote Google Fonts or advertising CDN integration was found in the inspected app code. Opening an external help or legal link connects to the destination you chose.

The current Firestore database inspected for this release is in India's `asia-south2` region. This does not mean all authentication, edge processing, AI requests, email or operational records remain in India. Providers and their subprocessors may process information in other countries, including countries with different privacy laws. [FILL IN: verified processor/subprocessor list, transfer countries and applicable agreements].

Where GDPR/UK GDPR applies, the proposed bases to verify are: contract or steps you request for necessary account/service functions; consent for optional cloud coaching and permissions where applicable; legitimate interests for proportionate security and abuse prevention, subject to a balancing assessment and children's rights; and legal obligations where required. OS permission approval and a service contract are not blanket consent to every purpose. [FILL IN: final purpose-by-purpose legal bases, legitimate-interest assessment and children's lawful basis].

[FILL IN: applicable adequacy decisions, EU Standard Contractual Clauses, UK IDTA/Addendum, transfer assessment and how to obtain safeguards]. An opt-in toggle alone is not a routine international-transfer safeguard. [FILL IN: EU/UK representative and data protection officer details where required]. Brazilian users may contact us to exercise applicable LGPD rights; [FILL IN: LGPD legal bases and international-transfer mechanism].

## 6. Retention and security

Local study records remain until you clear analytics, delete local/account data or uninstall the app. Different actions have different scopes: signing out keeps records; clearing analytics keeps settings and achievements; withdrawing cloud consent stops future coaching, and does not erase existing account/report data. Files you explicitly export or send to another app remain under your control after deletion.

Current application retention settings are:

| Record | Current rule |
|---|---|
| Profile/private progress, achievements and sharing records | Until deletion or the relevant feature's removal; no automatic inactive-account deletion is implemented |
| Ordinary chat conversation | App memory; the Worker does not intentionally create a general chat-history database |
| AI answer reports | Up to 90 days in application storage; new Firestore reports are periodically swept after expiry, historical KV reports have a 90-day TTL; manual/provider copies require separate controls |
| Answer/report allowance counters | Two-day expiry timestamp, with periodic server cleanup |
| Password-reset abuse counters | One-hour rolling window and expiry, with periodic cleanup |
| Encrypted reset-email queue | Fifteen-minute expiry; delivery removes completed jobs; scheduled retries/cleanup handle pending jobs |
| Minimal account-deletion fence | Retained at least seven days after request; scheduled cleanup removes it only after Firebase confirms the credential is gone. Interrupted deletions retain the fence. [FILL IN: confirm justified retention and legal basis] |
| Provider access/error/security logs and backups | [FILL IN: actual provider settings, retention, expiry/backup deletion schedule and lawful exceptions] |
| Support/grievance records | [FILL IN: justified period and any statutory retention] |

AI providers may temporarily retain requests under their own applicable terms; not creating a FocusForge chat database does not establish zero provider retention. No automatic inactive-account expiry currently runs.

The app and backend enforce HTTPS, authentication, ownership checks, request limits and generic errors. Android release builds block cleartext traffic and disable app backup/debugging; release shrinking is enabled. Cloud credentials are configured on servers, rather than bundled as model keys in the app. Android protects application files with its application sandbox and device protections. App preferences are **not** an app-encrypted vault, and Firebase manages its own credential persistence. We do not promise that every local record or SDK token is encrypted by FocusForge. [FILL IN: provider at-rest encryption, backup and access-management facts verified under contract].

No system is perfectly secure. If a qualifying personal-data breach occurs, we will investigate and notify people/regulators as required by the laws applicable to us. [FILL IN: incident process, required regulator contacts, DPDP/GDPR reporting arrangements and applicability of CERT-In reporting/log-retention obligations]. Do not claim a CERT-In six-hour process or 180-day Indian log retention without operational verification.

## 7. Your privacy rights and controls

In Settings → Account & privacy you can export your stored data as JSON, clear local analytics, turn Pip cloud coaching off/on, and request deletion of your account and app data. Export includes your active local account records, app-owned Android preferences, private Firebase records, your own sharing rows and Pip reports. SDK secrets and other users' private records are excluded. A linked-account export requires a working connection and current credentials; the app reports failure if it cannot fetch a cloud page.

Deletion asks for confirmation and, for a linked account, a fresh password/provider sign-in check. It removes your reports and auxiliary service records, private Firestore data, own shared rows and group memberships before deleting your Firebase sign-in credential. Local state, native app rules/reminders and temporary app cache are then cleared. If a required cloud step fails, the app keeps your login for retry and does not claim completed deletion. Historical KV deletion is subject to the storage service's propagation time. [FILL IN: verified deletion completion deadline, backup expiry, retained security/legal records and exceptional cases]. You do not need to purchase anything to request deletion.

The external account-deletion route is https://www.focus-forge.in/delete-account. If you cannot sign in, contact [FILL IN: monitored support email] for proportionate ownership verification and help. Access/deletion may require verification, but we do not need your password or complete ID documents by ordinary email.

Use Android Settings to revoke Usage Access, overlay, accessibility and notification permissions. The in-app app-list switch stops corresponding app-list access; Android's permission screen controls the underlying special permissions. Revoking a permission does not automatically erase Android's own usage history.

Depending on your country and the law's scope, you may have rights to access, correct, delete or obtain portable data, withdraw consent, object, restrict processing, nominate a representative, or complain to a regulator. Withdrawing consent does not change the lawfulness of earlier processing. GDPR/UK GDPR requests generally require a response within one month, with lawful extensions; [FILL IN: procedures and applicable deadlines in other jurisdictions]. If CCPA/CPRA applies, eligible California residents may request knowledge/access, deletion, correction and applicable sale/sharing or sensitive-information limitations, with protection against unlawful discrimination. [FILL IN: confirm applicability, categories, business practices and request/appeal channels]. We do not use local study coaching to make legal or similarly significant automated decisions about you.

## 8. Grievance officer and contact

Privacy/support email: [FILL IN: monitored email].

India Grievance Officer / data-protection contact: [FILL IN: designated person's name and title]. Postal address: [FILL IN: address]. Email: [FILL IN: dedicated grievance email]. Contact method: [FILL IN: phone or accessible alternative, where required].

How to submit a grievance: [FILL IN: accessible procedure, acknowledgement period, resolution period, appeal/escalation route and applicable DPDP Board/IT Rules mechanism]. These periods must match the rules actually applicable to the operator and the provisions in force. [FILL IN: EU/UK/LGPD and other required contacts].

We will explain material policy changes in [FILL IN: implemented notice channel] and seek a new choice where a new processing purpose requires it. Publishing new wording does not silently enable cloud coaching or expand previously given consent.

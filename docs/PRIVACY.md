# Privacy policy

**Last updated: 10 November 2026**

ExamVault is a study utility for Indian competitive-exam aspirants. This document
describes exactly what the app stores, what leaves your device, and what does not.
It is written to match the code; where the two disagree, that is a bug.

## The short version

- There is **no account**. No email, phone number or password is ever collected.
- Your admit cards, roll numbers and portal passwords are **encrypted on your
  device** and never uploaded.
- Roll numbers you type are **checked on your device** and are not sent anywhere.
- The app collects **no analytics, no advertising identifiers, and no location**.

## What is stored on your device

| Data | Where | Encrypted |
|---|---|---|
| Exam name, roll number, registration ID, centre, date, DOB/portal password | Android Keystore (AES-GCM, `EncryptedSharedPreferences`) | Yes |
| Your document checklist ticks | Same encrypted store | Yes |
| The last downloaded live feed, so the app opens offline | App-private storage | No — it is public data |
| The last downloaded roll-number index | App-private storage | No — it contains no roll numbers (see below) |

The encrypted store is excluded from Android Auto Backup and from device-to-device
transfer (`android:allowBackup="false"` plus an explicit data-extraction rule), so
your admit cards do not leave the phone even during a migration.

Deleting an admit card deletes its entry from the encrypted store. Uninstalling
the app removes everything.

**There is no way for us to recover your data.** We never hold a copy of it.

## What leaves your device

Three things, and nothing else:

1. **Plain HTTPS requests for public files.** The app downloads a small JSON feed
   and, when you check a result, one gzip index. The request contains no personal
   data — no roll number, no device identifier, no cookie. It is the same request
   any browser would make for the same public file.
2. **A push-notification token**, if you allow notifications. This is issued by
   Firebase Cloud Messaging or OneSignal and is used only to deliver exam alerts
   for the categories you are interested in. It is not linked to your vault, your
   roll number, or any other data in the app.
3. **Nothing else.** No crash reports, no usage events, no device fingerprint.

## Roll-number checks are local

To answer "is my roll in the list?", the app downloads a file containing only
**salted SHA-256 hashes** of the published roll numbers. Your phone hashes the
number you type and looks for a match on-device.

This means:

- the number you type is **never transmitted**;
- the file the app downloads **cannot be turned back into a candidate list**;
- we do not learn which result you checked, or what you found.

The official result documents belong to the commissions. The app **links** to them
on the commission's own website; it does not host or redistribute them.

## Third-party services

| Service | Purpose | Data received |
|---|---|---|
| Cloudflare (R2 + Workers) | Delivers the public feed and index files | The request itself: IP address, user agent, timestamp — standard web-server logs |
| Firebase Cloud Messaging | Optional push notifications | A push token and topic subscription |
| OneSignal | Optional push notifications | A push token and tag subscription |
| Official commission websites | Not contacted by the app; opened in your browser when you tap an official link | Whatever your browser sends them |

None of these receive your vault contents or your roll number.

## Children

The app is intended for adults preparing for competitive examinations. It is not
directed at children and does not knowingly collect data from them — consistent
with the statement above that it collects no personal data at all.

## Permissions, and why each one exists

| Permission | Why |
|---|---|
| `INTERNET` | Download the public feed and index |
| `ACCESS_NETWORK_STATE` | Show "cached" instead of a spinner when offline |
| `POST_NOTIFICATIONS` | Result alerts (Android 13+, only if you allow it) |
| `USE_BIOMETRIC` | Optional unlock for the vault |

There is no location, contacts, storage, camera or advertising permission.

## Your choices

- **Notifications:** deny the permission, or turn them off in Android settings.
- **Your data:** delete individual cards in the app, or uninstall to remove
  everything.
- **Offline only:** enable airplane mode. The feed and any index you have already
  downloaded keep working; nothing about the vault depends on the network.

## Changes

If this policy changes, the "last updated" date above changes and the new version
ships with the app release. There is no email list, so the app itself is the
notice.

## Contact

Questions about this policy, or a request about data you believe we hold (we hold
none): open an issue at <https://github.com/aasheesh333/ExamVault/issues>.

---

### For the Play Console "Data safety" form

- Does your app collect or share any of the required user data types? **No.**
- Is all of the user data encrypted in transit? **Yes** (HTTPS only;
  `usesCleartextTraffic="false"`).
- Does your app provide a way for users to request that their data be deleted?
  **Yes** — deleting a card in-app, or uninstalling, removes all data.
- Are you using a third-party analytics or advertising SDK? **No.**

# Privacy policy

**Last updated: 16 November 2026**

ExamVault is a study utility for Indian competitive-exam aspirants. This document
describes exactly what the app stores, what leaves your device, and what does not.
It is written to match the code; where the two disagree, that is a bug.

## The short version

- There is **no account**. No email, phone number or password is ever collected.
- Your admit cards, roll numbers and portal passwords are **encrypted on your
  device** and never uploaded.
- Roll numbers you type are **checked on your device** and are not sent anywhere.
- The app collects **no analytics, no advertising identifiers, and no location**.
- If you allow notifications, the push providers (Firebase Cloud Messaging /
  OneSignal) hold a **push token — a device identifier** used only to route exam
  alerts for the categories you choose to your device. Details below, and in the
  Play "Data safety" answers at the end.

## What is stored on your device

| Data | Where | Encrypted |
|---|---|---|
| Exam name, roll number, registration ID, centre, date, DOB/portal password | `flutter_secure_storage` (v11 defaults): values encrypted with AES-GCM under a key wrapped with RSA-OAEP; the wrapping key lives in the hardware-backed Android Keystore and never leaves it | Yes |
| Your document checklist ticks | Same encrypted store | Yes |
| The last downloaded live feed, so the app opens offline | App-private storage | No — it is public data |
| The last downloaded roll-number index | App-private storage | No — it contains no roll numbers (see below) |

The encrypted store is excluded from Android Auto Backup and from device-to-device
transfer (`android:allowBackup="false"` plus an explicit data-extraction rule), so
your admit cards do not leave the phone even during a migration.

Deleting an admit card deletes its entry from the encrypted store.

**Delete all data**, in the app's About sheet, removes every admit card, every
setting (including the notification categories you chose) and the cached feed and
result index in one tap, without uninstalling. It also drops this device's push
subscriptions — every per-exam bell and every category topic — and then
re-subscribes the fresh-install default, which is all five categories, so the
Notifications section in About shows what the device is actually subscribed to.
The push token itself is kept — it carries no exam or vault data, and
re-registering on every wipe would churn the provider for no privacy gain.
Uninstalling the app removes everything, and the push token goes with it.

**There is no way for us to recover your data.** We never hold a copy of it.

## What leaves your device

Three things, and nothing else:

1. **Plain HTTPS requests for public files.** The app downloads a small JSON feed
   and, when you check a result, one gzip index. The request contains no personal
   data — no roll number, no device identifier, no cookie. It is the same request
   any browser would make for the same public file.
2. **A push-notification token**, if you allow notifications. This token is a
   device identifier: it is issued by Firebase Cloud Messaging or OneSignal, and
   the provider uses it to route exam alerts to your device. The About sheet has
   a **Notifications** section where you choose which of the five exam categories
   (SSC, UPSC, Banking, Railways, State PSC) you follow. The token is subscribed
   only to the topics for the categories you chose, and turning one off
   unsubscribes it from that topic. Choosing no categories is allowed: you then
   receive no **category** alerts (per-exam bells you switched on separately are
   a different subscription and keep working), and the app says so on that
   screen. The token is not linked to your vault, your roll number, or any other
   data in the app, and it goes away when you turn notifications off or
   uninstall.
3. **Nothing else.** No crash reports, no usage events, no device fingerprint.
   (The in-app error logger writes to the Dart VM's debug sink only; a release
   build has no such sink, and nothing is uploaded.)

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
| Firebase Cloud Messaging | Optional push notifications | A push token (a device identifier used for routing) and the category-topic subscriptions you chose |
| OneSignal | Optional push notifications | A push token / player ID (a device identifier) and the same chosen categories as boolean tags |
| Official commission websites | Not contacted by the app; opened in your browser when you tap an official link | Whatever your browser sends them |

None of these receive your vault contents or your roll number. The push
providers **do** hold the token itself — that is exactly what the
"Device or other IDs" answer in the Play data-safety form below discloses. The
token is not sold, is used only to deliver the alerts you opted into, and is
dropped when you unsubscribe (notifications off) or uninstall.

## Children

The app is intended for adults preparing for competitive examinations. It is not
directed at children and does not knowingly collect data from them. The only
identifier that ever leaves the device is the push token described above, which
exists solely to route notifications and is not associated with any person by us.

## Permissions, and why each one exists

ExamVault itself declares exactly **three** permissions. The *merged release
manifest* — what Android and Play actually see — carries **26**, because the push
SDKs and AndroidX libraries merge in their own. Regenerated from the merged
manifest and the manifest-merger blame report
(`app/build/app/outputs/logs/manifest-merger-release-report.txt`); every row
below names the component that contributes it.

**Declared by ExamVault** (`app/android/app/src/main/AndroidManifest.xml`):

| Permission | Why |
|---|---|
| `INTERNET` | Download the public feed and index |
| `ACCESS_NETWORK_STATE` | Show "cached" instead of a spinner when offline |
| `POST_NOTIFICATIONS` | Result alerts (Android 13+, only if you allow it) |

**Merged in by the push stack:**

| Permission | From | Why it exists |
|---|---|---|
| `WAKE_LOCK` | `firebase_messaging` plugin | Deliver a push while the CPU dozes |
| `app.examvault.permission.C2D_MESSAGE` | `com.onesignal:notifications` | App-private C2D channel: only this app can receive its own pushes |
| `com.google.android.c2dm.permission.RECEIVE` | `com.onesignal:notifications` | Receive FCM/GCM messages |
| `VIBRATE` | `com.onesignal:notifications` | Notification vibration |
| `RECEIVE_BOOT_COMPLETED` | `com.onesignal:notifications` | Restore the push subscription after a reboot |
| 16 launcher badge permissions: `com.sec.android.provider.badge.permission.READ`/`WRITE`, `com.htc.launcher.permission.READ_SETTINGS`/`UPDATE_SHORTCUT`, `com.sonyericsson.home.permission.BROADCAST_BADGE`, `com.sonymobile.home.permission.PROVIDER_INSERT_BADGE`, `com.anddoes.launcher.permission.UPDATE_COUNT`, `com.majeur.launcher.permission.UPDATE_BADGE`, `com.huawei.android.launcher.permission.CHANGE_BADGE`/`READ_SETTINGS`/`WRITE_SETTINGS`, `android.permission.READ_APP_BADGE`, `com.oppo.launcher.permission.READ_SETTINGS`/`WRITE_SETTINGS`, `me.everything.badger.permission.BADGE_COUNT_READ`/`BADGE_COUNT_WRITE` | `com.onesignal:notifications` (bundled ShortcutBadger) | Unread-count badges on Samsung/HTC/Sony/Apex/Solid/Huawei/OPPO and other OEM launchers. Each is only ever granted by that launcher's own app; on stock Android they do nothing |

**Merged in by AndroidX:**

| Permission | From | Why it exists |
|---|---|---|
| `FOREGROUND_SERVICE` | `androidx.work:work-runtime` (pulled in by the push stack's retry scheduling) | Run scheduled background work |
| `app.examvault.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` | `androidx.core:core` | Android 14+ requirement: keeps dynamically registered broadcast receivers private to the app |

There is no location, contacts, storage, camera or advertising permission, and no
biometric permission — the vault has no biometric unlock; it is protected by
device-level encryption alone.

## Your choices

- **Notifications:** deny the permission, or turn them off in Android settings —
  either unsubscribes the device, and the provider's token for it goes away.
  The About sheet's **Notifications** section also lets you choose which exam
  categories to follow; turning every category off stops category alerts without
  changing the OS permission (per-exam bells are a separate subscription).
- **Your data:** delete individual cards in the app, use **Delete all data** in
  About to remove every card and setting at once (it also drops the per-exam
  bells and the category topics, then re-applies the default of all five
  categories), or uninstall to remove everything.
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

- Does your app collect or share any of the required user data types?
  **Yes — exactly one type: "Device or other IDs".**
  - What: the push token (FCM registration token / OneSignal player ID) —
    collected by the push providers to deliver exam alerts to the device. The
    in-app picker narrows which exam-category topics this same token subscribes
    to; it does not add a data type, a second identifier, or a new recipient.
  - Sold to third parties? **No.**
  - Purpose: **App functionality** (notifications the user opted into by
    allowing notifications).
  - Deletion: the token is deleted when the user turns notifications off
    (unsubscribe) or uninstalls the app.
  No other data type is collected or shared: no personal info, health, financial
  info, photos, location, activity, web history, or advertising ID. (Answering
  "No" here while FCM/OneSignal ship in the binary was the previous — wrong —
  answer; the push SDKs provably transmit a device-scoped token.)
- Is all of the user data encrypted in transit? **Yes** (HTTPS only;
  `usesCleartextTraffic="false"`).
- Does your app provide a way for users to request that their data be deleted?
  **Yes** — **Delete all data** in the About sheet removes every card, setting
  and cached public file on the device, deleting a card removes that card, and
  uninstalling removes everything; uninstalling or disabling notifications
  unsubscribes the push token.
- Are you using a third-party analytics or advertising SDK? **No.**

# Play Store submission

Everything below is verified against the actual build, not assumed.

## What CI produces

Every push to `master` builds two artefacts (job `Build release APK`):

| Artefact | Path | Size | Use |
|---|---|---|---|
| App Bundle | `app-release.aab` | ~54 MB | **Play upload** |
| APK arm64-v8a | `app-arm64-v8a-release.apk` | ~20 MB | sideload, most phones |
| APK armeabi-v7a | `app-armeabi-v7a-release.apk` | ~18 MB | older devices |
| APK x86_64 | `app-x86_64-release.apk` | ~22 MB | emulators |

The bundle is signed with the upload key (`CN=ExamVault, O=ExamVault, C=IN`,
SHA-256 `F4:D8:1E:…:E0:EB`), materialised in CI from four repository secrets:

```
ANDROID_KEYSTORE_BASE64   ANDROID_STORE_PASSWORD
ANDROID_KEY_ALIAS         ANDROID_KEY_PASSWORD
```

**Keep a copy of `upload-keystore.jks` and its password somewhere durable.** Play
will not accept an update to `app.examvault` signed with a different key unless you
enrol in Play App Signing key reset, which takes days. The keystore is git-ignored
by design, so it exists only in the secrets and wherever you store the backup.

## Store listing

- **App name:** ExamVault
- **Short description (79 chars, limit is 80):** Encrypted admit cards & instant roll checks — SSC, UPSC, Banking, Railways, PSC
  - The previous line ("Admit cards and instant roll-number result checks — SSC,
    UPSC, Banking, Railways, PSC.") was 86 chars and would have been rejected by
    the Console's hard limit.
- **Category:** Education
- **Icon:** `app/assets/branding/app_icon_512.png` (512×512)
- **Feature graphic:** 1024×500 — still to make
- **Screenshots:** 393×852 renders are in the design file; the four screens must
  be captured at 1080×2340 or larger from a real device build.

## Version codes: sideloaded APKs vs the Play AAB

`pubspec.yaml` carries `version: 1.0.0+1` (versionCode 1). `flutter build apk
--split-per-abi` makes Flutter add `1000 × ABI index` to that, so the artefacts
CI uploads are:

| Artefact | versionCode |
|---|---|
| `app-release.aab` (Play) | **1** |
| `app-armeabi-v7a-release.apk` | **1001** |
| `app-arm64-v8a-release.apk` | **2001** |
| `app-x86_64-release.apk` | **3001** |

Consequence to remember before distributing APK links: a phone that sideloaded a
split APK sits at versionCode 1001/2001/3001. Play updates carry the AAB's plain
versionCode (1, 2, 3 …), which is **lower**, so the Play Store will refuse to
update that install in place — Android treats it as a downgrade. A sideloaded
user must uninstall and install the Play build instead; uninstalling deletes the
device-local vault, so they re-enter their cards once. Two independent blockers
force that uninstall: the versionCode downgrade above, and — if the app is
enrolled in Play App Signing — the fact that the sideloaded APK carries the
*upload* key's signature while Play delivers builds signed by the *app signing*
key. Alternatively, keep the sideload line's versionCode deliberately ahead of
the Play line and accept that the two channels never converge. Pick one channel
per user.

## Data safety

Answer exactly as in `docs/PRIVACY.md` § *For the Play Console "Data safety"
form*:

- Collects or shares required user data? **Yes — "Device or other IDs" only**:
  the push token held by FCM/OneSignal to deliver exam alerts. Not sold;
  purpose "App functionality"; deleted on unsubscribe (notifications off) or
  uninstall. Answering "No" is wrong: the push SDKs ship in the binary and
  provably transmit a device-scoped token.
- Encrypted in transit? **Yes** (`usesCleartextTraffic="false"`, HTTPS only).
- Deletion request path? **Yes** — delete a card in-app, uninstall, or turn off
  notifications (which drops the push token).
- Analytics/advertising SDK? **No.**

## Content rating

Utility app, no user-generated content, no ads, no purchases. Answer the
questionnaire literally; the expected outcome is Everyone / 3+.

## Permissions in the merged release manifest, with attribution

The app declares **3** permissions; the merged release manifest ships **26**,
because the push SDKs and AndroidX merge in their own. Play reviewers and the
Console's APK analysis see the merged set, so paste attributions, not guesses.
Regenerated from
`app/build/app/intermediates/merged_manifests/release/processReleaseManifest/arm64-v8a/AndroidManifest.xml`
and `app/build/app/outputs/logs/manifest-merger-release-report.txt`.

| # | Permission | Added by | Justification to paste into Play |
|---|---|---|---|
| 1 | `android.permission.INTERNET` | ExamVault | Downloads the public result feed and roll index |
| 2 | `android.permission.ACCESS_NETWORK_STATE` | ExamVault | Shows "cached" instead of a spinner when offline |
| 3 | `android.permission.POST_NOTIFICATIONS` | ExamVault | Result alerts (optional runtime permission, Android 13+) |
| 4 | `android.permission.WAKE_LOCK` | `firebase_messaging` plugin | Keeps push delivery alive while the device dozes |
| 5 | `app.examvault.permission.C2D_MESSAGE` | `com.onesignal:notifications` | App-private push channel; only this app can receive its own messages |
| 6 | `com.google.android.c2dm.permission.RECEIVE` | `com.onesignal:notifications` | Receives FCM push messages |
| 7 | `android.permission.VIBRATE` | `com.onesignal:notifications` | Notification vibration |
| 8 | `android.permission.RECEIVE_BOOT_COMPLETED` | `com.onesignal:notifications` | Restores the push subscription after reboot |
| 9–24 | 16 launcher badge permissions: `com.sec.android.provider.badge.permission.READ`/`WRITE`, `com.htc.launcher.permission.READ_SETTINGS`/`UPDATE_SHORTCUT`, `com.sonyericsson.home.permission.BROADCAST_BADGE`, `com.sonymobile.home.permission.PROVIDER_INSERT_BADGE`, `com.anddoes.launcher.permission.UPDATE_COUNT`, `com.majeur.launcher.permission.UPDATE_BADGE`, `com.huawei.android.launcher.permission.CHANGE_BADGE`/`READ_SETTINGS`/`WRITE_SETTINGS`, `android.permission.READ_APP_BADGE`, `com.oppo.launcher.permission.READ_SETTINGS`/`WRITE_SETTINGS`, `me.everything.badger.permission.BADGE_COUNT_READ`/`BADGE_COUNT_WRITE` | `com.onesignal:notifications` (bundled ShortcutBadger) | Unread-count badge on OEM launchers (Samsung, HTC, Sony, Apex, Solid, Huawei, OPPO, EvMe). Each is defined and granted only by that launcher's own app; inert everywhere else |
| 25 | `android.permission.FOREGROUND_SERVICE` | `androidx.work:work-runtime` (push stack's retry scheduling) | Runs scheduled background work |
| 26 | `app.examvault.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` | `androidx.core:core` | Android 14+ requirement keeping dynamic broadcast receivers app-private |

No location, contacts, storage, camera, or advertising-ID permission, and no
`USE_BIOMETRIC` — the app has no biometric unlock (no `local_auth` dependency,
no biometric code); an earlier revision declared it aspirationally and it was
removed.

## Before you press publish

- [ ] Replace the throwaway upload keystore with one you have backed up
- [ ] Capture real screenshots from a device build at ≥1080×2340
- [ ] Make the 1024×500 feature graphic
- [ ] Host `docs/PRIVACY.md` at a public URL and paste it into the listing
- [ ] Decide the licensing stance on any mirrored PDF (currently: link-only, no
      mirroring — see `docs/DATA_PIPELINE.md`)
- [ ] Create the Play Console app and upload `app-release.aab` to internal testing
      first; the internal track surfaces policy warnings without a public review

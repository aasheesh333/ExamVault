# Play Store submission

Everything below is verified against the actual build, not assumed.

## What CI produces

Every push to `master` builds one App Bundle and three split APKs (job `Build
release APK`), published as two downloadable workflow artefacts:

| Workflow artefact | File | Path in the build | Use |
|---|---|---|---|
| `examvault-aab` | `app-release.aab` | `app/build/app/outputs/bundle/release/` | **Play upload** |
| `examvault-apk` | `app-arm64-v8a-release.apk` | `app/build/app/outputs/flutter-apk/` | sideload, most phones |
| `examvault-apk` | `app-armeabi-v7a-release.apk` | `app/build/app/outputs/flutter-apk/` | older 32-bit devices |
| `examvault-apk` | `app-x86_64-release.apk` | `app/build/app/outputs/flutter-apk/` | emulators |

Both upload steps use `if-no-files-found: error`, so a build that produced no
bundle fails the job instead of quietly shipping nothing. Artefacts are kept for
14 days. (`.github/workflows/ci.yml`, job `build-android`, steps *Build APK*,
*Upload APKs*, *Upload App Bundle*.)

Sizes are not asserted anywhere and drift with the Flutter version — read them
off the workflow run rather than quoting a number here.

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
  - Re-verified at 79 characters (counting the em dash and both spaces). The
    Console's limit is a hard 80; anything longer is rejected at save time.
  - The previous line ("Admit cards and instant roll-number result checks — SSC,
    UPSC, Banking, Railways, PSC.") was 86 chars and would have been rejected.
  - Every claim in it is backed by the app: admit cards are encrypted at rest
    (`app/lib/data/local/secure_vault_store.dart:108,130`), roll checks are answered
    from a local hashed index (`app/lib/features/result_checker/engine/hashed_index.dart:13`),
    and all five families exist as `ExamCategory` values
    (`app/lib/domain/entities/exam_category.dart:8`).
- **Category:** Education
- **Icon:** `app/assets/branding/app_icon_512.png` (512×512)
- **Feature graphic:** `design/exports/feature_graphic_1024x500.png` — **done**,
  exactly 1024×500. Drawn from the repo's own brand tokens (navy canvas, the
  shield mark from `tools/branding/make_icons.py`, the Plus Jakarta Sans wordmark,
  the five exam families); no stock imagery, no statistics, no invented UI.
  Regenerate with:
  ```
  python3 tools/branding/make_feature_graphic.py
  ```
  It writes the PNG **and** the SVG it rendered (`design/exports/feature_graphic_1024x500.svg`),
  needs only `python3` (stdlib) and `google-chrome`, and fails if the result is
  not exactly 1024×500.
- **Screenshots:** `design/exports/screenshots/` — five PNGs at **1179×2556**
  (`01-home`, `02-vault`, `03-dates`, `04-radar`, `05-share`), above Play's
  1080×2340 floor. Regenerate with:
  ```
  cd app && EV_SCREENSHOTS=1 flutter test test/screenshot_capture_test.dart
  ```
  **These are rendered from the real widgets, not captured on a device.** The
  harness pumps the shipped `RootShell` at a 393×852 logical viewport and
  rasterises the frame through `RepaintBoundary.toImage(pixelRatio: 3)`, so the
  output is 3× the layout — the same pixel density a 3× phone reports — using the
  same `app/test/support/matrix.dart` fixture the layout matrix asserts against
  and the app's bundled fonts. Nothing is drawn by hand, so the pictures cannot
  show a screen the app does not have — but they also carry no status bar, no
  device chrome and no real network: the feed is the matrix's canned JSON. When a
  physical device is available, re-capture on it and replace these; the pipeline
  above stays the reproducible fallback and the regression check.

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
form*. The four facts behind every answer, with the code that proves them:

| Fact | Evidence |
|---|---|
| No account, no profile, nothing to sign in to | no auth dependency in `app/pubspec.yaml`; the About sheet says so in the app (`app/lib/features/about/about_sheet.dart:538`) |
| The vault is encrypted on the device and never uploaded | `app/lib/data/local/secure_vault_store.dart:108,130` — `flutter_secure_storage` v11 defaults (AES-GCM under an RSA-OAEP key in the Android Keystore), `resetOnError: false` so a Keystore fault cannot silently wipe it; `android:allowBackup="false"` in `app/android/app/src/main/AndroidManifest.xml` |
| No analytics, no advertising identifier | no analytics/ad SDK in `app/pubspec.yaml`; `AppLogger` writes to the Dart VM sink only, which a release build does not have (`app/lib/data/services/app_logger.dart:5`) |
| Roll numbers never leave the device | `app/lib/features/result_checker/engine/hashed_index.dart:13` — the downloaded index holds salted SHA-256 hashes, and the comparison is local |

Then answer the Console form:

- Collects or shares required user data? **Yes — "Device or other IDs" only**:
  the push token held by FCM/OneSignal to deliver exam alerts. Not sold;
  purpose "App functionality"; deleted on unsubscribe (notifications off) or
  uninstall. Answering "No" is wrong: the push SDKs ship in the binary and
  provably transmit a device-scoped token.
- Encrypted in transit? **Yes** (`usesCleartextTraffic="false"`, HTTPS only).
- Deletion request path? **Yes** — delete a card in-app, uninstall, or turn off
  notifications (which drops the push token).
- Analytics/advertising SDK? **No.** (OneSignal's own dashboard reports push
  delivery — that is the token disclosure above, server-side, not in-app
  analytics. The binary contains no analytics or advertising SDK.)

One detail the form does not ask for but a reviewer may: when notifications are
allowed the token is subscribed to **all five** exam-category topics
(`app/lib/main.dart:144` calls `push.syncTopics(ExamCategory.values.toSet())`), so
the current release is "all exam alerts" or "none". That is still a single
"Device or other IDs" entry with purpose *App functionality* — the answer does
not change if a per-category picker ships, because the picker narrows *which*
topics the same token is subscribed to.

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
- [x] Feature graphic: `design/exports/feature_graphic_1024x500.png` (regen:
      `python3 tools/branding/make_feature_graphic.py`)
- [x] Screenshots at ≥1080×2340: `design/exports/screenshots/` — 1179×2556,
      rendered from the real widgets (regen: `cd app && EV_SCREENSHOTS=1 flutter
      test test/screenshot_capture_test.dart`). Replace with device captures if a
      phone is available; the widget pipeline is the reproducible fallback.
- [ ] Host `docs/PRIVACY.md` at a public URL and paste it into the listing
- [ ] Decide the licensing stance on any mirrored PDF (currently: link-only, no
      mirroring — see `docs/DATA_PIPELINE.md`)
- [ ] Create the Play Console app and upload `app-release.aab` to internal testing
      first; the internal track surfaces policy warnings without a public review

## Every listing claim, and where the repo proves it

Re-verified against the code on 2026-11-16. If any of these stops being true,
the listing copy changes in the same commit as the code.

| Claim | Verified by |
|---|---|
| **No PDF is mirrored or re-hosted.** Result documents open on the commission's own site. | `app/lib/domain/entities/live_update.dart:81` — `officialPdf`/`officialPage` are links, and the only use of them is `launchUrl(..., LaunchMode.externalApplication)` (`instant_result_checker_screen.dart:621`, `exam_detail_sheet.dart:490`); `app/lib/features/result_checker/engine/hashed_index.dart:13` — the published index holds hashes only. The legacy `resultPdfPath` mirror route (`app_config.dart:63`) still has `pdfBytes`/`pdfUrl` wrappers, but **nothing in `lib/` or `test/` calls them** — no code path downloads a PDF. |
| **No analytics, no crash reporting, no ad SDK.** | `app/pubspec.yaml` dependency list (no analytics/crash/ads package); `app/lib/data/services/app_logger.dart:5` — `developer.log` only, inert in a release AOT build; `app/lib/features/about/about_sheet.dart:567` states it in-app |
| **No account.** No email, phone, password, login, or profile field exists. | `app/lib/features/about/about_sheet.dart:156,538`; no auth dependency in `app/pubspec.yaml` |
| **No location.** No location permission and no location code. | `app/android/app/src/main/AndroidManifest.xml:6` (comment) and the declared-permission block below it; `app/lib/features/about/about_sheet.dart:568` |
| **Encrypted local vault.** Cards, roll numbers and portal passwords are encrypted at rest and excluded from backup. | `app/lib/data/local/secure_vault_store.dart:108,130`; `android:allowBackup="false"` + `dataExtractionRules` in the manifest |
| **The only identifier that leaves the device is the push token.** | `app/lib/data/services/push_service.dart:176,261`; `app/lib/main.dart:144` |
| **Roll numbers are checked on the device and never sent.** | `app/lib/features/result_checker/engine/hashed_index.dart:13` (hashes only) and `roll_index_engine.dart` (local binary search) |


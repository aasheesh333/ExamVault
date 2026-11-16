# Play Store submission

Everything below was verified against a real build or against the code in this
repository. Where a claim is a record of an earlier build rather than something
this environment can re-derive, it says so.

## Release notes — 1.0.1

Written for the student, not for us. Every line describes behaviour the shipped
code has; the commit-level record is in `docs/AUDIT_2026-11-16.md` § *Disposition*.

**Paste-ready for the Console's "What's new" field** (the field caps it at 500
characters per language — re-check the counter at submission):

> ExamVault 1.0.1 — Screen readers can now activate every button, including Retry and Add. The alerts inbox says when it is still checking instead of claiming nothing needs your attention. Share exports the card you picked. The vault form names each field and can no longer hang while saving. Delete all data is in About. Choose which exam categories notify you. The radar marks what arrived since your last visit, Dates is grouped, and the status pill stays readable at large text.

**Full notes**

- **Every button works with a screen reader.** A group of controls were announced
  as buttons — "Retry", "Add", "N saved", "Notice details", "See live results",
  "Try again", "Browse live results", the alert bell, "Copy roll number", "Edit
  caption" — but double-tapping did nothing. They now activate, and a test fails
  the build if a button on the five main screens ships without an action again.
- **The alerts inbox no longer guesses.** It used to say "Nothing needs your
  attention" before it had checked anything — on result day, with a dead network.
  It now says it is checking, or that it could not check and offers Retry, and
  only claims there is nothing to report once it has actually looked.
- **Share exports the card you selected.** After tapping a radar row, swiping to
  another card and opening Share used to export the first exam. The selected card
  now wins, the header names the exam being exported, and the details are read
  from the current feed — so a result that arrived after you tapped no longer
  exports as "update awaited". Dismissing the share sheet says nothing was sent
  instead of claiming it shared for you. The exported image is sized from the
  card rather than the device, so a wide screen no longer produces a huge file.
- **The vault form says what each field is.** All twelve text fields are
  announced by their name ("Exam name", "Centre address", "Gate", "Roll number")
  rather than by their example text, the password toggle is labelled, and a
  refused save is read aloud instead of only turning red. If the exam date is
  what is blocking the save, the form scrolls to it. A save that hangs now times
  out with a message and a Retry instead of leaving the button spinning forever,
  and Retry cannot create a duplicate card.
- **"Delete all data" exists.** It is in About, under "Your data", behind a
  confirmation. It removes every admit card, every setting and the cached feed.
  Your push token is kept (it carries no exam or vault data); the per-exam bells
  are dropped, and the notification categories go back to the default of all
  five, so the Notifications section shows what the device is really subscribed
  to.
- **You choose which exam categories notify you.** About has a Notifications
  section with the five categories. Turning them all off is allowed and the app
  says what that means.
- **The radar marks what is new.** A rule labelled "EARLIER" separates the rows
  that arrived since your last visit from the rest, so the dot on the tab now
  points at something you can see. It never appears when nothing is new, and never
  on a fresh install.
- **The Dates tab is grouped.** Entries are under "Next 7 days", "Next 30 days"
  and "Later" — day counts, not calendar weeks or months — in the same
  nearest-first order as before, and a screen reader can jump between the three
  headings.
- **The status pill stays readable.** At large text — and on a narrow phone at the
  normal size — the pill used to be squeezed until its label painted below the
  app's own minimum type size. It now paints at full size at every setting.
- **A search says how much it found.** With a query or a category chip active, the
  vault header reads "1 of 5" instead of "5 saved" over a single card.
- **Landscape works on iPhone and iPad.** Rotating the device is supported again,
  including the orientations iPad Split View needs.

**Verification note (not user copy).** This environment has no Android SDK and no
JDK, so `flutter build apk` / `appbundle` cannot be run here and no AAB or APK was
produced for this section. The Android artefacts come from CI
(`.github/workflows/ci.yml`, job `build-android`), which derives the version from
`app/pubspec.yaml` and passes it as `EV_APP_VERSION` to both build invocations;
with `version: 1.0.1+2` in place that value is `1.0.1+2` (verified by running the
step's own script from `app/` with a stubbed `flutter`). The web release build,
analyze, format and the full test suite were run locally on this tree: analyze
`No issues found!`, format 0 changed, `flutter test` 948 passed / 7 skipped /
0 failed, `node --test` 49/49, `flutter build web --release` succeeded.

## What CI produces

The `build-android` job (`Build release APK`) runs on every push to `master` or
`main`, on `v*` tags, and on manual `workflow_dispatch` — never on pull requests
(secrets are unavailable to fork PRs). It builds one App Bundle and three split
APKs, published as two downloadable workflow artefacts:

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
    (`app/lib/data/local/secure_vault_store.dart:113-133`), roll checks are answered
    from a local hashed index (`app/lib/features/result_checker/engine/hashed_index.dart:74-83`),
    and all five families exist as `ExamCategory` values
    (`app/lib/domain/entities/exam_category.dart:8`).
- **Category:** Education
- **Icon:** `app/assets/branding/app_icon_512.png` (512×512)
- **Feature graphic:** `design/exports/feature_graphic_1024x500.png` — **done**,
  exactly 1024×500. Every colour in it is an existing token from
  `design/tokens.json` / `app/lib/core/theme/theme_tokens.dart` — nothing is
  invented, and the script's header table maps each constant to its token. The
  mark reuses `make_icons.py`'s `_shield` geometry and `build_svg.py`'s `markBlue`
  ramp; the type is the app's bundled Plus Jakarta Sans and IBM Plex Mono. No
  stock imagery, no statistics, no invented UI. Regenerate with:
  ```
  python3 tools/branding/make_feature_graphic.py
  ```
  It writes the PNG, needs only `python3` (stdlib) and `google-chrome`, and fails
  if the result is not exactly 1024×500. It also drops the intermediate SVG beside
  it (`feature_graphic_1024x500.svg`); that file is regenerated by the same
  command and is not needed for upload.
- **Screenshots:** `design/exports/screenshots/` — five PNGs at **1410×2808**
  (`01-home`, `02-vault`, `03-dates`, `04-radar`, `05-share`). That is 1.99:1,
  inside Play's **2:1** aspect ceiling, and above its 1080×2340 pixel floor —
  both constraints matter, and the app's own 393×852 reference viewport fails
  the second one (it is 2.17:1 and would be rejected at upload). Regenerate with:
  ```
  cd app && EV_SCREENSHOTS=1 flutter test test/screenshot_capture_test.dart
  ```
  **These are rendered from the real widgets, not captured on a device.** The
  harness pumps the shipped `RootShell` at a 470×936 logical viewport and
  rasterises the frame through `RepaintBoundary.toImage(pixelRatio: 3)`, so the
  output is 3× the layout — the pixel density a 3× phone reports — using the same
  `app/test/support/matrix.dart` fixture the layout matrix asserts against and
  the app's bundled fonts. Nothing is drawn by hand, so the pictures cannot show
  a screen the app does not have — but they also carry no status bar, no device
  chrome and no real network: the feed is the matrix's canned JSON.

  470 dp is a **large-Android width** (the app's own matrix tops out at 430 dp),
  chosen because at the 2:1 ceiling the 393 dp reference has only 786 dp of height
  and at that size Vault's floating dock and Share's fixed CTA each cover the last
  row of their screen. Every shot is captured **at rest** — no scroll offsets —
  with its title bar, content and tab bar all intact, and the harness now asserts
  that framing (header in the top third, tab bar at the bottom) rather than only
  the pixel dimensions.

  Two fixture details to know before re-running it:
  - the Vault capture lands on a card with **empty** `centerAddress`, `gate` and
    `reportBy`, so the pass page omits its centre card and everything fits above
    the floating dock. Re-running with a fully-populated card produces a
    different, taller page — that is the fixture, not a broken harness. The state
    is layout-tested by `state_matrix_test.dart`'s `noCentreDetails` case.
  - the feed is trimmed to two rows so the Home radar block is not cut by the tab
    bar.

  When a physical device is available, re-capture on it and replace these; the
  pipeline above stays a reproducible manual check — nothing runs it in CI, by
  design, because it writes files into the repo.

## Version codes: sideloaded APKs vs the Play AAB

`pubspec.yaml` carries `version: 1.0.1+2` (versionCode 2). `flutter build apk
--split-per-abi` makes Flutter add `1000 × ABI index` to that, so the artefacts
CI uploads are:

| Artefact | versionCode |
|---|---|
| `app-release.aab` (Play) | **2** |
| `app-armeabi-v7a-release.apk` | **1002** |
| `app-arm64-v8a-release.apk` | **2002** |
| `app-x86_64-release.apk` | **3002** |

(1.0.0+1 was versionCode 1, so the numbers above are 1.0.1's. Re-derive this table
from `pubspec.yaml` whenever the build number changes — it is arithmetic, not a
claim about a build.)

Consequence to remember before distributing APK links: a phone that sideloaded a
split APK sits at versionCode 1002/2002/3002 (for 1.0.1; 1001/2001/3001 for
1.0.0). Play updates carry the AAB's plain
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
| No account, no profile, nothing to sign in to | no auth dependency in `app/pubspec.yaml`; the About sheet says so in the app — `app/lib/features/about/about_sheet.dart`, `_PolicySheet._sections` (the "No account, no profile" entry) and the "What we store" bullet "There is no account, so there is nothing to sign in to" |
| The vault is encrypted on the device and never uploaded | `app/lib/data/local/secure_vault_store.dart:113-133` — `flutter_secure_storage` v11 defaults (AES-GCM under an RSA-OAEP key in the Android Keystore), `resetOnError: false` so a Keystore fault cannot silently wipe it; `android:allowBackup="false"` in `app/android/app/src/main/AndroidManifest.xml` |
| No analytics, no advertising identifier | no analytics/ad SDK in `app/pubspec.yaml`; `AppLogger` writes to the Dart VM sink only, which a release build does not have (`app/lib/data/services/app_logger.dart:5`) |
| Roll numbers never leave the device | `app/lib/features/result_checker/engine/hashed_index.dart:74-83` — the downloaded index holds salted SHA-256 hashes, and the comparison is local |

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

One detail the form does not ask for but a reviewer may: the About sheet has a
**Notifications** section (`_NotificationCategories` in
`app/lib/features/about/about_sheet.dart`) where the student chooses which of the
five exam categories the push token subscribes to. Boot reconciles the token to
that stored set — `bootPush` in `app/lib/main.dart` ends with
`push.syncTopics(container.read(followedCategoriesProvider))` — and an install
that never opened the picker has no stored set, which defaults to **all five**
(`FollowedCategoriesNotifier.build`), so existing users keep the behaviour they
had. A stored empty set is a real choice: every category off means no exam
alerts, without changing the OS permission. Either way it is a single
"Device or other IDs" entry with purpose *App functionality*, because the picker
only narrows *which* topics the same token is subscribed to — it adds no data
type, no second identifier and no new recipient.

## Content rating

Utility app, no user-generated content, no ads, no purchases. Answer the
questionnaire literally; the expected outcome is Everyone / 3+.

## Permissions in the merged release manifest, with attribution

The app declares **3** permissions; the merged release manifest ships **26**,
because the push SDKs and AndroidX merge in their own. Play reviewers and the
Console's APK analysis see the merged set, so paste attributions, not guesses.

**Provenance.** These 26 rows were read from a release build's merged manifest
(`app/build/app/intermediates/merged_manifests/release/processReleaseManifest/arm64-v8a/AndroidManifest.xml`)
and its merger report
(`app/build/app/outputs/logs/manifest-merger-release-report.txt`) at the time
this document was written. **They cannot be regenerated in the environment that
maintained this document**: there is no Android SDK there and no *release* build
output — `app/build/` exists but holds only `flutter test` artefacts
(`native_assets`, `test_cache`, `unit_test_assets`), and neither the merged
release manifest nor the merger report is present. Nothing here was re-derived
for 1.0.1. Treat the count and the attributions as
a record of that build, and re-derive both from a fresh `flutter build appbundle`
(or `flutter build apk`) before pasting anything into the Console: a new plugin
version can add or drop a permission, and the number in particular is expected to
drift.

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
- [x] Screenshots at ≥1080×2340 and ≤2:1: `design/exports/screenshots/` —
      1410×2808 (1.99:1), rendered from the real widgets (regen: `cd app &&
      EV_SCREENSHOTS=1 flutter test test/screenshot_capture_test.dart`). Replace
      with device captures if a phone is available; the widget pipeline is the
      reproducible fallback.
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
| **No PDF is mirrored or re-hosted.** Result documents open on the commission's own site. | `app/lib/domain/entities/live_update.dart:81` — `officialPdf`/`officialPage` are URLs the feed carries, and every use of them is a link the user taps or a URL printed as text: `launchUrl(..., LaunchMode.externalApplication)` in `instant_result_checker_screen.dart`'s `_openUrl` and `exam_detail_sheet.dart`'s `_LinkRow` onTap; copy-to-clipboard of the same URL (`instant_result_checker_screen.dart:550`); `LiveUpdate.officialUrl` (`officialPdf ?? officialPage`) passed to the share card (`whatsapp_share_card_screen.dart:129`), where `ShareInfographic.link` (`share_infographic.dart:47`) only feeds a hostname label in `_CtaBar` (`:519-568`) and the caption text; and re-serialised as `official_pdf`/`official_page` in `app/lib/data/models/live_feed_dto.dart:252-253`. None of those fetches, downloads or stores the document — the app never requests it. `app/lib/features/result_checker/engine/hashed_index.dart:74-83` — the published index holds hashes only. `AppConfig.resultPdfPath` (the legacy mirror route) still exists but has **no callers anywhere in `lib/` or `test/`**, and the `pdfBytes`/`pdfUrl` wrappers that used to sit beside it were deleted — no code path downloads a PDF. |
| **No analytics, no crash reporting, no ad SDK.** | `app/pubspec.yaml` dependency list (no analytics/crash/ads package); `app/lib/data/services/app_logger.dart:5` — `developer.log` only, inert in a release AOT build; `app/lib/features/about/about_sheet.dart` — the `_PolicySheet._sections` entry "No analytics, no adverts" states it in-app |
| **No account.** No email, phone, password, login, or profile field exists. | `app/lib/features/about/about_sheet.dart` — `_PolicySheet._sections` ("No account, no profile") and the "What we store" bullet "There is no account"; no auth dependency in `app/pubspec.yaml` |
| **No location.** No location permission and no location code. | `app/android/app/src/main/AndroidManifest.xml:6` (comment) and the declared-permission block below it; `app/lib/features/about/about_sheet.dart` — `_PolicySheet._sections` ("No analytics, no adverts", which also says "no location permission") |
| **Encrypted local vault.** Cards, roll numbers and portal passwords are encrypted at rest and excluded from backup. | `app/lib/data/local/secure_vault_store.dart:113-133`; `android:allowBackup="false"` + `dataExtractionRules` in the manifest |
| **The only identifier that leaves the device is the push token.** | `app/lib/data/services/push_service.dart` — `_syncOneSignalTags` (`:176`) and `syncTopics` (`:281`) send only category tags/topics; `bootPush` in `app/lib/main.dart` (`:150`) feeds them the student's chosen set |
| **Roll numbers are checked on the device and never sent.** | `app/lib/features/result_checker/engine/hashed_index.dart:74-83` (hashes only) and `roll_index_engine.dart` (local binary search) |


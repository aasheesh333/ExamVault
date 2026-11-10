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
- **Short description (80 char):** Admit cards and instant roll-number result checks — SSC, UPSC, Banking, Railways, PSC.
- **Category:** Education
- **Icon:** `app/assets/branding/app_icon_512.png` (512×512)
- **Feature graphic:** 1024×500 — still to make
- **Screenshots:** 393×852 renders are in the design file; the four screens must
  be captured at 1080×2340 or larger from a real device build.

## Data safety

Answer exactly as in `docs/PRIVACY.md`:

- Collects or shares required user data? **No.**
- Encrypted in transit? **Yes** (`usesCleartextTraffic="false"`, HTTPS only).
- Deletion request path? **Yes** — delete a card in-app, or uninstall.
- Analytics/advertising SDK? **No.**

## Content rating

Utility app, no user-generated content, no ads, no purchases. Answer the
questionnaire literally; the expected outcome is Everyone / 3+.

## Permissions declared, and the justification to paste into Play

| Permission | Justification |
|---|---|
| `INTERNET` | Downloads the public result feed and index |
| `ACCESS_NETWORK_STATE` | Shows "cached" instead of a spinner when offline |
| `POST_NOTIFICATIONS` | Result alerts (optional, Android 13+) |
| `USE_BIOMETRIC` | Optional vault unlock |

No location, contacts, storage, camera or advertising ID.

## Before you press publish

- [ ] Replace the throwaway upload keystore with one you have backed up
- [ ] Capture real screenshots from a device build at ≥1080×2340
- [ ] Make the 1024×500 feature graphic
- [ ] Host `docs/PRIVACY.md` at a public URL and paste it into the listing
- [ ] Decide the licensing stance on any mirrored PDF (currently: link-only, no
      mirroring — see `docs/DATA_PIPELINE.md`)
- [ ] Create the Play Console app and upload `app-release.aab` to internal testing
      first; the internal track surfaces policy warnings without a public review

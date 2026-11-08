# GitHub Actions secrets

Nothing in this list is ever committed to the repository. All of it is injected
at build time via `--dart-define` (Dart) or the environment (Wrangler).

Add them with:

```sh
gh secret set NAME --repo <owner>/ExamVault --body "<value>"
```

or: **Settings → Secrets and variables → Actions → New repository secret**.

---

## Required for a push-enabled build

| Secret | Where it comes from | Used by |
|---|---|---|
| `EV_FIREBASE_API_KEY` | Firebase console → Project settings → Your apps → `apiKey` | `--dart-define` |
| `EV_FIREBASE_APP_ID` | same → `appId` | `--dart-define` |
| `EV_FIREBASE_SENDER_ID` | same → `messagingSenderId` | `--dart-define` |
| `EV_FIREBASE_PROJECT_ID` | same → `projectId` | `--dart-define` |
| `EV_FIREBASE_STORAGE_BUCKET` | same → `storageBucket` | `--dart-define` |

> These are *client* identifiers, not secrets in the cryptographic sense — they
> ship inside every Firebase app binary. They are still kept out of the repo so
> that a fork cannot accidentally inherit production quotas, and so that
> rotation is a one-line change.

## Optional — push via OneSignal

| Secret | Where it comes from |
|---|---|
| `EV_ONESIGNAL_APP_ID` | OneSignal → Settings → Keys & IDs → OneSignal App ID |

## Optional — edge endpoint overrides

| Secret | Default if unset |
|---|---|
| `EV_CDN_BASE` | `https://cdn.examvault.in` |
| `EV_WEB_BASE` | `https://examvault.in` |

## Optional — Android release signing

Without these the build falls back to debug keys and `flutter build apk
--release` still succeeds; the APK just cannot be uploaded to Play.

| Secret | Notes |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 upload-keystore.jks` |
| `ANDROID_STORE_PASSWORD` | keystore password |
| `ANDROID_KEY_ALIAS` | key alias |
| `ANDROID_KEY_PASSWORD` | key password |

## Required for edge deploy

| Secret | How to create |
|---|---|
| `CLOUDFLARE_API_TOKEN` | Cloudflare dashboard → My Profile → API Tokens → *Edit Cloudflare Workers* template. Needs **Workers Scripts:Edit**, **Workers R2 Storage:Edit**. |
| `CLOUDFLARE_ACCOUNT_ID` | Cloudflare dashboard → Workers → right sidebar |

---

## What must never be added

- `google-services.json` — use the `EV_FIREBASE_*` dart-defines instead. The app
  builds without it.
- OneSignal REST API key — that key can send notifications to every user. It
  belongs in the publish job (a separate service), never in the app or in CI for
  the app.
- Anything from `~/.wrangler/config/default.toml`.

## Verifying nothing leaked

```sh
# Should print nothing.
git log -p | grep -nE 'AIza[0-9A-Za-z_-]{35}|cfoat_|ghp_[A-Za-z0-9]{36}|-----BEGIN'
```

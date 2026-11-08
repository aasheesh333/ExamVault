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
| `CLOUDFLARE_API_TOKEN` | ✅ **set** — token `examvault-ci-deploy`, scoped to Workers Scripts:Edit, Workers R2 Storage:Edit, Workers KV Storage:Edit, Account Settings:Read |
| `CLOUDFLARE_ACCOUNT_ID` | ✅ **set** — `7fb570ac615a8e2a41a6aff7913114d5` |

> The token is scoped to *account* policies only. There is deliberately no Zone
> policy: the worker deploys to `workers.dev`, so it needs no zone route. The
> stock "Edit Cloudflare Workers" template adds a zone policy, which makes the
> Summary step require a zone — building the token from scratch avoids that.

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

---

## Current values (verified 2026-11-08)

| Secret | State |
|---|---|
| `EV_FIREBASE_API_KEY` | set (Firebase project `examvault-49b1a`) |
| `EV_FIREBASE_APP_ID` | set — `1:722361800293:android:1dab5ec2d3df41437e588c` |
| `EV_FIREBASE_SENDER_ID` | set — `722361800293` |
| `EV_FIREBASE_PROJECT_ID` | set — `examvault-49b1a` |
| `EV_FIREBASE_STORAGE_BUCKET` | set |
| `EV_ONESIGNAL_APP_ID` | set — `062ce6a9-a47e-48d8-bb4d-dfee88b60026` |
| `EV_CDN_BASE` | set — worker URL |
| `EV_WEB_BASE` | set — `https://examvault.in` |

`CLOUDFLARE_API_TOKEN` / `CLOUDFLARE_ACCOUNT_ID` still need adding for the edge
deploy job (Wrangler used an interactive OAuth token locally, which is
deliberately not committed).

### OneSignal notes

The app `062ce6a9-…` is an **Android/iOS** app (its web-push endpoint replies
`"This app is not configured for web push"`), which matches how the app uses it.
`PushService` therefore skips OneSignal on web and only activates it on mobile.
Categories map to OneSignal boolean tags: `exam_ssc`, `exam_upsc`,
`exam_banking`, `exam_railways`, `exam_state_psc`.

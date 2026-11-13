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

## Edge endpoint overrides

`EV_CDN_BASE` is **required for a usable build** — there is no fallback. An
*empty* secret is the dangerous case: `--dart-define=EV_CDN_BASE=""` overrides
the worker URL compiled into `AppConfig.cdnBase` as its default, every request
becomes a schemeless path, and the result is a permanent "no feed" that looks
like an outage rather than a misconfiguration — with green CI. The `Build APK`
step in `.github/workflows/ci.yml` therefore refuses to build when the secret is
empty or missing (`::error::` + exit 1), which is the loud failure this section
used to only promise.

`EV_WEB_BASE` feeds the share card's deep link (`result_index_repository.dart`
→ `shareUrl()` → `<base>/r/<examId>`). **Leave it UNSET until the project owns
a real domain.**

The worker's `GET /r/<examId>` route works and is deployed (it resolves the
link against the live feed and 302s to the commission's own result PDF/page),
so pointing this at the worker origin is *technically* functional — but a
`*.workers.dev` URL printed on a card whose whole job is going viral reads as
a dev server, not a product. Owner decision, 2026-11-12: the secret was set for
one day, then deleted again. While unset, `shareUrl()` returns null and the
card prints **the commission's own URL** — the more trustworthy link anyway.

When a domain is bought: add it to the Cloudflare account, route it at the
worker, set `EV_WEB_BASE=https://<that-domain>`, and the already-deployed `/r/`
route starts appearing on cards with zero code changes. **The project owns no
domain** — never point this at a name nobody registered (e.g. the never-owned
`examvault.in` from early mockups).

## Android release signing

Without these the build falls back to debug keys: `flutter build apk --release`
still succeeds locally, but the artefact **cannot be uploaded to Play**, and
in-place updates break because the key differs per machine.

`app/android/app/build.gradle.kts` reads `android/key.properties` (written by CI,
git-ignored). **Back up the keystore and its password.** Play will not accept an
update to `app.examvault` signed with a different key without a signed key-reset
request, which takes days.

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

## Current values (verified 2026-11-10)

| Secret | State |
|---|---|
| `EV_FIREBASE_API_KEY` | set (Firebase project `examvault-49b1a`) |
| `EV_FIREBASE_APP_ID` | set — `1:722361800293:android:1dab5ec2d3df41437e588c` |
| `EV_FIREBASE_SENDER_ID` | set — `722361800293` |
| `EV_FIREBASE_PROJECT_ID` | set — `examvault-49b1a` |
| `EV_FIREBASE_STORAGE_BUCKET` | set |
| `EV_ONESIGNAL_APP_ID` | set — `062ce6a9-a47e-48d8-bb4d-dfee88b60026` |
| `EV_ONESIGNAL_REST_KEY` | **optional** — unset today. Set it to send exam alerts through OneSignal (REST key from the dashboard). |
| `FCM_SERVICE_ACCOUNT_JSON` | **optional** — unset today. Set it (Firebase service-account JSON, raw or base64) to send through FCM HTTP v1 topics instead. Preferred when available. |
| `EV_CDN_BASE` | set — worker origin `https://examvault-edge.aasheeshkatheriya.workers.dev` |
### Exam alerts need one of these two keys

The per-exam bells in the app subscribe to `exam_<examId>` topics/tags. The
refresh workflow diffs each new snapshot against the previous one and calls
`tools/dispatch_alerts.mjs`, which sends through **whichever** provider has
credentials:

* `FCM_SERVICE_ACCOUNT_JSON` → FCM HTTP v1, one send per topic (free on Spark,
  no per-device fan-out). Create it in Firebase console → Project settings →
  Service accounts → Generate new private key, for project `examvault-49b1a`.
* or `EV_ONESIGNAL_REST_KEY` → OneSignal REST, filtered to the same tag.

With neither set the workflow still succeeds and logs exactly what it *would*
have sent — a missing notification must never redden the pipeline that
publishes the data. Nothing else needs to change when a key is added: the
channel id (`exam_alerts_v2`) and topic names are already in the app.

| `EV_WEB_BASE` | **deliberately UNSET** — a workers.dev URL on the share card reads as a dev server; until a real domain is owned the card prints the commission's own URL (see above) |
| `CLOUDFLARE_API_TOKEN` | set |
| `CLOUDFLARE_ACCOUNT_ID` | set |
| `ANDROID_KEYSTORE_BASE64` | set — upload keystore, `CN=ExamVault` |
| `ANDROID_STORE_PASSWORD` | set |
| `ANDROID_KEY_ALIAS` | set — `examvault-upload` |
| `ANDROID_KEY_PASSWORD` | set |

Verified: the AAB built by CI is signed with
`SHA-256 F4:D8:1E:BC:8C:DF:91:D7:15:52:01:CB:4F:77:46:C1:87:1E:32:E4:50:E5:6C:D4:17:53:A3:47:EA:34:E0:EB`.

> If an `EV_WEB_BASE` secret exists in your environment from the 2026-11-11
> experiment, delete it: `gh secret delete EV_WEB_BASE`. The `/r/<examId>`
> route stays deployed and tested either way — it deploys automatically on
> any push to `master` that touches `infra/**` (CI job `deploy-edge`), so it
> is ready the day a real domain is mapped.

### OneSignal notes

The app `062ce6a9-…` is an **Android/iOS** app (its web-push endpoint replies
`"This app is not configured for web push"`), which matches how the app uses it.
`PushService` therefore skips OneSignal on web and only activates it on mobile.
Categories map to OneSignal boolean tags: `exam_ssc`, `exam_upsc`,
`exam_banking`, `exam_railways`, `exam_state_psc`.

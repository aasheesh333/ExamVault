# Provisioning status

Verified 2026-11-08. Read this before assuming any credential exists.

| Service | State | Evidence |
|---|---|---|
| **Cloudflare R2** | ✅ Live | bucket `examvault-cdn` created in account `7fb570ac…114d5` |
| **Cloudflare Worker** | ✅ Live | `https://examvault-edge.aasheeshkatheriya.workers.dev` |
| **Edge cache + 304** | ✅ Verified | `curl` shows `x-examvault-cache: HIT` and `304` on `If-None-Match` |
| **Roll index object** | ✅ Published | `v1/rolls/ssc_cgl_tier1_2026_rolls.json.gz`, 19 782 rolls, 106 KB gzip |
| **Live feed object** | ✅ Published | `v1/live_feed_v1.json`, 4 updates |
| **Firebase project** | ❌ Blocked | Firebase console enforces account-level MFA; this Google account has 2SV off. Console redirects every route to `/mfa`. |
| **OneSignal app** | ❌ Blocked | `dashboard.onesignal.com` returns HTTP 403 for this datacenter IP (country/IP blocklist). Not bypassable from a VPS. |

Both blockers are **account/IP gatekeeping, not code**. The app already supports
either backend and needs only an ID.

---

## Finish Firebase (≈3 minutes, needs your phone)

1. Open <https://myaccount.google.com/signinoptions/two-step-verification> and
   enable 2-Step Verification (Firebase requires it).
2. Then <https://console.firebase.google.com> → **Add project** → name it
   `ExamVault`.
3. Project settings → **Your apps** → Add Android app, package
   `app.examvault`.
4. Copy the five values into GitHub secrets:

```sh
gh secret set EV_FIREBASE_API_KEY      --repo aasheesh333/ExamVault
gh secret set EV_FIREBASE_APP_ID       --repo aasheesh333/ExamVault
gh secret set EV_FIREBASE_SENDER_ID    --repo aasheesh333/ExamVault
gh secret set EV_FIREBASE_PROJECT_ID   --repo aasheesh333/ExamVault
gh secret set EV_FIREBASE_STORAGE_BUCKET --repo aasheesh333/ExamVault
```

No `google-services.json` is needed — the app reads these at runtime.

## Finish OneSignal (≈2 minutes, needs a normal connection)

1. Open <https://dashboard.onesignal.com/signup> from a residential/mobile
   connection (the dashboard blocks this VPS IP).
2. New app → name `ExamVault` → platform **Android** →
   Firebase project (or "Not a Firebase project" to skip).
3. Settings → **Keys & IDs** → copy the OneSignal App ID:

```sh
gh secret set EV_ONESIGNAL_APP_ID --repo aasheesh333/ExamVault
```

The app prefers OneSignal when `EV_ONESIGNAL_APP_ID` is present and falls back to
FCM topics otherwise; with neither, push silently disables and everything else
works.

## Add the Cloudflare deploy token

Wrangler here used an interactive OAuth token (`~/.wrangler/config/default.toml`),
which is **not** committed and must not be. Create a scoped token for CI:

Cloudflare → My Profile → API Tokens → *Edit Cloudflare Workers* template
(+ **Workers R2 Storage:Edit**), then:

```sh
gh secret set CLOUDFLARE_API_TOKEN  --repo aasheesh333/ExamVault
gh secret set CLOUDFLARE_ACCOUNT_ID --repo aasheesh333/ExamVault
```

## Verify the edge yourself

```sh
curl -sI https://examvault-edge.aasheeshkatheriya.workers.dev/v1/live_feed_v1.json
curl -sI https://examvault-edge.aasheeshkatheriya.workers.dev/v1/rolls/ssc_cgl_tier1_2026_rolls.json.gz
```

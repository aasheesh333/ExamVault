# Provisioning status

Verified 2026-11-08, after a manual MFA bootstrap of the Google account.

| Service | State | Evidence |
|---|---|---|
| **Cloudflare R2** | ✅ Live | bucket `examvault-cdn` |
| **Cloudflare Worker** | ✅ Live | `https://examvault-edge.aasheeshkatheriya.workers.dev` |
| **Edge cache + 304** | ✅ Verified | `x-examvault-cache: HIT`, `304` on `If-None-Match` |
| **Roll index** | ✅ Published | `v1/rolls/ssc_cgl_tier1_2026_rolls.json.gz` — 19 782 rolls, 106 KB gzip |
| **Live feed** | ✅ Published | `v1/live_feed_v1.json` — 4 updates |
| **Firebase project** | ✅ Created | **ExamVault** · `examvault-49b1a` · number `722361800293` |
| **Firebase Android app** | ✅ Registered | package `app.examvault` · app id `1:722361800293:android:1dab5ec2d3df41437e588c` |
| **Firebase secrets** | ✅ Set | 7 repo secrets (see `.github/SECRETS.md`) |
| **OneSignal** | ❌ Blocked | signup **and** login both return "Something went wrong"; Google OAuth returns HTTP 403 (datacenter IP blocklist). Not a code issue. |

## Verified end-to-end

Built the app for web with the real Firebase + Cloudflare values, served it, and
drove it through the browser:

- radar shows **LIVE · EDGE**, 4 updates, `82ms` mirror latency
- conditional GET confirmed: repeated `live_feed_v1.json` calls return **304**
- result checker fetched `…_rolls.json.gz` from the edge (**200**)
- lookup of a present roll → **"SELECTED IN MERIT LIST", merit rank 5000, 40.1 ms**
- lookup of an absent roll → honest *"not in this list yet"* with the row count
- Firebase Messaging initialised (`flutterfire-firebase_messaging` in console)

Two real bugs were found and fixed at this stage — see commit `0eb47ab`.

## Fixing OneSignal

The dashboard blocks this datacenter IP. Do it from a normal connection:

1. <https://dashboard.onesignal.com/signup> → new app named **ExamVault**
2. Platform **Android**, package `app.examvault`
3. Settings → **Keys & IDs** → copy the **OneSignal App ID**

```sh
gh secret set EV_ONESIGNAL_APP_ID --repo aasheesh333/ExamVault
```

The app already prefers OneSignal when `EV_ONESIGNAL_APP_ID` is present
(`PushService` selects the provider and maps categories to OneSignal tags), and
falls back to FCM topics otherwise.

## Adding Android to FCM (optional)

`firebase_messaging` also needs the FCM server key path set up in the console —
nothing to configure in code: the app subscribes to topics
`exam_ssc`, `exam_upsc`, `exam_banking`, `exam_railways`, `exam_state_psc`.

## Verify the edge yourself

```sh
curl -sI https://examvault-edge.aasheeshkatheriya.workers.dev/v1/live_feed_v1.json
curl -sI https://examvault-edge.aasheeshkatheriya.workers.dev/v1/rolls/ssc_cgl_tier1_2026_rolls.json.gz
```

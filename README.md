# ExamVault

Ultra-fast exam utility for Indian competitive exam aspirants — SSC, UPSC, IBPS/Banking, Railways, State PSC.

Built to survive **result day**: the minute a PDF drops, ~10 million students hit the same page at once. ExamVault answers the only question that matters — *"am I selected?"* — from a 150 KB edge-cached index, on the device, in under a millisecond. No 60 MB PDF. No crashed server queue.

```
ExamVault/
├── app/                      Flutter application (Flutter 3.47 · Material 3 · Impeller)
├── design/                   Design system, tokens, 8 Figma frames (dark + light)
├── infra/                    Cloudflare R2 + edge worker
└── .github/workflows/        CI: analyze → test → build, secrets injected at build time
```

---

## The architecture in one page

| Problem on result day | What breaks normally | What ExamVault does |
|---|---|---|
| Official site | 504s under 10M concurrent users | Never load it. Fetch a 150 KB gzip index from Cloudflare's edge. |
| "Am I selected?" | Download a 60 MB PDF, scroll, find your roll | `Isolate.run()` → gunzip → JSON parse → **binary search** in < 1 ms |
| Push to 10M users | Fan-out messaging needs a paid plan + queue | **FCM topics** — one publish, unlimited subscribers, free on Spark |
| App launch on 2G | Cold start blocks on network | Hive cache paints first frame; network refreshes behind it |
| Server cost | ₹lakhs/month at spike | **$0** — R2 + CDN cache + Spark plan |

### The load-bearing decisions

**1. Binary search over a sorted index, not a PDF.**
`ssc_cgl_tier1_rolls.json.gz` is a lexicographically sorted JSON array of roll numbers. The app decompresses it inside a Dart isolate, keeping the UI thread completely free, then binary-searches it. 1M rolls ≈ 150 KB gzipped, ≈ 12 MB in memory, one search ≈ 0.02 ms. This is the single reason the app is useful at 09:12 when the SSC site is not.

**2. Cloudflare R2 + `s-maxage=3600`.**
One object, one cache key, served from the nearest PoP. Origin sees roughly one request per object per TTL window regardless of how many users request it. Egress from R2 through Cloudflare is free; the CDN absorbs the stampede.

**3. Single-flight + conditional GET + full jitter.**
`CdnClient` guarantees that N widgets asking for the same object in one frame produce exactly one socket, revalidates with `If-None-Match` (a 304 costs ~200 bytes instead of 150 KB), and retries with *full* jitter so a PoP hiccup never becomes a synchronised retry storm. Verified in `test/cdn_client_test.dart`.

**4. Stale-while-offline.**
A 72-hour-old cached feed beats an error screen. The radar always shows *where the data came from* — `LIVE · EDGE`, `CACHED`, or `SAMPLE DATA` — because trust is the product.

**5. Credentials never leave the device.**
Roll numbers, portal passwords and DOB live in `flutter_secure_storage` (Android Keystore, AES-GCM + RSA-OAEP key wrapping). No backend, no account, no sync. The vault is explicitly excluded from Android Auto Backup and device transfer, because the Keystore key does not travel with it.

---

## Screens

| # | Screen | What it does |
|---|---|---|
| 1 | **Command Center** | Category chips, Apple-Wallet-style stacked passes with 1-tap roll copy + haptics, live result radar with glowing status pills |
| 2 | **Boarding-pass Vault** | Encrypted credentials with per-field copy, exam-day document checklist, centre address + map deep link |
| 3 | **Instant Result Checker** | Auto-fills the saved roll number, `Check` → edge index → isolate binary search → "🎉 SELECTED IN MERIT LIST" or an honest "not in this list" |
| 4 | **WhatsApp Share Card** | `RepaintBoundary` → 1080 px PNG → share sheet, with an editable caption preview |

Both themes ship in `design/exports/examvault-sheet.svg` (8 frames). The pass cards stay deep navy in **both** themes on purpose — they are physical objects, and it keeps the 31px roll number at 13.96:1 contrast.

---

## Run it

```sh
cd app
flutter pub get
flutter run                       # works with no credentials at all
```

No `google-services.json` is required. Firebase is configured at **runtime** from `--dart-define` values; with none supplied, push degrades to a no-op and everything else works. That is deliberate — CI and forks must build.

Point it at a real edge:

```sh
flutter run \
  --dart-define=EV_CDN_BASE=https://cdn.examvault.in \
  --dart-define=EV_FIREBASE_API_KEY=... \
  --dart-define=EV_FIREBASE_APP_ID=... \
  --dart-define=EV_FIREBASE_SENDER_ID=... \
  --dart-define=EV_FIREBASE_PROJECT_ID=...
```

## Verify

```sh
cd app
flutter analyze     # 0 issues
flutter test        # 42 tests
```

The suite covers the parts that are expensive to get wrong: binary search against `List.indexOf` on 2000 random inputs, roll-number normalisation of PDF-pasted whitespace, index decode with unsorted/malformed payloads, CDN single-flight, 304 revalidation, retry-with-jitter, download-budget enforcement, vault codec corruption, and a widget smoke test that fails on any RenderFlex overflow or sub-8px text.

## Infrastructure

```sh
cd infra
npx wrangler r2 bucket create examvault-cdn
npx wrangler deploy
```

`infra/src/index.js` is the edge worker that serves the feed and the gzip roll index with the correct cache headers and CORS. See `infra/README.md`.

## CI/CD

`.github/workflows/ci.yml` runs analyze + test on every push, and builds a signed APK on tags. **No credential is ever in the repository** — all of it comes from GitHub Actions secrets and is injected with `--dart-define`.

Required secrets are listed in `.github/SECRETS.md`.

---

## What is intentionally *not* here

- **No backend.** There is no server to fall over, and nothing to pay for.
- **No analytics SDK.** A utility that knows your exam roll numbers should not ship a tracking pixel.
- **No account system.** The vault is local; there is nothing to breach.
- **No invented data.** Cut-offs, ranks and "12,480 aspirants" are only rendered when a publisher actually released them.

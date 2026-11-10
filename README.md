# ExamVault

Ultra-fast exam utility for Indian competitive exam aspirants — SSC, UPSC, Banking, Railways, State PSC.

Built to survive **result day**: the minute a PDF drops, ~10 million students hit the same page at once. ExamVault answers the only question that matters — *"am I in the list?"* — from a small edge-cached index, on the device, in under a millisecond. No 60 MB PDF. No crashed server queue.

```
ExamVault/
├── app/                      Flutter application (Material 3 · Impeller · Riverpod)
├── design/                   Design system, tokens, Figma frames (dark + light)
├── infra/                    Cloudflare R2 + edge worker
├── tools/                    Ingestion, hashed index builder, branding
├── docs/                     Data pipeline · privacy policy · Play submission
└── .github/workflows/        CI: analyze → test → signed AAB + APKs
```

---

## Coverage

Five official sources, each verified against the live site before its adapter was
written. Sources that do not answer are reported, never filled with samples.

| Category | Source | Method | Result lists |
|---|---|---|---|
| SSC | `ssc.gov.in` | public JSON API | yes |
| UPSC | `upsc.gov.in` | “What’s New” HTML | yes |
| Banking | `ibps.in` | recruitment grid | registration windows |
| Railways | `rrbchennai.gov.in` | CEN notices | notices only |
| State PSC | `tnpsc.gov.in` | results grid | yes |

See `docs/DATA_PIPELINE.md` for the adapter details, the rejected sources and why,
and the Health block the pipeline publishes.

---

## The architecture in one page

| Problem on result day | What breaks normally | What ExamVault does |
|---|---|---|
| Official site | 504s under load | Never load it. Fetch a ~35 KB gzip index from Cloudflare's edge. |
| "Am I selected?" | Download a 60 MB PDF, scroll, find your roll | `Isolate.run()` → gunzip → binary search on salted hashes, < 1 ms |
| Push to 10M users | Fan-out messaging needs a paid plan + queue | **FCM topics** / OneSignal segments — one publish, unlimited subscribers |
| App launch on 2G | Cold start blocks on network | Hive cache paints first frame; network refreshes behind it |
| Server cost | ₹lakhs/month at spike | **$0** — R2 + CDN cache + Firebase Spark |

### The load-bearing decisions

**1. A one-way hashed index, not a PDF and not a roll list.**

The published object contains **no roll numbers at all** — only salted SHA-256
digests (8 bytes, sorted). The device hashes what you type and binary-searches.
This is what makes the feature defensible: the object answers one question per
query and cannot be used to reconstruct the candidate list. The official PDF is
never mirrored; every "Official PDF" button opens the commission's own URL.

Dart and Python must agree byte-for-byte, so `test/hashed_index_test.dart` pins
both against shared vectors. A drift there would answer "not selected" for
everybody.

**2. Content-addressed object names.**

`<exam>_<sha256(body)[:12]>_rolls.json.gz`. The roll route is cached
`immutable`, which is only true if the URL never changes — with a stable URL the
edge served the *first* published index for 24 hours, including after a corrected
list replaced it.

**3. Cloudflare R2 + edge caching.**

One object, one cache key, served from the nearest PoP. Origin sees roughly one
request per object per TTL window regardless of user count. Egress from R2 through
Cloudflare is free.

**4. Single-flight + conditional GET + full jitter.**

`CdnClient` guarantees that N widgets asking for the same object in one frame
produce exactly one socket, revalidates with `If-None-Match` (a 304 costs ~200
bytes instead of 35 KB), and retries with *full* jitter so a PoP hiccup never
becomes a synchronised retry storm.

**5. Stale-while-offline.**

A three-day-old cached feed beats an error screen. The radar always shows where
the data came from — `LIVE · EDGE`, `EDGE · 54m OLD`, `CACHED · 2h` — and how old
it is, because trust is the product.

**6. Credentials never leave the device.**

Roll numbers, portal passwords and DOB live in `flutter_secure_storage` (Android
Keystore, AES-GCM). No backend, no account, no sync. Excluded from Android Auto
Backup and device transfer.

---

## Screens

| # | Screen | What it does |
|---|---|---|
| 1 | **Command Center** | Category chips, wallet-style stacked passes with 1-tap roll copy, live radar with status pills, and a per-commission health panel in About |
| 2 | **Boarding-pass Vault** | Encrypted credentials with per-field copy, exam-day checklist, centre address |
| 3 | **Instant Result Checker** | Auto-fills the saved roll, `Check` → edge index → local hash lookup → "YOUR ROLL IS IN THE LIST" or an honest "not in this list" with the reason |
| 4 | **Share Card** | `RepaintBoundary` → PNG → share sheet, with an editable caption and an optional roll number |

Pass cards stay deep navy in **both** themes on purpose — they are physical
objects, and it keeps the 31px roll number at 13.96:1 contrast.

---

## Run it

```sh
cd app
flutter pub get
flutter run                       # works with no credentials at all
```

No `google-services.json` is required. Firebase is configured at **runtime** from
`--dart-define` values; with none supplied, push degrades to a no-op and everything
else works.

Point it at the real edge:

```sh
flutter run \
  --dart-define=EV_CDN_BASE=https://examvault-edge.aasheeshkatheriya.workers.dev
```

## Verify

```sh
cd app
flutter analyze --fatal-infos   # 0 issues
flutter test                    # 115 tests
```

The suite covers the parts that are expensive to get wrong: cross-language hash
parity, binary search against `List.indexOf` on random inputs, index decode with
malformed payloads, CDN single-flight/304/jitter/budget, vault codec corruption, the
**result-day path end to end** (`result_day_test.dart` drives the real UI through a
mocked edge), and a live test that downloads the actual published object from the
real edge and asserts it carries no plaintext roll numbers.

## Data pipeline

```sh
cd tools
node fetch_official_feeds.mjs --out ../data/live_feed.json   # five sources
python3 build_indexes.py --feed ../data/live_feed.json       # PDFs → hashed indexes
node publish_feed.mjs --in ../data/live_feed.json            # to the edge
```

Runs every 30 minutes from `.github/workflows/refresh-data.yml`.

## Infrastructure

```sh
cd infra
npx wrangler r2 bucket create examvault-cdn
npx wrangler deploy
```

## CI/CD

`.github/workflows/ci.yml` runs analyze + test on every push, then builds a
**signed App Bundle and split APKs**. Release signing comes from four repository
secrets; no credential is ever in the repository.

---

## What is intentionally *not* here

- **No backend.** There is no server to fall over, and nothing to pay for.
- **No analytics SDK.** A utility that knows your exam roll numbers should not ship
  a tracking pixel.
- **No account system.** The vault is local; there is nothing to breach.
- **No invented data.** Every row came from a commission's website. Cut-offs and
  ranks are rendered only when a publisher actually released them.
- **No mirrored PDFs.** The app links to the official document and hosts no copy.

# Provisioning status

Verified 2026-11-10 against the live services.

This file is a **dated snapshot**, not a live dashboard. It records what was
verified on the date above; the feed's own `sources[].status` block is the live
answer for any given day, and a commission's site being down is not a change to
the code. Re-observed while preparing 1.0.1 (2026-11-16, feed `revision 13`,
`fetched_at 2026-11-16T11:01:50Z`): `ssc` ok with 17 rows, `upsc` unavailable,
`ibps` empty, `tnpsc` ok with 10 rows, `railways` unavailable — 33 published
updates in total. Nothing below has been rewritten to match that observation; it
stays as the record of 2026-11-10.

| Service | State | Evidence |
|---|---|---|
| **Cloudflare R2** | ✅ Live | bucket `examvault-cdn` |
| **Cloudflare Worker** | ✅ Live | `https://examvault-edge.aasheeshkatheriya.workers.dev` |
| **Live feed** | ✅ Published | `v1/live_feed_v1.json` — 60 rows, 5 sources `ok` (as of 2026-11-10) |
| **Roll indexes** | ✅ Published | 17 hashed indexes as of 2026-11-10, all v2 (`sha256-8-salted`), verified from the edge |
| **Firebase project** | ✅ Created | **ExamVault** · `examvault-49b1a` |
| **Firebase Android app** | ✅ Registered | package `app.examvault` |
| **OneSignal** | ✅ Created | app id `062ce6a9-a47e-48d8-bb4d-dfee88b60026` (Android/iOS; web-push intentionally off) |
| **Release signing** | ✅ Working | AAB signed with `CN=ExamVault` upload key, SHA-256 `F4:D8:1E:…:E0:EB` |
| **CI** | ✅ Green | `dart format` (`lib test tool`), analyze, and the full suite in `app/test` (live-network tests gated behind `EV_LIVE=1`, skipped in CI) · signed App Bundle + 3 split APKs · edge deploy, which runs only on pushes that touch `infra/**` |

Repository secrets: Cloudflare (2), Firebase (5), OneSignal (1), Android signing (4),
edge base (2). Listed in `.github/SECRETS.md`.

## Verified end to end

Every line below was produced by driving the built app, not by asserting intent.

| Claim | How it was checked |
|---|---|
| Five categories carry real rows | feed's `sources` block: ssc 17, upsc 12, ibps 5, tnpsc 10, railways 25 — 69 raw adapter rows, which become the 60 published `updates` after `fetch_official_feeds.mjs` dedupes by `exam_id` (UPSC 12→8) and caps each source at 20 rows (Railways 25→20) |
| Published indexes are hashed | fetched all 17 from the edge; each is `v:2`, `sha256-8-salted`, counts match the feed, and **zero** 7- or 12-digit roll numbers appear in the payload |
| A real roll is found | UPSC CDSE-II index (8,956 rolls) → `2100058` found in **93 µs**; a fabricated roll rejected |
| A saved card resolves its index | typed a UPSC card → matcher linked the published row → checker fetched 2,526 rolls → roll `0801786` found in 13.4 ms |
| A custom index needs its version | content-addressed URL fetched 200; the old stable URL now 404s, proving the immutable-cache fix |
| Empty states are honest | fresh install: Home, Vault, Dates, Radar and Share each explain the next step; no sample rows anywhere |
| Failure is honest | an exam with no published list shows "no list yet" + "Result not published yet", never "not selected" |
| Offline still paints | cached feed renders with an explicit `CACHED · <age>` label |
| Share card exports correctly | captured PNG reviewed: no clipped glyphs, no cut-off claim, no dead button, roll optional |

## Known gaps

Documented rather than hidden — see `docs/DATA_PIPELINE.md` § *Known gaps*.

- Railways has no searchable index: RRB boards publish notices, not roll-list PDFs.
- Only one RRB (Chennai) and one state PSC (Tamil Nadu) answer reliably from this
  network; the other boards either render client-side or have broken TLS.
- IBPS publishes registration windows, not result lists, on the page used.

# ExamVault — Cloudflare edge

One Worker, one private R2 bucket, no database, no origin.

**The only public host is the worker URL:**
`https://examvault-edge.aasheeshkatheriya.workers.dev`
The project owns no domain. Any instruction you find elsewhere that points a
build, a bucket domain or a share link at something like `cdn.examvault.in` is
fiction from an earlier draft — that domain was never registered by anyone here.

```
app ──HTTPS──> Cloudflare PoP (Cache API) ──miss──> Worker ──> R2 bucket
                     │
                     └── hit: ~15 ms, zero origin ops, zero egress cost
```

## Routes

| Route | Serves | Cache |
|---|---|---|
| `GET /v1/live_feed_v1.json` | radar document (~1 KB) | browser 30 s, **not edge-cached** |
| `GET /v1/rolls/<examId>_<hash>_rolls.json.gz` | content-addressed roll index | `public, max-age=3600, s-maxage=86400, immutable` |
| `GET /v1/pdf/<examId>_result.pdf` | mirrored result PDF (fixtures; the app links official PDFs) | `max-age=600, s-maxage=86400` |
| `GET /r/<examId>` | 302 → the exam's `official_pdf` (else `official_page`) from the live feed; plain-text 404 `"This result link is no longer active."` when the exam is not in the feed | 60 s |
| `GET /health` | liveness | `no-store` |

`/r/<examId>` is deployed and tested, but `EV_WEB_BASE` is **deliberately
unset**: printing a `*.workers.dev` URL on the share card reads as a dev
server, so until the project owns a real domain the card prints the
commission's own URL instead. Map a domain at the worker and set `EV_WEB_BASE`
to it, and this route becomes the card's deep link with no code changes.

## Why this survives 10M concurrent users

**Request collapsing.** Cloudflare de-duplicates concurrent requests for the same
cache key. 10M devices asking for the same roll index inside the same second
produce *one* R2 read per PoP, not 10M.

**`s-maxage`, not `max-age` — and the feed is deliberately NOT edge-cached.**
The content-addressed roll indexes keep `s-maxage=86400, immutable`, which is
only sound because new content always arrives at a new URL. The feed is the
opposite case: it changes the moment a result drops, and workers.dev has no
zone, so there is no cache to purge. From `src/index.js`:

```js
    // It is deliberately NOT edge-cached. An earlier version gave it
    // `s-maxage=3600`, which meant a publish could stay invisible for an hour —
    // and because there is no zone behind workers.dev, there is no cache to
    // purge either. One R2 read per request for a 1 KB object costs nothing, and
    // Cloudflare still collapses concurrent requests upstream.
    maxAge: 30,
    sMaxAge: 0,
    immutable: false,
    edgeCacheTtl: 0,
    noEdgeCache: true,
```

So: the *browser* may keep the feed for 30 s; the *edge* never keeps it at all.
Any older text claiming "the edge keeps the feed for an hour" described the bug,
not the behaviour.

**Objects are already compressed.** The roll index is stored *as* a `.json.gz`
object with `Content-Type: application/gzip` and no `Content-Encoding`. That is
intentional: it stops the socket from decoding the body so the app can inflate it
inside an isolate, where a 12 MB allocation cannot drop a frame.

**404 is a first-class answer.** At 09:11 the index does not exist yet. The
worker returns 404 with a 15 s TTL, and the app reports "Result not published
yet". There is **no demo index and no fallback data** — the app's
`result_index_repository.dart` removed the very type that could express one:

> "There is deliberately no 'demo'/'mock' member. … Fabricating an exam outcome
> is unacceptable, so the type system no longer has a way to express it."

Nothing retries in a loop.

## Deploy

CI deploys on every push to `master`/`main` that touches `infra/**`
(`.github/workflows/ci.yml`, job `deploy-edge`). Manually:

```sh
cd infra
npx wrangler r2 bucket create examvault-cdn   # once
npx wrangler deploy
```

The worker runs on `workers.dev` (`workers_dev = true` in `wrangler.toml`).
A custom domain is *optional* and only possible with a domain you actually own
and have added to the Cloudflare account; until one exists, the workers.dev URL
above is the public host used by `EV_CDN_BASE`. (`EV_WEB_BASE` stays unset on
purpose — see the `/r/` note above.)

## Publish objects

The publisher is the refresh workflow (`tools/fetch_official_feeds.mjs` →
`tools/build_indexes.py` → `tools/publish_feed.mjs`), not this worker. Manual
equivalents:

```sh
# radar document (rewritten whenever state changes)
npx wrangler r2 object put examvault-cdn/v1/live_feed_v1.json --file=feed.json \
  --content-type='application/json; charset=utf-8'

# roll index — MUST be sorted ascending, deduplicated and gzipped, and the key
# MUST carry the content hash the publisher recorded in the feed's
# `index_version` field (that is what makes `immutable` caching sound)
node ../tools/build_roll_index.mjs --exam ssc_cgl_tier1_2026 --in rolls.txt \
  --out build/ssc_cgl_tier1_2026_rolls.json.gz
npx wrangler r2 object put \
  examvault-cdn/v1/rolls/ssc_cgl_tier1_2026_<sha256-12>_rolls.json.gz \
  --file=build/ssc_cgl_tier1_2026_rolls.json.gz \
  --content-type='application/gzip'
```

**No purge step exists, on purpose.** `purge_cache` is a *zone* API and
workers.dev has no zone. Republishing never needs a purge because roll keys are
content-addressed (a corrected list lands at a new URL) and the feed is not
edge-cached (a republished feed is visible on the next request). Any instruction
to `curl …/zones/$ZONE/purge_cache` for this worker is leftover fiction.

## Verification

```sh
EDGE=https://examvault-edge.aasheeshkatheriya.workers.dev

curl -sI $EDGE/v1/live_feed_v1.json | grep -i cache-control      # s-maxage=0
curl -sI $EDGE/v1/live_feed_v1.json | grep -i x-examvault-cache  # BYPASS, never HIT
curl -s  $EDGE/health                                            # {"ok":true,"edge":true}

# a roll index (second call must report HIT and carry the immutable directive)
curl -sI $EDGE/v1/rolls/<examId>_<hash>_rolls.json.gz | grep -i x-examvault-cache
curl -sI $EDGE/v1/rolls/<examId>_<hash>_rolls.json.gz | grep -i cache-control

# deep-link redirect: 302 to the commission's page, or a plain-text 404
curl -sI $EDGE/r/<examId> | grep -i location
```

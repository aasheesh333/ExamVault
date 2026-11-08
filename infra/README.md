# ExamVault — Cloudflare edge

One Worker, one private R2 bucket, no database, no origin.

```
app ──HTTPS──> Cloudflare PoP (Cache API) ──miss──> Worker ──> R2 bucket
                    │
                    └── hit: ~15 ms, zero origin ops, zero egress cost
```

## Why this survives 10M concurrent users

**Request collapsing.** Cloudflare de-duplicates concurrent requests for the same
cache key. 10M devices asking for `live_feed_v1.json` inside the same second
produce *one* R2 read per PoP, not 10M.

**`s-maxage`, not `max-age`.** The browser TTL is deliberately short (60 s for the
feed) so a user pulling to refresh gets fresh state, while the edge keeps its copy
for an hour. The two are tuned independently.

**Objects are already compressed.** The roll index is stored *as* a `.json.gz`
object with `Content-Type: application/gzip` and no `Content-Encoding`. That is
intentional: it stops the socket from decoding the body so the app can inflate it
inside an isolate, where a 12 MB allocation cannot drop a frame.

**404 is a first-class answer.** At 09:11 the index does not exist yet. The worker
returns 404 with a 15 s TTL, the app treats it as "not published" and uses its
local demo index. Nothing retries in a loop.

## Deploy

```sh
cd infra
npx wrangler r2 bucket create examvault-cdn
npx wrangler deploy
```

Attach a custom domain (recommended — it makes the cache key stable and lets you
set a longer edge TTL):

```sh
npx wrangler r2 bucket domain add examvault-cdn --domain cdn.examvault.in
```

## Publish objects

The publisher is a cron job, not this worker. It writes three kinds of object:

```sh
# radar document (rewritten whenever state changes)
npx wrangler r2 object put examvault-cdn/v1/live_feed_v1.json --file=feed.json \
  --content-type='application/json; charset=utf-8'

# roll index — MUST be sorted ascending and gzipped
node ../tools/build_roll_index.mjs --exam ssc_cgl_tier1_2026 --in rolls.txt \
  --out build/ssc_cgl_tier1_2026_rolls.json.gz
npx wrangler r2 object put \
  examvault-cdn/v1/rolls/ssc_cgl_tier1_2026_rolls.json.gz \
  --file=build/ssc_cgl_tier1_2026_rolls.json.gz \
  --content-type='application/gzip'
```

Then purge the edge for that key so users do not wait out the TTL:

```sh
npx wrangler r2 object ... # or:
curl -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE/purge_cache" \
  -H "Authorization: Bearer $CF_API_TOKEN" \
  -H 'content-type: application/json' \
  -d '{"files":["https://cdn.examvault.in/v1/rolls/ssc_cgl_tier1_2026_rolls.json.gz"]}'
```

## Verification

```sh
curl -sI https://cdn.examvault.in/v1/live_feed_v1.json | grep -i cache
curl -sI https://cdn.examvault.in/v1/live_feed_v1.json | grep -i x-examvault-cache
# second call must report "HIT"
```

# Where the data comes from

ExamVault ships **no** invented content. This document describes exactly how the
radar document reaches the edge, and what happens when nobody publishes.

```
official notification (operator)  →  data/live_feed.json  →  tools/publish_feed.mjs
                                             ↓ validates, stamps generated_at + expires_at
                                       R2 object  v1/live_feed_v1.json
                                             ↓ served uncached
                                        Cloudflare Worker
                                             ↓ polled every 60 s
                                            the app
```

## Publishing

```sh
cd tools
node publish_feed.mjs --in ../data/live_feed.json           # publish
node publish_feed.mjs --in ../data/live_feed.json --dry-run  # validate only
```

The script refuses to publish if:

- a required field (`exam_id`, `category`, `exam_name`, `status`, `published_at`) is missing
- `category` is not one of `ssc · upsc · banking · railways · state_psc`
- `status` is not a known value
- `published_at` is unparseable **or in the future**

It also stamps every row with `expires_at` (48 h for `result_out`, 36 h for
`admit_card_live`, 12 h for `form_closing`, 72 h for `answer_key`, 30 days for
`awaited`). The app hides expired rows, so a forgotten row degrades to silence
instead of turning into a lie.

## What the app does with a missing or short feed

| Situation | Behaviour |
|---|---|
| Never fetched, no cache | Radar shows "Nothing live yet"; header reads `NO FEED` |
| 404 on the index | Checker says "Result not published yet" and does not search |
| Row past `expires_at` | Hidden from the list, the badge and the hero count |
| Feed older than 2 min | Header reads `EDGE · 26m OLD` instead of `LIVE` |
| Vault empty | Every screen shows an explicit empty state with one way forward |

## Fully automated (this is now real)

The feed is no longer hand-maintained. `tools/fetch_official_feeds.mjs` calls
SSC's own public JSON API — the same one ssc.gov.in uses:

```
GET /api/general-website/portal/records?contentType=results&…
GET /api/general-website/portal/records?contentType=notice-boards&…
```

That API needs no auth and is reachable from a datacenter. (An earlier version of
this document claimed the commissions blocked datacenter IPs and that ingestion
had to stay manual. That was wrong — it was never tested. It is tested now, and
it works.)

```
tools/fetch_official_feeds.mjs  →  data/live_feed.json
tools/publish_feed.mjs          →  R2  v1/live_feed_v1.json
tools/build_indexes.py          →  R2  v1/rolls/<exam_id>_rolls.json.gz
```

`build_indexes.py` closes the loop between "a result was declared" and "the app can
search it": for every `result_out` row that carries a PDF under `masterData/Results`
and whose headline says *list of candidates* / *merit list*, it downloads the PDF,
extracts the roll numbers, verifies the sort, and publishes a gzip index under the
**same exam id** the feed row uses.

### The two guards that matter

1. **`--min-rolls` (default 100).** SSC publishes two kinds of PDF: a *candidate
   list* (thousands of rolls) and a *writeup* (a handful of explanatory rows). Early
   runs published an 11-roll index generated from a writeup — which would have told
   every other candidate they were not selected. The floor, plus a headline filter,
   rejects writeups outright.
2. **Strictly-ascending verification** before writing, because the app binary
   searches the array.

### Verified end to end

```
$ flutter test test/live_edge_integration_test.dart
verified 3507 real rolls · middle=325160290539 · lookup=27683µs
```

That test downloads the real object from the real edge and looks up a real roll
number from the official PDF.

## Running it on a schedule

`.github/workflows/refresh-data.yml` runs every 30 minutes:

1. fetch the official feed
2. validate it (`publish_feed.mjs --dry-run`)
3. publish the feed
4. build up to 3 roll indexes
5. commit the snapshot to `data/live_feed.json` so history is reviewable

**Caveat:** GitHub disables scheduled workflows after 60 days of repository
inactivity. For a production service, run the same commands from a real cron —
a small VPS, a Cloudflare Cron Trigger, or a scheduled Worker — and keep the
workflow as the manual/fallback path.

## What is still not automated

- **UPSC, IBPS, RRB.** Only SSC is wired up. UPSC returns a 307 to
  `www.upsc.gov.in` and does not expose the same JSON shape; IBPS refused the
  connection from this host. Each needs its own verified adapter. Adding one
  without verifying it would reintroduce exactly the class of bug this file
  documents the removal of.
- **Legal decision on mirroring.** The app links to the official PDF; it never
  re-hosts one. Roll-number *sets* are derived and published, which is a
  different thing from copying the document. If you decide to mirror PDFs for
  speed, that is a licensing call to make deliberately, not by default.

## Roll-number indexes

Same rule: never generate one. `tools/build_roll_index.mjs` takes a text file of
real roll numbers, deduplicates, normalises (BOM / NBSP / zero-width / en-dash),
sorts with a plain comparator (**not** `localeCompare`, which would break the
app's binary search), and verifies strict ascending order before writing. The app
treats an unpublished index as `unavailable`, never as "not selected".

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

## Going fully live (the remaining work)

`data/live_feed.json` is currently maintained by hand. To automate it, replace the
input of `publish_feed.mjs` with a fetch of the official feeds and run it on a
schedule:

```yaml
# .github/workflows/publish-feed.yml
on:
  schedule: [{ cron: '*/15 * * * *' }]
jobs:
  publish:
    steps:
      - run: node tools/fetch_official_feeds.mjs --out data/live_feed.json
      - run: node tools/publish_feed.mjs --in data/live_feed.json
        env:
          CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
          CLOUDFLARE_ACCOUNT_ID: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
```

That fetcher is intentionally **not** written yet: each commission publishes in a
different format, several block datacenter IPs, and some only publish a PDF.
Guessing at those parsers would produce exactly the wrong "RESULT OUT" this
codebase was just cleaned of. Until a source is verified, publishing stays manual.

## Roll-number indexes

Same rule: never generate one. `tools/build_roll_index.mjs` takes a text file of
real roll numbers, deduplicates, normalises (BOM / NBSP / zero-width / en-dash),
sorts with a plain comparator (**not** `localeCompare`, which would break the
app's binary search), and verifies strict ascending order before writing. The app
treats an unpublished index as `unavailable`, never as "not selected".

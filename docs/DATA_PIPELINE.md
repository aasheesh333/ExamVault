# Where the data comes from

ExamVault ships **no** invented content. Every row, date and link in the app is
copied from a commission's own website by a script in `tools/`. This document
describes that path end to end, including the parts that are still gaps.

```
official websites (SSC · UPSC · IBPS · TNPSC · RRB)
        ↓  tools/fetch_official_feeds.mjs      (per-source adapters, HTML/JSON)
  data/live_feed.json
        ↓  tools/build_indexes.py              (PDF → roll numbers → salted hashes)
  R2: v1/live_feed_v1.json                     (feed, published uncached)
  R2: v1/rolls/<exam>_<version>_rolls.json.gz  (hashed index, immutable)
        ↓  Cloudflare Worker
      the app  (feed polled every 60 s; index downloaded once per exam version)
```

## Coverage, verified 2026-11-10

Each adapter was pointed at the live site from a datacenter before being written.
Where a source could not be reached, that is recorded here rather than papered
over with sample data.

| Category | Source | Method | Status |
|---|---|---|---|
| SSC | `ssc.gov.in` | public JSON API (`/portal/records`) | ✅ 17 rows, roll lists indexable |
| UPSC | `upsc.gov.in` | “What’s New” HTML + detail page per row | ✅ 12 rows, roll lists indexable |
| Banking | `ibps.in` | ongoing-recruitment grid (HTML) | ✅ 5 rows — registration windows |
| Railways | `rrbchennai.gov.in` | CEN list (server-rendered HTML) | ✅ 25 rows |
| State PSC | `tnpsc.gov.in` | results grid (HTML) | ✅ 10 rows, roll lists indexable |

Sources that were tried and **rejected**, with the reason, so nobody re-tries them
blindly:

| Attempt | Result |
|---|---|
| `rrbapply.gov.in` | NXDOMAIN — the domain does not resolve |
| `rrbcdg.gov.in`, `rrbsecunderabad`, `rrbahmedabad` | connection timeouts / cert failure |
| `indianrailways.gov.in` | reachable, but the word “recruitment” appears nowhere on it |
| `upsc.gov.in/jsonapi` | 404 — no API; the HTML has to be parsed |
| `mpsc.gov.in` | React SPA with no public content endpoint |
| `uppsc.up.nic.in` | Angular shell; rows are rendered client-side |
| `ibps.in` without a CA fix | `unknown CA` — the server omits its intermediate (see below) |

`ibps.in` serves only its leaf certificate, so every client that lacks the
intermediate fails the handshake (curl and Node do; Chrome succeeds because it
cached it earlier). Turning verification off would be the wrong fix for a
pipeline that decides whether a student is told “RESULT OUT”. Instead the
intermediate — public certificate data published by GlobalSign — is pinned in
`tools/certs/` and passed as an extra CA **alongside the normal root store**, so
the chain is still verified in full. If IBPS rotates to another CA the fetch fails
closed, the source is reported `unavailable`, and nothing is published from it.
A missing or corrupt PEM file **also fails closed** with an error naming the
file: `ibps.mjs` never silently degrades to the bare root store, because that
fallback *is* the “unknown CA” outage the pin exists to prevent.

> **Rotation note — the pinned intermediate
> (`GlobalSign GCC R46 OV TLS CA 2025`) expires 2029-06-23.** Before that date,
> download GlobalSign's then-current issuing intermediate for `www.ibps.in`
> (`openssl s_client -showcerts -connect www.ibps.in:443` once the server sends
> it, or from GlobalSign's repository), replace
> `tools/certs/globalsign-gcc-r46-ov-tls-ca-2025.pem` (or add the new file and
> update `CERT_FILE` in `tools/sources/ibps.mjs`), and confirm the source
> reports `ok` in the feed health block. After expiry every IBPS fetch fails
> closed until this is done — by design.

## Health is published, not implied

`data/live_feed.json` carries a `sources` block:

```json
"sources": [
  { "id": "ssc", "status": "ok", "rows": 17, "checked_at": "…", "elapsed_ms": 232 },
  { "id": "ibps", "status": "unavailable", "rows": 0, "reason": "HTTP 403" }
]
```

`rows` is the count the source actually has in the published document —
**after** dedupe, the per-source cap and the global cap (retained searchable
results included). It used to be the pre-dedupe fetch count, so the app's
About sheet could claim “25 items” for a source contributing 20. An outage in
one commission is therefore visible in the artefact, not only in CI logs. The
orchestrator also refuses to overwrite a populated feed with an empty one, so a
bad afternoon on the network cannot blank the radar for every client.

## The feed

```sh
cd tools
node fetch_official_feeds.mjs --out ../data/live_feed.json           # build
node fetch_official_feeds.mjs --out ../data/live_feed.json --dry-run # build, don't write
node publish_feed.mjs --in ../data/live_feed.json                    # publish
node publish_feed.mjs --in ../data/live_feed.json --dry-run          # validate only
```

`publish_feed.mjs` refuses a document with a missing field, an unknown
category/status, an unparseable or future `published_at`, or a row with no
official link. It stamps `expires_at` per status **only when the row does not
carry one**, so an adapter can pin an explicit expiry to a real-world deadline
— IBPS does exactly that: a registration row expires at the end of its closing
day instead of 7 days after it opened. A forgotten row degrades to silence
instead of turning into a lie.

Date-only notices (`9 Nov 2026`) are stamped at **00:00 UTC**. They used to be
stamped at noon, which made any same-day notice “in the future” for every run
between 00:00 and 12:00 UTC — and since the publisher rejects future
timestamps wholesale, one same-day UPSC notice could take the entire document
down for half the day.

`revision` counts distinct feed **states**, not refresh runs: the fetcher bumps
it only when the normalized content (volatile timestamps stripped — see
`tools/normalize_feed.mjs`) actually changed, and the publisher never bumps it.
It used to rise twice per cycle (once in the snapshot, once only in the
uploaded copy), so the edge and the repo permanently disagreed and the number
climbed ~48/day through runs that changed nothing.

| Situation | Behaviour |
|---|---|
| Never fetched, no cache | Radar shows “Nothing live yet”; header reads `NO FEED` |
| 404 on an index | Checker says “Result not published yet” and never searches |
| Row past `expires_at` | Hidden from the list, the badge and the hero count |
| Feed older than 2 min | Header reads `EDGE · 26m OLD` instead of `LIVE` |
| Vault empty | Every screen shows an explicit empty state with one way forward |

## Dates shown in the app

Each row may carry up to three **optional** date fields:

| Field | Meaning |
|---|---|
| `exam_date` | the day the exam is held (or the first day of a published range) |
| `result_date` | the day the result is declared |
| `deadline` | registration / application last date (the form closes) |

All are `YYYY-MM-DD`. **Absence means “not announced”** — the app shows no date
rather than a placeholder, and nothing downstream may fill one in.

### The never-invent rule

A date is emitted only when the commission actually wrote it in the notice text
(or exposed it as a structured field on its own page). `tools/sources/lib.mjs`
exports `extractDates({ headline, context, text })`, which:

- anchors on explicit phrases only — `examination will be held on`,
  `exam dates`, `held on`, `date of examination`; `result will be declared on`,
  `declared on`, `result date`, `declaration of result`; `last date`,
  `closing date`, `registration closes`, `apply before/by`, `closes on`;
- accepts a date only within ~60 characters **after** the trigger phrase, so an
  unrelated date earlier in the sentence is never captured;
- parses `21.11.2026`, `21/11/2026`, `21-11-2026`, `2026-11-21`,
  `21 Nov 2026`, `21 November 2026` and `November 21, 2026`, plus ranges
  (`21.11.2026 to 24.11.2026`, `21 & 22 November 2026`) whose **first day** is
  used;
- rejects impossible calendar dates (`31 Feb`) and years outside
  `[now − 1 year, now + 3 years]`;
- never mistakes `Part-IV` or `12,480 aspirants` for a date.

Structured source fields win over text: IBPS's grid exposes `closes`, which is
merged into `deadline` after extraction. Adapters with no date field leave the
field out entirely.

### Validation and carry-forward

`publish_feed.mjs` validates any present date field as a real `YYYY-MM-DD`
calendar date. Unlike `published_at`, these fields are **not** subject to the
future-guard — an exam or result date is normally in the future, which is the
whole point of surfacing it.

`carryIndexFields` will copy an old date forward only when the row still points
at the identical source document (same `official_pdf`/`official_page` **and**
same `context`), and only if the fresh row has no date of its own. If the source
now has no date and the link or context changed, the old date is dropped rather
than resurrected. The date fields are ordinary row content to
`tools/normalize_feed.mjs`, so a change in any of them counts as a content change
(revision bump / snapshot commit) and unchanged values do not cause churn.

## Roll-number indexes — the copyright problem

The headline feature is “is my roll in the list?” without downloading a 60 MB
PDF. The obvious implementation — publish the candidate list as text — reproduces
a government document we do not own. So the published object contains **no roll
numbers at all**.

`tools/build_indexes.py` extracts the roll numbers from the official PDF, hashes
each one, and publishes only the digests:

```json
{ "v": 2, "mode": "sha256-8-salted", "salt": "7236…", "total": 8956,
  "hashes": ["00a1b2c3d4e5f607", "…"] }
```

- **Digest** — `sha256("<salt>:<NORMALISED_ROLL>")` truncated to 8 bytes, hex.
- **Normalisation** — strip whitespace, NBSP, zero-width spaces and dashes, then
  uppercase. Byte-identical in Dart (`HashedRollIndex.normalise`) and Python
  (`tools/hashed_index.py`). Pinned twice: `test/hashed_index_test.dart` keeps
  hardcoded vectors on the Dart side, and `.github/workflows/parity.yml` runs
  the Python side for real (`hashed_index.py --emit-vectors`) and feeds the
  output to `app/tool/parity_check.dart`, which recomputes every digest with
  the app's own engine and fails the build on any mismatch. Before that gate
  existed, an edit to the Python normalisation shipped green and would have
  answered “not selected” for everybody.
- **Salt** — derived per exam from the exam id
  (`sha256("examvault/v2/<exam_id>")`), so one precomputed table cannot serve
  every exam, and a rebuild of unchanged data produces byte-identical output.
- **Lookup** — the device hashes the input and binary-searches. The typed roll
  number never leaves the phone.

What this means, stated plainly: the published object answers exactly one
question per query and cannot be used to enumerate candidates without hashing the
whole roll space per exam. It is a derived artefact, not a copy of the document,
and the document itself is never mirrored — every “Official PDF” button opens the
commission's own URL.

### Content-addressed object names

Objects are published as `<exam_id>_<sha256(body)[:12]>_rolls.json.gz`. The roll
route is cached `immutable`, which is only true if the URL never changes. With a
stable URL the edge served the *first* published index for 24 hours — including
after a corrected list replaced it. Naming an object after its own content makes
`immutable` correct and lets old URLs stay valid forever.

`gzip.compress(..., mtime=0)` matters here: the default header stamps the wall
clock, which would change the bytes — and therefore the version — on every run.

### The guards that matter

1. **`--min-rolls` (default 20).** A *writeup* PDF quotes a handful of
   representative rolls; publishing it would tell every other candidate they were
   not selected. Any PDF whose URL says `writeup` is rejected outright, and the
   floor catches the rest. Twenty is low enough to keep a genuinely small final
   list (a 30-post LDCE publishes 30 rolls).
2. **Ascending order is structural, not checked.** The extractor returns
   `sorted(set(...))`, so the array the app binary-searches cannot be unsorted —
   an earlier “strictly-ascending check before writing” was dead code that
   could never fire, and this document used to list it as a guard. It has been
   replaced by a check that carries real signal: a **bimodal digit-length
   warning**. A genuine list has one roll shape (SSC 12 digits, UPSC 7);
   two populated length modes usually mean an interleaved PDF column (serial
   numbers, dates, marks) was captured as rolls. That prints a loud WARNING
   for the operator — it does not fail the build, because a combined list can
   legitimately mix shapes.
3. **Device size budget.** The app refuses index downloads above
   `AppConfig.maxDownloadBytes` (12 MB). After gzip, an index larger than
   10 MB is NOT published — it would be an object no phone can load. The row
   is skipped with the memo `index exceeds device budget` and a loud warning;
   lists that big need chunking, which is a deliberate feature, not a silent
   publish.
4. **Per-source roll patterns.** SSC uses 12-digit rolls (`125160000498`), UPSC
   uses zero-padded 7-digit rolls (`0100823`), TNPSC uses 9-digit registration
   numbers. A single pattern silently drops real candidates, so `ROLL_PATTERNS`
   in `build_indexes.py` declares one per source and the build prints the count it
   found so a wrong guess is visible.
5. **Failure memo.** A PDF that yields three rolls today yields three rolls in
   half an hour. Failures are stamped with `index_attempted_at` /
   `index_skipped` and cooled down for a week, so a small `--limit` budget is
   not consumed by the same writeups every run. The memo is written to
   `data/live_feed.json` **even when a run builds nothing**, and the fetcher
   carries it across regenerations — previously it was discarded on every
   built-zero run and erased on every fetch, so dead PDFs were re-downloaded
   every 30 minutes forever.
6. **Multi-part SSC lists pause indexing.** SSC splits big candidate lists
   across several attachments. Indexing attachment 1 alone would publish a
   PARTIAL index — and a partial index answers “NOT SELECTED” to every
   candidate in parts 2+. Such rows keep their official link, carry the
   context `Multi-part list — indexing paused` and the flag
   `index_skipped: multi-part list (N attachments)`, and `build_indexes.py`
   never indexes them. (Partial indexing of verification notices is separately
   prevented by classification: IV/DV/“shortlisted for verification” headlines
   are `admit_card_live`, never `result_out`.)

### Verified end to end

```
$ EV_LIVE_ROLL=2100058 flutter test test/live_edge_integration_test.dart
verified 8956 hashed rolls from upsc_…cdse_ii@ec7dd2aa1ba9 · lookup=93µs
```

The test reads the live feed, picks the largest published list, downloads that
exact object from the edge, asserts the format carries no plaintext roll numbers,
and (optionally) looks up a real roll. CI runs the structural half; the positive
lookup is opt-in because committing a real candidate's roll number to the
repository would be its own privacy problem.

## Running it on a schedule

`.github/workflows/refresh-data.yml` runs every 30 minutes:

1. fetch all sources → `data/live_feed.json`
2. validate it (`publish_feed.mjs --dry-run`)
3. build up to 8 roll indexes, scheduled **round-robin** between two classes:
   rows with no index yet (newest first), and rows whose index is due for a
   revisit — `index_available` but `index_built_at` older than 7 days (oldest
   verification first). Failed rows cool down for a week via the failure memo;
   multi-part SSC rows are paused and excluded. The revisit class is why a
   commission correcting a PDF **at the same URL** no longer serves a stale
   index forever: previously unindexed rows had absolute priority, and with a
   standing backlog the indexed rows were never revisited at all.
4. publish the feed **after** the indexes, so `index_version` reaches the app
5. commit the snapshot **only when its normalized content changed** (volatile
   timestamps stripped via `tools/normalize_feed.mjs`, keys sorted), rebasing
   before push — an unchanged refresh produces no commit, instead of the ~48
   guaranteed-dirty noise commits per day the raw `git diff` produced

**Caveat:** GitHub disables scheduled workflows after 60 days of repository
inactivity. For a production service, run the same commands from a real cron — a
small VPS, a Cloudflare Cron Trigger, or a scheduled Worker — and keep the
workflow as the manual/fallback path.

## Known gaps

- **Railways has no searchable index.** RRB boards publish CEN notices as HTML
  pages, not roll-list PDFs, so there is nothing to hash. The radar row links to
  the board; the checker honestly reports that no index exists.
- **Only one RRB is read** (Chennai). It is the only board that answered with a
  valid certificate from this network; the CEN vocabulary is national, but the
  row count is one board's view, and the row text says so.
- **State PSC coverage is one state** (Tamil Nadu). Other PSCs either render
  client-side or sit behind broken TLS; each needs its own verified adapter.
- **IBPS publishes registration windows, not result lists** on the page used here.
  Banking results would need the CWE result pages, which are session-gated.

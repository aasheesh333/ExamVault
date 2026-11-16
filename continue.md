# CONTINUE — ExamVault 1.0.1 release

**Read this file first.** It is the complete state of the work done in the previous
session, written so a different harness (or a fresh agent) can pick it up without
re-reading 99 commits.

Last updated: 2026-11-16. Branch: `release/play-store-ready`. Base: `master` @ `4b5b617`.

---

## 1. What this project is

ExamVault — a Flutter utility for Indian competitive-exam aspirants (SSC, UPSC,
Banking, Railways, State PSC). Admit-card vault, live exam radar, and an instant
roll-number result checker that answers "am I in the list?" from a ~150 KB hashed
index on the device instead of a 60 MB PDF.

- App: `app/` (Flutter, Material 3, Riverpod, Hive, flutter_secure_storage)
- Edge: `infra/` (Cloudflare Worker + R2)
- Pipeline: `tools/` (Node + Python; fetches official commission pages, builds hashed indexes, publishes)
- Product docs: `README.md`, `docs/DATA_PIPELINE.md`, `docs/PLAY_STORE.md`, `docs/PRIVACY.md`

**Non-negotiable product rules** (they appear in code comments and tests; do not break them):

1. Never render a value the data does not carry. Absent is absent — no `0`, no `TBA`, no guess.
2. Never say "not selected"/"not found" when nothing was searched.
3. Never claim freshness that was not observed (age labels, `checked_at`, `CACHED`/`LIVE`).
4. A link label must describe where the link actually goes.
5. Roll numbers never leave the device; the published index holds salted hashes only.
6. No analytics, no account, no location. The only identifier that leaves the device is the push token.

---

## 2. The three requests made in this session, in order

### Request 1 — verbatim

> plz find bugs issu3s and ui ux iasues half done features and ui ux improvements use @modern-web-guidance @using-superpowers

**What was done:** a full audit of the repo. Every `lib/` file was read, then the
gates were actually run (not assumed): `flutter analyze`, `dart format`, the full
test suite, a release web build, a headless-browser run against the live edge, and
throwaway widget probes that dumped the semantics tree and measured layouts at
320×568 @2.0×.

**Result:** 3 P0, 7 P1, 15 P2 defects, 8 half-finished/dead-code items, 8 UI/UX
improvements. Every finding cited `file:line`. Notably the P0 "dead buttons" defect
was *proven* with a semantics dump (`isButton`, zero actions) rather than inferred.

**Where it lives now:** the audit text was moved into this file's section 4 (the
original `docs/AUDIT_2026-11-16.md` was removed at the user's request — recover it
with `git show e1e6e31:docs/AUDIT_2026-11-16.md`).

### Request 2 — verbatim

> start using subagent driven unlimited subagents and you are working play store ready production project fix everything and do implement not done things or none working to working use todo to track every singke change

**What was done:** the audit was turned into a 20-task plan and executed with
subagents — one implementer per task, a fresh reviewer per task, a fix loop, then a
whole-branch review. Work ran in git worktrees so tasks with disjoint file sets could
go in parallel. Every task was reviewed for *spec compliance* and *code quality*
before merge.

**Result:** 99 commits, 67 files, +12.6k/−1.1k lines. All gates green.

### Request 3 — verbatim

> iss session ko dusre harness me use karna h mujhe koi md file h to hata do iss project se and continue.md bana do exact yahi session chats ka details ho yahi questions ho yahi continue ho commit and push karke batao

**What was done:** this file. The four session-artifact markdown files were removed
from the project and their content consolidated here. The branch was committed and
pushed.

---

## 3. Current state — read this before doing anything

```
branch:        release/play-store-ready
base:          master @ 4b5b617
commits ahead: 99
working tree:  clean
remote:        origin  https://github.com/aasheesh333/ExamVault.git
```

### Gates, all run on this branch (not asserted)

| Gate | Result |
|---|---|
| `cd app && flutter analyze --fatal-infos` | `No issues found!` |
| `cd app && dart format --output=none --set-exit-if-changed lib test tool` | 0 changed, exit 0 |
| `cd app && flutter test` | **957 passed, 7 skipped, 0 failed** |
| `cd tools && node --test test/*.mjs` | 49 passed, 0 failed |
| `cd app && flutter build web --release` | success |
| `EV_LIVE=1 EV_LIVE_ROLL=2100058 flutter test test/live_edge_integration_test.dart` | 8,956 hashed rolls from the live edge; real roll found in **92 µs** |

The 7 skips are the 5 screenshot-capture cases (gated behind `EV_SCREENSHOTS=1`)
plus 2 pre-existing.

### Not run in this environment

`flutter build apk` / `appbundle` — **no JDK and no Android SDK here** (`java` is not
installed). The AAB and split APKs come from CI. Do not claim they were built.

---

## 4. The audit findings and what happened to each

This is the disposition table. **Fixed** = changed with the commit subject quoted.
**Deferred** = not fixed, with the reason. **Not a defect** = disproved by measurement.

### P0 — fix before release

| # | Finding | Verdict |
|---|---|---|
| P0-1 | Every text action was a **dead button for screen readers**: `excludeSemantics: true` dropped the child `InkWell`'s tap action, so the node was `isButton` with **zero actions**. Proven with a semantics dump (`HAS_TAP=false`). | **Fixed** `7ecd45b fix(a11y): give every button a tap action` — six of seven sites now pass `onTap` to the wrapper; the eighth (`EvCard`) was found during review and carries the action on its labelled wrapper; `a11y_matrix_test.dart` now asserts every `isButton` node exposes a tap action across 5 screens × 3 matrix points. `_PageCounter` is the one legitimate label-only exception (a page indicator, not a control). |
| P0-2 | The test suite was **red** from a wall-clock-dependent fixture (`form_closing` row relying on a default 7-day TTL, expired 2026-11-16). | **Fixed** `33aae80 test(live-feed): make the liveCount fixture clock-independent` — explicit far-future and explicitly-expired `expires_at`, plus an injected-clock test. |
| P0-3 | Renaming a card silently kept the **old `examId` and the VERIFIED badge**, so the checker searched the wrong index and Share printed "IN THE LIST" for an exam never checked. | **Fixed** `c3d6224 fix(vault): stop a renamed card from keeping the old exam's index` — `resolveExamId` reuses `previous` only when the name is unchanged; `keepsVerification` requires `!renamed`. |

### P1 — wrong information shown to the user

| # | Finding | Verdict |
|---|---|---|
| P1-1 | Alerts inbox said "Nothing needs your attention" while the feed was **loading or dead**. | **Fixed** `7bf6952`, `27f93be`, `e330f2f` — four states (checking / failed / loaded-empty / rows). The key insight: `LiveFeedNotifier.build()` never rethrows, so a dead edge arrives as `AsyncData` with `value.error`, not `AsyncError`; and `FeedSource.none` + empty + `error == null` is the reliable "never answered" sentinel. |
| P1-2 | Share tab could export a **different exam** than the one selected. | **Fixed** `c5215e5` — an explicit selection wins when its `examId` differs from the pinned radar row. |
| P1-3 | Share card built from a **frozen** feed snapshot, so status/link went stale. | **Fixed** `c5215e5` — re-resolved by `examId` every build. |
| P1-4 | "Apply online" was the notice URL **relabelled** — one URL under two labels. | **Fixed** `d70ed5b` (row removed). A real `apply_url` is deferred — see below. |
| P1-5 | Detail sheet mixed exam B's notice with **exam A's card**. | **Fixed** `d70ed5b` — gated on `card.examId == examId`, foreign card omitted with a note. |
| P1-6 | Vault form fields announced by **hint** ("Street, area, city"), never by name. | **Fixed** `ea9509f` — `Semantics(label:)` + `ExcludeSemantics(hint)`. The brief's `labelText` recipe would have hidden every hint (Material's `showHint = isEmpty && !_hasInlineLabel`), so the implementer rejected it on evidence. |
| P1-7 | About claimed to show "the time each was last checked" and **never did**. | **Fixed** `2ea25c0` — renders `checked_at` ("17 items · checked 4h ago"), silent when null, nothing for a future timestamp. |

### P2 — layout, feedback, data handling

| # | Finding | Verdict |
|---|---|---|
| P2-1 | Detail sheet overflowed 10 px at 320 @2.0×. | **Fixed** `d70ed5b` — stacks above 1.4×. Probe: zero overflow at 6 viewports. |
| P2-2 | Alerts pill ate the exam name at 2.0×. | **Fixed** `7bf6952`, then superseded by `0d30a55`/`9e58fcb`/`7aff83d` (pill owns a full-width line at every scale). |
| P2-3 | Sensitive clipboard wipe could **destroy unrelated user data** (blanked a message copied in another app). | **Fixed** `4c19d20` + `da9dd17` + `71c21f8` — reads back, clears only on exact match, skips when not foregrounded, **suspends and re-arms** on resume. A `null` read means "not ours" (an image may be there). |
| P2-4 | A hung vault write **trapped** the user in the form. | **Fixed** `ea9509f` (15 s bound → error + Retry) + `17b5f78` (Retry is idempotent via a held `_pendingCardId`). |
| P2-5 | Share export had no max width (~2300 px / ~27 MB on desktop web). | **Fixed** `c5215e5` — ≤400 dp, `pixelRatio` derived from laid-out width. |
| P2-6 | Share-text fallback reported success when the user **cancelled**. | **Fixed** `e54ab75` — three-way: success / dismissed / unavailable (each with its own honest wording). |
| P2-7 | `ClipboardService.copy` had no failure path. | **Fixed** `4c19d20`. |
| P2-8 | Duplicate detection silently skipped while the vault was opening. | **Fixed** `ea9509f` — awaits the load or says it is unavailable. |
| P2-9 | Validation/save failures were **visual-only**. | **Fixed** `ea9509f` — live regions + `SemanticsService.sendAnnouncement`. |
| P2-10 | "Choose the exam date" pointed at an off-screen field. | **Fixed** `ea9509f` — keyed + `Scrollable.ensureVisible`. |
| P2-11 | "Copy official link" ellipsised to "Copy / officia…". | **Fixed** `e54ab75` — 94 dp tile, 3 lines. |
| P2-12 | Section headings cut at 2.0× when there was no trailing widget. | **Fixed** `2ea25c0` — wrap independent of `trailing`. |
| P2-13 | Detail-sheet link rows not announced as links. | **Fixed** `d70ed5b` — `Semantics(link: true)`. |
| P2-14 | "Link failed → copied instead" toast was **invisible** (rendered behind the modal barrier). | **Fixed** `6b36abd` — the sheet owns its `ScaffoldMessenger` *inside* the `DraggableScrollableSheet` builder. |
| P2-15 | About/detail sheets could be **stacked** by a double tap. | **Fixed** `c995051` — a synchronous `SheetOpenGuard` covers About, the detail sheet and all five `showVaultFormSheet` call sites (process-wide there, because two vault forms is never legitimate). |

### Half-finished features / dead code

| # | Finding | Verdict |
|---|---|---|
| 1 | **"Delete all data" did not exist** — `wipe()` was documented as used by it, with no caller and no UI. | **Fixed** `2ea25c0` — About control, confirm dialog, wipes vault + settings + cached feed/HTTP cache, resets providers. `c995051` closed the last gap: drops push topics (bells and categories) then re-subscribes the fresh-install default. |
| 2 | Notification categories were **promised but not choosable**. | **Fixed** `2bcdee8` — persisted `followed_categories` (default all five), chips in About gated on `canDeliver`, empty set legal. `7e649ff` fixed a pre-existing bug found on the way (see section 6). |
| 3 | `EvStatusPill`'s unnamed constructor was dead and would null-assert. | **Fixed** `419d90d`. |
| 4 | Unused API surface. | **Fixed** `419d90d` — deleted `CdnClient.peek`, `pdfBytes`, `pdfUrl`, `clearMemo`, `countBy`, `isNewerThan`, `relativeAge`, `cdnPdfPath`, `cdnRollIndexPath`, `ExamCategoryFilter`. Kept `evictAll` (delete-all uses it) and `primaryCardProvider` (still uncalled — see deferred). |
| 5 | Play submission blocked on assets (no feature graphic, no screenshots). | **Fixed** `d081a4a`, `4f2cea6`, `e417c4c`, `e717728`, `fa707c1` — 1024×500 feature graphic + five 1410×2808 screenshots (1.99:1, inside Play's 2:1 ceiling), all generated from the real widgets. |
| 6 | `build.gradle.kts` carried Flutter's scaffold TODO. | **Fixed** `419d90d`. |
| 7 | `minSdk = 23 // Android 6.0` comment was wrong (real value 24). | **Fixed** `419d90d`. |
| 8 | `design/index.html` is an archived deck. | **Not a defect** — banner-labelled "ARCHIVED — NOT SPEC". |

### UI/UX improvements

| # | Finding | Verdict |
|---|---|---|
| 1 | No bell on alert-inbox rows. | **Deferred** — the whole row is the tap target that opens the notice; a trailing bell competes with it. Home/Dates/detail already offer a per-exam bell. |
| 2 | Radar had no "what changed since I last looked" marker. | **Fixed** `08333bd` + `ce31bf9` — a rule labelled **`EARLIER`**, drawn only when a row is newer than `alertsSeenAt` and never on a fresh install. It sits *below* the unseen block because the feed is newest-first; labelling it `NEW` would read backwards. |
| 3 | Search had no result summary for the vault. | **Fixed** `08333bd` — "1 of 5" while a query or chip is active; "5 saved" unchanged when not. |
| 4 | `fontSize: 10` in live UI contradicted the design floor. | **Fixed** `37ef10e` — both rows inherit their tokens (11.0 px at 320@2.0×). |
| 5 | Dates tab was a flat list. | **Fixed** `08333bd` + `ce31bf9` — **"Next 7 days" / "Next 30 days" / "Later"** (rolling day windows, not calendar periods), empty groups omitted, order preserved, headers are `Semantics(header: true)`. |
| 6 | Web manifest had no `id`. | **Fixed** `419d90d` — `"id": "/"`. |
| 7 | iOS display name casing + iOS landscape for a portrait app. | **Fixed** `419d90d` (casing) and `3e088d8` (landscape restored — see section 7, ruling 11). |
| 8 | Play short description needs re-verification. | **Not a defect** — 79 chars, limit 80. |

---

## 5. Defects found *during review*, not by the audit

These matter because they show where the remaining risk was. All are fixed.

| Defect | Found by | Commit |
|---|---|---|
| **`about_sheet.dart` rendered against the TOP of the screen** in shipped code (barrier unreachable, snackbars below the sheet). Measured `(1,1)-(392,766)`; now `(1,86)-(392,851)`. | Task 6's reviewer, confirmed by my own geometry probe | `2ea25c0` |
| **`EvCard` — an eighth dead-button site** (Dates rows, vault centre card). | Task 2's implementer, via the new matrix assertion | `7ecd45b` |
| **FCM unsubscribed every per-exam bell at boot** — `syncTopics` diffed the category target against a set that also held `exam_<id>` topics. The per-exam alert feature could never work on FCM. | Task 10's reviewer, confirmed by reading the code | `7e649ff` |
| **The mirror bug**: `syncExamAlerts` unsubscribed all five *category* topics on every bell toggle. | Task 10's implementer, while fixing the above | `7e649ff` |
| **Clipboard wipe never fired** in copy → switch app → paste, while the toast promised it would. | Task 8's reviewer | `71c21f8` |
| **Retry after a timed-out save duplicated the card** — the id was minted per `_save` call. | Task 7's reviewer | `17b5f78` |
| **CI shipped `EV_APP_VERSION=""`** — the build job runs in `app/` but grepped `app/pubspec.yaml`; a failed command substitution inside an argument does not trip `set -e`. | Me, while checking release plumbing | `9932eca` |
| **The radar status pill painted at 8.25 px at 1.0× and 9.49 px at 2.0×** — `FittedBox` shrank an 11 px label into a ~100 px column. | Task 4's reviewer measured it; I confirmed with a `RenderParagraph × RenderFittedBox` probe | `9e58fcb`, `7aff83d` |
| **Two Play screenshots showed a UI that no longer existed** (Dates ungrouped, pre-fix radar row). | The final whole-branch review | `fa707c1` |
| **The "never answered" sentinel was applied to one widget only** — Home still said `NO FEED` / "Nothing live right now" for the whole first fetch, which is guaranteed right after delete-all. | The final whole-branch review | `3503550` |

---

## 6. Decisions taken (what to know before changing behaviour)

Twenty-six rulings, each with what it costs if wrong. The four most load-bearing:

**The radar rule says `EARLIER`, not `NEW`.** The feed is newest-first, so the unseen rows are a block at the top and the only informative line is *below* it. A "NEW" label there reads backwards ("the older rows are new"). The rule marks **arrivals**; the tab dot marks **actionable** rows (`resultOut`/`admitCardLive`/`formClosing`). Those are deliberately different numbers — a reviewer preferred one shared status filter, and the implementer correctly argued that filtering would leave a row that arrived after the last visit *below* a line labelled `EARLIER`.

**Delete-all drops every topic, then re-subscribes the default five.** Deleting `followed_categories` makes the picker read "all five"; without a re-sync the backend would hold zero subscriptions while the UI showed five selected — the exact "UI claims a subscription the backend does not have" defect this release removes. The token is kept (it carries no vault data); the per-exam bells are dropped.

**iOS is landscape-enabled; Android is unlocked.** A previous task locked iOS to portrait claiming "a rotated phone got a stretched UI". I probed `RootShell` at 852×393, 900×500 and 393×852: **no exception, no overflow**. The lock removed working behaviour *and* iPad Split View. Reverted. The web manifest's `portrait-primary` stays — it is a PWA display preference, not a restriction.

**The status pill owns a full-width line at every text scale.** Putting it on the meta line cannot fit (pill + bell = 178 px at 1.0× against a ~158 px column; at 2.0× the pill alone is 233 px). One layout replaced two, which also fixed the 1.0× violation. Cost: ~11 px extra row height at 1.0×.

Other rulings worth knowing: `microLabel` stays at 10.5 px (the token's own header exempts micro-labels; the real defects were call sites overriding *down* to 10); a null clipboard read means "not ours"; the delete confirm dialog fits at 320@2.0× (measured, so it was not restructured); the vault form's open-guard releases on dispose (accepting a ~200 ms window, because the alternative wedges "Add card" permanently).

**Four things I declined to "fix":**
1. A reviewer claimed the Home screenshot rendered "Tier-12026" (missing space). I zoomed the PNG 4× (the space is there) and measured the font: the space advance is 3.03 px at 17 px, identical with kerning on and off. It is the typeface's own narrow space. Not a defect.
2. Did not add `cupertino_icons` to silence a tree-shaker warning — it is not a dependency and no code references it.
3. Did not rewrite `INFRA_STATUS.md`'s dated numbers (they are a verification snapshot; source availability genuinely fluctuates).
4. Did not fabricate RED evidence when a plan's acceptance bullet was wrong; recorded a ruling that the plan was wrong instead.

---

## 7. Deferred — deliberately not done, with reasons

| Item | Why |
|---|---|
| `apply_url` in the feed contract | The invented "Apply online" label was removed, which is the honest fix available in the app. A real apply link needs a pipeline change plus a publisher-side definition of what an apply URL *is* per commission. |
| RRB / additional state-PSC source coverage | Source availability, not a code defect — those boards publish notices, render client-side, or have broken TLS. See `docs/DATA_PIPELINE.md` § Known gaps. |
| A "past notices" archive view | Product decision. `filterUpdates(includeExpired:)` already exists as the seam. |
| Per-exam bell on alert-inbox rows | Adds an affordance rather than fixing illegibility; the row is already the tap target. |
| `slugifyExamName('SSC') == 'ssc'` collides with the SSC category topic | Pre-existing. A hand-typed bell whose name slugs to a category id shares that topic, so category-off kills the bell (bell still shows ON) and bell-off does nothing (alerts keep arriving). Needs a namespace change plus a topic migration — disproportionate pre-release. Fails safe: the student gets the category's alerts, never someone else's. |
| `CdnClient.evictAll` is not a hard guarantee under concurrency | An in-flight fetch can repopulate the cache after delete-all. Documented in code; the confirmation says the public feed "may be downloaded again" rather than promising an empty cache. The bytes are public data, never user data. |
| Clipboard deadline uses `DateTime.now()` (non-monotonic) | A backward clock step can stretch the secret's dwell time. Failure direction is safe (foreground guard + exact-match read-back). |
| Cards corrupted by the pre-fix rename bug | The app has never been released, so no shipped install is affected. |
| `AppConfig.resultPdfPath` has no callers | Kept as the legacy/fixture-only route, with a comment marking it a deletion candidate. |
| `primaryCardProvider` has no callers | Held back for a task that did not use it. Deletion candidate. |
| The 26-permission merged-manifest table cannot be regenerated here | No Android SDK and no release build output. `docs/PLAY_STORE.md` states the provenance and says to re-derive before pasting into the Console. |

---

## 8. The exact continuation point

**The code is done and verified. The only thing outstanding is the integration decision.**

At the end of the previous session I presented the standard three options and the
user had not yet chosen when they asked for this handoff instead:

1. Merge back to `master` locally
2. Push and create a Pull Request
3. Keep the branch as-is

The branch **has since been pushed** (see section 9). So the remaining choice is
effectively **(1) merge to `master`** or **(2) open a PR**. Do not merge to `master`
without asking — `master` is the deployed branch and this is a 99-commit release.

### If you merge to master

```sh
cd /home/ubuntu/ExamVault
git checkout master && git pull
git merge --no-ff release/play-store-ready
cd app && flutter analyze --fatal-infos && dart format --output=none --set-exit-if-changed lib test tool && flutter test
cd ../tools && node --test test/*.mjs
```

If the merged result is not green, stop — nothing has been pushed to `master` yet.

### If you open a PR

The repo is `aasheesh333/ExamVault`. Branch `release/play-store-ready` → `master`.
A good PR body is section 4 of this file (the disposition table) plus the gate
results from section 3. There is no PR template in the repo.

### After integration

- 18 merged task worktrees remain under `/home/ubuntu/.local/share/opencode/worktree/d85dab/`. All are clean and fully merged. They are host-managed (not project-local), so remove them with `git worktree remove <path>` from the main checkout rather than deleting the directory, then `git worktree prune`.
- The plan's scratch workspace `.superpowers/` is gitignored and can be deleted; the git history is the record.

---

## 9. How to verify any of this yourself

```sh
cd /home/ubuntu/ExamVault/app
flutter pub get
flutter analyze --fatal-infos                                  # No issues found!
dart format --output=none --set-exit-if-changed lib test tool  # 0 changed
flutter test                                                  # 957 passed, 7 skipped
cd ../tools && node --test test/*.mjs                         # 49 passed
cd ../app && flutter build web --release                      # success
```

Against the **live** published index (opt-in; CI does not run it):

```sh
cd app && EV_LIVE=1 EV_LIVE_ROLL=2100058 flutter test test/live_edge_integration_test.dart
# → verified 8956 hashed rolls from upsc_..._ii_@ec7dd2aa1ba9 · lookup=92µs
```

Regenerate the store assets:

```sh
python3 tools/branding/make_feature_graphic.py                 # 1024×500 PNG + SVG
cd app && EV_SCREENSHOTS=1 flutter test test/screenshot_capture_test.dart
```

---

## 10. Gotchas a fresh agent will hit

1. **`flutter test` runs on a fake clock.** Anything that awaits real I/O must use `tester.runAsync(...)`, and a `pumpAndSettle` on an intentional loading spinner will time out — use bounded `pump`s.
2. **The feed arrives newest-first** (`LiveFeedDto.parse` sorts descending). Any "boundary" logic depends on that.
3. **`LiveFeedNotifier.build()` never rethrows.** A network failure arrives as `AsyncData` with `value.error`, not `AsyncError`. `FeedSource.none` + empty + `error == null` means "never answered" — that sentinel is now shared by the radar header, the radar empty state, the hero and the alerts inbox.
4. **The two topic namespaces are indistinguishable by prefix.** Category topics are `exam_ssc`, `exam_upsc`, …; per-exam bells are `exam_<examId>`. Classification is by `ExamCategory.fcmTopic` membership, never by prefix. Both diffs are pure functions (`categoryTopicDiff`, `bellTopicDiff`) precisely because `FirebaseMessaging.instance` cannot be faked.
5. **`_RenderStatusLine` is a hand-written render object** (in `live_radar_tile.dart`). It lays out exactly two children, LTR only, and asserts the arity. Do not add a third child.
6. **Sheets are tabs, not routes.** `Navigator.maybePop()` is a no-op on Home/Vault/Dates/Radar/Share — they switch tabs instead. That bug appeared four separate times.
7. **`showModalBottomSheet` inserts its barrier a frame late.** Any trigger needs a synchronous guard (`SheetOpenGuard`) or a double tap stacks two sheets.
8. **No JDK, no Android SDK here.** `flutter build apk` cannot run; do not report it as done.
9. **Text scale 2.0 is the design ceiling** and the layout matrix tests it at 320×568. A fixed height that works at 1.0× will slice text at 2.0× — this was the single most common defect class (12+ instances).
10. **`git log --oneline master..release/play-store-ready`** is the fastest way to see what changed; commit subjects state the user-visible defect, not the implementation.

---

## 11. File map for the parts that changed most

| Path | What it now does |
|---|---|
| `app/lib/providers/app_providers.dart` | `DataWiper` (delete-all), `FollowedCategoriesNotifier`, `ExamAlertsNotifier` (with real rollback), `LiveFeedNotifier`, `AlertsSeenNotifier`, `DayTickNotifier` |
| `app/lib/data/services/push_service.dart` | `initialise()` is a **shared future**; `syncTopics` / `syncExamAlerts` / `unsubscribeAll` classify the two topic namespaces via `categoryTopicDiff` / `bellTopicDiff` |
| `app/lib/data/repositories/live_feed_repository.dart` | hosts `neverAnswered()`; `readCached()` distinguishes "empty document" from "no data" |
| `app/lib/features/about/about_sheet.dart` | bottom-anchored sheet, real `checked_at` provenance, notification picker, delete-all, policy sheet |
| `app/lib/features/command_center/command_center_screen.dart` | radar `EARLIER` boundary, vault `N of M` fraction, `CHECKING…` header, sheet guards |
| `app/lib/features/command_center/widgets/live_radar_tile.dart` | full-width status line via `_RenderStatusLine`, age flush right at every scale |
| `app/lib/features/command_center/widgets/alerts_sheet.dart` | four honest states, same pill rule as the radar |
| `app/lib/features/vault/vault_form_sheet.dart` | labelled fields, announced refusals, 15 s save bound, held `_pendingCardId`, awaited duplicate check |
| `app/lib/core/utils/clipboard_service.dart` | read-back exact-match wipe, suspend/re-arm, loud failure |
| `app/lib/features/share_card/whatsapp_share_card_screen.dart` | selection wins over the pin, fresh facts, three-way share result, bounded export |
| `app/lib/features/calendar/exam_detail_sheet.dart` | no invented link, foreign-card gate, link semantics, own messenger, stacked date rows |
| `app/lib/features/calendar/exam_calendar_screen.dart` | grouped by rolling day windows |
| `app/test/a11y_matrix_test.dart` | asserts every `isButton` node exposes an action |
| `app/test/radar_pill_test.dart` | measures painted font size across six scales |
| `app/test/screenshot_capture_test.dart` | asserts both Play bounds on the rasterised image |
| `.github/workflows/ci.yml` | derives `EV_APP_VERSION` from the right path and fails on an empty value |
| `infra/src/index.js` | no `cache.put` on the `noEdgeCache` route |
| `tools/branding/make_feature_graphic.py` | deterministic 1024×500 graphic from brand tokens only |

---

## 12. One-paragraph summary for a standup

The app had 3 P0 defects (every text action was a dead button for screen readers; a
red test suite from a wall-clock fixture; renaming a card kept a stale exam id and a
false "verified" badge), 7 P1 defects where the UI stated things that were not true,
and 15 P2 layout/feedback bugs — plus a "Delete all data" that was documented and
did not exist, and a notification-category promise the code never kept. All of it is
fixed across 99 reviewed commits. Review also caught eight defects the audit itself
missed, including a sheet that rendered against the top of the screen in shipped
code and an FCM path that silently unsubscribed every per-exam alert at boot. The
branch passes analyze, format, 957 tests, 49 pipeline tests, a web release build, and
a live-edge check that finds a real roll number in 92 µs.

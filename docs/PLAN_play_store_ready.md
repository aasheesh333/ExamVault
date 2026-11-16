# Plan — Play-Store-ready release

Source of truth for defects: `docs/AUDIT_2026-11-16.md` (audited 16 Nov 2026,
every finding reproduced against the code, several with executed probes).
This plan turns that audit into shippable work **and** finishes the features the
audit found half-built, then makes the repo submission-ready.

## Global Constraints

Every task is bound by all of these. A reviewer may reject a diff that violates
any of them.

1. **Verification gates.** Before any task commits:
   - `cd app && flutter analyze --fatal-infos` → `No issues found!`
   - `cd app && dart format --output=none --set-exit-if-changed lib test tool` → exit 0
   - `cd app && flutter test` → all green (0 failures)
   - `cd tools && node --test test/*.mjs` → all green (only when `tools/` changed)
   A task that cannot reach these gates is not done.
2. **No new runtime dependencies.** The dependency list is a product decision
   (offline-first, no analytics). Adding one requires a controller ruling first.
3. **Honesty rules — non-negotiable.**
   - Never render a value the data does not carry. Absent is absent; never `0`,
     `TBA`, `—`, or a guess. (One exception already in the codebase: the vault
     pass prints `—` for an *empty user field*, which is the user's own data.)
   - Never say "not selected"/"not found" when nothing was searched.
   - Never claim freshness that is not observed (age labels, `checked_at`,
     `CACHED`/`LIVE` must reflect the real timestamp).
   - A link label must describe where the link actually goes.
4. **Design system.** Colours, spacing, radii, sizes and type come from
   `lib/core/theme/theme_tokens.dart` (`context.ev`, `context.type`, `EvSpace`,
   `EvRadius`, `EvSize`, `EvFont`, `EvGradient`). No raw hex, no off-grid
   spacing. Status colour is always paired with a text label.
5. **Accessibility floor.** Every tappable thing has a ≥44×44 hit area and a
   non-empty accessible name. A control that exposes `button: true` MUST also
   expose a tap action (this is the P0 defect being fixed in Task 2).
   Body text ≥11 px in live UI (bitmap-only widgets are exempt).
6. **Layout floor.** 320×568 at 2.0× text must not overflow and must not clip a
   label into meaninglessness. 393×852 at 1.0× must look unchanged unless the
   task says otherwise.
7. **Comment style.** This codebase documents *why* a non-obvious choice was
   made. Preserve existing comments unless the change makes them false, and when
   you fix a documented bug, update the comment so it no longer describes the
   old defect. Do not strip comments to "clean up".
8. **No scope creep.** Each task lists its files and its acceptance criteria.
   Improvements outside that list go in the task report as a suggestion, not
   into the diff.
9. **Commits.** One task = one or more commits, conventional prefixes
   (`fix(scope):`, `feat(scope):`, `test(scope):`, `docs:`, `chore:`), each
   explaining the user-visible defect it removes.

## Task 1 — Green the suite: the time-bomb test

**Defect (P0-2).** `app/test/live_feed_parsing_test.dart:109-124` expects
`liveCount == 3` from fixtures whose `form_closing` row relies on the default
7-day TTL. That row expired on 2026-11-16T09:58Z, so the suite is red today with
no code change. CI runs `flutter test`, so the next push is red and stays red.

**Files:** `app/test/live_feed_parsing_test.dart` (and any other test that
derives a verdict from `DateTime.now()` plus a default TTL — search for
`publishedAt:` fixtures without `expiresAt:`).

**Do:**
- Make the `liveCount` fixture independent of wall-clock: give each row an
  explicit far-future `expires_at`, and add a second assertion that an explicitly
  expired row is excluded, so the test still proves the filter.
- Add a test that `LiveFeed.liveCountAt(now)` takes an injected clock and returns
  the same answer for a fixed `now` regardless of when the suite runs.
- Audit the other fixture-based tests for the same trap; fix any that would flip
  with time. Do not change production code in this task.

**Acceptance:** `flutter test` is fully green; running the suite with the system
clock unchanged still proves both the inclusion and exclusion paths.

---

## Task 2 — Every control is operable: kill the `excludeSemantics` dead buttons

**Defect (P0-1, verified with a semantics dump).** `excludeSemantics: true`
drops the child subtree's semantics, including the `InkWell`'s
`SemanticsAction.tap`, and the `Semantics` wrapper was never given `onTap`. The
node is `isButton` with **zero actions**: TalkBack announces "Retry, button" and
double-tap does nothing. Probe output on Flutter 3.47.9:

```
LABEL= ACTIONS=0
HAS_TAP=false
CTRL_TAP=true          # identical tree without excludeSemantics
```

**Files (all seven sites, verified):**
- `app/lib/shared/widgets/ev_surfaces.dart:183-192` — `EvTextAction` (the app's
  only text action; used by Add / N saved / Retry ×3 / Notice details / See live
  results / Try again / Browse live results)
- `app/lib/features/command_center/widgets/live_radar_tile.dart:231-245` — `_AlertBell`
- `app/lib/features/calendar/exam_calendar_screen.dart:255-270` — calendar bell
- `app/lib/features/calendar/exam_detail_sheet.dart:580-604` — `_BellRow`
- `app/lib/features/command_center/widgets/wallet_pass_card.dart:447-460` — `_CopyPill`
  (a `GestureDetector`, so the node has no action at all)
- `app/lib/features/share_card/whatsapp_share_card_screen.dart:757-770` — "Edit caption"
- `app/lib/features/vault/admit_card_detail_screen.dart:329-337` — `_PageCounter`
  (label-only, correctly has no action — leave it, but confirm it is the only
  exception and note why in the report)

**Do:**
- Pass the action through: `Semantics(container: true, excludeSemantics: true,
  button: true, label: label, onTap: onPressed, child: …)`. Keep the label
  single-announcement behaviour (do not remove `excludeSemantics`).
- For `_CopyPill`, add `onTap:` to its `Semantics`.
- Add a guard to `app/test/a11y_matrix_test.dart`: for every semantics node with
  the `isButton` flag, assert `getSemanticsData().hasAction(SemanticsAction.tap)`
  (or `longPress`), across all five tabs at 320@2.0×. This is the assertion that
  prevents regression; the existing guidelines miss these nodes because they only
  inspect nodes that already have an action.
- Add a focused widget test that taps `EvTextAction` through the semantics layer
  (`tester.binding.pipelineOwner.semanticsOwner` / `performAction`) and asserts
  the callback ran, so the fix is proven at the API the screen reader uses.

**Acceptance:** the new matrix assertion fails on the pre-fix code and passes
after; `flutter test` green; no visual change.

---

## Task 3 — Renaming a card must not keep the old exam id or VERIFIED

**Defect (P0-3).** `app/lib/features/vault/vault_form_sheet.dart:23-32` falls back
to `previous` whenever the new name has no published match, even when the name
changed completely. Rename "SSC CHSL 2026" → "UPSC CSE 2027" (unpublished): the
card keeps `examId = ssc_chsl_2026` while the form simultaneously says "No
published result matches this name yet", and `keepsVerification` (`:371-375`)
still passes because `base.examId == examId` is trivially true. Result: the
checker searches the old exam's index and Share prints "IN THE LIST" for an exam
never checked.

**Files:** `app/lib/features/vault/vault_form_sheet.dart`,
`app/test/vault_form_test.dart`.

**Do:**
- `resolveExamId` gains the rename rule: reuse `previous` only when the exam name
  is unchanged. Suggested signature addition:
  `bool renamed` (or pass `previousName`). Keep the function
  `@visibleForTesting` and its doc comment truthful.
- `keepsVerification` must additionally require `!renamed`.
- Tests: (a) rename to an unpublished name produces a slug id and drops VERIFIED;
  (b) rename to a *published* name adopts the fresh feed id and drops VERIFIED;
  (c) editing an unrelated field (centre) keeps the id and keeps VERIFIED;
  (d) renaming back to the original name restores nothing implicitly (it is a new
  resolution, still no VERIFIED).
- Update the doc comment at the top of the file so it describes the rename rule.

**Acceptance:** all four new tests fail on pre-fix code, pass after; full suite
green.

---

## Task 4 — Alerts inbox tells the truth, and survives 2.0× text

**Defects (P1-1, P2-2).**
`app/lib/features/command_center/widgets/alerts_sheet.dart` derives `alerts` from
`feedAsync.value?.feed`, so during a cold start (`AsyncLoading`, no value) or a
hard failure with nothing cached (`AsyncError`), the list is empty and the sheet
reports "Nothing needs your attention." plus a paragraph explaining why nothing is
there — on result day, with a dead network. The radar's own `_FeedErrorCard` is
honest about the same failure. Separately, `_AlertRow`'s status pill is a
non-flex `Row` child, so at 2.0× "ADMIT CARD LIVE" consumes ~230 of 248 px and the
`Expanded` exam name collapses to a sliver (`live_radar_tile.dart:130-140` already
documents and fixes exactly this with `Flexible` + `FittedBox`).

**Files:** `app/lib/features/command_center/widgets/alerts_sheet.dart`,
`app/test/sheets_test.dart`.

**Do:**
- Branch the body on the async state, in this order:
  1. `!feedAsync.hasValue && feedAsync.isLoading` → "Checking for updates…" with a
     small progress indicator (no badge claim).
  2. `feedAsync.hasError && !feedAsync.hasValue` → "Could not check for updates."
     plus the repository's own reason and a Retry that calls
     `ref.invalidate(liveFeedProvider)`.
  3. loaded + empty → the current copy.
  4. loaded + rows → the list.
- The header subtitle must match the body state (do not say "Nothing needs your
  attention" above a spinner or an error).
- Keep the `onLoadedAlertsRendered` contract exactly: it may only fire for a
  loaded, non-empty, non-loading list (the caller's `markSeen` depends on it).
- Wrap the pill as `live_radar_tile.dart` does: `Flexible` + `FittedBox(scaleDown)`,
  right-aligned, so the exam name always wins the space it needs.
- Tests in `sheets_test.dart`: loading state, error state (with Retry invoking
  `invalidate`), empty state, and a 320×568 @2.0× render asserting no overflow and
  that the exam name's rect is wider than the pill's.

**Acceptance:** no overflow at 320@2.0×; the three non-row states are visually and
textually distinct; full suite green.

---

## Task 5 — Share tab: right card, fresh facts, honest share result

**Defects (P1-2, P1-3, P2-6, P2-5, P2-11).**
`app/lib/features/share_card/whatsapp_share_card_screen.dart`:
- `_cardFor` (`:140-156`) ignores `selectedCardIdProvider` whenever a radar row is
  pinned, so after any radar tap, swiping to another vault card and opening Share
  exports the *pinned* exam's card. The preview is the only warning.
- `_buildCard` reads `status`, `headline`, `officialUrl`, `pdfSizeLabel` from the
  frozen `LiveUpdate` captured at tap time; the feed repolls every 60 s and the
  checker already re-resolves for this reason. A row tapped while `awaited` still
  exports "UPDATE AWAITED" after the result drops.
- The text-fallback snackbar (`:322-327`) is unconditional, so a dismissed share
  sheet still says "shared the message text instead".
- The `RepaintBoundary` (`:424-427`) has no max width: the documented
  "1080 px / under 200 KB" contract only holds at ~360 dp × 3. On a 430 dp phone
  the export is 1194 px; in a desktop-web window ~2300 px (~27 MB bitmap).
- The fixed `SizedBox(width: 88)` share tile ellipsises "Copy official link" to
  "Copy / officia…" at 2.0×.

**Files:** `app/lib/features/share_card/whatsapp_share_card_screen.dart`,
`app/lib/data/services/share_service.dart` (only if the result type needs
narrowing), `app/test/share_flow_test.dart`, `app/test/share_infographic_test.dart`.

**Do:**
- **Selection:** an explicitly selected card wins when its `examId` differs from
  the pinned update's. Show the shared exam's name in the header so the user can
  see which one is being exported. When the selection matches the pinned exam,
  behaviour is unchanged.
- **Freshness:** resolve the feed row by `examId` on every build
  (`feed.updates.firstWhere(...) ?? pinned`) and use the fresh row for status,
  headline, subline, official URL and PDF size. Keep the tapped row only as a
  fallback for the window before the feed has loaded.
- **Share result:** branch on `ShareResult.status`; success → the current
  "shared the text instead" message, dismissed/unavailable → "Nothing was sent —
  your caption is still here."
- **Export width:** constrain the captured card to ≤400 dp and derive
  `pixelRatio` from the laid-out width so the PNG is ~1080 px wide on any device.
- **Tile label:** let the label wrap or split so no word is truncated at 2.0×.
- Tests: pinned-vs-selected card choice; stale `awaited` row upgraded to
  `result_out`; dismissed share produces the "nothing sent" message; capture
  ratio clamped at a wide viewport.

**Acceptance:** all five defects covered by a test that fails pre-fix; full suite
green; export width ≤ ~1200 px at 430 dp.

---

## Task 6 — Exam detail sheet: no invented links, no foreign card, no overflow

**Defects (P1-4, P1-5, P2-13, P2-14, P2-1).**
`app/lib/features/calendar/exam_detail_sheet.dart`:
- `:69-88` adds "Official website" for `officialPage` **and** "Apply online" for the
  same `officialPage` when the status is `notification`/`formClosing`. There is no
  apply URL in the model, so one URL is shown twice under two labels and the
  second promises a form the data never claimed.
- `:61-67` and `:264-300` never check `card!.examId == examId`. The checker passes
  both unconditionally and falls back to `cards.first`, so exam B's headline can
  sit above a "Your card" panel containing exam A's roll number, centre and
  report-by time.
- `_LinkTile` (`:481-484`) is not announced as a link, unlike the equivalent row in
  `about_sheet.dart:462-467`.
- `:494-500`: on link failure it copies the URL, but `ClipboardService` uses the
  root `ScaffoldMessenger`, whose snackbar renders **behind** the modal sheet and
  its barrier — so the fallback is invisible. `about_sheet.dart:46-56` documents
  and fixes exactly this.
- `_DateRowView` (`:380-417`) is a `Row` with an `Expanded` label, an unbounded
  date and a hard `SizedBox(width: 76)` countdown. Measured probe at 320×568
  @2.0×: `A RenderFlex overflowed by 10 pixels on the right` (×3 rows), label
  collapsed to 0, countdown lost its unit.

**Files:** `app/lib/features/calendar/exam_detail_sheet.dart`,
`app/test/exam_detail_test.dart` (new widget coverage; the existing file only
tests the model), `app/test/sheets_test.dart` if the shared pattern moves.

**Do:**
- Remove the invented "Apply online" row (or add a real `apply_url` to the feed
  contract — do **not** do the feed change in this task; removing the row is the
  honest fix now). Update the surrounding comment.
- Gate the "Exam date (your card)" row and the whole "Your card" section on
  `card.examId == examId`; when a card is present but belongs to another exam,
  either omit it or label it with its own exam name. Prefer omission plus a
  one-line note, and test it.
- Wrap `_LinkTile` in `Semantics(link: true)` (children remain the name, per the
  codebase rule).
- Give the sheet its own `ScaffoldMessenger` + transparent `Scaffold` (copy the
  About pattern) so the copy-fallback toast is visible above the barrier.
- Fix `_DateRowView` for 320@2.0×: date `Flexible` with ellipsis, countdown no
  longer a hard 76 px box, and stacked layout above ~1.4× text scale.
- Tests: no duplicate URL in `links`; foreign card hidden; `link: true` trait
  present; 320×568 @2.0× renders with no overflow.

**Acceptance:** probe-style test asserts zero overflow at 320@2.0×; no URL appears
under two labels; full suite green.

---

## Task 7 — Vault form: labelled fields, announced errors, no trapped save

**Defects (P1-6, P2-4, P2-8, P2-9, P2-10).**
`app/lib/features/vault/vault_form_sheet.dart`:
- `_Field` (`:848-880`) renders its label as a sibling `Text`; the
  `TextFormField` only has `hintText`, so TalkBack announces "Street, area, city"
  and "e.g. Gate 2" instead of "Centre address" and "Gate". Twelve
  indistinguishable fields.
- The password show/hide `IconButton` (`:604-614`) has no tooltip and no
  `semanticLabel`: a bare "Button".
- `_validationNotice` and `_error` (`:647-709`) are visual-only: not live regions,
  not announced, focus not moved.
- `_revealFirstInvalidField` (`:286-307`) knows only the name and roll keys; the
  exam date is a hard save blocker five rows above Save, off-screen on a phone,
  and the message says "tap the field above".
- `save()` is unbounded: loads have a 10 s ceiling, writes do not. A hung Keystore
  write leaves `_saving` true forever, the primary button a permanent spinner, and
  Cancel/back/barrier all hit `if (_saving) return;` silently.
- Duplicate detection uses `.value ?? const []`, so it is skipped while the vault
  is still opening (Add is deliberately available then) and a cold-start Add can
  save the same exam + roll twice.

**Files:** `app/lib/features/vault/vault_form_sheet.dart`,
`app/test/vault_form_test.dart`, `app/test/vault_states_test.dart`.

**Do:**
- Use `InputDecoration(labelText: label, floatingLabelBehavior:
  FloatingLabelBehavior.never, hintText: hint)` so the field's accessible name is
  its label while the visual layout stays as designed. Verify no duplicate visible
  label appears (the sibling `Text` may stay for the visual style — if the label
  renders twice, remove the sibling and rely on `labelText` styled to match).
- Password toggle: `tooltip: _obscureSecret ? 'Show password' : 'Hide password'`.
- Announce `_validationNotice` and `_error` with `Semantics(liveRegion: true)` and
  `SemanticsService.sendAnnouncement` when they are set (mirror the checker's
  pattern).
- Give `_DateField` a key, add it to `_revealFirstInvalidField` with a
  `date == null` predicate, and `Scrollable.ensureVisible` it.
- Bound the save: `await save(card).timeout(const Duration(seconds: 15))` inside
  the existing try/catch so `_error` + Retry appear on timeout. Make a close
  attempt during `_saving` say "Still saving your card…" instead of swallowing it.
- Duplicate check: if `admitCardsProvider` is not `AsyncData`, treat the check as
  unavailable and say so, or await the load; do not silently skip.
- Tests: field semantics label equals the field label; error announcement fires;
  date field is scrolled into view; a hanging save surfaces the error path (fake
  store with a never-completing write + `pump(16s)`); duplicate check waits for
  load.

**Acceptance:** all five behaviours covered; no regression in the existing vault
tests; full suite green.

---

## Task 8 — Clipboard: fail loudly, never eat someone else's copy

**Defects (P2-3, P2-7).** `app/lib/core/utils/clipboard_service.dart`:
- The 60-second sensitive wipe fires unconditionally, so copying a password, then
  copying a message in WhatsApp, blanks the message the user is now using.
  Android 10+ still permits background clipboard writes, so this fires while the
  app is backgrounded. The comment claims "any newer copy takes ownership", which
  is only true for copies made through this class.
- `Clipboard.setData` is unguarded: a throw escapes an `async onPressed`, no toast
  appears, and the haptic never runs — the silent failure the class exists to
  prevent. The empty-value branch also toasts before checking `context.mounted`.

**Files:** `app/lib/core/utils/clipboard_service.dart`,
`app/test/feedback_test.dart` (or a new `clipboard_service_test.dart`).

**Do:**
- Wrap the write and haptic in `try/catch`; on failure show
  "Could not copy — long-press the field instead" as an error toast and do not
  schedule a wipe.
- Before wiping, read the clipboard and only clear when the value is still the
  secret this timer owns; skip entirely when the app is not foregrounded
  (`AppLifecycleState`), and cancel the timer when the app goes to background so
  it does not fire unattended.
- Move the `context.mounted` check ahead of the empty-value toast.
- Tests: foreign clipboard content survives the timer; own content is cleared;
  a throwing clipboard produces the error toast and no timer; background
  transition cancels the timer.

**Acceptance:** four tests; full suite green.

---

## Task 9 — About: real provenance, wrapping headings, no stacked sheets, real "Delete all data"

**Defects (P1-7, P2-12, P2-15, plus the half-finished feature).**
`app/lib/features/about/about_sheet.dart`:
- The doc comment promises "the time each was last checked", but
  `SourceHealth.checkedAt` and `.homepage` are parsed and re-serialised and read
  by **no widget**. The real feed carries `checked_at` per source (SSC
  2026-11-15T10:42Z, Railways 10:44Z), so on a stale cache the panel presents old
  health as current — the one thing it exists to prevent. The "Official sources"
  links are hand-maintained rather than `source.homepage`.
- `_SheetHeader`/`EvSectionHeader` headings keep `maxLines: 1` when there is no
  trailing widget, so "WHERE THE DATA COMES FROM" and "WHY WE NEVER HOST THE PDF"
  ellipsise at 320 @2.0×.
- `_AboutButton` (`command_center_screen.dart:282-286`) and the detail sheet can be
  stacked by a fast double tap; the bell got a synchronous guard for exactly this
  (`:155-179`).
- `SecureVaultStore.wipe()` / `AdmitCardRepository.wipe()` are documented as
  "Used by 'Delete all data'" but have **no caller and no UI**. As written they
  also leave the Hive settings (`theme`, `exam_alerts`, `alerts_seen_at`) and the
  cached feed behind.

**Files:** `app/lib/features/about/about_sheet.dart`,
`app/lib/features/command_center/command_center_screen.dart`,
`app/lib/shared/widgets/ev_surfaces.dart` (heading wrap),
`app/lib/providers/app_providers.dart` (wipe orchestration),
`app/test/sheets_test.dart`, `app/test/empty_state_test.dart` if needed.

**Do:**
- Render `source.checkedAt` next to the row count ("17 items · checked 4h ago",
  full date beyond 24 h) and use `source.homepage` for the link when present,
  keeping the hand-written label. If `checkedAt` is null, say nothing about time
  rather than inventing one.
- Section headings: wrap to 2 lines above ~1.4× text scale regardless of whether a
  trailing action exists.
- Add a shared synchronous open-guard (a small `showOnceSheet` helper, or a
  `_opening` bool on a `StatefulWidget`) used by the About button and the exam
  detail sheet, mirroring the bell's `_alertsOpen`.
- **Fix the top-anchored sheet (verified defect, found during Task 6 review).**
  `about_sheet.dart:46-66` wraps the sheet in `ScaffoldMessenger` + `Scaffold`
  as the modal route's *direct* child, so the Scaffold fills the route and places
  the shrink-wrapped surface at `contentTop = 0`. Measured at 393x852 dpr 1.0:
  `DraggableScrollableSheet` rect = `(1, 1) - (392, 766)` — the About sheet
  renders against the **top** of the screen instead of the bottom, the barrier
  above it is unreachable (the surface absorbs the tap that used to dismiss),
  and any snackbar lands below the sheet over the dimmed page. Move the
  `ScaffoldMessenger`/`Scaffold` wrap *inside* the `DraggableScrollableSheet`
  builder so the route child stays shrink-wrapped, and assert the geometry
  (`sheet.bottom ≈ screen height`, `sheet.top > 100`). Task 6 fixed the identical
  defect in the detail sheet; copy that shape.
- Implement **Delete all data** in About, under a "Your data" section:
  confirm dialog ("This removes every admit card and every setting on this device.
  It cannot be undone."), then wipe the secure vault, the settings keys, and the
  cached feed + HTTP cache; reset the in-memory providers so the UI empties
  without a restart; show a confirmation. Make `wipe()` actually cover all of
  those, and fix the doc comments on both existing `wipe()` methods.
- Tests: `checkedAt` rendered and its age label correct for a fixed clock; no age
  shown when null; delete-all clears vault + settings + cache and leaves the app
  in the empty state; double-tap opens one sheet.

**Acceptance:** the About panel never shows a stale "checked" claim; delete-all is
reachable, confirmed, and complete; full suite green.

---

## Task 10 — Notification categories: make the promise true

**Defect (half-finished feature).** The About sheet tells the user a push token is
used "for the categories you follow" (`about_sheet.dart:561-565`), while
`docs/PRIVACY.md` correctly states there is no picker and every device subscribes
to all five (`main.dart:144`). The backend already supports both shapes:
`PushService.syncTopics(Set<ExamCategory>)` exists and is idempotent, and
`ExamCategory.fcmTopic` is already defined.

**Files:** `app/lib/providers/app_providers.dart` (a `FollowedCategoriesNotifier`,
persisted in the settings box, default = all five), `app/lib/main.dart`,
`app/lib/features/about/about_sheet.dart`, `docs/PRIVACY.md`,
`app/test/sheets_test.dart` or a new `followed_categories_test.dart`.

**Do:**
- Persist the followed set (key `followed_categories`, list of category ids).
  Default when absent: all five (so existing users keep today's behaviour).
- `_bootPush` uses the stored set instead of `ExamCategory.values.toSet()`.
- Toggling a category re-runs `syncTopics` immediately (optimistic UI, log-only
  failure, same posture as the per-exam bells). Never allow an empty set silently:
  if the user turns everything off, say "No categories — you will not get exam
  alerts." and keep the stored empty set.
- UI: chips in About under a "Notifications" section, with a one-line explanation
  that this is what the token is for. Hide the section when
  `!pushService.canDeliver`, and say why (web builds / no credentials).
- Update `docs/PRIVACY.md` to describe the picker instead of "no per-category
  picker in this release", and keep the Play "Data safety" wording consistent.
- **Also document "Delete all data"** (shipped in Task 9): `docs/PRIVACY.md:34`
  currently says only "Deleting an admit card deletes its entry from the encrypted
  store. Uninstalling the app removes everything." The app now has an explicit
  one-tap wipe in About, which is exactly what a privacy-conscious reader looks
  for. Name it, say what it removes (cards, settings, cached feed/index), and say
  the push token is kept while its topic subscriptions are dropped.
- Tests: default is all five; a toggle persists and survives a rebuild; boot sync
  receives the stored subset; empty set is allowed and announced.

**Also fix a false comment that hides a real inconsistency (verified by reading
the code).** `ExamAlertsNotifier.toggle` (`app_providers.dart`) says:

```dart
} catch (e) {
  // A failed write must not leave the UI claiming a subscription that will
  // be gone on next launch — same rule as the theme preference.
  AppLogger.w('alerts', 'could not persist exam alerts: $e');
}
```

It logs and returns; it does **not** roll back. `ThemePreferenceNotifier.select`
does (`state = previous;`), so the two notifiers contradict each other while one
of them claims to follow the other's rule. The consequence is the exact failure
the comment describes, one level deeper than the UI: the bell renders ON, the
caller then calls `syncExamAlerts(next)` and the topic subscription is created,
but the setting never reaches disk. On the next launch the bell reads OFF while
the subscription is still live, so the student keeps receiving alerts for an exam
the app says they do not follow — with no way to see why.

Fix: capture `previous`, roll `state` back in the `catch`, and **return the
rolled-back set** so the caller reconciles push against what is actually stored
rather than against a toggle that did not persist. Add a test with a settings box
whose `put` throws: the bell must end up off, and `syncExamAlerts` must be called
with the rolled-back set.

**Acceptance:** the About claim, the code and the privacy policy all agree; full
suite green.

---

## Task 11 — Remove dead code and fix documentation drift

**Defects.** Dead/uncalled API that misleads the next maintainer, plus docs that
contradict the build.

**Files / items:**
- `app/lib/shared/widgets/status_pill.dart`: the unnamed constructor (`:13-20`) has
  zero call sites and would dereference `_status!` on null at `:57`; `pillColor`
  (`:140`) is uncalled but its comment claims `live_radar_tile.dart` still uses it.
  Delete both, keep `EvStatusPill.status` as the only entry point, and fix the
  class doc.
- Unused API with zero callers in `lib/` and `test/` (verify each before deleting;
  keep anything that is a deliberate, documented seam and say so in the report):
  `CdnClient.peek`, `CdnClient.evictAll`, `ResultIndexRepository.pdfBytes`,
  `.pdfUrl`, `.clearMemo`, `LiveUpdate.countBy`, `.isNewerThan`,
  `LiveUpdateFormatting.relativeAge`, `.cdnPdfPath`, `.cdnRollIndexPath`,
  `primaryCardProvider`, `ExamCategoryFilter`.
  Exception: Task 9 may now use `evictAll`/cache clearing for delete-all — check
  before deleting.
- `app/android/app/build.gradle.kts:27`: remove Flutter's scaffold
  `TODO: Specify your own unique Application ID` (the id is real and shipped), and
  fix `:37`'s `minSdk = 23 // Android 6.0` comment — `flutter.minSdkVersion` is
  **24** (Android 7.0). Set the number from the Flutter default and make the
  comment true.
- `app/ios/Runner/Info.plist`: `CFBundleDisplayName` is `Examvault`; every other
  surface says `ExamVault`. Also the app is portrait-designed (the web manifest
  says `portrait-primary`) but iOS declares landscape support — restrict to
  portrait (both idioms) unless a landscape layout exists.
- `app/web/manifest.json`: add a stable `"id": "/"` so the installed app's
  identity survives a future `start_url` change (see the `install-web-app`
  guidance). Keep the existing per-scheme `<meta name="theme-color">` workaround in
  `index.html` — the manifest cannot express two schemes.
- `app/lib/features/calendar/exam_detail_sheet.dart:410` and
  `app/lib/features/calendar/exam_calendar_screen.dart:392` ship `fontSize: 10`
  for live UI while `theme_tokens.dart:11` sets the floor at 11 px. Raise to 11 and
  re-check those rows at 320@2.0× (bitmap-only `share_infographic.dart` 9 px values
  are exempt — that is a 3× export). **Already done in a Task 11 follow-up** — the
  countdown and the calendar source label now inherit their tokens; verify it and do
  not redo it.
- **`DayTickNotifier.build()` leaks an `AppLifecycleListener` on rebuild.**
  `app_providers.dart` reassigns `_lifecycle` without disposing the previous one,
  while `LiveFeedNotifier.build()` does `_lifecycle?.dispose()` first. Latent today
  (nothing invalidates `dayTickProvider`), but it is the exact pattern this file
  fixes elsewhere, and Task 10 owns the file. Add the dispose and note why it is
  defensive.

**Acceptance:** `flutter analyze --fatal-infos` clean, full suite green, no
remaining references to the deleted symbols, and every doc/comment touched now
matches the build.

---

## Task 12 — Play Store submission assets and listing

**Defect (blocking submission).** `docs/PLAY_STORE.md` still lists the 1024×500
feature graphic as "still to make" and screenshots as "must be captured … from a
real device build". There is no feature graphic and no screenshot set in the repo.

**Files:** `tools/branding/` (extend the existing deterministic asset tooling),
`docs/PLAY_STORE.md`, `.github/workflows/` only if a build step is genuinely
required (prefer local generation).

**Do:**
- Generate `design/exports/feature_graphic_1024x500.png` deterministically from
  the existing brand tokens (`app_icon_512.png`, the navy palette, the wordmark) —
  no stock imagery, no invented statistics, no fabricated UI. Keep the generator
  script in `tools/branding/` and document the command.
- Produce a screenshot pipeline: a script or documented Flutter command that
  captures the four screens at ≥1080×2340 from a device/emulator build, writing to
  `design/exports/screenshots/`. Do not commit fake screenshots; commit the
  pipeline and, if a capture is produced here, note the exact command and device
  used.
- Update `docs/PLAY_STORE.md`: artefact list matches what CI actually produces,
  feature graphic marked done with its path, screenshot instructions with the
  real command, the short description re-verified against the 80-character limit,
  and a "Data safety" section consistent with Task 10's category picker.
- Verify every listing claim against the code one final time (no PDFs mirrored, no
  analytics, no account) and correct anything that drifted.

**Acceptance:** the feature graphic exists at the documented path, is exactly
1024×500, and the doc's claims match the code.

---

## Task 14 — The two usability gaps the audit ranked highest

Two of the audit's "UI/UX improvements worth doing next" items are worth shipping
in this release because they make an existing signal *legible*; the other two are
deferred with reasons (see the disposition list).

**Defect A — the radar's badge is meaningless on the list itself.**
`liveRadarBadgeProvider` counts rows published after `alertsSeenAt`, and the tab
bar shows a dot, but the list draws no boundary between seen and unseen. A
student who opens the app after a week sees 40 rows in publication order with no
indication which 6 are the ones the badge was counting. Insert a divider (a
hairline plus a small "NEW" label) at the first row whose `publishedAt` is after
`alertsSeenAt`, and only when at least one row is newer. It must never appear
when the user has seen everything, and never when `alertsSeenAt` is the epoch
(fresh install — everything is new, so a divider above the first row says
nothing).

**Defect B — the Dates tab is a flat list of up to ~20 rows.**
`examCalendarProvider` already sorts nearest-first. Group the list under
"This week", "This month" and "Later" headers, computed from the same
`daysFrom` the row already uses. A group with no entries is not drawn. The
grouping must not reorder anything, and each header must be a real
`Semantics(header: true)` so a screen reader can jump between them.

**Defect C — the vault section says nothing when a filter narrows it.**
The radar header prints "3 of 34" while a search runs, but the "My admit cards"
section prints only the unfiltered "N saved". So with a query that matches one of
five cards, the header claims five and the list shows one, and the only
explanation is the empty state — which does not appear, because the list is not
empty. Mirror the radar's fraction in the vault header while a query or a
category chip is active: `1 of 5` instead of `5 saved`. When nothing is filtered,
keep the current wording exactly.

**Files:** `app/lib/features/command_center/command_center_screen.dart`,
`app/lib/features/calendar/exam_calendar_screen.dart`,
`app/test/sheets_test.dart` or `app/test/exam_calendar_test.dart`,
`app/test/user_journey_test.dart`.

**Do:** both changes, tests for both (divider appears only with unseen rows and
not on a fresh install; groups are ordered, empty groups absent, headers exposed
as headings), and a 320×568 @2.0× render of each to prove no overflow.

**Acceptance:** the divider cannot appear without an unseen row; the grouped
calendar preserves the existing order exactly; full suite green.

---

## Task 15 — The release build ships an empty app version

**Defect (verified by execution).** `.github/workflows/ci.yml` sets
`defaults.run.working-directory: app` for the build job, then derives the version
with:

```sh
--dart-define=EV_APP_VERSION="$(grep -m1 '^version:' app/pubspec.yaml | awk '{print $2}')"
```

From `app/`, that path is `app/app/pubspec.yaml` — it does not exist. Reproduced:

```sh
$ cd app && bash -c 'set -euo pipefail
  echo "arg=[$(grep -m1 "^version:" app/pubspec.yaml | awk "{print \$2}")]"'
grep: app/pubspec.yaml: No such file or directory
arg=[]
script exit=0
```

The inline-argument form does **not** trip `set -e` (a command substitution
failing inside an argument is not a command failure), so the build proceeds with
`EV_APP_VERSION=""`. `AppConfig.appVersion` is then empty and the About sheet
omits the version clause entirely — while the comment directly above the line
promises the version "can never drift from the shipped one". It always drifts, to
nothing.

**Files:** `.github/workflows/ci.yml` only.

**Do:**
- Fix the path to `pubspec.yaml` (the job already runs in `app/`).
- Add a guard in the same spirit as the existing `EV_CDN_BASE` check: if the
  derived version is empty, fail the job with a clear `::error::` rather than
  shipping a build whose About sheet has no version.
- Apply it to **both** build invocations (`flutter build apk` and
  `flutter build appbundle`).
- Do not restructure the workflow otherwise.

**Acceptance:** the derivation returns `1.0.1+2`-style values from `app/`, and an
empty result fails the job.

---

## Task 13 — Final verification and release notes

**Do:**
- `flutter analyze --fatal-infos`, `dart format --set-exit-if-changed`, full
  `flutter test`, `node --test test/*.mjs`, `flutter build web --release`.
- Re-read `docs/AUDIT_2026-11-16.md` and mark every P0/P1/P2 item either fixed
  (with the commit) or explicitly deferred with a reason. No silent drops.
- Add a short "Release notes — 1.0.1" section to `docs/PLAY_STORE.md` listing what
  changed for users (dead buttons fixed, honest alert states, correct share
  selection, delete-all-data, notification categories).
- Bump `app/pubspec.yaml` to `1.0.1+2` (the version the About sheet reads via
  `EV_APP_VERSION`), and confirm CI's derived version matches.

**Acceptance:** every gate green, audit fully dispositioned, version bumped.

---

## Dependency order

```
1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 → 10 → 11 → 12 → 13
```

Strictly sequential for implementation (all touch shared Flutter surfaces; Task 9
and Task 10 both edit `about_sheet.dart`). Reviews run after each task's
implementer reports; fix rounds resume the same implementer.

## Out of scope (deferred, with reasons recorded in Task 13)

- Adding `apply_url` to the feed contract (needs a pipeline change and a
  publisher-side definition; the honest fix now is to stop inventing the label).
- Rails/RRB index coverage and additional state PSCs (source availability, not a
  code defect — see `docs/DATA_PIPELINE.md` § Known gaps).
- A "past notices" archive view (`filterUpdates(includeExpired:)` already exists as
  the seam; it is a product decision, not a defect).
- Replacing the design deck in `design/index.html` (correctly banner-labelled
  "ARCHIVED — NOT SPEC").

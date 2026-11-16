# TODO — Play-Store-ready release

Every single change, tracked. `[ ]` pending · `[~]` in progress · `[x]` done ·
`[!]` blocked/deferred (reason required).

Branch: `release/play-store-ready`. Plan: `docs/PLAN_play_store_ready.md`.
Audit: `docs/AUDIT_2026-11-16.md`. Ledger: `.superpowers/sdd/PLAN_play_store_ready/progress.md`.

---

## Task 1 — Green the suite (time-bomb test)
- [x] `live_feed_parsing_test.dart` `liveCount` fixture: pin `expires_at` far-future
- [x] Keep an explicitly-expired row in the fixture so the exclusion path is still proven
- [x] New test: `liveCountAt(fixedNow)` stable for a fixed clock
- [x] Audit all other fixtures omitting `expires_at` that assert a count/inclusion
- [x] Fix any additional wall-clock-dependent fixture found
- [x] Gate: `flutter analyze --fatal-infos` clean
- [x] Gate: `dart format --set-exit-if-changed lib test tool` clean
- [x] Gate: `flutter test` fully green
- [x] Commit `test(...)`

## Task 2 — Every control operable (P0 dead buttons)
- [x] `ev_surfaces.dart` `EvTextAction`: pass `onTap` to `Semantics`
- [x] `live_radar_tile.dart` `_AlertBell`: pass `onTap`
- [x] `exam_calendar_screen.dart` calendar bell: pass `onTap`
- [x] `exam_detail_sheet.dart` `_BellRow`: pass `onTap`
- [x] `wallet_pass_card.dart` `_CopyPill`: add `onTap` to `Semantics`
- [x] `whatsapp_share_card_screen.dart` "Edit caption": pass `onTap`
- [x] `admit_card_detail_screen.dart` `_PageCounter`: confirm label-only is correct, document why
- [x] `ev_surfaces.dart` `EvCard` — 8th site found by the implementer: wrapper now carries `onTap`
- [x] `a11y_matrix_test.dart`: assert every `isButton` node has a tap/longPress action, all 5 tabs @320@2.0×
- [x] Guard exemption for explicitly disabled nodes (`isEnabled == false`), verified narrow
- [ ] DEFERRED → Task 9: `EvCard` inner `InkWell` still yields a second focus stop (`excludeFromSemantics` fix)
- [x] New test: activate `EvTextAction` through the semantics layer, assert callback ran
- [x] Verify the new matrix assertion FAILS on pre-fix code
- [x] Commit `fix(a11y):`

## Task 3 — Rename must not keep old exam id or VERIFIED
- [ ] `resolveExamId`: reuse `previous` only when the exam name is unchanged
- [ ] `keepsVerification`: add `!renamed`
- [ ] Test: rename → unpublished name ⇒ slug id + VERIFIED dropped
- [ ] Test: rename → published name ⇒ fresh feed id + VERIFIED dropped
- [ ] Test: edit a non-name field (centre) ⇒ id kept + VERIFIED kept
- [ ] Test: rename back to original ⇒ no implicit VERIFIED
- [ ] Update the file's doc comment to describe the rename rule
- [ ] Commit `fix(vault):`

## Task 4 — Alerts inbox honest + survives 2.0×
- [ ] Branch body: loading ⇒ "Checking for updates…" + progress
- [ ] Branch body: error & no value ⇒ "Could not check for updates." + reason + Retry (`invalidate`)
- [ ] Branch body: loaded & empty ⇒ current copy
- [ ] Branch body: loaded & rows ⇒ list
- [ ] Header subtitle matches body state (no "Nothing needs your attention" over spinner/error)
- [ ] Preserve `onLoadedAlertsRendered` contract exactly (loaded, non-empty, not loading)
- [ ] Wrap `_AlertRow` pill in `Flexible` + `FittedBox(scaleDown)` right-aligned
- [ ] Tests: loading / error+Retry / empty / 320@2.0× no overflow + name wider than pill
- [ ] Commit `fix(alerts):`

## Task 5 — Share: right card, fresh facts, honest result, bounded export
- [ ] `_cardFor`: explicit selection wins when `examId` differs from pinned update
- [ ] Show the shared exam's name in the header
- [ ] Resolve the feed row by `examId` every build; use fresh status/headline/subline/URL/pdf size
- [ ] Keep the tapped row as fallback only before the feed loads
- [ ] Branch on `ShareResult.status`; dismissed/unavailable ⇒ "Nothing was sent — your caption is still here."
- [ ] Constrain captured card to ≤400 dp; derive `pixelRatio` from laid-out width (~1080 px)
- [ ] Share tile label: no word truncated at 2.0×
- [ ] Tests: pinned-vs-selected; stale `awaited`→`result_out`; dismissed share message; capture ratio at wide viewport
- [ ] Commit `fix(share):`

## Task 6 — Detail sheet: no invented link, no foreign card, no overflow
- [ ] Remove the invented "Apply online" duplicate row; update the comment
- [ ] Gate "Exam date (your card)" + "Your card" section on `card.examId == examId`
- [ ] When a foreign card is present: omit it and show a one-line note
- [ ] `_LinkTile`: `Semantics(link: true)`
- [ ] Sheet gets its own `ScaffoldMessenger` + transparent `Scaffold` (About pattern) so the copy-fallback toast is visible
- [ ] `_DateRowView`: date `Flexible` + ellipsis
- [ ] `_DateRowView`: countdown no longer a hard 76 px box
- [ ] `_DateRowView`: stacked layout above ~1.4× text scale
- [ ] Tests: no duplicate URL; foreign card hidden; `link: true` trait; 320@2.0× zero overflow
- [ ] Commit `fix(detail):`

## Task 7 — Vault form: labelled fields, announced errors, no trapped save
- [ ] `_Field`: `labelText` (floating never) so the accessible name is the label; keep the visual label
- [ ] Verify the label does not render twice; drop the sibling `Text` if it does
- [ ] Password toggle: `tooltip: 'Show password' / 'Hide password'`
- [ ] `_validationNotice` + `_error`: `liveRegion` + `SemanticsService.sendAnnouncement`
- [ ] `_DateField` gets a key; added to `_revealFirstInvalidField`; `Scrollable.ensureVisible`
- [ ] `save()` bounded with `.timeout(15s)` inside the existing try/catch ⇒ `_error` + Retry
- [ ] Close during `_saving` says "Still saving your card…" instead of silently returning
- [ ] Duplicate check: handle non-`AsyncData` explicitly (await load or say unavailable)
- [ ] Tests: field semantics label; error announcement; date scrolled into view; hanging save surfaces error; duplicate waits for load
- [ ] Commit `fix(vault-form):`

## Task 8 — Clipboard: fail loudly, never eat someone else's copy
- [ ] Wrap `Clipboard.setData` + haptic in try/catch ⇒ error toast, no wipe scheduled
- [ ] Before wiping, read the clipboard and only clear when it still holds our secret
- [ ] Skip/cancel the timer when the app is not foregrounded
- [ ] `context.mounted` check ahead of the empty-value toast
- [ ] Tests: foreign content survives; own content cleared; throwing clipboard ⇒ error toast + no timer; background cancels timer
- [ ] Commit `fix(clipboard):`

## Task 9 — About: real provenance, wrapping headings, no stacked sheets, real delete-all
- [ ] Render `source.checkedAt` next to the row count ("17 items · checked 4h ago"; full date >24h)
- [ ] No age shown when `checkedAt` is null (never invent one)
- [ ] Use `source.homepage` for the source link when present
- [ ] `EvSectionHeader`: wrap to 2 lines above ~1.4× regardless of `trailing`
- [ ] Shared synchronous open-guard (`showOnceSheet` or `_opening` bool) for About + detail sheet
- [ ] Implement "Delete all data" UI in About under "Your data" with a confirm dialog
- [ ] Wipe secure vault + settings keys + cached feed + HTTP cache
- [ ] Reset in-memory providers so the UI empties without a restart
- [ ] Confirmation feedback after the wipe
- [ ] Fix the doc comments on both `wipe()` methods so they are true
- [ ] Tests: `checkedAt` rendered with correct age for a fixed clock; none when null; delete-all clears everything and lands in empty state; double-tap opens one sheet
- [ ] Commit `feat(about):`

## Task 10 — Notification categories: make the promise true
- [ ] `FollowedCategoriesNotifier` persisted (`followed_categories`), default = all five
- [ ] `_bootPush` uses the stored set instead of `ExamCategory.values.toSet()`
- [ ] Toggling re-runs `syncTopics` immediately (optimistic, log-only failure)
- [ ] Empty set allowed, with an explicit "you will not get exam alerts" message
- [ ] About UI: chips under a "Notifications" section + one-line explanation
- [ ] Hide the section when `!pushService.canDeliver`, and say why
- [ ] Update `docs/PRIVACY.md` to describe the picker (remove "no per-category picker")
- [ ] Keep Play "Data safety" wording consistent
- [ ] Tests: default all five; toggle persists across rebuild; boot sync receives the subset; empty set allowed + announced
- [ ] Commit `feat(push):`

## Task 11 — Dead code + documentation drift
- [ ] `status_pill.dart`: delete the unnamed constructor (zero callers, null-asserts)
- [ ] `status_pill.dart`: delete uncalled `pillColor` and fix the class doc
- [ ] Verify + delete unused: `CdnClient.peek`, `.evictAll` (unless Task 9 uses it), `ResultIndexRepository.pdfBytes`, `.pdfUrl`, `.clearMemo`, `LiveUpdate.countBy`, `.isNewerThan`, `LiveUpdateFormatting.relativeAge`, `.cdnPdfPath`, `.cdnRollIndexPath`, `primaryCardProvider`, `ExamCategoryFilter`
- [ ] `build.gradle.kts`: remove Flutter's scaffold TODO above the real applicationId
- [ ] `build.gradle.kts`: fix `minSdk = 23 // Android 6.0` ⇒ 24 / Android 7.0
- [ ] `Info.plist`: `CFBundleDisplayName` `Examvault` ⇒ `ExamVault`
- [ ] `Info.plist`: restrict to portrait (both idioms) or document landscape support
- [ ] `manifest.json`: add stable `"id": "/"`
- [ ] `exam_detail_sheet.dart:410` `fontSize: 10` ⇒ 11
- [ ] `exam_calendar_screen.dart:392` `fontSize: 10` ⇒ 11
- [ ] Re-check both rows at 320@2.0× after the size bump
- [ ] Commit `chore(cleanup):`

## Task 12 — Play Store assets + listing
- [ ] Generator in `tools/branding/` for `design/exports/feature_graphic_1024x500.png`
- [ ] Feature graphic generated, exactly 1024×500, from brand tokens only
- [ ] Screenshot pipeline (script or documented command) writing to `design/exports/screenshots/`
- [ ] `docs/PLAY_STORE.md`: artefact list matches CI
- [ ] `docs/PLAY_STORE.md`: feature graphic marked done with path
- [ ] `docs/PLAY_STORE.md`: screenshot instructions with the real command
- [ ] `docs/PLAY_STORE.md`: short description re-verified ≤80 chars
- [ ] `docs/PLAY_STORE.md`: Data safety section consistent with Task 10
- [ ] Final claim audit: no mirrored PDFs, no analytics, no account
- [ ] Commit `docs(play):`

## Task 13 — Final verification + release notes
- [ ] `flutter analyze --fatal-infos` clean
- [ ] `dart format --set-exit-if-changed` clean
- [ ] `flutter test` green
- [ ] `node --test test/*.mjs` green
- [ ] `flutter build web --release` succeeds
- [ ] `flutter build apk --release` succeeds (or document why not run here)
- [ ] Audit doc: every P0/P1/P2 dispositioned (fixed + commit, or deferred + reason)
- [ ] `docs/PLAY_STORE.md`: "Release notes — 1.0.1" section
- [ ] `app/pubspec.yaml` ⇒ `1.0.1+2`
- [ ] Commit `chore(release):`

---

## Final whole-branch review
- [ ] Dispatch broad review on the most capable model against `master..HEAD`
- [ ] Single fix wave for its findings
- [ ] Re-review clean
- [ ] Update `INFRA_STATUS.md` / `README.md` where claims changed
- [ ] Report to the user: what shipped, what was deferred, how to verify

## Deferred (with reasons — must appear in Task 13's disposition)
- [ ] `apply_url` in the feed contract (needs a pipeline + publisher definition)
- [ ] RRB/state-PSC source coverage (source availability, not code)
- [ ] "Past notices" archive view (product decision; seam exists)
- [ ] Redrawing `design/index.html` (correctly banner-labelled ARCHIVED)

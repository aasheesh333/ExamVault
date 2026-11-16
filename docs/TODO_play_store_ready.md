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
- [x] DEFERRED → Task 9: `EvCard` inner `InkWell` still yields a second focus stop (`excludeFromSemantics` fix)
- [x] New test: activate `EvTextAction` through the semantics layer, assert callback ran
- [x] Verify the new matrix assertion FAILS on pre-fix code
- [x] Commit `fix(a11y):`

## Task 3 — Rename must not keep old exam id or VERIFIED
- [x] `resolveExamId`: reuse `previous` only when the exam name is unchanged
- [x] `keepsVerification`: add `!renamed`
- [x] Test: rename → unpublished name ⇒ slug id + VERIFIED dropped
- [x] Test: rename → published name ⇒ fresh feed id + VERIFIED dropped
- [x] Test: edit a non-name field (centre) ⇒ id kept + VERIFIED kept
- [x] Test: rename back to original ⇒ no implicit VERIFIED
- [x] Update the file's doc comment to describe the rename rule
- [x] Commit `fix(vault):`

## Task 4 — Alerts inbox honest + survives 2.0×
- [x] Branch body: loading ⇒ "Checking for updates…" + progress
- [x] Branch body: error & no value ⇒ "Could not check for updates." + reason + Retry (`invalidate`)
- [x] Branch body: loaded & empty ⇒ current copy
- [x] Branch body: loaded & rows ⇒ list
- [x] Header subtitle matches body state (no "Nothing needs your attention" over spinner/error)
- [x] Preserve `onLoadedAlertsRendered` contract exactly (loaded, non-empty, not loading)
- [x] Wrap `_AlertRow` pill in `Flexible` + `FittedBox(scaleDown)` right-aligned
- [x] Tests: loading / error+Retry / empty / 320@2.0× no overflow + name wider than pill
- [x] Commit `fix(alerts):`

## Task 5 — Share: right card, fresh facts, honest result, bounded export
- [x] `_cardFor`: explicit selection wins when `examId` differs from pinned update
- [x] Show the shared exam's name in the header
- [x] Resolve the feed row by `examId` every build; use fresh status/headline/subline/URL/pdf size
- [x] Keep the tapped row as fallback only before the feed loads
- [x] Branch on `ShareResult.status`; dismissed/unavailable ⇒ "Nothing was sent — your caption is still here."
- [x] Constrain captured card to ≤400 dp; derive `pixelRatio` from laid-out width (~1080 px)
- [x] Share tile label: no word truncated at 2.0×
- [x] Tests: pinned-vs-selected; stale `awaited`→`result_out`; dismissed share message; capture ratio at wide viewport
- [x] Commit `fix(share):`

## Task 6 — Detail sheet: no invented link, no foreign card, no overflow
- [x] Remove the invented "Apply online" duplicate row; update the comment
- [x] Gate "Exam date (your card)" + "Your card" section on `card.examId == examId`
- [x] When a foreign card is present: omit it and show a one-line note
- [x] `_LinkTile`: `Semantics(link: true)`
- [x] Sheet gets its own `ScaffoldMessenger` + transparent `Scaffold` (About pattern) so the copy-fallback toast is visible
- [x] `_DateRowView`: date `Flexible` + ellipsis
- [x] `_DateRowView`: countdown no longer a hard 76 px box
- [x] `_DateRowView`: stacked layout above ~1.4× text scale
- [x] Tests: no duplicate URL; foreign card hidden; `link: true` trait; 320@2.0× zero overflow
- [x] Commit `fix(detail):`

## Task 7 — Vault form: labelled fields, announced errors, no trapped save
- [x] `_Field`: `labelText` (floating never) so the accessible name is the label; keep the visual label
- [x] Verify the label does not render twice; drop the sibling `Text` if it does
- [x] Password toggle: `tooltip: 'Show password' / 'Hide password'`
- [x] `_validationNotice` + `_error`: `liveRegion` + `SemanticsService.sendAnnouncement`
- [x] `_DateField` gets a key; added to `_revealFirstInvalidField`; `Scrollable.ensureVisible`
- [x] `save()` bounded with `.timeout(15s)` inside the existing try/catch ⇒ `_error` + Retry
- [x] Close during `_saving` says "Still saving your card…" instead of silently returning
- [x] Duplicate check: handle non-`AsyncData` explicitly (await load or say unavailable)
- [x] Tests: field semantics label; error announcement; date scrolled into view; hanging save surfaces error; duplicate waits for load
- [x] Commit `fix(vault-form):`

## Task 8 — Clipboard: fail loudly, never eat someone else's copy
- [x] Wrap `Clipboard.setData` + haptic in try/catch ⇒ error toast, no wipe scheduled
- [x] Before wiping, read the clipboard and only clear when it still holds our secret
- [x] Skip/cancel the timer when the app is not foregrounded
- [x] `context.mounted` check ahead of the empty-value toast
- [x] Tests: foreign content survives; own content cleared; throwing clipboard ⇒ error toast + no timer; background cancels timer
- [x] Commit `fix(clipboard):`

## Task 9 — About: real provenance, wrapping headings, no stacked sheets, real delete-all
- [x] Render `source.checkedAt` next to the row count ("17 items · checked 4h ago"; full date >24h)
- [x] No age shown when `checkedAt` is null (never invent one)
- [x] Use `source.homepage` for the source link when present
- [x] `EvSectionHeader`: wrap to 2 lines above ~1.4× regardless of `trailing`
- [x] **FIX the top-anchored About sheet** (verified: rect (1,1)-(392,766) at 393×852) — move ScaffoldMessenger/Scaffold inside the DraggableScrollableSheet builder; assert geometry
- [x] `EvCard` double focus stop: `InkWell(excludeFromSemantics: onTap != null && semanticLabel != null)`
- [x] Shared synchronous open-guard (`showOnceSheet` or `_opening` bool) for About + detail sheet
- [x] Implement "Delete all data" UI in About under "Your data" with a confirm dialog
- [x] Wipe secure vault + settings keys + cached feed + HTTP cache
- [x] Reset in-memory providers so the UI empties without a restart
- [x] Confirmation feedback after the wipe
- [x] Fix the doc comments on both `wipe()` methods so they are true
- [x] Tests: `checkedAt` rendered with correct age for a fixed clock; none when null; delete-all clears everything and lands in empty state; double-tap opens one sheet
- [x] Commit `feat(about):`

## Task 10 — Notification categories: make the promise true
- [~] `FollowedCategoriesNotifier` persisted (`followed_categories`), default = all five
- [~] `_bootPush` uses the stored set instead of `ExamCategory.values.toSet()`
- [~] Toggling re-runs `syncTopics` immediately (optimistic, log-only failure)
- [~] Empty set allowed, with an explicit "you will not get exam alerts" message
- [~] About UI: chips under a "Notifications" section + one-line explanation
- [~] Hide the section when `!pushService.canDeliver`, and say why
- [~] Update `docs/PRIVACY.md` to describe the picker (remove "no per-category picker")
- [~] `docs/PRIVACY.md:34`: document the new one-tap "Delete all data" (cards, settings, cached feed/index; token kept, topics dropped)
- [~] Keep Play "Data safety" wording consistent
- [~] Tests: default all five; toggle persists across rebuild; boot sync receives the subset; empty set allowed + announced
- [~] `ExamAlertsNotifier.toggle`: roll back `state` on a failed write and return the rolled-back set (comment claims this; code does not)
- [~] Test: a throwing settings write leaves the bell OFF and syncs the rolled-back set
- [~] Commit `feat(push):`

## Task 11 — Dead code + documentation drift
- [x] `status_pill.dart`: delete the unnamed constructor (zero callers, null-asserts)
- [x] `status_pill.dart`: delete uncalled `pillColor` and fix the class doc
- [x] Verify + delete unused: `CdnClient.peek`, `.evictAll` (unless Task 9 uses it), `ResultIndexRepository.pdfBytes`, `.pdfUrl`, `.clearMemo`, `LiveUpdate.countBy`, `.isNewerThan`, `LiveUpdateFormatting.relativeAge`, `.cdnPdfPath`, `.cdnRollIndexPath`, `primaryCardProvider`, `ExamCategoryFilter`
- [x] `build.gradle.kts`: remove Flutter's scaffold TODO above the real applicationId
- [x] `build.gradle.kts`: fix `minSdk = 23 // Android 6.0` ⇒ 24 / Android 7.0
- [x] `Info.plist`: `CFBundleDisplayName` `Examvault` ⇒ `ExamVault`
- [x] `Info.plist`: restrict to portrait (both idioms) or document landscape support
- [x] `manifest.json`: add stable `"id": "/"`
- [x] `exam_detail_sheet.dart:410` `fontSize: 10` ⇒ 11
- [x] `exam_calendar_screen.dart:392` `fontSize: 10` ⇒ 11
- [ ] `DayTickNotifier.build()`: dispose the previous `_lifecycle` before reassigning (Task 10 owns the file)
- [x] Re-check both rows at 320@2.0× after the size bump
- [x] Commit `chore(cleanup):`

## Task 12 — Play Store assets + listing
- [x] Generator in `tools/branding/` for `design/exports/feature_graphic_1024x500.png`
- [x] Feature graphic generated, exactly 1024×500, from brand tokens only
- [x] Screenshot pipeline (script or documented command) writing to `design/exports/screenshots/`
- [x] `docs/PLAY_STORE.md`: artefact list matches CI
- [x] `docs/PLAY_STORE.md`: feature graphic marked done with path
- [x] `docs/PLAY_STORE.md`: screenshot instructions with the real command
- [x] `docs/PLAY_STORE.md`: short description re-verified ≤80 chars
- [x] `docs/PLAY_STORE.md`: Data safety section consistent with Task 10
- [x] Final claim audit: no mirrored PDFs, no analytics, no account
- [x] Commit `docs(play):`

## Task 14 — Radar "new since last look" divider + Dates grouping
- [~] Radar: hairline + "NEW" label at the first row newer than `alertsSeenAt`
- [~] Never draw it when nothing is unseen
- [~] Never draw it on a fresh install (`alertsSeenAt` == epoch)
- [~] Test: divider appears with unseen rows, absent when all seen
- [~] Dates: group under "This week" / "This month" / "Later"
- [~] Empty groups are not drawn; existing order preserved exactly
- [~] Each group header is `Semantics(header: true)`
- [~] Tests: ordering, absent empty groups, headings exposed
- [~] 320×568 @2.0× render of both, no overflow
- [~] Vault header: show `1 of 5` while a query or category filter narrows it
- [~] Vault header: unchanged wording ("N saved") when nothing is filtered
- [~] Test: filtered fraction matches the rendered card count
- [~] Commit `feat(ux):`

## Task 15 — CI ships an empty app version
- [x] `.github/workflows/ci.yml`: version grep path `app/pubspec.yaml` → `pubspec.yaml` (job runs in `app/`)
- [x] Guard: empty derived version fails the job with `::error::`
- [x] Applied to BOTH `flutter build apk` and `flutter build appbundle`
- [x] Verified from `app/` that the derivation returns a real version
- [x] Commit `fix(ci):`

## Task 16 — Radar/alerts pill paints below the type floor at 2.0×
- [~] Above ~1.4× scale, put the status pill + age on their own line with full row width
- [~] Drop the `FittedBox` on that path so the label keeps its 11 px token size
- [~] Same rule in `alerts_sheet.dart` so the two lists match
- [~] Test: at 320×568 @2.0× the pill label is ≥11 logical px (not just "no overflow")
- [~] Test: the 320@1.0× arrangement is unchanged
- [~] Commit `fix(a11y):`

## Task 17 — Documentation reconciliation (docs only)
- [x] `README.md` Screens table rewritten from `EvTab`: five tabs in tab order
- [x] `README.md` + `app/README.md`: format command `lib test` → `lib test tool`
- [x] `docs/PLAY_STORE.md`: the false `pdfBytes`/`pdfUrl` sentence replaced
- [x] Re-verified every `file:line` citation (16 distinct / 23 occurrences; 8 fixed, 8 kept)
- [x] "all exam alerts or none" reconciled with the picker
- [x] 26-permission table: provenance stated, `app/build/` claim corrected
- [x] `INFRA_STATUS.md`: dated snapshot preserved + 2026-11-16 re-observation added
- [x] `AppConfig.resultPdfPath`: one-line legacy comment
- [x] README Dates row: bell only on notice dates, not card dates
- [x] README Radar row: quote the real string "Not in this list yet"
- [x] PDF claim: every use enumerated, none fetches the document
- [x] `docs/PRIVACY.md`: permission-table provenance matches `PLAY_STORE.md`
- [x] Commit `docs:`

## Task 18 — Edge worker caches the uncacheable feed route
- [ ] Skip `cache.put` when `route.noEdgeCache` is true
- [ ] Comment why: a write nobody reads is a per-request cost on the pass-through route
- [ ] Leave ETag/304, buffering, headers and other routes untouched
- [ ] `node --check infra/src/index.js`
- [ ] Commit `fix(infra):`

## Task 19 — Pill below the type floor at the DEFAULT text size (8.25 px)
- [ ] Fix the ≤1.4× path: give the pill its natural width instead of scaling the text
- [ ] Preferred: pill on the context line, age alone in the right column
- [ ] No `RenderFittedBox` above the label at ANY scale 1.0×–2.0×
- [ ] Painted size ≥ 11 px × scale at 1.0/1.2/1.4/1.6/1.8/2.0×
- [ ] Also fix the pre-existing 1.2 px meta-line overflow at 1.4×
- [ ] Alert bell keeps its 44 px target; label always present (colour-blind contract)
- [ ] Same rule in `alerts_sheet.dart`
- [ ] Commit `fix(a11y):`

## Task 13 — Final verification + release notes
- [ ] `flutter analyze --fatal-infos` clean
- [ ] `dart format --set-exit-if-changed` clean
- [ ] `flutter test` green
- [ ] `node --test test/*.mjs` green
- [ ] `flutter build web --release` succeeds
- [ ] `flutter build apk --release` succeeds (or document why not run here)
- [ ] Audit doc: every P0/P1/P2 dispositioned (fixed + commit, or deferred + reason)
- [ ] `docs/PLAY_STORE.md`: "Release notes — 1.0.1" section
- [ ] **Re-verify EVERY `file:line` citation in `docs/PLAY_STORE.md`** against the final merged tree — they drift (Task 9 rewrote `about_sheet.dart`; Task 11 deleted API)
- [ ] Fix the now-FALSE sentence at `docs/PLAY_STORE.md:206`: it says the legacy route "still has `pdfBytes`/`pdfUrl` wrappers" — Task 11 deleted both
- [ ] `AppConfig.resultPdfPath` is now uncalled (its only two callers were deleted) — delete it or document it as the future-PDF seam
- [ ] Reconcile `docs/PLAY_STORE.md`'s "the current release is 'all exam alerts' or 'none'" paragraph with Task 10's category picker
- [ ] Record that the 26-permission merged-manifest table cannot be regenerated in this environment (no Android SDK); state where it came from
- [ ] `app/pubspec.yaml` ⇒ `1.0.1+2`
- [ ] `app/ios/Runner/Info.plist`: restore landscape (probe: 852×393 / 900×500 / 393×852 all render cleanly; iPad Split View needs it) and correct the false "stretched portrait UI" comment
- [ ] Do NOT add `android:screenOrientation`; leave the web manifest `portrait-primary` (a PWA display preference, not a restriction)
- [ ] Commit `chore(release):`

---

## Final whole-branch review
- [ ] Dispatch broad review on the most capable model against `master..HEAD`
- [ ] Single fix wave for its findings
- [ ] Re-review clean
- [ ] Update `INFRA_STATUS.md` / `README.md` where claims changed
- [ ] `README.md` Screens table lists 4 screens but the app ships 5 tabs — **Dates / Exam Calendar is missing entirely**, and the numbering (Checker=3, Share=4) contradicts the tab order (Home, Vault, Dates, Radar, Share)
- [ ] `README.md` + `app/README.md` Verify blocks say `dart format ... lib test`; CI checks `lib test tool`
- [ ] Report to the user: what shipped, what was deferred, how to verify

## Deferred (with reasons — must appear in Task 13's disposition)
- [ ] `apply_url` in the feed contract (needs a pipeline + publisher definition)
- [ ] RRB/state-PSC source coverage (source availability, not code)
- [ ] "Past notices" archive view (product decision; seam exists)
- [ ] Redrawing `design/index.html` (correctly banner-labelled ARCHIVED)

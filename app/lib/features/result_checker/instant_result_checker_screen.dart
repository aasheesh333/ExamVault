import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/motion.dart';
import '../../core/theme/theme_tokens.dart';
import '../../core/utils/clipboard_service.dart';
import '../../core/utils/ev_haptics.dart';
import '../../data/repositories/result_index_repository.dart';
import '../../data/services/app_logger.dart';
import '../../domain/entities/admit_card.dart';
import '../../domain/entities/live_update.dart';
import '../../features/result_checker/engine/roll_index_engine.dart';
import '../../providers/app_providers.dart';
import '../shell/root_shell.dart';
import '../../shared/widgets/ev_controls.dart';
import '../../shared/widgets/ev_surfaces.dart';
import '../calendar/exam_detail_sheet.dart';

/// Screen 3 — Instant result checker.
///
/// The entire point of this screen is that `Check` is one tap and one second,
/// while the official site is on its third 504. It never opens a PDF to answer
/// "am I selected?" — it answers from a 150 KB index with a binary search.
class InstantResultCheckerScreen extends ConsumerStatefulWidget {
  const InstantResultCheckerScreen({super.key});

  @override
  ConsumerState<InstantResultCheckerScreen> createState() =>
      _InstantResultCheckerScreenState();
}

class _InstantResultCheckerScreenState
    extends ConsumerState<InstantResultCheckerScreen> {
  late final TextEditingController _roll = TextEditingController(
    text: _initialRoll(),
  );

  /// Which saved card this screen is checking.
  ///
  /// Previously the screen always used `cards.first`, so a student with two
  /// admit cards could only ever check the one with the earliest exam date, with
  /// no way to switch. Null means "not chosen yet" and falls back to the first.
  String? _cardId;

  /// Which card the roll field was auto-filled from, so the prefill happens
  /// once per card and never fights a field the student cleared on purpose.
  String? _prefilledFor;

  /// A roll rejected by the pre-flight plausibility check in [_check], before
  /// any network. Renders the same [_InvalidRollCard] the engine's post-fetch
  /// rejection would — minus the 12 MB download that rejection cost first.
  String? _localInvalidMessage;

  /// The detail sheet's open guard: the modal barrier appears a frame after the
  /// call, so a fast double tap on "Notice details" used to stack two sheets.
  final _detailGuard = SheetOpenGuard();

  String _initialRoll() {
    final card = _targetCard(ref.read(admitCardsProvider).value, null);
    return card?.rollNumber ?? '';
  }

  @override
  void initState() {
    super.initState();
    _roll.addListener(_onRollEdited);
  }

  /// A pre-flight rejection describes the field's text at the moment Check was
  /// tapped. Once the student edits the number, drop the card rather than keep
  /// scolding a roll that has already been fixed.
  void _onRollEdited() {
    if (_localInvalidMessage == null) return;
    final text = _roll.text.trim();
    if (text.isEmpty || RollIndexEngine.isPlausibleRoll(text)) {
      setState(() => _localInvalidMessage = null);
    }
  }

  /// Keeps the form pointing at the card the user chose elsewhere.
  ///
  /// The screen lives in an `IndexedStack`, so it is built once at launch — long
  /// before any card exists. Vault's "Check my result" then sets
  /// `selectedCardIdProvider` and switches tab, and without this the field stayed
  /// empty and the header described the wrong exam.
  void _syncWithSelectedCard(AdmitCard? card) {
    if (card == null) return;
    if (_cardId == card.id && _roll.text.isNotEmpty) return;
    _cardId = card.id;
    // The field's contents now belong to this card — record the ownership so
    // the cold-start prefill does not fire again for it and the stale-roll
    // guard knows whose number the field holds.
    _prefilledFor = card.id;
    if (card.rollNumber.isNotEmpty) _roll.text = card.rollNumber;
    // A verdict computed for the *previous* card must not survive the switch:
    // the card below only gates on exam id, and two saved cards can share an
    // exam — a stale NOT FOUND under a new roll reads as "this roll failed".
    // `_selectCard` resets for the same reason; this path forgot to.
    _localInvalidMessage = null;
    ref.read(resultCheckerProvider.notifier).reset();
  }

  @override
  void dispose() {
    _roll.dispose();
    super.dispose();
  }

  /// The published index version for [examId], from whatever the feed knows.
  String? _indexVersionFor(String examId) {
    final feed = ref.read(liveFeedProvider).value?.feed;
    if (feed == null) return null;
    for (final u in feed.updates) {
      if (u.examId == examId) return u.indexVersion;
    }
    return null;
  }

  /// The feed row for the card being checked, so the header and mirror panel can
  /// show "published" instead of "no list yet" when a list does exist.
  LiveUpdate? _updateForCard(AdmitCard? card) {
    final feed = ref.watch(liveFeedProvider).value?.feed;
    if (feed == null || card == null) return null;
    for (final u in feed.updates) {
      if (u.examId == card.examId) return u;
    }
    return null;
  }

  AdmitCard? _targetCard(
    List<AdmitCard>? cards,
    AdmitCard? fallback, {
    String? chosenId,
  }) {
    if (cards == null || cards.isEmpty) return fallback;
    final update = ref.read(resultExamIdProvider);
    if (update != null) {
      for (final c in cards) {
        if (c.examId == update.examId) return c;
      }
    }
    // An explicit choice — from the picker here, or from Vault's "Check my
    // result" — outranks "whichever card sorts first".
    for (final id in [_cardId, chosenId]) {
      if (id == null) continue;
      for (final c in cards) {
        if (c.id == id) return c;
      }
    }
    return cards.first;
  }

  void _selectCard(AdmitCard card) {
    setState(() {
      _cardId = card.id;
      // A different card invalidates a pre-flight rejection of the old text.
      _localInvalidMessage = null;
    });
    // Publish the choice. `selectedCardIdProvider` is the screen's other input
    // (the vault pager writes it on every swipe) and the build syncs *from* it
    // whenever it disagrees with `_cardId` — so a pick made only locally was
    // reverted one frame later, snapping the chip back and overwriting the roll
    // field. Writing both keeps the two sources agreeing.
    ref.read(selectedCardIdProvider.notifier).select(card.id);
    // The roll field belongs to the chosen card; leaving another card's roll in
    // place would search the wrong number against the wrong list.
    if (card.rollNumber.isNotEmpty) {
      _roll.text = card.rollNumber;
    }
    ref.read(resultCheckerProvider.notifier).reset();
  }

  Future<void> _check(AdmitCard? card, {bool force = false}) async {
    final roll = _roll.text.trim();
    if (roll.length < 4) {
      _showToast('Enter your roll number first.');
      return;
    }

    // Reject an implausible roll *before* the fetch, not after. The engine has
    // always rejected >24-char input — but only inside `searchCompressed`,
    // i.e. after `repo.load()` downloaded and gunzipped up to 12 MB of index
    // to be told "invalid". The field's maxLength stops typed/pasted input;
    // this stops everything else, with zero network on this path.
    if (!RollIndexEngine.isPlausibleRoll(roll)) {
      FocusScope.of(context).unfocus();
      setState(() {
        _localInvalidMessage = RollLookupResult.invalid(roll).errorMessage;
      });
      return;
    }
    if (_localInvalidMessage != null) {
      setState(() => _localInvalidMessage = null);
    }

    FocusScope.of(context).unfocus();

    final update = ref.read(resultExamIdProvider);
    final examId = update?.examId ?? card?.examId;
    if (examId == null) {
      _showToast('Pick an exam first — add an admit card or tap a result.');
      return;
    }

    // The index lives at a content-addressed URL, so the version must be sent.
    // Resolve it fresh from the feed on *every* check, ahead of the tapped
    // radar row's copy: the row is a frozen snapshot, while the feed repolls
    // every 60s. When the commission publishes a corrected list, the feed
    // carries the new indexVersion but the tapped object keeps the old one —
    // trusting the snapshot searched the pre-correction list for the whole
    // process lifetime and reported "not in this list" for a roll the
    // corrected list contains. Old versioned URLs stay valid on the immutable
    // edge, so the stale fetch does not even 404 and self-heal. The tapped row
    // remains the source of examId/examName; its version is only a fallback
    // for the window before the feed has loaded.
    final indexVersion =
        _indexVersionFor(examId) ??
        (update?.examId == examId ? update?.indexVersion : null);

    // `force` must actually travel: "Try again" on the unavailable card passes
    // force: true to escape the session's memoised 404/malformed bundle, and it
    // was silently dropped here — every retry re-decoded the same bad bytes.
    final result = await ref
        .read(resultCheckerProvider.notifier)
        .check(
          examId: examId,
          rollNumber: roll,
          indexVersion: indexVersion,
          force: force,
        );

    if (!mounted || result == null) return;

    // Announce the outcome for screen readers: without this the flow is silent.
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        result.isFound
            ? 'Roll ${result.rollNumber} is in the published list.'
            : result.state == RollLookupState.notFound
            ? 'Roll ${result.rollNumber} was not found in the published list.'
            : (result.errorMessage ?? 'Could not check your result.'),
        Directionality.of(context),
      ),
    );

    // Touch feedback at the moment the answer lands.
    //
    // Fire-and-forget on purpose: awaiting a haptic puts the platform channel on
    // the critical path between "answer known" and "answer shown", and if the
    // platform never replies the dialog never opens.
    unawaited(result.isFound ? EvHaptics.success() : EvHaptics.failure());

    if (result.isFound) {
      // Only the card whose *own* roll was found may be stamped verified. The
      // field is freely editable — a student checking a sibling's roll (or a
      // mistyped one that happens to exist) must not print a permanent
      // "VERIFIED" onto a card whose roll was never matched.
      //
      // Compare normalised, not raw: the engine searches `normaliseRoll(input)`
      // (trimmed, upper-cased), so a student who typed their own roll in
      // lowercase got the celebration but the raw `==` refused the stamp. And
      // require exam identity: a found verdict computed against a *tapped radar
      // row's* exam says nothing about this card's exam, even when the roll
      // text matches — stamping there certifies the wrong list.
      final ownRoll =
          card != null &&
          examId == card.examId &&
          normaliseRoll(roll) == normaliseRoll(card.rollNumber);
      // A bookkeeping update must never swallow the answer. If marking the card
      // verified fails, the student still needs to see that their roll is in the
      // list — that is the entire product.
      if (ownRoll) {
        try {
          await ref.read(admitCardsProvider.notifier).markVerified(card.id);
        } catch (e, st) {
          AppLogger.e('checker', 'could not mark card verified', e, st);
        }
      }
      if (!mounted) return;
      // The celebration belongs on the checker. `showDialog` uses the root
      // navigator, so a student who switched tabs while the check was in
      // flight used to get the "you are through" modal dropped over whatever
      // screen they had landed on — or stacked on top of a sheet they had
      // already opened. The FOUND badge in "Your check" keeps the verdict on
      // this screen either way, so skipping silently loses nothing.
      final onCheckerTab = ref.read(tabIndexProvider) == EvTab.radar;
      final nothingAbove = ModalRoute.of(context)?.isCurrent ?? true;
      if (onCheckerTab && nothingAbove) {
        await _showSelectedDialog(
          result,
          card,
          examName: update?.examName ?? card?.examName,
        );
      }
    }
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: context.type.label.copyWith(color: Colors.white),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.ev;
    final cards = ref.watch(admitCardsProvider).value;
    final state = ref.watch(resultCheckerProvider);
    final tapped = ref.watch(resultExamIdProvider);

    // A card chosen from the vault takes precedence over "the first card".
    final chosenId = ref.watch(selectedCardIdProvider);
    final card = _targetCard(cards, null, chosenId: chosenId);
    if (chosenId != null && chosenId != _cardId) {
      final chosen = cards?.where((c) => c.id == chosenId).firstOrNull;
      if (chosen != null) {
        // Deferred: mutating controllers during build trips assertions in debug.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() => _syncWithSelectedCard(chosen));
        });
      }
    }

    // Cold-start prefill. The controller's `text: _initialRoll()` ran during the
    // launch build, when the vault was still loading, so it always resolved to
    // '' — and with exactly one saved card the picker is hidden, leaving no way
    // to fill the field except retyping a roll the app already has. Fill it once
    // per card, but only while the student has not typed anything.
    if (card != null && _prefilledFor != card.id && _roll.text.isEmpty) {
      final prefillId = card.id;
      final prefillRoll = card.rollNumber;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _prefilledFor = prefillId;
          if (_roll.text.isEmpty && prefillRoll.isNotEmpty) {
            _roll.text = prefillRoll;
            // Record *ownership*, not just content. The stale-roll guard below
            // keys on which card the field belongs to, and the cold-start
            // prefill is the app's primary flow — without this, `_cardId`
            // stayed null until an explicit pick, the guard was dead code on
            // that flow, and a later tapped radar row searched this card's
            // roll against the other exam's list.
            _cardId = prefillId;
          }
        });
      });
    }

    // Resolve the exam from something real: the radar row the user tapped, or
    // their own saved card, or an explicit pick. Never a hardcoded default — the
    // screen used to search the SSC CGL index for anybody with an empty vault.
    //
    // A saved card also has a matching feed row when the commission has published
    // something for it; using that row means the header, the mirror panel and the
    // official link all describe the published result rather than the typed name.
    final update = tapped ?? _updateForCard(card);
    final examName = tapped?.examName ?? card?.examName;
    final examId = tapped?.examId ?? card?.examId;

    // Clear a roll that belongs to a different exam.
    //
    // Tapping a radar row for exam B while a saved exam-A card existed left A's
    // roll in the field, the header saying B, and "YOUR CHECK" showing A. One tap
    // on Check then searched A's roll against B's list and could report "not in
    // this list" — the worst possible wrong answer.
    //
    // The owner is `_cardId ?? _prefilledFor`: the cold-start prefill fills the
    // field before any explicit pick, and a card whose roll number is empty
    // records only `_prefilledFor` — the guard must know the field's card in
    // both shapes, or it is dead on exactly the flow every cold start takes.
    final fieldOwnerId = _cardId ?? _prefilledFor;
    if (tapped != null && fieldOwnerId != null) {
      final fieldCard = cards?.where((c) => c.id == fieldOwnerId).firstOrNull;
      // Only clear when the field still holds *that card's* number — never a
      // value the student typed by hand.
      final stale =
          fieldCard != null &&
          fieldCard.examId != tapped.examId &&
          _roll.text == fieldCard.rollNumber;
      if (stale) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _roll.clear();
          ref.read(resultCheckerProvider.notifier).reset();
        });
      }
    }

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _NavBar(update: update),
            Padding(
              // On a 320x568 screen the primary CTA landed under the tab bar on
              // first paint. The content does scroll, but an exam-morning user
              // should not have to discover that, so a short viewport tightens the
              // vertical rhythm until the button clears the bar.
              padding: EdgeInsets.fromLTRB(
                EvSpace.gutter,
                MediaQuery.sizeOf(context).height < 700 ? 6 : 14,
                EvSpace.gutter,
                0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // No "SSC" fallback: with nothing selected the screen used to
                  // label itself SSC, which is a claim about the exam the user has
                  // not made. Blank is honest; the title below asks the question.
                  Text(
                    (update?.category.label ?? card?.category.label ?? '')
                        .toUpperCase(),
                    style: context.type.microLabel.copyWith(letterSpacing: 1.7),
                  ),
                  const SizedBox(height: 6),
                  _TitleWithAccent(examName: examName),
                  if (update != null || card != null) ...[
                    const SizedBox(height: 4),
                    // The aggregator-site question a radar row cannot answer:
                    // when, how many posts, what fee, where to apply.
                    Align(
                      alignment: Alignment.centerLeft,
                      child: EvTextAction(
                        label: 'Notice details',
                        icon: Icons.open_in_new_rounded,
                        onPressed: () => _detailGuard.run<void>(
                          () => showExamDetailSheet(
                            context,
                            update: update,
                            card: card,
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  // Shown whenever there is more than one card — *including*
                  // while an exam is resolved. It used to hide the moment any
                  // update existed (tapped row OR the card's own feed row),
                  // which made a mismatch uncorrectable: when no saved card
                  // matches the tapped row's exam, the header follows the row
                  // while the resolved card belongs to a different exam, and
                  // with no chips on screen there was no way to pick the card
                  // that actually matches. The header still follows the tapped
                  // row; the picker just stays reachable.
                  if (cards != null && cards.length > 1) ...[
                    const SizedBox(height: 10),
                    const EvSectionHeader(
                      label: 'Which card?',
                      padding: EdgeInsets.zero,
                    ),
                    const SizedBox(height: 6),
                    _CardPicker(
                      cards: cards,
                      selectedId: card?.id,
                      onSelect: _selectCard,
                    ),
                  ],
                  _MirrorCard(
                    indexSource: state.indexSource,
                    observedLatencyMs: update?.mirrorLatencyMs,
                    publishedForExam: update?.hasIndex ?? false,
                  ),
                  const SizedBox(height: 8),
                  _RetryNote(state: state, rollCount: update?.rollCount),
                  const SizedBox(height: 14),
                  _RollField(
                    controller: _roll,
                    busy: state.isBusy,
                    onSubmitted: () => _check(card),
                  ),
                  const SizedBox(height: 10),
                  EvPrimaryButton(
                    label: state.isBusy
                        ? 'Checking…'
                        : 'Check my result instantly',
                    icon: state.isBusy ? null : Icons.bolt_rounded,
                    busy: state.isBusy,
                    enabled: examId != null,
                    onPressed: examId == null ? null : () => _check(card),
                  ),
                  if (examId == null) ...[
                    const SizedBox(height: 8),
                    // "Tap a result on the Radar tab" was wrong twice over: this
                    // *is* the Radar tab, and the live list is on Home. Advice
                    // that points at the screen you are already on reads as a bug.
                    Text(
                      'Add an admit card, or open a result from Home. We will not '
                      'guess which exam to search.',
                      style: context.type.bodyMuted.copyWith(),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: EvTextAction(
                        label: 'See live results',
                        icon: Icons.arrow_forward_rounded,
                        onPressed: () => ref
                            .read(tabIndexProvider.notifier)
                            .select(EvTab.home),
                      ),
                    ),
                  ],
                  // We open the commission's own PDF rather than a copy of it.
                  // Re-hosting a government result document is exactly the kind
                  // of redistribution this app must not do, and it also means a
                  // corrected PDF upstream is immediately the one users see.
                  if (update?.officialUrl != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: EvSecondaryButton(
                            label: update!.officialPdf != null
                                ? 'Official PDF'
                                : 'Official site',
                            icon: update.officialPdf != null
                                ? Icons.picture_as_pdf_outlined
                                : Icons.account_balance_outlined,
                            onPressed: () => _openUrl(update.officialUrl!),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: EvSecondaryButton(
                            label: 'Copy link',
                            icon: Icons.link_rounded,
                            onPressed: () => ClipboardService.copy(
                              context,
                              value: update.officialUrl!,
                              label: 'Official result link',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.open_in_new_rounded,
                          size: 11,
                          color: p.textTertiary,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            'Opens the notice on the commission\'s own site — '
                            'we never host a copy of it.',
                            style: context.type.bodyMuted.copyWith(),
                          ),
                        ),
                      ],
                    ),
                  ],
                  // A verdict belongs to the exam it was computed for. Without
                  // this guard, tapping a second radar row re-rendered the first
                  // exam's "Roll N was not found among M published roll numbers"
                  // under the new exam's title — which reads as "you failed B".
                  //
                  // A pre-flight rejection renders *instead* of any stored
                  // verdict: nothing was searched for the text now in the field,
                  // so a neighbouring stored card would describe older input.
                  if (_localInvalidMessage != null) ...[
                    const SizedBox(height: 16),
                    _InvalidRollCard(message: _localInvalidMessage),
                  ] else if (examId != null && state.belongsTo(examId)) ...[
                    if (state.phase == ResultPhase.done &&
                        state.result != null &&
                        !state.result!.isFound) ...[
                      const SizedBox(height: 16),
                      // A rejected roll number is a *validation* state, not a
                      // verdict. It used to render "not found among 0 published
                      // roll numbers" — contradicting the mirror panel's real
                      // count and claiming a list was searched when it was not.
                      if (state.result!.state == RollLookupState.invalidInput)
                        _InvalidRollCard(message: state.result!.errorMessage)
                      else
                        _NotFoundCard(result: state.result!),
                    ],
                    if (state.isUnavailable) ...[
                      const SizedBox(height: 16),
                      _UnavailableCard(
                        message: state.error,
                        onRetry: () => _check(card, force: true),
                      ),
                    ],
                    const SizedBox(height: 22),
                    _RecentChecks(
                      card: card,
                      lastResult: state.result,
                      indexSource: state.indexSource,
                    ),
                  ],
                  SizedBox(height: EvChrome.bottomInset(context)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      _showToast('Could not open the PDF. Check your connection.');
    }
  }

  Future<void> _showSelectedDialog(
    RollLookupResult result,
    AdmitCard? card, {
    String? examName,
  }) async {
    HapticFeedback.heavyImpact();

    await showDialog<void>(
      context: context,
      // The purpose-built theme token, not a hardcoded black at 0.72: `scrim`
      // is tuned per palette (light mode dims with a lighter navy veil), and
      // the dialog ignored all of it.
      barrierColor: context.scrim,
      builder: (context) => _SelectedDialog(
        result: result,
        card: card,
        examName: examName,
        onShare: () {
          // "Share the news" used to only close the dialog, which is a dead
          // primary CTA: the user taps the loudest button on the screen and
          // nothing happens. It now closes the sheet and lands on Share, where
          // the card is already built from this lookup.
          Navigator.of(context).pop();
          ref.read(tabIndexProvider.notifier).select(EvTab.share);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _NavBar extends ConsumerWidget {
  const _NavBar({this.update});

  /// Typed, not `dynamic`: the field was untyped, which silently accepted any
  /// object and defeated every compile-time check on it.
  final LiveUpdate? update;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ev;
    final isLive = update != null;

    return ConstrainedBox(
      // A floor, not a fixed height. At a fixed 40px this bar squeezed its own
      // 44px icon buttons down to 40, so back/close missed the 44px minimum.
      constraints: const BoxConstraints(minHeight: EvSize.minTapTarget),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
            children: [
              const SizedBox(width: EvSpace.x2),
              EvIconButton(
                icon: Icons.arrow_back_ios_new_rounded,
                ghost: true,
                iconSize: 17,
                tooltip: 'Back to Home',
                // This screen is a tab, not a pushed route, so `maybePop()` did
                // nothing at all — a visible back arrow that ignored every tap.
                onPressed: () =>
                    ref.read(tabIndexProvider.notifier).select(EvTab.home),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(right: EvSpace.x4),
                child: Container(
                  // Floor, not fixed: at a hard 24px the pill sliced its own
                  // label at large text scales. No `alignment:` — inside a Row
                  // that would expand the pill to the row's full width; the
                  // inner min-sized Row fills the minHeight instead.
                  constraints: const BoxConstraints(minHeight: 24),
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  decoration: BoxDecoration(
                    color: (isLive ? p.success : p.textTertiary).withValues(
                      alpha: 0.12,
                    ),
                    borderRadius: BorderRadius.circular(EvRadius.pill),
                    border: Border.all(
                      color: (isLive ? p.success : p.textTertiary).withValues(
                        alpha: 0.3,
                      ),
                    ),
                  ),
                  child: Row(
                    // min — a max-sized Row in loose constraints expands to the
                    // nav bar's full width, the same ballooning `alignment:`
                    // would have caused.
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: isLive ? p.success : p.textTertiary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        isLive ? 'LIVE' : 'READY',
                        style: context.type.statusPill.copyWith(
                          letterSpacing: 1.1,
                          color: isLive ? p.successText : p.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Positioned.fill(
            child: Padding(
              // The centred title and the right-hand pill are independent Stack
              // children: on a 320px screen at 2.0x text they overlapped. The
              // title now owns only the space between back button and pill, and
              // scales down to stay whole.
              padding: const EdgeInsets.symmetric(horizontal: 96),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'Result Radar',
                    maxLines: 1,
                    style: context.type.navTitle,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TitleWithAccent extends StatelessWidget {
  const _TitleWithAccent({required this.examName});

  /// Null when no exam has been chosen: the header then asks the user to pick one
  /// instead of inventing an exam name.
  final String? examName;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;

    if (examName == null) {
      return Text('Which result?', style: context.type.screenTitle);
    }

    // "Result" is always the last word, tinted green. Text.rich (rather than two
    // positioned Texts) wraps correctly at any text scale.
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: examName!.replaceAll(' Result', ''),
            style: context.type.screenTitle,
          ),
          TextSpan(
            text: ' Result',
            style: context.type.screenTitle.copyWith(color: p.success),
          ),
        ],
      ),
      // Without `ellipsis` a long official headline is clipped mid-word with no
      // indication — "… LDCE-2025 and" reads like a broken layout rather than a
      // truncated title.
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Horizontal chooser for the saved card being checked.
///
/// Only shown once there is more than one card — a picker with a single option is
/// noise, and the empty state already explains how to get here.
class _CardPicker extends StatelessWidget {
  const _CardPicker({
    required this.cards,
    required this.selectedId,
    required this.onSelect,
  });

  final List<AdmitCard> cards;
  final String? selectedId;
  final ValueChanged<AdmitCard> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: EvSize.minTapTarget,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cards.length,
        separatorBuilder: (_, _) => const SizedBox(width: 7),
        itemBuilder: (context, i) {
          final card = cards[i];
          return EvChip(
            label: card.examCode.isNotEmpty ? card.examCode : card.examName,
            selected: card.id == selectedId,
            onTap: () => onSelect(card),
          );
        },
      ),
    );
  }
}

/// Shows where the answer comes from, using only values we actually observed.
///
/// Earlier this widget hardcoded `upsc.gov.in` / `1,204ms` regardless of the exam
/// being checked, which is both wrong and misleading — it invented a latency
/// number for a server the app never contacted.
class _MirrorCard extends StatelessWidget {
  const _MirrorCard({
    this.indexSource,
    this.observedLatencyMs,
    this.publishedForExam = false,
  });

  final IndexSource? indexSource;

  /// Measured round-trip for the index fetch, when we have one.
  final int? observedLatencyMs;

  /// The feed says this exam has a published index.
  ///
  /// Without this the card read "not published / IDLE" for an exam whose index
  /// was demonstrably on the CDN — it only reflected whether *this session* had
  /// fetched one yet. What we know from the feed is a fact; showing it sooner is
  /// not a guess.
  final bool publishedForExam;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;

    // The observed source wins over the feed's claim. `indexSource` is what
    // this session actually saw on the wire; `publishedForExam` is only what
    // the (up to 60s stale) feed believes. The old `||` let the feed override
    // an observed `IndexSource.unavailable`, painting a green READY
    // "published" row directly above a card saying the index could not be
    // reached or was not published — two contradictory answers on one screen.
    // The feed flag is now a fallback for "nothing observed yet".
    final hasIndex =
        indexSource?.isReal ?? (publishedForExam && indexSource == null);
    final unavailable = indexSource == IndexSource.unavailable;

    final rows = <_MirrorRow>[
      _MirrorRow(
        name: 'Edge CDN index',
        // Kept short on purpose: this cell is ~120px wide beside a state badge,
        // and a longer sentence is silently truncated to "not published for …".
        sub: hasIndex ? 'published' : 'no list yet',
        state: hasIndex ? 'READY' : (unavailable ? 'MISSING' : 'IDLE'),
        color: hasIndex
            ? p.success
            : (unavailable ? p.warning : p.textTertiary),
        textColor: hasIndex
            ? p.successText
            : (unavailable ? p.warningText : p.textTertiary),
        fill: hasIndex ? 0.28 : 0.06,
        value: observedLatencyMs != null
            ? '${observedLatencyMs}ms'
            : (hasIndex ? 'on demand' : '—'),
      ),
      _MirrorRow(
        name: 'Binary search',
        sub: 'on device',
        state: hasIndex ? 'READY' : 'IDLE',
        color: p.accent,
        textColor: p.accentText,
        fill: hasIndex ? 0.10 : 0.05,
        value: '<1ms',
      ),
    ];

    return EvCard(
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 6),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text('MIRROR STATUS', style: context.type.microLabel),
              ),
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: p.success,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              // Flexible + ellipsis: this label is fixed-size chrome beside a
              // flexible title, so at large text it pushed the row 115px past
              // the card.
              Flexible(
                child: Text(
                  'AUTO-REFRESH 60s',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: context.type.statusPill.copyWith(
                    color: p.successText,
                    letterSpacing: 0.9,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Container(height: 1, color: context.hairline),
            _MirrorRowView(row: rows[i]),
          ],
        ],
      ),
    );
  }
}

class _MirrorRow {
  const _MirrorRow({
    required this.name,
    required this.sub,
    required this.state,
    required this.color,
    required this.textColor,
    required this.fill,
    required this.value,
  });

  final String name;
  final String sub;
  final String state;
  final Color color;
  final Color textColor;
  final double fill;
  final String value;
}

class _MirrorRowView extends StatelessWidget {
  const _MirrorRowView({required this.row});

  final _MirrorRow row;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;

    return ConstrainedBox(
      // A floor, not a ceiling: the fixed 46px row clipped its own contents
      // once text scale pushed the badges past it.
      constraints: const BoxConstraints(minHeight: 46),
      child: Row(
        children: [
          Expanded(
            // The subtitle is context ("published", "on device"), not a value —
            // it used to be appended inline and truncated to "…" on a 320px
            // screen, leaving a row that said nothing. It now drops entirely
            // rather than dying mid-word, and the state badge already carries the
            // information it was repeating.
            child: LayoutBuilder(
              builder: (context, box) => RichText(
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: row.name,
                      style: context.type.label.copyWith(
                        color: p.textPrimary,
                        fontSize: 12,
                      ),
                    ),
                    if (row.sub.isNotEmpty && box.maxWidth > 140)
                      TextSpan(
                        text: '  ${row.sub}',
                        style: context.type.bodyMuted.copyWith(),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Container(
            width: 52,
            height: 4,
            decoration: BoxDecoration(
              color: p.surfaceSunken,
              borderRadius: BorderRadius.circular(2),
            ),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: row.fill,
              child: Container(
                decoration: BoxDecoration(
                  color: row.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Wide enough for "MISSING" on one line at 1.0x: at 42px it broke into
          // "MISSI / NG", which reads as broken chrome on the panel whose whole
          // job is to look trustworthy. Never wraps — and now *actually*
          // shrinks: the cells used `TextOverflow.visible`, which paints outside
          // the box (at 2.0x the badge overran the progress bar); the FittedBox
          // scales the text down inside its allotted width instead.
          SizedBox(
            width: 58,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                row.state,
                maxLines: 1,
                softWrap: false,
                style: context.type.statusPill.copyWith(color: row.textColor),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 62,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                row.value,
                maxLines: 1,
                softWrap: false,
                style: context.type.monoMeta.copyWith(color: p.textTertiary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RetryNote extends StatelessWidget {
  const _RetryNote({required this.state, this.rollCount});

  final ResultCheckState state;

  /// Candidates in the published list, when the feed says. Used instead of a
  /// hardcoded "12,000+" — that number was invented and was wrong for every
  /// exam in the feed.
  final int? rollCount;

  /// True when the failure was transport, not absence. Mirrors the vocabulary
  /// of `_UnavailableCard._describe`: every connection-flavoured reason the
  /// repository, the CDN client and the notifier can emit contains one of
  /// these ('Could not reach…', '…connection…', 'Request timed out').
  static bool _isConnectionError(String? error) {
    final e = (error ?? '').toLowerCase();
    return e.contains('reach') ||
        e.contains('connection') ||
        e.contains('timed out');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.ev;
    final count = rollCount == null ? null : _thousands(rollCount!);

    final label = switch (state.phase) {
      ResultPhase.downloading => 'Fetching the published index…',
      ResultPhase.searching =>
        count == null
            ? 'Searching on this device…'
            : 'Searching $count roll numbers on this device…',
      ResultPhase.done =>
        state.indexSource == IndexSource.unavailable
            ? 'No published index for this exam yet — the official PDF is the '
                  'only source right now.'
            : 'Checked against the published list. Your roll number was never '
                  'sent anywhere.',
      // The card below says why in full. Repeating it here as a one-liner made
      // the screen state the same sentence twice, ten pixels apart — but the
      // one-liner must not *contradict* the card either: it claimed "No index
      // to search yet." even for a pure transport failure whose card says
      // "Could not reach the result index". Nothing-published and
      // cannot-reach are different faults with different remedies.
      ResultPhase.unavailable =>
        _isConnectionError(state.error)
            ? 'Retry when you are back online.'
            : 'No index to search yet.',
      ResultPhase.idle =>
        count == null
            ? 'One small index instead of a multi-megabyte PDF.'
            : '$count roll numbers, fetched once. Not the multi-megabyte PDF.',
    };

    return Row(
      children: [
        Icon(Icons.auto_awesome_rounded, size: 11, color: p.textTertiary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            // Three lines with an ellipsis: two lines cut the sentence mid-word
            // ("...multi-megab") at 1.35x and above.
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: context.type.bodyMuted.copyWith(),
          ),
        ),
      ],
    );
  }
}

class _RollField extends StatelessWidget {
  const _RollField({
    required this.controller,
    required this.busy,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final bool busy;

  /// Pressing the keyboard's search key runs the check — previously Enter did
  /// nothing, which is the second thing every user tries.
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        return Container(
          height: 56,
          padding: const EdgeInsets.only(left: 14, right: 6),
          decoration: BoxDecoration(
            color: p.surfaceSunken,
            borderRadius: BorderRadius.circular(EvRadius.button),
            border: Border.all(color: p.borderStrong),
          ),
          child: Row(
            children: [
              Icon(Icons.search_rounded, size: 17, color: p.textTertiary),
              const SizedBox(width: 9),
              Expanded(
                // The field was 20px tall inside a 56px row: only the text line
                // could be tapped to focus it, not the visible box.
                child: SizedBox(
                  height: EvSize.minTapTarget,
                  child: TextField(
                    // Named so tests (and future automation) can target the roll
                    // field unambiguously — the Home screen now also has a search
                    // TextField, and "the first TextField" is no longer this one.
                    key: const ValueKey('roll-field'),
                    controller: controller,
                    enabled: !busy,
                    autocorrect: false,
                    enableSuggestions: false,
                    textCapitalization: TextCapitalization.characters,
                    keyboardType: TextInputType.visiblePassword,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) {
                      if (!busy) onSubmitted?.call();
                    },
                    // Hard cap at the engine's plausibility ceiling. Without it
                    // a 40-char paste was accepted, and the rejection only
                    // arrived *after* the index (up to 12 MB) had been
                    // downloaded and gunzipped. The counter is suppressed:
                    // "n/24" is chrome noise inside this 56px field, and the
                    // pre-flight card in _check explains any rejection.
                    maxLength: 24,
                    buildCounter:
                        (
                          _, {
                          required int currentLength,
                          required bool isFocused,
                          int? maxLength,
                        }) => null,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[A-Za-z0-9\-/]'),
                      ),
                    ],
                    style: context.type.fieldValue.copyWith(fontSize: 15),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      hintText: 'Roll number',
                      hintStyle: context.type.bodyMuted.copyWith(
                        fontSize: 13,
                        letterSpacing: 0,
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ),
              if (value.text.isNotEmpty)
                // EvIconButton, not a bare IconButton: the M3 default is 40px,
                // under the 44px floor, and the ghost variant matches the nav
                // bar's icon language.
                EvIconButton(
                  icon: Icons.cancel_rounded,
                  ghost: true,
                  iconSize: 16,
                  iconColor: p.textTertiary,
                  tooltip: 'Clear',
                  onPressed: busy ? null : controller.clear,
                ),
            ],
          ),
        );
      },
    );
  }
}

/// The roll number itself was rejected — a validation state, not a verdict.
///
/// Distinct from [_NotFoundCard] on purpose: nothing was searched, and saying
/// "not found among 0 roll numbers" both contradicts the mirror panel's real
/// count and reads as a failed exam result.
class _InvalidRollCard extends StatelessWidget {
  const _InvalidRollCard({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(EvRadius.card),
        border: Border.all(color: p.warning.withValues(alpha: 0.26)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.backspace_rounded, size: 16, color: p.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Check the roll number',
                  style: context.type.tileTitle.copyWith(color: p.warningText),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            message ??
                'Roll numbers are 4–24 characters: letters, digits, - and /. '
                    'Nothing was searched yet.',
            style: context.type.bodyMuted,
          ),
        ],
      ),
    );
  }
}

class _NotFoundCard extends StatelessWidget {
  const _NotFoundCard({required this.result});
  final RollLookupResult result;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(EvRadius.card),
        border: Border.all(color: p.warning.withValues(alpha: 0.26)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.hourglass_bottom_rounded, size: 16, color: p.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Not in this list yet',
                  style: context.type.tileTitle.copyWith(color: p.warningText),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Roll ${result.rollNumber} was not found among ${_format(result.totalRolls)} published roll numbers. '
            'That could mean a different list (Tier-2, region-wise), or that your result is still being uploaded.',
            style: context.type.bodyMuted,
          ),
          const SizedBox(height: 4),
          Text(
            'Searched in ${(result.elapsedMicros / 1000).toStringAsFixed(1)} ms on this device.',
            style: context.type.monoMeta,
          ),
          if (result.privacyPreserving) ...[
            const SizedBox(height: 8),
            _HashedNote(
              text:
                  'Compared as a one-way hash — the candidate list itself never '
                  'reaches your phone.',
            ),
          ],
        ],
      ),
    );
  }

  static String _format(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

class _UnavailableCard extends StatelessWidget {
  const _UnavailableCard({this.message, this.onRetry});

  final String? message;

  /// Retries the lookup. The card told the user to "tap check again" while the
  /// failed fetch was memoised for the session, so the instruction was a no-op.
  final VoidCallback? onRetry;

  /// Three very different faults — nothing published, our network, a bad
  /// payload — used to be reported with one heading ("Result not published yet")
  /// and one body, sending the student to the wrong place (or showing them a Dart
  /// exception string).
  ({String title, String body, bool retryable}) _describe() {
    final reason = (message ?? '').toLowerCase();

    if (reason.contains('connection') ||
        reason.contains('reach') ||
        reason.contains('timeout') ||
        reason.contains('network')) {
      return (
        title: 'Could not reach the result index',
        body:
            'This is usually a weak connection. Try again — nothing was lost.',
        retryable: true,
      );
    }
    if (reason.contains('malformed') || reason.contains('format')) {
      return (
        title: 'The published index could not be read',
        body:
            'That is a fault on our side, not a result. We will fix it; the '
            'official PDF is still the source of truth.',
        retryable: true,
      );
    }
    // 'not been published' is not a typo-variant of 'not published' — it is
    // what the repository actually emits for a 404 ('The result for this exam
    // has not been published yet.'), and `contains('not published')` does not
    // match it. The honest branch was therefore unreachable: a genuinely
    // unpublished exam fell through to the generic 'Could not check this exam'
    // plus a 'Try again' that just 404'd again.
    if (reason.contains('not published') ||
        reason.contains('not been published') ||
        reason.contains('not found') ||
        reason.isEmpty) {
      return (
        title: 'Result not published yet',
        body:
            'The commission has not published a candidate list for this exam. '
            'When it does, we index it on the next refresh.',
        retryable: false,
      );
    }
    return (
      title: 'Could not check this exam',
      body: 'Please try again in a moment.',
      retryable: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.ev;
    final d = _describe();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(EvRadius.card),
        border: Border.all(color: p.warning.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.hourglass_empty_rounded, size: 16, color: p.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  d.title,
                  style: context.type.tileTitle.copyWith(color: p.warningText),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(d.body, style: context.type.bodyMuted),
          if (d.retryable && onRetry != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: EvSize.minTapTarget,
              child: Align(
                alignment: Alignment.centerLeft,
                child: EvTextAction(
                  label: 'Try again',
                  icon: Icons.refresh_rounded,
                  onPressed: onRetry,
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 6),
            Text(
              'We never show a result we cannot verify.',
              style: context.type.microLabel,
            ),
          ],
        ],
      ),
    );
  }
}

class _RecentChecks extends StatelessWidget {
  const _RecentChecks({required this.card, this.lastResult, this.indexSource});

  final AdmitCard? card;
  final RollLookupResult? lastResult;
  final IndexSource? indexSource;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;
    if (card == null) return const SizedBox.shrink();

    // Three states, not two. "NOT CHECKED" under a completed not-found verdict
    // contradicted the card directly above it ("searched 10,066 rolls, not
    // found") — a finished search *is* a check. NOT FOUND only applies when the
    // verdict was about this card's own roll and the search really ran.
    final result = lastResult;
    final aboutThisRoll =
        result != null &&
        // The engine returns the *normalised* roll; compare the card's number
        // through the same normalisation so a lowercase-stored card does not
        // lose its badge to a case mismatch.
        result.rollNumber == normaliseRoll(card!.rollNumber) &&
        result.state != RollLookupState.invalidInput;
    final notFound = aboutThisRoll && result.state == RollLookupState.notFound;
    // FOUND must respect roll identity exactly like the NOT FOUND arm does:
    // `verified` used to OR-in *any* found result, so checking a sibling's
    // roll printed FOUND on this card — a claim about a number that was never
    // searched. Only the durable flag (stamped by markVerified under strict
    // roll + exam identity) or a found verdict about this card's own roll
    // earns the badge.
    final verified =
        card!.rollNumberVerified || (aboutThisRoll && result.isFound);

    final badgeFg = verified
        ? p.success
        : notFound
        ? p.warning
        : p.textTertiary;
    final badgeText = verified
        ? p.successText
        : notFound
        ? p.warningText
        : p.textTertiary;
    final badgeLabel = verified
        ? 'FOUND'
        : notFound
        ? 'NOT FOUND'
        : 'NOT CHECKED';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EvSectionHeader(
          label: 'Your check',
          padding: EdgeInsets.zero,
          trailing: Text(
            indexSource?.label.toUpperCase() ?? 'NOT RUN',
            style: context.type.microLabel.copyWith(),
          ),
        ),
        const SizedBox(height: 8),
        EvCard(
          padding: const EdgeInsets.symmetric(
            horizontal: EvSpace.x4,
            vertical: 12,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      card!.examName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.type.tileTitle,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Roll ${card!.rollNumber}',
                      style: context.type.monoMeta.copyWith(),
                    ),
                  ],
                ),
              ),
              Container(
                // Floor, not fixed: the hard 20px box sliced the label at large
                // text scales. No `alignment:` — inside a Row that would expand
                // the badge to the row's full width and starve the Expanded
                // beside it; the min-sized Row fills the minHeight and centres.
                constraints: const BoxConstraints(minHeight: 20),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeFg.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(EvRadius.badge),
                  border: Border.all(color: badgeFg.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      badgeLabel,
                      maxLines: 1,
                      style: context.type.statusPill.copyWith(color: badgeText),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// The celebration
// ---------------------------------------------------------------------------

class _SelectedDialog extends StatelessWidget {
  const _SelectedDialog({
    required this.result,
    this.card,
    this.examName,
    this.onShare,
  });

  final RollLookupResult result;
  final AdmitCard? card;

  /// The exam this answer belongs to. Null only if the caller genuinely does not
  /// know — the dialog then says so rather than inventing a name.
  final String? examName;

  /// Takes the user to the share sheet. Null only in previews/tests.
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;

    return Dialog(
      backgroundColor: Colors.transparent,
      // Vertical insets too: with only horizontal padding the dialog could
      // claim the full screen height and still overflow it at 2.0x text on a
      // 320x568 phone — the one celebration moment that must not show
      // yellow-and-black stripes.
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: TweenAnimationBuilder<double>(
        // 0.94 -> 1 with an 8px rise, no overshoot. The old 0.86 pop on
        // `easeOutBack` overshot past 100% — the wrong tone for the moment a
        // student learns they got through.
        tween: Tween(begin: 0, end: 1),
        duration: EvMotion.of(context, EvMotion.reveal),
        curve: EvMotion.curveOf(context, EvMotion.enter),
        builder: (context, t, child) => Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 8 * (1 - t)),
            child: Transform.scale(scale: 0.94 + 0.06 * t, child: child),
          ),
        ),
        child: Container(
          // Scrollable, and clipped to its own rounded corners: the fixed
          // Column was taller than a 320x568 viewport at 2.0x text — the
          // dialog overflowed at the exact moment a student learns they got
          // through. Padding moved onto the scroll view so content scrolls
          // inside the decoration instead of over it.
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: p.success.withValues(alpha: 0.35)),
            boxShadow: [
              BoxShadow(
                color: p.success.withValues(alpha: 0.24),
                blurRadius: 48,
                spreadRadius: -8,
              ),
            ],
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        p.success.withValues(alpha: 0.9),
                        p.success.withValues(alpha: 0.55),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: p.success.withValues(alpha: 0.5),
                        blurRadius: 26,
                        spreadRadius: -4,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.emoji_events_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  // Accurate for both cases this screen actually sees: a final
                  // merit list and a shortlist for the next stage (UPSC's "Written
                  // Result … qualified for the Personality Test"). "SELECTED" was
                  // wrong for the second, and wrong here means a student believes
                  // they have the job.
                  'YOUR ROLL IS IN THE LIST',
                  textAlign: TextAlign.center,
                  style: context.type.sectionTitle.copyWith(
                    color: p.successText,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  examName ?? 'Your result',
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.type.bodyMuted,
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: p.surfaceSunken,
                    borderRadius: BorderRadius.circular(EvRadius.inner),
                    border: Border.all(color: p.border),
                  ),
                  child: Column(
                    children: [
                      Text('ROLL NUMBER', style: context.type.microLabel),
                      const SizedBox(height: 4),
                      // Scaled to fit: a 20-character roll at 22px + 2.0 text
                      // scale is wider than the dialog.
                      SizedBox(
                        width: double.infinity,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            result.rollNumber,
                            maxLines: 1,
                            style: context.type.fieldValue.copyWith(
                              fontSize: 22,
                              letterSpacing: 1.6,
                              color: p.textPrimary,
                            ),
                          ),
                        ),
                      ),
                      if (result.hasRank) ...[
                        const SizedBox(height: 8),
                        Text(
                          'MERIT RANK ${result.meritRank}',
                          style: context.type.statusPill.copyWith(
                            color: p.successText,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Found in ${(result.elapsedMicros / 1000).toStringAsFixed(1)} ms '
                  'among ${result.totalRolls} roll numbers.',
                  textAlign: TextAlign.center,
                  style: context.type.microLabel.copyWith(),
                ),
                if (result.privacyPreserving) ...[
                  const SizedBox(height: 8),
                  _HashedNote(
                    align: TextAlign.center,
                    text:
                        'Matched on your device. We never download the official '
                        'candidate list — only one-way hashes of it.',
                  ),
                ],
                const SizedBox(height: 18),
                EvPrimaryButton(
                  label: 'Share the news',
                  icon: Icons.ios_share_rounded,
                  onPressed: onShare ?? () => Navigator.of(context).pop(),
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Close',
                    style: context.type.label.copyWith(color: p.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A one-line statement of the guarantee, shown next to every lookup result.
///
/// It is deliberately factual rather than reassuring: the app cannot prove what
/// the publisher did upstream, but it *can* state what reached the device, and
/// that is what a student worried about their roll number being shared wants to
/// know.
class _HashedNote extends StatelessWidget {
  const _HashedNote({required this.text, this.align = TextAlign.start});

  final String text;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: align == TextAlign.center
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      children: [
        Icon(Icons.lock_outline_rounded, size: 10, color: p.textTertiary),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            textAlign: align,
            style: context.type.microLabel.copyWith(height: 1.5),
          ),
        ),
      ],
    );
  }
}

/// 3507 -> "3,507". Local to this screen; `intl` would be a dependency for one
/// call site.
String _thousands(int n) {
  final digits = n.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

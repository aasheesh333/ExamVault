import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/motion.dart';
import '../../core/theme/theme_tokens.dart';
import '../../data/services/app_logger.dart';
import '../../domain/entities/admit_card.dart';
import '../../domain/entities/exam_category.dart';
import '../../domain/entities/live_update.dart';
import '../../domain/services/exam_matcher.dart';
import '../../providers/app_providers.dart';
import '../../shared/widgets/ev_controls.dart';
import '../result_checker/engine/roll_index_engine.dart';

/// The id the result checker will look the roll index up by.
///
/// A fresh feed match always wins. The stored id is reused only when the exam
/// name is unchanged: renaming "SSC CHSL 2026" to "UPSC CSE 2027" must not pin
/// the old exam's id onto the card, or the checker searches another exam's
/// index and Share prints a verdict for a list this card was never checked
/// against. A renamed card with no published match gets a slug of its new name.
///
/// [previousName] is what makes the reuse possible at all: without it the
/// caller cannot show the name was unchanged, so [previous] is ignored and the
/// typed name is slugged instead.
@visibleForTesting
String resolveExamId({
  required String examName,
  LiveUpdate? match,
  String? previous,
  String? previousName,
}) {
  final fresh = match?.examId;
  if (fresh != null && fresh.isNotEmpty) return fresh;
  final unchanged =
      previousName != null && _sameExamName(previousName, examName);
  if (unchanged && previous != null && previous.isNotEmpty) return previous;
  return slugifyExamName(examName);
}

/// Whether two typed exam names name the same exam.
///
/// Case-insensitive and ignoring leading/trailing whitespace: fixing the case
/// or padding of a name is not a rename, so it must not discard the card's
/// resolved id or VERIFIED. Internal spacing is *not* normalised — only the
/// ends are trimmed, so "SSC CHSL" and "SSC  CHSL" count as different names.
bool _sameExamName(String a, String b) =>
    a.trim().toLowerCase() == b.trim().toLowerCase();

/// Fallback id when nothing has been published for the typed name yet.
@visibleForTesting
String slugifyExamName(String examName) =>
    examName.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');

/// Add / edit an admit card.
///
/// Portal passwords and DOBs are exactly the fields people mistype, so every
/// input here is `TextInputType.visiblePassword`, autocorrect is off, and the
/// secret field is masked by default — a vault screen is often opened in public.
Future<void> showVaultFormSheet(
  BuildContext context,
  WidgetRef ref, {
  AdmitCard? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    // Dragging the sheet down pops the route directly, bypassing PopScope — the
    // unsaved-changes guard only works with the drag-dismiss disabled.
    enableDrag: false,
    builder: (_) => _VaultFormSheet(existing: existing),
  );
}

class _VaultFormSheet extends ConsumerStatefulWidget {
  const _VaultFormSheet({this.existing});

  final AdmitCard? existing;

  @override
  ConsumerState<_VaultFormSheet> createState() => _VaultFormSheetState();
}

class _VaultFormSheetState extends ConsumerState<_VaultFormSheet> {
  final _formKey = GlobalKey<FormState>();

  /// Anchors for the fields that carry a validator, so a failed Save can scroll
  /// to the first offender instead of painting its error somewhere off-screen.
  final _examNameFieldKey = GlobalKey(debugLabel: 'field-exam-name');
  final _rollFieldKey = GlobalKey(debugLabel: 'field-roll-number');

  /// The date is a hard save blocker but carries no validator (it is not a
  /// [TextFormField]), so it needs its own anchor to be scrolled to.
  final _dateFieldKey = GlobalKey(debugLabel: 'field-exam-date');

  late final _name = TextEditingController(
    text: widget.existing?.candidateName,
  );
  late final _examName = TextEditingController(text: widget.existing?.examName);
  late final _body = TextEditingController(
    text: widget.existing?.conductingBody,
  );
  late final _examCode = TextEditingController(text: widget.existing?.examCode);
  late final _roll = TextEditingController(text: widget.existing?.rollNumber);
  late final _regId = TextEditingController(
    text: widget.existing?.registrationId,
  );
  late final _secret = TextEditingController(
    text: widget.existing?.dobOrPortalPassword,
  );
  late final _centreCode = TextEditingController(
    text: widget.existing?.centerCode,
  );
  late final _centreAddress = TextEditingController(
    text: widget.existing?.centerAddress,
  );
  late final _gate = TextEditingController(text: widget.existing?.gate);
  late final _reportBy = TextEditingController(text: widget.existing?.reportBy);
  late final _shift = TextEditingController(text: widget.existing?.shift);

  late ExamCategory _category = widget.existing?.category ?? ExamCategory.ssc;
  // No fabricated default: a date the user never chose must never become an
  // exam-day countdown.
  late DateTime? _examDate = widget.existing?.examDate;

  /// Baseline captured at construction so the close guard can tell a real edit
  /// from the values a card already had.
  late final Map<TextEditingController, String> _baseline;
  late final ExamCategory _initialCategory;
  late final DateTime? _initialDate;

  bool _obscureSecret = true;
  bool _saving = false;
  bool _confirmingDiscard = false;
  String? _error;

  /// A blocking reason shown next to Save (missing date, duplicate card) —
  /// distinct from [_error], which is a failed write and offers Retry.
  String? _validationNotice;

  @override
  void initState() {
    super.initState();
    // Capture eagerly: a lazy `late final` would baseline after the first edit.
    _initialCategory = _category;
    _initialDate = _examDate;
    _categoryPicked = widget.existing != null;
    _baseline = {
      for (final c in [
        _name,
        _examName,
        _body,
        _examCode,
        _roll,
        _regId,
        _secret,
        _centreCode,
        _centreAddress,
        _gate,
        _reportBy,
        _shift,
      ])
        c: c.text,
    };
  }

  /// True when the form differs from what was opened.
  bool get _dirty =>
      _category != _initialCategory ||
      _examDate != _initialDate ||
      _baseline.entries.any((e) => e.key.text != e.value);

  /// Close via the Cancel button, the barrier or system back.
  Future<void> _requestClose() async {
    // A close tap during a save used to vanish: the sheet stayed up and the
    // only sign anything happened was the spinner it was already showing. Say
    // what is going on and stay put until the bounded write finishes.
    if (_saving) {
      _showNotice('Still saving your card…', saving: true);
      return;
    }
    if (_confirmingDiscard) return;
    if (!_dirty) {
      Navigator.of(context).pop();
      return;
    }
    _confirmingDiscard = true;
    final discard = await _confirmDiscard();
    _confirmingDiscard = false;
    if (discard && mounted) Navigator.of(context).pop();
  }

  /// Says [message] through the platform screen reader.
  ///
  /// The notice rows below are live regions too, but a live region only
  /// announces a *change* to a node that is already on screen — and Save sits
  /// at the bottom of a ten-field form, so the message can be born off-screen.
  /// The explicit announcement is what a screen-reader user actually hears.
  void _announce(String message) {
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        message,
        Directionality.of(context),
      ),
    );
  }

  /// Shows [message] next to Save and announces it.
  ///
  /// [saving] keeps the primary button busy: the duplicate check can now wait
  /// for the vault to open, and the button must not look dead while it does.
  void _showNotice(String message, {bool saving = false}) {
    setState(() {
      _saving = saving;
      _validationNotice = message;
      _error = null;
    });
    _announce(message);
  }

  /// Shows a failed-write [message] next to Save, with Retry, and announces it.
  void _showError(String message) {
    setState(() {
      _saving = false;
      _error = message;
      _validationNotice = null;
    });
    _announce(message);
  }

  Future<bool> _confirmDiscard() async {
    final p = context.ev;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: p.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: p.border),
        ),
        title: Text('Discard this card?', style: context.type.sectionTitle),
        content: Text(
          'Your changes, including the portal password, have not been saved.',
          style: context.type.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              'Keep editing',
              style: context.type.label.copyWith(color: p.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              'Discard',
              style: context.type.label.copyWith(
                color: p.dangerText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// True once the user taps a category chip, so inference never overrides a
  /// deliberate choice.
  ///
  /// Editing an existing card counts as picked: its chip was already a
  /// deliberate (or accepted) choice, and retyping the exam name to fix a
  /// typo must not silently re-file the card under an inferred category.
  late bool _categoryPicked;

  /// Mirrors the typed name into the category chip so a "UPSC CSE" card is not
  /// filed under SSC.
  void _onExamNameChanged(String value) {
    final inferred = ExamMatcher.categoryFor(value);
    if (_categoryPicked || inferred == null) {
      // Still rebuild: the match banner is derived from the same text.
      setState(() {});
      return;
    }
    setState(() => _category = inferred);
  }

  /// True only during the first feed load with nothing cached: [_match]
  /// returning null is then indistinguishable from "nothing published", and
  /// the banner must not claim the latter while the former is possible.
  bool _feedLoading() {
    final state = ref.watch(liveFeedProvider);
    return state.isLoading && state.value == null;
  }

  /// The published result this card belongs to, if one is close enough.
  ///
  /// `watch` for the banner (the feed can arrive while the form is open, and
  /// `build` then rebuilds), `read` for the save path — reading a provider during
  /// a callback is fine, watching it is not.
  LiveUpdate? _match({required bool watch}) {
    final feed =
        (watch ? ref.watch(liveFeedProvider) : ref.read(liveFeedProvider))
            .value
            ?.feed;
    if (feed == null) return null;
    return ExamMatcher.best(_examName.text, feed.updates);
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _examName,
      _body,
      _examCode,
      _roll,
      _regId,
      _secret,
      _centreCode,
      _centreAddress,
      _gate,
      _reportBy,
      _shift,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// The field validators as members rather than inline closures, so [_save]
  /// can re-run them to find the first offender and scroll it into view.
  String? _validateExamName(String? v) =>
      (v == null || v.trim().length < 3) ? 'Enter the exam name' : null;

  String? _validateRoll(String? v) {
    final t = v?.trim() ?? '';
    if (t.length < 4) return 'Roll number looks too short';
    return null;
  }

  /// Scrolls the first field that still fails validation into view.
  ///
  /// Runs after the frame completes: validate() has just inserted error text
  /// under the fields, changing content heights, so the scroll target computed
  /// against the old layout would land off by the error line's height.
  void _revealFirstInvalidField() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Listed in the order the fields appear, so the scroll lands on the
      // first offender rather than the last. The date is here even though it
      // has no validator: it is a hard save blocker that sits five rows above
      // Save, off-screen on a phone, so a refusal that only says "choose a
      // date" left the user hunting for the field.
      final invalid = <GlobalKey>[
        if (_validateExamName(_examName.text) != null) _examNameFieldKey,
        if (_validateRoll(_roll.text) != null) _rollFieldKey,
        if (_examDate == null) _dateFieldKey,
      ];
      if (invalid.isEmpty) return;
      final fieldContext = invalid.first.currentContext;
      if (fieldContext == null) return;
      Scrollable.ensureVisible(
        fieldContext,
        duration: EvMotion.of(context, EvMotion.inline),
        curve: EvMotion.curveOf(context, EvMotion.enter),
        alignment: 0.1,
      );
    });
  }

  /// The cards the duplicate check runs against, or null when they could not
  /// be read.
  ///
  /// The vault is deliberately allowed to still be opening when Add is tapped,
  /// so `.value` is null then. Treating that as an empty vault skipped the
  /// check entirely and let a cold-start Add save the same exam + roll twice,
  /// so the load is awaited instead — bounded like the repository's own read,
  /// because a Keystore read can hang on some OEMs.
  Future<List<AdmitCard>?> _cardsForDuplicateCheck() async {
    final vault = ref.read(admitCardsProvider);
    if (vault is AsyncData<List<AdmitCard>>) return vault.value;
    try {
      return await ref
          .read(admitCardsProvider.future)
          .timeout(const Duration(seconds: 10));
    } catch (e, st) {
      AppLogger.e(
        'VaultForm',
        'duplicate check could not read the vault',
        e,
        st,
      );
      return null;
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) {
      // validate() paints each error at its field, but Save sits at the bottom
      // of a ten-field scrollable form — when the offender is scrolled out of
      // view, nothing on screen changes and the button looks dead. Say why
      // Save refused (next to the button) and scroll to the field to fix.
      _showNotice('Fix the highlighted field above');
      _revealFirstInvalidField();
      return;
    }

    final date = _examDate;
    if (date == null) {
      // "tap the field above" pointed at nothing: the date field is five rows
      // up and off-screen on a phone. Name it and bring it into view.
      _showNotice('Choose the exam date before saving.');
      _revealFirstInvalidField();
      return;
    }

    // Busy from here on: the duplicate check may have to wait for the vault to
    // open, and a Save that silently does nothing for seconds reads as broken.
    setState(() {
      _saving = true;
      _error = null;
      _validationNotice = null;
    });

    final now = DateTime.now();
    final base = widget.existing;
    final roll = _roll.text.trim().toUpperCase();

    // The checker looks the index up by this id, so a hand-derived slug could
    // never resolve. Re-resolve on every save: a fresh match first, then the id
    // the card already had — but only when the name is unchanged, because a
    // renamed card must not search the old exam's index — then a slug of the
    // typed name.
    final examId = resolveExamId(
      examName: _examName.text,
      match: _match(watch: false),
      previous: base?.examId,
      previousName: base?.examName,
    );

    final cards = await _cardsForDuplicateCheck();
    if (!mounted) return;
    if (cards == null) {
      // Never claim the check passed when it could not run: the student would
      // end up with two passes for one exam and one roll.
      _showNotice(
        'Could not check your vault for duplicates. Try again in a moment.',
      );
      return;
    }
    final duplicate = cards.any(
      (c) =>
          c.id != base?.id &&
          c.examId == examId &&
          normaliseRoll(c.rollNumber) == normaliseRoll(roll),
    );
    if (duplicate) {
      _showNotice('You already saved this card — same exam and roll number.');
      return;
    }

    // VERIFIED is a claim about one exact roll number against one exact
    // published index — the checker only stamps it when the card's *own* roll
    // was found. Editing either invalidates the old claim: fixing a roll typo
    // must not carry a permanent VERIFIED badge for a roll never matched. A
    // rename is the same: the badge belongs to the exam it was earned against,
    // and `base.examId == examId` alone would pass trivially when the old id
    // survived a rename.
    final keepsVerification =
        base != null &&
        _sameExamName(base.examName, _examName.text) &&
        base.rollNumberVerified &&
        base.rollNumber == roll &&
        base.examId == examId;

    final card = AdmitCard(
      candidateName: _name.text.trim(),
      id:
          base?.id ??
          '${_category.id}_${now.millisecondsSinceEpoch.toRadixString(36)}',
      examId: examId,
      category: _category,
      examName: _examName.text.trim(),
      conductingBody: _body.text.trim(),
      examCode: _examCode.text.trim(),
      rollNumber: roll,
      registrationId: _regId.text.trim(),
      dobOrPortalPassword: _secret.text.trim(),
      centerCode: _centreCode.text.trim(),
      centerAddress: _centreAddress.text.trim(),
      gate: _gate.text.trim(),
      reportBy: _reportBy.text.trim(),
      examDate: date,
      shift: _shift.text.trim(),
      createdAt: base?.createdAt ?? now,
      updatedAt: now,
      rollNumberVerified: keepsVerification,
      checklist: base?.checklist ?? const {},
    );

    try {
      // Loads are bounded (10 s in the repository); writes were not, and a
      // hung Keystore write left `_saving` true forever: a permanent spinner on
      // the primary button, with Cancel, back and the barrier all returning
      // silently. Bounding the write turns that into the normal error path,
      // which offers Retry.
      await ref
          .read(admitCardsProvider.notifier)
          .save(card)
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${card.examName} saved to vault',
            style: context.type.label.copyWith(color: Colors.white),
          ),
        ),
      );
    } on TimeoutException catch (e, st) {
      AppLogger.e('VaultForm', 'Admit card save timed out', e, st);
      if (!mounted) return;
      // Honest about what is unknown: the write may still land after the
      // ceiling, so this must not claim the card was not saved.
      _showError(
        'Saving took too long. Your details are still here — check your vault '
        'before trying again.',
      );
    } catch (e, st) {
      AppLogger.e('VaultForm', 'Admit card save failed', e, st);
      if (!mounted) return;
      // Never surface a platform exception: the user needs an action, not a stack.
      _showError('That card could not be saved. Your details are still here.');
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final current = _examDate;
    final earliest = DateTime(now.year - 1, now.month, now.day);
    final latest = DateTime(now.year + 3, now.month, now.day);
    // The range must contain the value, or showDatePicker asserts for any card
    // saved more than a year (or three years) out.
    final firstDate = current != null && current.isBefore(earliest)
        ? DateTime(current.year, current.month, current.day)
        : earliest;
    final lastDate = current != null && current.isAfter(latest)
        ? DateTime(current.year, current.month, current.day)
        : latest;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: firstDate,
      lastDate: lastDate,
    );
    // Guarded like every other await in this file: the route is normally kept
    // alive by PopScope while the picker is open, but a system-initiated
    // teardown mid-picker would turn this setState into a crash.
    if (picked != null && mounted) {
      setState(() {
        _examDate = picked;
        _validationNotice = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.ev;

    return PopScope(
      // canPop stays false so back/barrier can never discard the form silently;
      // dirtiness is read at pop time, not baked into the last build.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _requestClose();
      },
      child: Container(
        // Clip to the rounded top: the form scrolls, and unclipped scrolled
        // text painted over the dimmed page outside the corner arcs — the same
        // bleed the about and alerts sheets already guard against.
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: p.border),
        ),
        child: DraggableScrollableSheet(
          expand: false,
          // Starts fully open: this is a data-entry form with ten fields, and a
          // half-height sheet hid the save button below the fold on a 6.1" phone.
          initialChildSize: 0.94,
          minChildSize: 0.6,
          maxChildSize: 0.96,
          builder: (context, controller) {
            return Form(
              key: _formKey,
              // A lazy ListView disposes offscreen fields, and Form.validate()
              // silently skips unregistered ones — the form could save with the
              // exam name still empty. A plain scroll view keeps all fields alive.
              child: SingleChildScrollView(
                controller: controller,
                // Keyboard-aware: the drop-down keyboard used to cover the
                // Save button with no way to scroll it clear.
                padding: EdgeInsets.fromLTRB(
                  20,
                  8,
                  20,
                  28 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // A sheet with no handle and no close button reads as a page you
                    // are stuck on. The handle plus Cancel says "you can leave".
                    _FormHeader(
                      title: widget.existing == null
                          ? 'Add admit card'
                          : 'Edit admit card',
                      onClose: _requestClose,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Everything below is encrypted on this device with the Android '
                      'Keystore. Nothing is uploaded.',
                      style: context.type.bodyMuted,
                    ),
                    const SizedBox(height: 6),
                    // Hints used to be plausible *values* ("2201049821"), which reads
                    // as a pre-filled answer rather than an example — and a student
                    // who saved one would carry a stranger's roll number. They now
                    // describe the field instead.
                    Text(
                      'Copy the details exactly as they appear on your admit card.',
                      style: context.type.microLabel.copyWith(),
                    ),
                    const SizedBox(height: 20),
                    // The one field that is about the student, not the exam.
                    // Optional: a card without a name still saves, checks and
                    // shares exactly as before.
                    _Field(
                      controller: _name,
                      label: 'Your name (optional)',
                      hint: 'Printed on your share card',
                      caps: TextCapitalization.words,
                      maxLength: 40,
                    ),
                    _Field(
                      fieldKey: _examNameFieldKey,
                      controller: _examName,
                      label: 'Exam name',
                      hint: 'As printed on your admit card',
                      onChanged: _onExamNameChanged,
                      validator: _validateExamName,
                    ),
                    _CategoryPicker(
                      value: _category,
                      onChanged: (c) => setState(() {
                        _category = c;
                        _categoryPicked = true;
                      }),
                    ),
                    if (_match(watch: true) case final match?)
                      _LinkedResult(match: match)
                    else if (_examName.text.trim().length >= 3 &&
                        _feedLoading())
                      // While the feed is still loading, a null match means
                      // "not known yet" — claiming "no published result" at
                      // that moment is a false statement a student could read
                      // as "I was not selected".
                      const _CheckingResults()
                    else if (_examName.text.trim().length >= 3)
                      // Say plainly that no published result is linked, so a student
                      // does not read "no index" later as "I was not selected".
                      _NoLinkedResult(),
                    const SizedBox(height: 4),
                    _Field(
                      controller: _body,
                      label: 'Conducting body',
                      hint: 'e.g. Staff Selection Commission',
                    ),
                    _Field(
                      controller: _examCode,
                      label: 'Exam code',
                      hint: 'Short code from the card',
                      caps: TextCapitalization.characters,
                    ),
                    _Field(
                      fieldKey: _rollFieldKey,
                      controller: _roll,
                      label: 'Roll number',
                      // Several boards and state PSCs issue alphanumeric rolls;
                      // a digits-only filter silently turned "A1234567" into a
                      // different, plausible-looking number on paste.
                      hint: 'Letters, digits, - or / as printed',
                      mono: true,
                      caps: TextCapitalization.characters,
                      rollChars: true,
                      upperCase: true,
                      maxLength: 24,
                      validator: _validateRoll,
                    ),
                    _Field(
                      controller: _regId,
                      label: 'Registration ID',
                      hint: 'Application / registration ID',
                      mono: true,
                      caps: TextCapitalization.characters,
                    ),
                    _Field(
                      controller: _secret,
                      label: 'DOB / portal password',
                      hint: 'DD/MM/YYYY or portal password',
                      mono: true,
                      obscure: _obscureSecret,
                      suffix: IconButton(
                        icon: Icon(
                          _obscureSecret
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 18,
                          color: p.textTertiary,
                        ),
                        // Without this the most sensitive field on the form
                        // was announced as a bare "Button". The tooltip is the
                        // IconButton's accessible name.
                        tooltip: _obscureSecret
                            ? 'Show password'
                            : 'Hide password',
                        onPressed: () =>
                            setState(() => _obscureSecret = !_obscureSecret),
                      ),
                    ),
                    _Field(
                      controller: _centreCode,
                      label: 'Centre code',
                      hint: 'Centre code from the card',
                      mono: true,
                      caps: TextCapitalization.characters,
                    ),
                    _Field(
                      controller: _centreAddress,
                      label: 'Centre address',
                      hint: 'Street, area, city',
                    ),
                    _DateField(
                      fieldKey: _dateFieldKey,
                      date: _examDate,
                      onTap: _pickDate,
                    ),
                    // Reporting time, shift and gate were copied from the old card
                    // but never editable, so the pass showed empty lines forever.
                    _Field(
                      controller: _shift,
                      label: 'Exam shift',
                      hint: 'e.g. 10:00 AM – 11:00 AM',
                    ),
                    _Field(
                      controller: _reportBy,
                      label: 'Reporting time',
                      hint: 'e.g. 08:00 AM',
                      mono: true,
                    ),
                    _Field(
                      controller: _gate,
                      label: 'Gate',
                      hint: 'e.g. Gate 2',
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.error_outline_rounded,
                            size: 16,
                            color: p.dangerText,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            // A live region so a screen reader re-reads the row
                            // when a save fails; the explicit announcement in
                            // [_showError] covers the first appearance.
                            child: Semantics(
                              liveRegion: true,
                              child: Text(
                                _error!,
                                style: context.type.body.copyWith(
                                  color: p.dangerText,
                                ),
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: _saving ? null : _save,
                            style: TextButton.styleFrom(
                              minimumSize: const Size(
                                EvSize.minTapTarget,
                                EvSize.minTapTarget,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                            ),
                            child: Text(
                              'Retry',
                              style: context.type.label.copyWith(
                                color: p.accentText,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (_validationNotice != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.error_outline_rounded,
                            size: 16,
                            color: p.dangerText,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            // Same live-region treatment: a Save that refuses
                            // must say why out loud, not only in paint.
                            child: Semantics(
                              liveRegion: true,
                              child: Text(
                                _validationNotice!,
                                style: context.type.body.copyWith(
                                  color: p.dangerText,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    EvPrimaryButton(
                      label: 'Save to vault',
                      icon: Icons.lock_outline_rounded,
                      busy: _saving,
                      onPressed: _save,
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        'AES-256 · ANDROID KEYSTORE · OFFLINE',
                        style: context.type.microLabel.copyWith(),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FormHeader extends StatelessWidget {
  const _FormHeader({required this.title, required this.onClose});

  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: p.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: context.type.sectionTitle.copyWith(fontSize: 17),
              ),
            ),
            // Cancel, not just a chevron: it can be tapped by a thumb and it is
            // the control that raises the unsaved-changes guard.
            TextButton(
              onPressed: onClose,
              style: TextButton.styleFrom(
                minimumSize: const Size(
                  EvSize.minTapTarget,
                  EvSize.minTapTarget,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: Text(
                'Cancel',
                style: context.type.label.copyWith(
                  color: p.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    this.fieldKey,
    required this.controller,
    required this.label,
    this.hint,
    this.mono = false,
    this.obscure = false,
    this.suffix,
    this.validator,
    this.caps = TextCapitalization.sentences,
    this.rollChars = false,
    this.upperCase = false,
    this.maxLength,
    this.onChanged,
  });

  /// Attached to the field's outer box so a failed Save can scroll the field
  /// into view via `Scrollable.ensureVisible`.
  final GlobalKey? fieldKey;

  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool mono;
  final bool obscure;
  final Widget? suffix;
  final String? Function(String?)? validator;
  final TextCapitalization caps;

  /// Restricts input to the roll grammar the result engine accepts.
  final bool rollChars;

  /// Upper-cases the visible value, so a pasted lowercase roll is normalised.
  final bool upperCase;

  final int? maxLength;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;
    final formatters = <TextInputFormatter>[
      if (rollChars)
        // Same grammar as roll_index_engine: A-Z, digits, dash, slash. The
        // filter also strips the spaces people paste in from a PDF.
        FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\-/]')),
      if (upperCase) const _UpperCaseFormatter(),
    ];
    // The theme's own hint style, so the example still looks exactly like the
    // `hintText` it replaced (Material adds `height: 1` to the inline hint).
    final hintStyle = Theme.of(
      context,
    ).inputDecorationTheme.hintStyle?.copyWith(height: 1);

    return Padding(
      key: fieldKey,
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 6),
            // The field carries this text as its accessible name (below), so
            // reading it here as well would announce every label twice.
            child: ExcludeSemantics(
              child: Text(label.toUpperCase(), style: context.type.microLabel),
            ),
          ),
          // The field's accessible name. `labelText` is the obvious way to
          // carry it, but Material suppresses `hintText` whenever a label sits
          // inline (`showHint = isEmpty && !_hasInlineLabel`), which would have
          // blanked the example under every empty field on this form; letting
          // the label float (`always`) would instead cut the invisible label's
          // notch out of the outline border. Naming the field here keeps the
          // 393×852 look untouched.
          Semantics(
            label: label,
            child: TextFormField(
              controller: controller,
              validator: validator,
              onChanged: onChanged,
              obscureText: obscure,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: caps,
              keyboardType: obscure || mono
                  ? TextInputType.visiblePassword
                  : TextInputType.text,
              maxLength: maxLength,
              inputFormatters: formatters.isEmpty ? null : formatters,
              style: mono
                  ? context.type.fieldValue
                  : context.type.body.copyWith(
                      color: p.textPrimary,
                      fontSize: 13,
                    ),
              decoration: InputDecoration(
                // Rendered from the theme's own hint style so the example looks
                // exactly like `hintText` did. Excluded from semantics because
                // a hint merged into a field's node *becomes* its name — the
                // very bug being fixed: "Street, area, city" instead of
                // "Centre address".
                hint: hint == null
                    ? null
                    : ExcludeSemantics(child: Text(hint!, style: hintStyle)),
                suffixIcon: suffix,
                // maxLength would otherwise add a counter row under the field.
                counterText: maxLength == null ? null : '',
                suffixIconConstraints: const BoxConstraints(
                  minWidth: 44,
                  minHeight: 44,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Normalises the visible roll to upper case as it is typed or pasted.
class _UpperCaseFormatter extends TextInputFormatter {
  const _UpperCaseFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final upper = newValue.text.toUpperCase();
    if (upper == newValue.text) return newValue;
    return TextEditingValue(
      text: upper,
      selection: newValue.selection,
      composing: TextRange.empty,
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({this.fieldKey, required this.date, required this.onTap});

  /// Attached to the field's outer box so a failed Save can scroll the date
  /// into view — it blocks saving but has no validator to anchor to.
  final GlobalKey? fieldKey;

  final DateTime? date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;
    const months = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ];
    final selected = date;

    return Padding(
      key: fieldKey,
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 6),
            child: Text('EXAM DATE', style: context.type.microLabel),
          ),
          // The sheet paints its own opaque surface and this field paints an
          // opaque sunken box, so the InkWell's splash used to render on the
          // route's Material *underneath* both — tapping the date field gave
          // zero press feedback (pattern: command_center radar rows). The
          // transparent Material adds an ink canvas above the sheet surface,
          // and `Ink` paints the field's decoration onto that same canvas,
          // *below* the splash, so the ripple is visible on the field itself.
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(EvRadius.button),
              child: Ink(
                decoration: BoxDecoration(
                  color: p.surfaceSunken,
                  borderRadius: BorderRadius.circular(EvRadius.button),
                  border: Border.all(color: p.borderStrong),
                ),
                child: Container(
                  // Min height, not a fixed 52px: the placeholder wraps at 2.0x.
                  constraints: const BoxConstraints(minHeight: 52),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          // An untouched date must read as missing, never as a
                          // confident exam-day countdown.
                          selected == null
                              ? 'Not set — tap to choose'
                              : '${selected.day.toString().padLeft(2, '0')} '
                                    '${months[selected.month - 1]} ${selected.year}',
                          style: selected == null
                              ? context.type.fieldValue.copyWith(
                                  color: p.textTertiary,
                                )
                              : context.type.fieldValue,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.calendar_today_rounded,
                        size: 16,
                        color: p.textTertiary,
                      ),
                    ],
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

class _CategoryPicker extends StatelessWidget {
  const _CategoryPicker({required this.value, required this.onChanged});

  final ExamCategory value;
  final ValueChanged<ExamCategory> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 6),
            child: Text('CATEGORY', style: context.type.microLabel),
          ),
          Wrap(
            spacing: 7,
            runSpacing: 4,
            children: [
              for (final c in ExamCategory.values)
                EvChip(
                  label: c.label,
                  selected: value == c,
                  onTap: () => onChanged(c),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Shown when the typed exam name matches a published result.
///
/// It states the link and what it buys ("your roll can be checked"), because a
/// silent match would be invisible — and an invisible feature is one nobody
/// trusts.
class _LinkedResult extends StatelessWidget {
  const _LinkedResult({required this.match});

  final LiveUpdate match;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
      decoration: BoxDecoration(
        color: p.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(EvRadius.inner),
        border: Border.all(color: p.success.withValues(alpha: 0.26)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.link_rounded, size: 13, color: p.successText),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Linked to a published result',
                  style: context.type.tileTitle.copyWith(color: p.successText),
                ),
                const SizedBox(height: 2),
                Text(
                  match.examName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.type.bodyMuted.copyWith(),
                ),
                if (match.hasIndex) ...[
                  const SizedBox(height: 3),
                  Text(
                    'Your roll number can be checked in this list.',
                    style: context.type.microLabel.copyWith(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown when the name matches nothing published yet.
class _NoLinkedResult extends StatelessWidget {
  const _NoLinkedResult();

  @override
  Widget build(BuildContext context) {
    final p = context.ev;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 12, color: p.textTertiary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'No published result matches this name yet. The card still works '
              'for exam-day details; result checking starts when the commission '
              'publishes a list.',
              style: context.type.bodyMuted.copyWith(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown while the feed itself is still loading.
///
/// Neutral wording is the point: `_match` returns null both for "nothing
/// published" and for "the feed has not arrived yet", and only the second one
/// is honest here — the app cannot claim no result exists before it has
/// looked.
class _CheckingResults extends StatelessWidget {
  const _CheckingResults();

  @override
  Widget build(BuildContext context) {
    final p = context.ev;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 2),
      child: Row(
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              valueColor: AlwaysStoppedAnimation(p.textTertiary),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              'Checking published results…',
              style: context.type.bodyMuted.copyWith(),
            ),
          ),
        ],
      ),
    );
  }
}

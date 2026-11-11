import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
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
/// A fresh feed match wins over the stored id: renaming a card, or saving one
/// before the exam was published, must re-resolve instead of pinning a slug
/// that the checker can never find.
@visibleForTesting
String resolveExamId({
  required String examName,
  LiveUpdate? match,
  String? previous,
}) {
  final fresh = match?.examId;
  if (fresh != null && fresh.isNotEmpty) return fresh;
  if (previous != null && previous.isNotEmpty) return previous;
  return slugifyExamName(examName);
}

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
    _baseline = {
      for (final c in [
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
    if (_saving || _confirmingDiscard) return;
    if (!_dirty) {
      Navigator.of(context).pop();
      return;
    }
    _confirmingDiscard = true;
    final discard = await _confirmDiscard();
    _confirmingDiscard = false;
    if (discard && mounted) Navigator.of(context).pop();
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
  bool _categoryPicked = false;

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

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final date = _examDate;
    if (date == null) {
      setState(() {
        _validationNotice = 'Choose the exam date — tap the field above.';
        _error = null;
      });
      return;
    }

    final now = DateTime.now();
    final base = widget.existing;
    final roll = _roll.text.trim().toUpperCase();

    // The checker looks the index up by this id, so a hand-derived slug could
    // never resolve. Re-resolve on every save: a fresh match first, then the id
    // the card already had, then a slug of the typed name.
    final examId = resolveExamId(
      examName: _examName.text,
      match: _match(watch: false),
      previous: base?.examId,
    );

    final cards = ref.read(admitCardsProvider).value ?? const <AdmitCard>[];
    final duplicate = cards.any(
      (c) =>
          c.id != base?.id &&
          c.examId == examId &&
          normaliseRoll(c.rollNumber) == normaliseRoll(roll),
    );
    if (duplicate) {
      setState(() {
        _validationNotice =
            'You already saved this card — same exam and roll number.';
        _error = null;
      });
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
      _validationNotice = null;
    });

    final card = AdmitCard(
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
      rollNumberVerified: base?.rollNumberVerified ?? false,
      checklist: base?.checklist ?? const {},
    );

    try {
      await ref.read(admitCardsProvider.notifier).save(card);
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
    } catch (e, st) {
      AppLogger.e('VaultForm', 'Admit card save failed', e, st);
      if (!mounted) return;
      setState(() {
        _saving = false;
        // Never surface a platform exception: the user needs an action, not a stack.
        _error = 'That card could not be saved. Your details are still here.';
      });
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
                    _Field(
                      controller: _examName,
                      label: 'Exam name',
                      hint: 'As printed on your admit card',
                      onChanged: _onExamNameChanged,
                      validator: (v) => (v == null || v.trim().length < 3)
                          ? 'Enter the exam name'
                          : null,
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
                      validator: (v) {
                        final t = v?.trim() ?? '';
                        if (t.length < 4) return 'Roll number looks too short';
                        return null;
                      },
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
                    _DateField(date: _examDate, onTap: _pickDate),
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
                            child: Text(
                              _error!,
                              style: context.type.body.copyWith(
                                color: p.dangerText,
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
                            child: Text(
                              _validationNotice!,
                              style: context.type.body.copyWith(
                                color: p.dangerText,
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 6),
            child: Text(label.toUpperCase(), style: context.type.microLabel),
          ),
          TextFormField(
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
              hintText: hint,
              suffixIcon: suffix,
              // maxLength would otherwise add a counter row under the field.
              counterText: maxLength == null ? null : '',
              suffixIconConstraints: const BoxConstraints(
                minWidth: 44,
                minHeight: 44,
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
  const _DateField({required this.date, required this.onTap});

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
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 6),
            child: Text('EXAM DATE', style: context.type.microLabel),
          ),
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(EvRadius.button),
            child: Container(
              // Min height, not a fixed 52px: the placeholder wraps at 2.0x.
              constraints: const BoxConstraints(minHeight: 52),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: p.surfaceSunken,
                borderRadius: BorderRadius.circular(EvRadius.button),
                border: Border.all(color: p.borderStrong),
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

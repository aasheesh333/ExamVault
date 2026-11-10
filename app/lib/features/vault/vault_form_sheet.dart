import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_tokens.dart';
import '../../domain/entities/admit_card.dart';
import '../../domain/entities/exam_category.dart';
import '../../domain/entities/live_update.dart';
import '../../domain/services/exam_matcher.dart';
import '../../providers/app_providers.dart';
import '../../shared/widgets/ev_controls.dart';

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

  late ExamCategory _category = widget.existing?.category ?? ExamCategory.ssc;
  late DateTime _examDate =
      widget.existing?.examDate ?? DateTime.now().add(const Duration(days: 14));

  bool _obscureSecret = true;
  bool _saving = false;
  String? _error;

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
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    final now = DateTime.now();
    final base = widget.existing;

    final card = AdmitCard(
      id:
          base?.id ??
          '${_category.id}_${now.millisecondsSinceEpoch.toRadixString(36)}',
      // Reuse the published row's id when we matched one. The checker looks up
      // the roll index by this id, so a hand-derived id could never resolve —
      // which made a saved card useless on result day.
      examId:
          base?.examId ??
          _match(watch: false)?.examId ??
          _examName.text.trim().toLowerCase().replaceAll(
            RegExp(r'[^a-z0-9]+'),
            '_',
          ),
      category: _category,
      examName: _examName.text.trim(),
      conductingBody: _body.text.trim(),
      examCode: _examCode.text.trim(),
      rollNumber: _roll.text.trim().toUpperCase(),
      registrationId: _regId.text.trim(),
      dobOrPortalPassword: _secret.text.trim(),
      centerCode: _centreCode.text.trim(),
      centerAddress: _centreAddress.text.trim(),
      gate: base?.gate ?? '',
      reportBy: base?.reportBy ?? '',
      examDate: _examDate,
      shift: base?.shift ?? '',
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save. $e';
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _examDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (picked != null) setState(() => _examDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.ev;

    return Container(
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
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                // A sheet with no handle and no close button reads as a page you
                // are stuck on. The handle is the only visible affordance that
                // says "swipe me down".
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: p.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  widget.existing == null
                      ? 'Add admit card'
                      : 'Edit admit card',
                  style: context.type.sectionTitle.copyWith(fontSize: 17),
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
                  style: context.type.microLabel.copyWith(fontSize: 9),
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
                else if (_examName.text.trim().length > 3)
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
                  hint: 'Digits only, as printed',
                  mono: true,
                  caps: TextCapitalization.characters,
                  digitsOnly: true,
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
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: context.type.body.copyWith(color: p.dangerText),
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
                    style: context.type.microLabel.copyWith(fontSize: 9),
                  ),
                ),
              ],
            ),
          );
        },
      ),
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
    this.digitsOnly = false,
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
  final bool digitsOnly;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;

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
            inputFormatters: digitsOnly
                ? [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\-/]'))]
                : null,
            style: mono
                ? context.type.fieldValue
                : context.type.body.copyWith(
                    color: p.textPrimary,
                    fontSize: 13,
                  ),
            decoration: InputDecoration(
              hintText: hint,
              suffixIcon: suffix,
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

class _DateField extends StatelessWidget {
  const _DateField({required this.date, required this.onTap});

  final DateTime date;
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
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: p.surfaceSunken,
                borderRadius: BorderRadius.circular(EvRadius.button),
                border: Border.all(color: p.borderStrong),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${date.day.toString().padLeft(2, '0')} '
                      '${months[date.month - 1]} ${date.year}',
                      style: context.type.fieldValue,
                    ),
                  ),
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
                  style: context.type.tileTitle.copyWith(
                    fontSize: 10.5,
                    color: p.successText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  match.examName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.type.bodyMuted.copyWith(fontSize: 9.5),
                ),
                if (match.hasIndex) ...[
                  const SizedBox(height: 3),
                  Text(
                    'Your roll number can be checked in this list.',
                    style: context.type.microLabel.copyWith(fontSize: 9),
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
              style: context.type.bodyMuted.copyWith(fontSize: 9.5),
            ),
          ),
        ],
      ),
    );
  }
}

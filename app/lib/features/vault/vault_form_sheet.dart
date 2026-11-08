import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_tokens.dart';
import '../../domain/entities/admit_card.dart';
import '../../domain/entities/exam_category.dart';
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
  late final _body = TextEditingController(text: widget.existing?.conductingBody);
  late final _examCode = TextEditingController(text: widget.existing?.examCode);
  late final _roll = TextEditingController(text: widget.existing?.rollNumber);
  late final _regId =
      TextEditingController(text: widget.existing?.registrationId);
  late final _secret =
      TextEditingController(text: widget.existing?.dobOrPortalPassword);
  late final _centreCode =
      TextEditingController(text: widget.existing?.centerCode);
  late final _centreAddress =
      TextEditingController(text: widget.existing?.centerAddress);

  late ExamCategory _category =
      widget.existing?.category ?? ExamCategory.ssc;
  late DateTime _examDate =
      widget.existing?.examDate ?? DateTime.now().add(const Duration(days: 14));

  bool _obscureSecret = true;
  bool _saving = false;
  String? _error;

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
      id: base?.id ??
          '${_category.id}_${now.millisecondsSinceEpoch.toRadixString(36)}',
      examId: base?.examId ??
          _examName.text.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_'),
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
        initialChildSize: 0.92,
        minChildSize: 0.6,
        maxChildSize: 0.96,
        builder: (context, controller) {
          return Form(
            key: _formKey,
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
              children: [
                Text(
                  widget.existing == null ? 'Add admit card' : 'Edit admit card',
                  style: context.type.sectionTitle.copyWith(fontSize: 17),
                ),
                const SizedBox(height: 4),
                Text(
                  'Everything below is encrypted on this device with the Android Keystore. '
                  'Nothing is uploaded.',
                  style: context.type.bodyMuted,
                ),
                const SizedBox(height: 20),
                _Field(
                  controller: _examName,
                  label: 'Exam name',
                  hint: 'SSC CGL Tier-1 2026',
                  validator: (v) => (v == null || v.trim().length < 3)
                      ? 'Enter the exam name'
                      : null,
                ),
                _CategoryPicker(
                  value: _category,
                  onChanged: (c) => setState(() => _category = c),
                ),
                _Field(
                  controller: _body,
                  label: 'Conducting body',
                  hint: 'Staff Selection Commission',
                ),
                _Field(
                  controller: _examCode,
                  label: 'Exam code',
                  hint: 'CGL · TIER-1',
                  caps: TextCapitalization.characters,
                ),
                _Field(
                  controller: _roll,
                  label: 'Roll number',
                  hint: '2201049821',
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
                  hint: 'SSC-CGL-26-884213',
                  mono: true,
                  caps: TextCapitalization.characters,
                ),
                _Field(
                  controller: _secret,
                  label: 'DOB / portal password',
                  hint: '14/03/1999',
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
                  hint: 'DL-04-1187',
                  mono: true,
                  caps: TextCapitalization.characters,
                ),
                _Field(
                  controller: _centreAddress,
                  label: 'Centre address',
                  hint: 'Sector 12, Dwarka, New Delhi',
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
                    style: context.type.microLabel.copyWith(fontSize: 8),
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
              suffixIconConstraints:
                  const BoxConstraints(minWidth: 44, minHeight: 44),
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
      'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
      'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
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
                  Icon(Icons.calendar_today_rounded,
                      size: 16, color: p.textTertiary),
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

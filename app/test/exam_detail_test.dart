import 'package:examvault/core/theme/app_theme.dart';
import 'package:examvault/domain/entities/exam_category.dart';
import 'package:examvault/domain/entities/live_update.dart';
import 'package:examvault/shared/widgets/status_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The per-exam detail page must show only what the notice states.
///
/// This is the aggregator-site feature done honestly: dates, vacancy and fee
/// appear when the commission printed them, and the sheet is simply shorter
/// when it did not. A "TBA" placeholder would be a promise the app cannot keep.
void main() {
  LiveUpdate row({
    DateTime? examDate,
    DateTime? resultDate,
    DateTime? deadline,
    int? vacancy,
    String? fee,
    String? pdf = 'https://ssc.gov.in/list.pdf',
    String? page,
    UpdateStatus status = UpdateStatus.notification,
  }) => LiveUpdate(
    examId: 'ssc_cgl_2026',
    category: ExamCategory.ssc,
    examName: 'SSC CGL 2026',
    contextLine: 'Official notice',
    status: status,
    publishedAt: DateTime(2026, 11, 10),
    examDate: examDate,
    resultDate: resultDate,
    deadline: deadline,
    vacancy: vacancy,
    fee: fee,
    officialPdf: pdf,
    officialPage: page,
  );

  group('the notice model', () {
    test('a vacancy and fee survive parsing when present', () {
      final r = row(vacancy: 1234, fee: '₹100');
      expect(r.vacancy, 1234);
      expect(r.fee, '₹100');
    });

    test('absent facts stay null — never zero, never a placeholder', () {
      final r = row();
      expect(r.vacancy, isNull);
      expect(r.fee, isNull);
      expect(r.examDate, isNull);
      expect(r.resultDate, isNull);
      expect(r.deadline, isNull);
    });

    test('the new vacancy status has its own honest label', () {
      // "CLOSING SOON" on a notice published this morning is simply untrue.
      expect(UpdateStatus.notification.label, 'NEW VACANCY');
      expect(UpdateStatus.fromId('notification'), UpdateStatus.notification);
      expect(UpdateStatus.fromId('form_closing'), UpdateStatus.formClosing);
    });
  });

  group('status rendering', () {
    testWidgets('a new vacancy renders with the accent, not danger red', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          // The palette is a ThemeExtension: accentOn() reads context.ev.
          theme: AppTheme.dark(),
          home: Builder(
            builder: (context) {
              final accent = UpdateStatus.notification.accentOn(context);
              final danger = UpdateStatus.formClosing.accentOn(context);
              expect(accent, isNot(danger));
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });
  });
}

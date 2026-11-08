import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;

import '../../domain/entities/admit_card.dart';
import '../../domain/entities/exam_category.dart';
import '../../domain/entities/live_update.dart';

/// Deterministic content for a brand-new install.
///
/// A brand-new install has an empty vault and an empty feed. Showing three blank
/// screens is the fastest way to lose a user, so the first run is seeded with one
/// realistic card and one radar row — both are clearly marked as sample data in
/// the UI and are deleted the moment the user adds their own.
abstract final class DemoSeed {
  static const sampleMarker = 'sample';

  /// Relative date helper: always "12 days from today" so the countdown is
  /// honest whenever the app is first opened.
  static DateTime _inDays(int days) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day).add(Duration(days: days));
  }

  static List<AdmitCard> admitCards() {
    final now = DateTime.now();
    return [
      AdmitCard(
        id: 'sample_ssc_cgl_tier1_2026',
        examId: 'ssc_cgl_tier1_2026',
        category: ExamCategory.ssc,
        examName: 'SSC CGL Tier-1 2026',
        conductingBody: 'Staff Selection Commission',
        examCode: 'CGL · TIER-1',
        rollNumber: '2201049821',
        registrationId: 'SSC-CGL-26-884213',
        dobOrPortalPassword: '14/03/1999',
        centerCode: 'DL-04-1187',
        centerAddress: 'Sector 12, Dwarka, New Delhi',
        gate: 'Gate 3',
        reportBy: '08:15 AM',
        examDate: _inDays(12),
        shift: '09:00 AM – 10:00 AM',
        createdAt: now,
        updatedAt: now,
        checklist: const {
          ChecklistItem.admitCardPdf,
          ChecklistItem.passportPhotos,
          ChecklistItem.originalId,
        },
      ),
      AdmitCard(
        id: 'sample_ibps_po_prelims_2026',
        examId: 'ibps_po_prelims_2026',
        category: ExamCategory.banking,
        examName: 'IBPS PO Prelims 2026',
        conductingBody: 'Institute of Banking Personnel Selection',
        examCode: 'PO · PRELIMS',
        rollNumber: '2188473920',
        registrationId: 'IBPS-PO-26-119344',
        dobOrPortalPassword: '02/08/1998',
        centerCode: 'MH-11-0420',
        centerAddress: 'Andheri East, Mumbai',
        gate: 'Gate 1',
        reportBy: '07:45 AM',
        examDate: _inDays(21),
        shift: '10:30 AM – 11:30 AM',
        createdAt: now,
        updatedAt: now,
        checklist: const {ChecklistItem.admitCardPdf},
      ),
      AdmitCard(
        id: 'sample_rrb_ntpc_2026',
        examId: 'rrb_ntpc_2026',
        category: ExamCategory.railways,
        examName: 'RRB NTPC 2026',
        conductingBody: 'Railway Recruitment Board',
        examCode: 'NTPC · CBT-1',
        rollNumber: '4471203668',
        registrationId: 'RRB-NTPC-26-550812',
        dobOrPortalPassword: '27/11/1997',
        centerCode: 'UP-09-0033',
        centerAddress: 'Gomti Nagar, Lucknow',
        gate: 'Gate 2',
        reportBy: '08:00 AM',
        examDate: _inDays(34),
        shift: '12:00 PM – 01:00 PM',
        createdAt: now,
        updatedAt: now,
        checklist: const {},
      ),
    ];
  }

  static LiveFeed liveFeed() {
    final now = DateTime.now();
    return LiveFeed(
      generatedAt: now,
      revision: 1,
      updates: [
        LiveUpdate(
          examId: 'ssc_cgl_tier1_2026',
          category: ExamCategory.ssc,
          examName: 'SSC CGL Tier-1 2026',
          contextLine: 'Direct PDF · 18.4 MB',
          status: UpdateStatus.resultOut,
          publishedAt: now.subtract(const Duration(minutes: 2)),
          pdfSizeLabel: '18.4 MB',
          mirrorLatencyMs: 82,
        ),
        LiveUpdate(
          examId: 'ibps_po_prelims_2026',
          category: ExamCategory.banking,
          examName: 'IBPS PO Prelims 2026',
          contextLine: '4 mirrors live · no queue',
          status: UpdateStatus.admitCardLive,
          publishedAt: now.subtract(const Duration(minutes: 18)),
          mirrorLatencyMs: 120,
        ),
        LiveUpdate(
          examId: 'upsc_cse_prelims_2026',
          category: ExamCategory.upsc,
          examName: 'UPSC CSE Prelims 2026',
          contextLine: 'Result PDF released 09:12 IST',
          status: UpdateStatus.resultOut,
          publishedAt: now.subtract(const Duration(minutes: 41)),
          pdfSizeLabel: '4.2 MB',
          mirrorLatencyMs: 82,
        ),
        LiveUpdate(
          examId: 'rrb_ntpc_2026',
          category: ExamCategory.railways,
          examName: 'RRB NTPC 2026',
          contextLine: 'Application closes 11:59 PM',
          status: UpdateStatus.formClosing,
          publishedAt: now.subtract(const Duration(hours: 1)),
        ),
      ],
    );
  }
}

/// Generates a realistic, correctly-shaped roll index so the full lookup path can
/// be exercised offline.
///
/// Mirrors production exactly: lexicographically sorted, optionally ranked,
/// gzip-compressed JSON.
abstract final class MockRollIndex {
  /// [rolls] defaults to ~12 000 rows, which is the order of magnitude of a
  /// Tier-1 shortlist. Pass [includeRoll] to guarantee a hit.
  static Future<Uint8List> generate({
    required String examId,
    String? includeRoll,
    int count = 12000,
    bool withRanks = true,
  }) {
    Uint8List build() {
      final seed = examId.codeUnits.fold<int>(17, (a, b) => (a * 31 + b) & 0x7fffffff);
      final rng = Random(seed);

      final rolls = <String>{};
      // A plausible SSC roll block.
      final base = 2201000000 + rng.nextInt(90000);
      var guard = 0;
      while (rolls.length < count && guard < count * 4) {
        guard++;
        rolls.add('${base + rng.nextInt(900000)}');
      }
      if (includeRoll != null && includeRoll.trim().isNotEmpty) {
        rolls.add(includeRoll.trim().toUpperCase());
      }

      final sorted = rolls.toList()..sort();

      final payload = withRanks
          ? [
              for (var i = 0; i < sorted.length; i++)
                {'r': sorted[i], 'rank': i + 1},
            ]
          : sorted;

      final raw = utf8.encode(jsonEncode(payload));
      return Uint8List.fromList(gzip.encode(raw));
    }

    // Generation + gzip of 12k rows is ~10 ms, but it stays off the UI isolate
    // for consistency with the real path. The web has no isolates, so it runs
    // inline there — `Isolate.run` throws `Unsupported operation` on dart2js.
    return kIsWeb ? Future.value(build()) : Isolate.run(build);
  }
}


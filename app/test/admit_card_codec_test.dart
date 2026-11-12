import 'dart:convert';

import 'package:examvault/data/local/secure_vault_store.dart';
import 'package:examvault/domain/entities/admit_card.dart';
import 'package:examvault/domain/entities/exam_category.dart';
import 'package:flutter_test/flutter_test.dart';

AdmitCard _card() => AdmitCard(
  id: 'ssc_cgl_tier1_2026',
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
  examDate: DateTime(2026, 11, 20),
  shift: '09:00 AM – 10:00 AM',
  createdAt: DateTime(2026, 11, 1, 9, 30),
  updatedAt: DateTime(2026, 11, 2, 10, 15),
  rollNumberVerified: true,
  checklist: const {ChecklistItem.admitCardPdf, ChecklistItem.originalId},
);

void main() {
  group('AdmitCardCodec', () {
    test('round-trips the candidate name', () {
      final original = _card().copyWith(candidateName: 'Asha Verma');
      final c = AdmitCardCodec.decode(AdmitCardCodec.encode(original));
      expect(c?.candidateName, 'Asha Verma');
    });

    test(
      'cards saved before the name field existed decode with empty name',
      () {
        // Legacy payloads carry no 'name' key: absent must mean empty, never an
        // error — the same per-field tolerance every other field gets.
        final map =
            jsonDecode(AdmitCardCodec.encode(_card())) as Map<String, dynamic>;
        map.remove('name');
        final legacy = jsonEncode(map);
        expect(legacy.contains('"name"'), isFalse);
        final c = AdmitCardCodec.decode(legacy);
        expect(c, isNotNull);
        expect(c!.candidateName, '');
      },
    );

    test('round-trips every field', () {
      final original = _card();
      final decoded = AdmitCardCodec.decode(AdmitCardCodec.encode(original));

      expect(decoded, isNotNull);
      final c = decoded!;
      expect(c.id, original.id);
      expect(c.examId, original.examId);
      expect(c.category, original.category);
      expect(c.examName, original.examName);
      expect(c.conductingBody, original.conductingBody);
      expect(c.examCode, original.examCode);
      expect(c.rollNumber, original.rollNumber);
      expect(c.registrationId, original.registrationId);
      expect(c.dobOrPortalPassword, original.dobOrPortalPassword);
      expect(c.centerCode, original.centerCode);
      expect(c.centerAddress, original.centerAddress);
      expect(c.gate, original.gate);
      expect(c.reportBy, original.reportBy);
      expect(c.examDate, original.examDate);
      expect(c.shift, original.shift);
      expect(c.createdAt, original.createdAt);
      expect(c.updatedAt, original.updatedAt);
      expect(c.rollNumberVerified, isTrue);
      expect(c.checklist, original.checklist);
    });

    test('rejects a truncated payload instead of throwing', () {
      final raw = AdmitCardCodec.encode(_card());
      final truncated = raw.substring(0, raw.length ~/ 2);

      expect(AdmitCardCodec.decode(truncated), isNull);
    });

    test('rejects unknown categories', () {
      final raw = AdmitCardCodec.encode(
        _card(),
      ).replaceFirst('"category":"ssc"', '"category":"alien_exam"');

      expect(AdmitCardCodec.decode(raw), isNull);
    });

    test('ignores unknown checklist ids but keeps the known ones', () {
      final raw = AdmitCardCodec.encode(_card()).replaceFirst(
        '["admitCardPdf","originalId"]',
        '["admitCardPdf","somethingNew"]',
      );

      final decoded = AdmitCardCodec.decode(raw);
      expect(decoded, isNotNull);
      expect(decoded!.checklist, {ChecklistItem.admitCardPdf});
    });

    test('defaults a missing updatedAt to createdAt', () {
      final raw = AdmitCardCodec.encode(
        _card(),
      ).replaceFirst(RegExp(r',"updatedAt":"[^"]*"'), '');

      final decoded = AdmitCardCodec.decode(raw);
      expect(decoded, isNotNull);
      expect(decoded!.updatedAt, decoded.createdAt);
    });
  });

  group('countdown', () {
    test('counts whole days between today and the exam', () {
      final now = DateTime(2026, 11, 8, 14, 30);
      final card = _card().copyWith(examDate: DateTime(2026, 11, 20));

      expect(card.daysUntilExam(now), 12);
    });

    test('is zero on exam day regardless of the clock time', () {
      final now = DateTime(2026, 11, 20, 23, 59);
      final card = _card().copyWith(examDate: DateTime(2026, 11, 20));

      expect(card.daysUntilExam(now), 0);
    });

    test('goes negative after the exam', () {
      final now = DateTime(2026, 11, 25);
      final card = _card().copyWith(examDate: DateTime(2026, 11, 20));

      expect(card.daysUntilExam(now), -5);
    });
  });

  group('checklist', () {
    test('is complete only when all three items are ticked', () {
      expect(_card().checklistComplete, isFalse);
      expect(
        _card()
            .copyWith(checklist: ChecklistItem.values.toSet())
            .checklistComplete,
        isTrue,
      );
    });
  });
}

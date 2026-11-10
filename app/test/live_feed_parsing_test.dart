import 'dart:convert';

import 'package:examvault/data/models/live_feed_dto.dart';
import 'package:examvault/domain/entities/exam_category.dart';
import 'package:examvault/domain/entities/live_update.dart';
import 'package:flutter_test/flutter_test.dart';

/// Feed parsing contract.
///
/// Write this file because of a real on-device defect: the repository decoded
/// edge bytes with `String.fromCharCodes`, which maps each byte to a code point,
/// so every multi-byte character arrived mangled — "Direct PDF · 18.4 MB" rendered
/// as "Direct PDF Â· 18.4 MB", and any Devanagari text would have been destroyed.
void main() {
  String doc(List<Map<String, dynamic>> updates, {String? generatedAt}) =>
      jsonEncode({
        'generated_at': generatedAt ?? '2026-11-09T10:00:00Z',
        'revision': 3,
        'updates': updates,
      });

  Map<String, dynamic> row({
    String examId = 'ssc_cgl_tier1_2026',
    String name = 'SSC CGL Tier-1 2026',
    String context = 'Direct PDF · 18.4 MB',
    String status = 'result_out',
    String category = 'ssc',
    String publishedAt = '2026-11-09T09:58:00Z',
  }) => {
    'exam_id': examId,
    'category': category,
    'exam_name': name,
    'context': context,
    'status': status,
    'published_at': publishedAt,
  };

  group('UTF-8 decoding', () {
    test('preserves the middle dot and other multi-byte characters', () {
      // This is the exact byte path the app takes: utf8 bytes -> utf8.decode.
      final bytes = utf8.encode(doc([row()]));
      final feed = LiveFeedDto.parse(utf8.decode(bytes, allowMalformed: true));

      expect(feed.updates.single.contextLine, 'Direct PDF · 18.4 MB');
      expect(feed.updates.single.contextLine.contains('Â'), isFalse);
    });

    test('preserves Devanagari exam names', () {
      final bytes = utf8.encode(doc([row(name: 'एसएससी सीजीएल टियर-1 2026')]));
      final feed = LiveFeedDto.parse(utf8.decode(bytes, allowMalformed: true));

      expect(feed.updates.single.examName, 'एसएससी सीजीएल टियर-1 2026');
    });
  });

  group('parsing', () {
    test('reads status, category and timestamp', () {
      final feed = LiveFeedDto.parse(doc([row()]));
      final u = feed.updates.single;

      expect(u.status, UpdateStatus.resultOut);
      expect(u.category, ExamCategory.ssc);
      expect(
        u.publishedAt.isAtSameMomentAs(
          DateTime.parse('2026-11-09T09:58:00Z').toLocal(),
        ),
        isTrue,
      );
    });

    test('skips malformed rows instead of blanking the feed', () {
      final feed = LiveFeedDto.parse(
        jsonEncode({
          'generated_at': '2026-11-09T10:00:00Z',
          'updates': [
            row(),
            {
              'exam_id': 'x',
              'category': 'not_a_category',
              'exam_name': 'Bad',
              'status': 'result_out',
              'published_at': '2026-11-09T09:00:00Z',
            },
            {'exam_name': 'No id'},
            row(examId: 'ibps_po_prelims_2026', name: 'IBPS PO Prelims 2026'),
          ],
        }),
      );

      expect(feed.updates.length, 2);
      expect(
        feed.updates.map((u) => u.examId),
        containsAll(['ssc_cgl_tier1_2026', 'ibps_po_prelims_2026']),
      );
    });

    test('sorts newest first so the radar leads with what just happened', () {
      final feed = LiveFeedDto.parse(
        doc([
          row(examId: 'old', publishedAt: '2026-11-08T09:00:00Z'),
          row(examId: 'new', publishedAt: '2026-11-09T09:59:00Z'),
        ]),
      );

      expect(feed.updates.first.examId, 'new');
      expect(feed.updates.last.examId, 'old');
    });

    test('liveCount only counts actionable statuses', () {
      final feed = LiveFeedDto.parse(
        jsonEncode({
          'generated_at': '2026-11-09T10:00:00Z',
          'updates': [
            row(examId: 'a', status: 'result_out'),
            row(examId: 'b', status: 'admit_card_live'),
            row(examId: 'c', status: 'form_closing'),
            row(examId: 'd', status: 'awaited'),
            row(examId: 'e', status: 'answer_key'),
          ],
        }),
      );

      expect(feed.liveCount, 3);
    });

    test('an empty updates array is valid and empty', () {
      final feed = LiveFeedDto.parse(doc([]));
      expect(feed.isEmpty, isTrue);
      expect(feed.liveCount, 0);
    });

    test('rejects a non-object document', () {
      expect(() => LiveFeedDto.parse('[]'), throwsA(isA<FormatException>()));
    });
  });

  group('expiry', () {
    test('uses the publisher expiry when supplied', () {
      final feed = LiveFeedDto.parse(
        jsonEncode({
          'generated_at': '2026-11-09T10:00:00Z',
          'updates': [
            {...row(), 'expires_at': '2026-11-09T11:00:00Z'},
          ],
        }),
      );

      final u = feed.updates.single;
      expect(u.expiresAt, isNotNull);
      expect(u.isExpired(DateTime.parse('2026-11-09T10:30:00Z')), isFalse);
      expect(u.isExpired(DateTime.parse('2026-11-09T11:30:00Z')), isTrue);
    });

    test('applies a per-status default TTL when omitted', () {
      final feed = LiveFeedDto.parse(doc([row()])); // result_out, 09:58Z
      final u = feed.updates.single;

      // result_out now defaults to 30 days — long enough that a real SSC notice
      // stays visible, short enough that a stale banner eventually clears.
      expect(
        u.expiresAt!.isAtSameMomentAs(
          DateTime.parse('2026-12-09T09:58:00Z').toLocal(),
        ),
        isTrue,
      );
    });

    test('a form-closing row survives the day it was posted', () {
      final feed = LiveFeedDto.parse(
        doc([row(status: 'form_closing', publishedAt: '2026-11-09T09:00:00Z')]),
      );
      final u = feed.updates.single;

      // Still relevant on the last day to apply…
      expect(
        u.isExpired(DateTime.parse('2026-11-10T09:00:00Z').toLocal()),
        isFalse,
      );
      // …and gone a week later.
      expect(
        u.isExpired(DateTime.parse('2026-11-17T09:00:00Z').toLocal()),
        isTrue,
      );
    });

    test('activeAt drops expired rows but keeps live ones', () {
      final feed = LiveFeedDto.parse(
        jsonEncode({
          'generated_at': '2026-11-09T10:00:00Z',
          'updates': [
            {...row(examId: 'gone'), 'expires_at': '2026-11-09T09:00:00Z'},
            {...row(examId: 'live'), 'expires_at': '2026-11-20T00:00:00Z'},
          ],
        }),
      );

      final active = feed.activeAt(
        DateTime.parse('2026-11-09T12:00:00Z').toLocal(),
      );
      expect(active.map((u) => u.examId), ['live']);
    });

    test('a feed whose rows have all expired reads as empty', () {
      final feed = LiveFeedDto.parse(
        jsonEncode({
          'generated_at': '2026-11-01T10:00:00Z',
          'updates': [
            {...row(), 'expires_at': '2026-11-02T10:00:00Z'},
          ],
        }),
      );

      expect(
        feed.activeAt(DateTime.parse('2026-11-09T10:00:00Z').toLocal()),
        isEmpty,
      );
      expect(feed.isEmpty, isFalse, reason: 'the document still has rows');
    });
  });

  group('round-trip', () {
    test('store json re-parses to the same content', () {
      final original = LiveFeedDto.parse(doc([row()]));
      final restored = LiveFeedStore.fromDynamic(
        LiveFeedStore.toJson(original),
      );

      expect(restored, isNotNull);
      expect(
        restored!.updates.single.examName,
        original.updates.single.examName,
      );
      expect(
        restored.updates.single.contextLine,
        original.updates.single.contextLine,
      );
    });
  });
}

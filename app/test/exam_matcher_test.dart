import 'package:examvault/domain/entities/exam_category.dart';
import 'package:examvault/domain/entities/live_update.dart';
import 'package:examvault/domain/services/exam_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

/// A saved admit card must be able to find its result.
///
/// The checker resolves the roll index from an exam id. Feed rows get theirs from
/// the commission's record; a hand-typed card gets a slug of whatever the student
/// wrote. Those never collide, so before this matcher a card alone could never
/// resolve an index and the checker reported "not published" for an exam that was
/// published — an honest answer that was still useless on result day.
void main() {
  LiveUpdate update({
    required String id,
    required String name,
    String context = 'Official PDF · upsc.gov.in',
    bool hasIndex = true,
    DateTime? publishedAt,
  }) => LiveUpdate(
    examId: id,
    category: ExamCategory.upsc,
    examName: name,
    contextLine: context,
    status: UpdateStatus.resultOut,
    publishedAt: publishedAt ?? DateTime(2026, 11, 6),
    indexVersion: hasIndex ? 'abc123abc123' : null,
    rollCount: hasIndex ? 100 : null,
  );

  group('categoryFor', () {
    test('recognises each commission from the exam name', () {
      expect(
        ExamMatcher.categoryFor('UPSC CSE Prelims 2027'),
        ExamCategory.upsc,
      );
      expect(ExamMatcher.categoryFor('SSC CGL Tier-1 2026'), ExamCategory.ssc);
      expect(ExamMatcher.categoryFor('SBI PO 2026'), ExamCategory.banking);
      expect(ExamMatcher.categoryFor('RRB NTPC'), ExamCategory.railways);
      expect(ExamMatcher.categoryFor('TNPSC Group IV'), ExamCategory.statePsc);
    });

    test('returns null rather than guessing wildly', () {
      expect(ExamMatcher.categoryFor('Nursery teacher recruitment'), isNull);
    });

    test('does not read "PSC" inside a word', () {
      // "psc" appears inside "descriptive" / "landscape"; a substring match would
      // misfile those as state PSC.
      expect(
        ExamMatcher.categoryFor('Descriptive Test'),
        isNot(ExamCategory.statePsc),
      );
    });
  });

  group('best', () {
    final feed = [
      update(
        id: 'upsc_csm_2026',
        name: 'Written Result: Civil Services (Main) Examination, 2026',
      ),
      update(
        id: 'upsc_ldce',
        name: "Final Result: Combined Section Officers' (Grade 'B') LDCE-2025",
      ),
      update(id: 'ssc_chsl', name: 'SSC CHSL 2025 Final Result'),
    ];

    test('a short typed name matches the long official headline', () {
      final match = ExamMatcher.best('UPSC Civil Services Main', feed);
      expect(match?.examId, 'upsc_csm_2026');
    });

    test('a typed year that contradicts the headline blocks the match', () {
      // This test pinned the OPPOSITE until the audit ("the exam is the same
      // and the roll is still worth checking"). It is not worth checking: a
      // 2027-cycle roll cannot appear in the 2026 published list, so the link
      // produced a confident false "not found" on result day — precisely the
      // wrong-verdict harm this file's contract names ("a wrong link would
      // point the student at another exam's candidate list, which is worse
      // than no link"). Last year's row is another cycle's candidate list.
      final match = ExamMatcher.best('Civil Services Main 2027', feed);
      expect(match, isNull);
    });

    test('a year the headline never mentions stays neutral', () {
      // Neutral means "neither helps nor blocks" — that only holds when the
      // candidate carries no year of its own to contradict.
      final noYear = [
        update(
          id: 'upsc_csm_next',
          name: 'Written Result: Civil Services (Main) Examination',
        ),
      ];
      final match = ExamMatcher.best('Civil Services Main 2027', noYear);
      expect(match?.examId, 'upsc_csm_next');
    });

    test('matches on distinctive words, not on "result"', () {
      // "result" is in every headline and must carry no weight, otherwise every
      // card links to whichever row happens to be newest.
      final match = ExamMatcher.best('SSC CHSL', feed);
      expect(match?.examId, 'ssc_chsl');
    });

    test('nothing close enough resolves to null, not to a wrong exam', () {
      expect(ExamMatcher.best('Kerala PSC Village Officer', feed), isNull);
    });

    test('an empty name matches nothing', () {
      expect(ExamMatcher.best('', feed), isNull);
      expect(ExamMatcher.best('   ', feed), isNull);
    });

    test('prefers a searchable row when scores tie', () {
      final tied = [
        update(
          id: 'no_index',
          name: 'Combined Defence Services Examination',
          hasIndex: false,
        ),
        update(
          id: 'with_index',
          name: 'Combined Defence Services Examination',
          hasIndex: true,
        ),
      ];

      expect(
        ExamMatcher.best('Combined Defence Services', tied)?.examId,
        'with_index',
      );
    });

    test('prefers the newest of two equally good searchable rows', () {
      final tied = [
        update(
          id: 'old',
          name: 'National Defence Academy Examination',
          publishedAt: DateTime(2026, 1, 1),
        ),
        update(
          id: 'new',
          name: 'National Defence Academy Examination',
          publishedAt: DateTime(2026, 11, 1),
        ),
      ];

      expect(ExamMatcher.best('National Defence Academy', tied)?.examId, 'new');
    });
  });

  test('score is bounded and ordered', () {
    final exact = ExamMatcher.score(
      'Civil Services Main',
      update(id: 'x', name: 'Civil Services Main'),
    );
    final partial = ExamMatcher.score(
      'Civil Services Main',
      update(id: 'y', name: 'Civil Services Preliminary'),
    );

    expect(exact, 1.0);
    expect(partial, lessThan(exact));
    expect(partial, greaterThanOrEqualTo(0));
  });
}

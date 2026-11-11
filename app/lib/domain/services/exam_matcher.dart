import '../../domain/entities/exam_category.dart';
import '../../domain/entities/live_update.dart';

/// Links a hand-typed admit card to a published result, when they are the same
/// exam.
///
/// ## Why this exists
///
/// The result checker resolves the exam id from the feed row the user tapped, or
/// from the saved card. A card is typed by hand, so its id is a slug of whatever
/// the student called the exam ("upsc_cse_prelims_2027"). The feed row's id is
/// derived from the commission's own record ("upsc_whats_new_…"). Those never
/// match — so a saved card alone could never find its index, and the checker
/// would honestly but uselessly report "not published" for an exam that was
/// published.
///
/// Rather than guess silently at check time, the match is made once, at save
/// time, where the form can show the student what it found. If nothing matches,
/// the card keeps its own id and the checker says so.
abstract final class ExamMatcher {
  /// Words that appear in almost every official headline and therefore carry no
  /// signal. Stripping them stops "Result" matching every result.
  static const _stop = {
    'result',
    'results',
    'final',
    'written',
    'declared',
    'declaration',
    'notice',
    'list',
    'candidates',
    'candidate',
    'examination',
    'exam',
    'the',
    'of',
    'and',
    'for',
    'with',
    'name',
    'names',
    'marks',
    'recommended',
    'qualified',
    'shortlisted',
    'stage',
    'paper',
  };

  /// Lowercase alphanumeric tokens, minus noise.
  static Set<String> _tokens(String text) {
    final normalised = text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
    return normalised
        .split(' ')
        .where((t) => t.length > 1 && !_stop.contains(t))
        .toSet();
  }

  /// Scores how well [update] matches the typed [examName], 0..1.
  ///
  /// Deliberately simple: token overlap weighted by the number of meaningful
  /// tokens in the shorter string. With a short typed name ("SSC CGL") and a
  /// long headline, only the shared tokens can count, so containment scores high
  /// without a long headline diluting it.
  static double score(String examName, LiveUpdate update) {
    final want = _tokens(examName);
    if (want.isEmpty) return 0;
    final have = _tokens('${update.examName} ${update.contextLine}');
    if (have.isEmpty) return 0;

    final yearRe = RegExp(r'^\d{4}$');
    final wantYears = want.where(yearRe.hasMatch).toSet();
    final haveYears = have.where(yearRe.hasMatch).toSet();
    // A typed year is a *requirement*, not a free point. The old rule added any
    // 4-digit token to the numerator unconditionally — "SSC JE 2027" scored
    // 2/3 (0.67 ≥ threshold) against a feed row for "SSC GD Constable Result
    // 2026" and pinned the wrong exam's id onto the card, so the checker then
    // searched another exam's roll index and reported a confident false "not
    // found". Contradicting years now block the match outright.
    if (wantYears.isNotEmpty &&
        haveYears.isNotEmpty &&
        wantYears.intersection(haveYears).isEmpty) {
      return 0;
    }

    var shared = 0;
    for (final token in want) {
      if (have.contains(token)) {
        shared += 1;
        continue;
      }
      // A year the headline does not mention at all stays neutral: the *exam*
      // can still be identified by its other tokens. (A headline that mentions
      // a *different* year was rejected above.)
      if (yearRe.hasMatch(token)) shared += 1;
    }
    return shared / want.length;
  }

  /// The best match at or above [threshold], newest first on ties.
  ///
  /// Returns null when nothing is close enough — a wrong link would point the
  /// student at another exam's candidate list, which is worse than no link.
  static LiveUpdate? best(
    String examName,
    Iterable<LiveUpdate> updates, {
    double threshold = 0.6,
  }) {
    LiveUpdate? winner;
    var bestScore = 0.0;
    for (final update in updates) {
      final s = score(examName, update);
      if (s < threshold || s < bestScore) continue;
      // Prefer an update we can actually search, then the newest.
      final current = winner;
      if (current != null && s == bestScore) {
        if (update.hasIndex && !current.hasIndex) {
          winner = update;
        } else if (!update.hasIndex && current.hasIndex) {
          continue;
        } else if (update.publishedAt.isAfter(current.publishedAt)) {
          winner = update;
        }
        continue;
      }
      winner = update;
      bestScore = s;
    }
    return winner;
  }

  /// Best guess at the category from the typed name alone, used to preselect the
  /// chip so a "UPSC CSE" card is not filed under SSC.
  static ExamCategory? categoryFor(String examName) {
    final h = examName.toLowerCase();
    if (RegExp(
      r'\b(upsc|civil services|ias|ifs|ips|nda|cds|capf|upsc cse)\b',
    ).hasMatch(h)) {
      return ExamCategory.upsc;
    }
    if (RegExp(
      r'\b(ibps|sbi|rbi|bank|po\b|clerk|nabard|rrb po)\b',
    ).hasMatch(h)) {
      return ExamCategory.banking;
    }
    if (RegExp(
      r'\b(rrb|railway|railways|ntpc|alp|group d|rpf)\b',
    ).hasMatch(h)) {
      return ExamCategory.railways;
    }
    if (RegExp(
      r'\b(tnpsc|mpsc|uppsc|bpsc|kpsc|appsc|tspsc|psc|state psc)\b',
    ).hasMatch(h)) {
      return ExamCategory.statePsc;
    }
    if (RegExp(r'\b(ssc|cgl|chsl|mts|gd|stenographer|je\b)\b').hasMatch(h)) {
      return ExamCategory.ssc;
    }
    return null;
  }
}

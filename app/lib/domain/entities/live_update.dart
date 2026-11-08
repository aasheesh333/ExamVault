import 'package:meta/meta.dart';

import 'exam_category.dart';

/// Severity of a radar row. Drives colour **and** the label — never colour alone.
enum UpdateStatus {
  resultOut('result_out', 'RESULT OUT'),
  admitCardLive('admit_card_live', 'ADMIT CARD LIVE'),
  formClosing('form_closing', 'CLOSING SOON'),
  answerKey('answer_key', 'ANSWER KEY'),
  awaited('awaited', 'AWAITED');

  const UpdateStatus(this.id, this.label);

  final String id;
  final String label;

  static UpdateStatus fromId(String? id) {
    for (final s in UpdateStatus.values) {
      if (s.id == id) return s;
    }
    return UpdateStatus.awaited;
  }
}

/// One row of the live radar. Mirrors `live_feed_v1.json` on the edge.
@immutable
class LiveUpdate {
  const LiveUpdate({
    required this.examId,
    required this.category,
    required this.examName,
    required this.contextLine,
    required this.status,
    required this.publishedAt,
    this.pdfSizeLabel,
    this.mirrorLatencyMs,
  });

  final String examId;
  final ExamCategory category;
  final String examName;

  /// One short, factual line: "Direct PDF · 18.4 MB".
  final String contextLine;
  final UpdateStatus status;
  final DateTime publishedAt;

  final String? pdfSizeLabel;

  /// Last measured latency of the fastest mirror, when known.
  final int? mirrorLatencyMs;

  bool isNewerThan(DateTime when) => publishedAt.isAfter(when);
}

/// The whole edge document.
@immutable
class LiveFeed {
  const LiveFeed({
    required this.generatedAt,
    required this.updates,
    required this.revision,
  });

  static const empty = LiveFeed(generatedAt: null, updates: [], revision: 0);

  /// Null when the server has never been reached and nothing is cached.
  final DateTime? generatedAt;
  final List<LiveUpdate> updates;
  final int revision;

  bool get isEmpty => updates.isEmpty;

  int countBy(UpdateStatus status) =>
      updates.where((u) => u.status == status).length;

  /// How many rows are "actionable right now" — used by the hero subtitle.
  /// This is deliberately *derived*, so the copy can never drift from the list
  /// the way a hardcoded "1 live update" did in the design.
  int get liveCount => updates
      .where(
        (u) =>
            u.status == UpdateStatus.resultOut ||
            u.status == UpdateStatus.admitCardLive ||
            u.status == UpdateStatus.formClosing,
      )
      .length;
}

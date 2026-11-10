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
    this.expiresAt,
    this.officialPdf,
    this.officialPage,
    this.indexVersion,
    this.rollCount,
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

  /// When this row stops being useful, supplied by the publisher.
  ///
  /// A radar that still shouts "RESULT OUT" three days later is worse than an
  /// empty one: the student taps through, finds nothing new, and stops trusting
  /// the app. Rows past this instant are dropped client-side.
  final DateTime? expiresAt;

  /// Direct link to the PDF on the commission's own server.
  ///
  /// The app never re-hosts this document — it opens the official URL. That keeps
  /// the app out of the business of redistributing government publications, and
  /// means a corrected PDF upstream is immediately the one users see.
  final String? officialPdf;

  /// The commission's own notice page, for rows whose announcement is HTML
  /// rather than a document (UPSC publishes both).
  ///
  /// Only ever a link. Nothing behind this URL is copied into the app.
  final String? officialPage;

  /// The best link to open for this update: the official document when one
  /// exists, otherwise the official notice page. `null` when the row carries
  /// neither — which the feed validator rejects, so in practice it is never null.
  String? get officialUrl => officialPdf ?? officialPage;

  /// Content hash of the published roll index, when one exists. Part of the CDN
  /// path, which is what lets the edge cache it as `immutable` safely.
  final String? indexVersion;

  /// Number of candidates in that index (already public information).
  final int? rollCount;

  /// True when this row has a searchable roll index behind it.
  bool get hasIndex => indexVersion != null;

  bool isNewerThan(DateTime when) => publishedAt.isAfter(when);

  bool isExpired(DateTime now) => expiresAt != null && now.isAfter(expiresAt!);
}

/// One commission the pipeline reads, and whether it answered.
///
/// Published by the producer in the feed's `sources` block. The app surfaces it
/// so a student can see *which* bodies are covered and which were unreachable —
/// an empty Railways section should not look like "no railway results exist".
@immutable
class SourceHealth {
  const SourceHealth({
    required this.id,
    required this.label,
    required this.status,
    required this.rows,
    this.homepage,
    this.note,
    this.checkedAt,
  });

  final String id;
  final String label;

  /// `ok`, `empty`, or `unavailable` — verbatim from the publisher.
  final String status;

  /// Rows this source contributed to the current document.
  final int rows;

  final String? homepage;
  final String? note;
  final DateTime? checkedAt;

  bool get isAvailable => status == 'ok' || status == 'empty';
}

/// The whole edge document.
@immutable
class LiveFeed {
  const LiveFeed({
    required this.generatedAt,
    required this.updates,
    required this.revision,
    this.sources = const [],
  });

  static const empty = LiveFeed(generatedAt: null, updates: [], revision: 0);

  /// Null when the server has never been reached and nothing is cached.
  final DateTime? generatedAt;
  final List<LiveUpdate> updates;
  final int revision;

  /// Per-commission health, as published. Empty for older documents and for the
  /// on-device copy of a feed that predates the field.
  final List<SourceHealth> sources;

  bool get isEmpty => updates.isEmpty;

  /// Rows that are still actionable right now.
  List<LiveUpdate> activeAt(DateTime now) =>
      updates.where((u) => !u.isExpired(now)).toList(growable: false);

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

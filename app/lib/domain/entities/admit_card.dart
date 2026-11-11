import 'package:meta/meta.dart';

import 'exam_category.dart';

/// The documents an aspirant must physically carry on exam day.
enum ChecklistItem {
  admitCardPdf('admitCardPdf', 'Admit card PDF saved', 'Available offline'),
  passportPhotos('passportPhotos', '2 passport photos', 'Recent, 50 × 50 mm'),
  originalId('originalId', 'Original photo ID', 'Aadhaar / PAN / DL');

  const ChecklistItem(this.id, this.title, this.subtitle);

  final String id;
  final String title;
  final String subtitle;

  static ChecklistItem? fromId(String? id) {
    if (id == null) return null;
    for (final i in ChecklistItem.values) {
      if (i.id == id) return i;
    }
    return null;
  }
}

/// A saved exam credential set.
///
/// This object is **only ever** held in memory or inside `flutter_secure_storage`.
/// It is written to Hive as ciphertext (see `SecureAdmitCardRepository`) — Hive is
/// used for the index, never for the values.
@immutable
class AdmitCard {
  const AdmitCard({
    required this.id,
    required this.examId,
    required this.category,
    required this.examName,
    required this.conductingBody,
    required this.examCode,
    required this.rollNumber,
    required this.registrationId,
    required this.dobOrPortalPassword,
    required this.centerCode,
    required this.centerAddress,
    required this.gate,
    required this.reportBy,
    required this.examDate,
    required this.shift,
    required this.createdAt,
    required this.updatedAt,
    this.rollNumberVerified = false,
    this.checklist = const {},
  });

  final String id;

  /// Stable slug used for CDN object names, e.g. `ssc_cgl_tier1_2026`.
  final String examId;
  final ExamCategory category;
  final String examName;
  final String conductingBody;
  final String examCode;

  final String rollNumber;
  final String registrationId;
  final String dobOrPortalPassword;
  final String centerCode;
  final String centerAddress;
  final String gate;
  final String reportBy;

  final DateTime examDate;
  final String shift;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// True once this roll number has been found in a published result index.
  final bool rollNumberVerified;

  final Set<ChecklistItem> checklist;

  /// Days until the exam. Negative once it has passed.
  int daysUntilExam([DateTime? now]) {
    final today = now ?? DateTime.now();
    // Calendar-date math in UTC. `Duration.inDays` between two *local*
    // midnights truncates across a DST shift: a 23-hour day made the eve of
    // the exam compute to 0, and the countdown read "TODAY" a day early —
    // on the one screen where being wrong is catastrophic. UTC has no DST,
    // so the difference is always an exact multiple of 24 h.
    final a = DateTime.utc(today.year, today.month, today.day);
    final b = DateTime.utc(examDate.year, examDate.month, examDate.day);
    return b.difference(a).inDays;
  }

  bool get checklistComplete => checklist.length == ChecklistItem.values.length;

  AdmitCard copyWith({
    String? examName,
    String? conductingBody,
    String? examCode,
    String? rollNumber,
    String? registrationId,
    String? dobOrPortalPassword,
    String? centerCode,
    String? centerAddress,
    String? gate,
    String? reportBy,
    DateTime? examDate,
    String? shift,
    DateTime? updatedAt,
    bool? rollNumberVerified,
    Set<ChecklistItem>? checklist,
  }) {
    return AdmitCard(
      id: id,
      examId: examId,
      category: category,
      examName: examName ?? this.examName,
      conductingBody: conductingBody ?? this.conductingBody,
      examCode: examCode ?? this.examCode,
      rollNumber: rollNumber ?? this.rollNumber,
      registrationId: registrationId ?? this.registrationId,
      dobOrPortalPassword: dobOrPortalPassword ?? this.dobOrPortalPassword,
      centerCode: centerCode ?? this.centerCode,
      centerAddress: centerAddress ?? this.centerAddress,
      gate: gate ?? this.gate,
      reportBy: reportBy ?? this.reportBy,
      examDate: examDate ?? this.examDate,
      shift: shift ?? this.shift,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      rollNumberVerified: rollNumberVerified ?? this.rollNumberVerified,
      checklist: checklist ?? this.checklist,
    );
  }
}

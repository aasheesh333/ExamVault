import '../../core/config/app_config.dart';

/// The five exam families ExamVault tracks.
///
/// `id` is used in CDN paths and secure-storage keys — never rename it without a
/// migration. `label` is the only thing that may change freely.
enum ExamCategory {
  ssc('ssc', 'SSC', AppConfig.topicSsc),
  upsc('upsc', 'UPSC', AppConfig.topicUpsc),
  banking('banking', 'Banking', AppConfig.topicBanking),
  railways('railways', 'Railways', AppConfig.topicRailways),
  statePsc('state_psc', 'State PSC', AppConfig.topicStatePsc);

  const ExamCategory(this.id, this.label, this.fcmTopic);

  final String id;
  final String label;

  /// FCM topic this category fans out to.
  final String fcmTopic;

  static ExamCategory? fromId(String? id) {
    if (id == null) return null;
    for (final c in ExamCategory.values) {
      if (c.id == id) return c;
    }
    return null;
  }
}

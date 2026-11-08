/// Compile-time configuration.
///
/// Everything here is overridable with `--dart-define` so the same binary can be
/// pointed at staging, a mirror, or a local fixture server without a rebuild of
/// the source. No secret is ever committed.
///
/// ```sh
/// flutter run \
///   --dart-define=EV_CDN_BASE=https://cdn.examvault.in \
///   --dart-define=EV_FIREBASE_API_KEY=... \
///   --dart-define=EV_FIREBASE_APP_ID=...
/// ```
abstract final class AppConfig {
  // ---------------------------------------------------------------- identity
  static const appName = 'ExamVault';
  static const supportEmail = 'support@examvault.in';

  /// Deep-link base used by the viral share card.
  static const webBase = String.fromEnvironment(
    'EV_WEB_BASE',
    defaultValue: 'https://examvault.in',
  );

  // -------------------------------------------------------------------- edge
  /// Cloudflare R2 custom domain. Requests hit the nearest PoP and are served
  /// from cache — origin (R2) sees one request per object per TTL window, which
  /// is what makes a 10M-user spike survivable on a free tier.
  static const cdnBase = String.fromEnvironment(
    'EV_CDN_BASE',
    defaultValue: 'https://cdn.examvault.in',
  );

  /// The single edge document the radar renders. One object, one cache key.
  static const liveFeedPath = '/v1/live_feed_v1.json';

  /// gzip-compressed, lexicographically sorted JSON array of roll numbers.
  /// ~150 KB on the wire for a 1M-row result set.
  static String rollIndexPath(String examId) =>
      '/v1/rolls/${examId}_rolls.json.gz';

  /// Human-facing official PDF (mirrored, so the source site never gets hit).
  static String resultPdfPath(String examId) => '/v1/pdf/${examId}_result.pdf';

  /// The R2 object is stored as `application/gzip` with **no** `Content-Encoding`
  /// header, so the socket does not transparently decompress it. We decompress
  /// deliberately inside an isolate. If ops ever enables `Content-Encoding: gzip`
  /// this flips to true and the isolate skips `gzip.decode`.
  static const rollIndexIsTransportEncoded = bool.fromEnvironment(
    'EV_ROLLS_TRANSPORT_ENCODED',
    defaultValue: false,
  );

  // ------------------------------------------------------------------- cache
  /// Radar poll cadence. Matches the object's `s-maxage` so we never pay for a
  /// request the edge would answer from cache anyway.
  static const feedPollInterval = Duration(seconds: 60);

  /// A cached feed younger than this is used with no network call at all.
  static const feedFreshWindow = Duration(seconds: 60);

  /// Past this age we still paint the cached feed (offline boot) but show a
  /// "stale" affordance and refresh in the background.
  static const feedStaleWindow = Duration(hours: 72);

  /// Roll indexes change rarely — a day is conservative and keeps egress at ~0.
  static const rollIndexFreshWindow = Duration(hours: 12);

  // ----------------------------------------------------------------- network
  static const connectTimeout = Duration(seconds: 8);
  static const receiveTimeout = Duration(seconds: 20);
  static const maxDownloadBytes = 12 * 1024 * 1024;
  static const maxAttempts = 3;

  // -------------------------------------------------------------------- push
  /// FCM topic per exam family. Published by the (free) FCM topic fan-out.
  static const topicSsc = 'exam_ssc';
  static const topicUpsc = 'exam_upsc';
  static const topicBanking = 'exam_banking';
  static const topicRailways = 'exam_railways';
  static const topicStatePsc = 'exam_state_psc';

  /// Firebase is configured at runtime. When these are empty the app runs
  /// perfectly — push is simply disabled. This keeps the repository buildable
  /// without shipping a `google-services.json`.
  static const firebaseApiKey = String.fromEnvironment('EV_FIREBASE_API_KEY');
  static const firebaseAppId = String.fromEnvironment('EV_FIREBASE_APP_ID');
  static const firebaseMessagingSenderId = String.fromEnvironment(
    'EV_FIREBASE_SENDER_ID',
  );
  static const firebaseProjectId = String.fromEnvironment(
    'EV_FIREBASE_PROJECT_ID',
  );
  static const firebaseStorageBucket = String.fromEnvironment(
    'EV_FIREBASE_STORAGE_BUCKET',
  );

  static bool get pushConfigured =>
      firebaseApiKey.isNotEmpty &&
      firebaseAppId.isNotEmpty &&
      firebaseMessagingSenderId.isNotEmpty;

  /// OneSignal App ID. When set, OneSignal is preferred over FCM — it is the
  /// path that still works when a Firebase project is unavailable.
  static const oneSignalAppId = String.fromEnvironment('EV_ONESIGNAL_APP_ID');

  // --------------------------------------------------------------------- hive
  static const boxAdmitCards = 'admit_cards_v1';
  static const boxLiveFeed = 'live_feed_v1';
  static const boxSettings = 'settings_v1';
  static const boxHttpCache = 'http_cache_v1';

  // ------------------------------------------------------------ secure store
  static const secureNamespace = 'examvault.vault.v1';
  static const secureIndexKey = 'examvault.vault.v1.index';
}

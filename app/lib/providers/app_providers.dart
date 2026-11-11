import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import '../core/config/app_config.dart';
import '../data/repositories/admit_card_repository.dart';
import '../data/repositories/live_feed_repository.dart';
import '../data/repositories/result_index_repository.dart';
import '../data/remote/cdn_client.dart';
import '../data/services/app_logger.dart';
import '../data/services/push_service.dart';
import '../data/services/share_service.dart';
import '../domain/entities/admit_card.dart';
import '../domain/entities/exam_category.dart';
import '../domain/entities/live_update.dart';
import '../features/result_checker/engine/roll_index_engine.dart';

/// ---------------------------------------------------------------------------
/// Infrastructure — overridden in `main.dart` after Hive has opened.
/// ---------------------------------------------------------------------------

final httpCacheBoxProvider = Provider<Box<dynamic>>(
  (ref) => throw UnimplementedError('override httpCacheBoxProvider in main()'),
);

final settingsBoxProvider = Provider<Box<dynamic>>(
  (ref) => throw UnimplementedError('override settingsBoxProvider in main()'),
);

/// Light / dark / follow-system.
///
/// The palette already shipped both modes with contrast verified for each, but
/// the app was hardwired to `ThemeMode.dark` — so half the design system was dead
/// code and a student on a bright train had no way out of a dark screen.
///
/// Default is `system`: a utility should look like the rest of the phone unless
/// the user says otherwise.
enum ThemePreference {
  system('system', 'Match system'),
  light('light', 'Light'),
  dark('dark', 'Dark');

  const ThemePreference(this.id, this.label);

  final String id;
  final String label;

  static ThemePreference fromId(String? id) {
    for (final p in values) {
      if (p.id == id) return p;
    }
    return ThemePreference.system;
  }

  ThemeMode get mode => switch (this) {
    ThemePreference.system => ThemeMode.system,
    ThemePreference.light => ThemeMode.light,
    ThemePreference.dark => ThemeMode.dark,
  };
}

class ThemePreferenceNotifier extends Notifier<ThemePreference> {
  static const _key = 'theme';

  @override
  ThemePreference build() {
    final box = ref.watch(settingsBoxProvider);
    // A non-String value used to throw TypeError here, escaping into the app
    // build and bricking the theme; treat anything unexpected as "system".
    final raw = box.get(_key);
    return ThemePreference.fromId(raw is String ? raw : null);
  }

  Future<void> select(ThemePreference pref) async {
    final previous = state;
    state = pref;
    try {
      await ref.read(settingsBoxProvider).put(_key, pref.id);
    } catch (_) {
      // A failed settings write must not leave the UI claiming a preference
      // that will be gone on next launch, so roll the state back.
      state = previous;
    }
  }
}

final themePreferenceProvider =
    NotifierProvider<ThemePreferenceNotifier, ThemePreference>(
      ThemePreferenceNotifier.new,
    );

final cdnClientProvider = Provider<CdnClient>((ref) {
  final client = CdnClient(cache: ref.watch(httpCacheBoxProvider));
  ref.onDispose(client.dispose);
  return client;
});

final admitCardRepositoryProvider = Provider<AdmitCardRepository>((ref) {
  final repo = AdmitCardRepository();
  ref.onDispose(repo.dispose);
  return repo;
});

final liveFeedRepositoryProvider = Provider<LiveFeedRepository>((ref) {
  return LiveFeedRepository(
    cdn: ref.watch(cdnClientProvider),
    cache: ref.watch(httpCacheBoxProvider),
  );
});

final resultIndexRepositoryProvider = Provider<ResultIndexRepository>((ref) {
  return ResultIndexRepository(cdn: ref.watch(cdnClientProvider));
});

final pushServiceProvider = Provider<PushService>((ref) {
  final service = PushService();
  ref.onDispose(service.dispose);
  return service;
});

final shareServiceProvider = Provider<ShareService>((ref) => ShareService());

/// ---------------------------------------------------------------------------
/// Vault
/// ---------------------------------------------------------------------------

/// All saved cards, soonest exam first.
///
/// The notifier keeps state in memory and mirrors the repository stream, so the
/// UI rebuilds exactly once per mutation instead of once per listener.
class AdmitCardsNotifier extends AsyncNotifier<List<AdmitCard>> {
  @override
  Future<List<AdmitCard>> build() async {
    final repo = ref.watch(admitCardRepositoryProvider);

    // Subscribe BEFORE the first load resolves — `changes` is the source of
    // truth for this state. Subscribing after `await repo.load()` missed every
    // emit that fired while the Keystore read was in flight (a save landed
    // during boot), and Riverpod applies this build future's value
    // unconditionally when it resolves — the vault visibly rolled back to its
    // pre-save snapshot until the next mutation.
    final sub = repo.changes.listen((cards) {
      state = AsyncData(cards);
    });
    ref.onDispose(sub.cancel);

    await repo.load();

    // Resolve with the cache read at *resolution time*, not the list `load()`
    // returned: a write that landed mid-load has already updated `repo.cached`,
    // and this future is applied after it.
    return repo.cached;
  }

  Future<AdmitCard> save(AdmitCard card) async {
    final repo = ref.read(admitCardRepositoryProvider);
    final saved = await repo.save(card);
    state = AsyncData(repo.cached);
    return saved;
  }

  Future<void> delete(String id) async {
    final repo = ref.read(admitCardRepositoryProvider);
    await repo.delete(id);
    state = AsyncData(repo.cached);
  }

  Future<void> toggleChecklist(String id, ChecklistItem item) async {
    final repo = ref.read(admitCardRepositoryProvider);
    await repo.toggleChecklist(id, item);
    state = AsyncData(repo.cached);
  }

  Future<void> markVerified(String id) async {
    final repo = ref.read(admitCardRepositoryProvider);
    await repo.markVerified(id);
    state = AsyncData(repo.cached);
  }
}

final admitCardsProvider =
    AsyncNotifierProvider<AdmitCardsNotifier, List<AdmitCard>>(
      AdmitCardsNotifier.new,
    );

/// The card whose pass sits on top of the stack.
final primaryCardProvider = Provider<AdmitCard?>((ref) {
  final cards = ref.watch(admitCardsProvider).value;
  if (cards == null || cards.isEmpty) return null;

  final now = DateTime.now();
  for (final c in cards) {
    if (c.examDate.isAfter(now)) return c;
  }
  return cards.first;
});

/// ---------------------------------------------------------------------------
/// Filters
/// ---------------------------------------------------------------------------

/// `null` == "All".
class CategoryFilterNotifier extends Notifier<ExamCategory?> {
  @override
  ExamCategory? build() => null;

  void select(ExamCategory? category) => state = category;
}

final categoryFilterProvider =
    NotifierProvider<CategoryFilterNotifier, ExamCategory?>(
      CategoryFilterNotifier.new,
    );

/// Free-text query over the radar and the saved cards.
///
/// The radar carries 60 rows from five commissions — roughly five and a half
/// screens of scrolling — and the category chips only narrow it to about 20. A
/// student looking for "RRB CEN 01/2025" had no way to ask for it by name, and no
/// way at all to find the radar row that matches the card already in their wallet.
class SearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String value) => state = value.trim();

  void clear() => state = '';
}

final searchQueryProvider = NotifierProvider<SearchQueryNotifier, String>(
  SearchQueryNotifier.new,
);

/// Case- and accent-insensitive token match.
///
/// Deliberately forgiving: the user is typing a fragment of a long official
/// headline ("civil serv", "rrb cen 01"), so it matches on all query tokens being
/// present anywhere in the haystack rather than on a prefix.
bool _matchesQuery(String query, String haystack) {
  if (query.isEmpty) return true;
  final hay = haystack.toLowerCase();
  for (final token in query.toLowerCase().split(RegExp(r'\s+'))) {
    if (token.isEmpty) continue;
    if (!hay.contains(token)) return false;
  }
  return true;
}

/// Vault cards after the active category filter and search query.
final filteredCardsProvider = Provider<List<AdmitCard>>((ref) {
  final cards = ref.watch(admitCardsProvider).value ?? const [];
  final filter = ref.watch(categoryFilterProvider);
  final query = ref.watch(searchQueryProvider);

  return cards
      .where((c) {
        if (filter != null && c.category != filter) return false;
        return _matchesQuery(
          query,
          '${c.examName} ${c.examCode} ${c.conductingBody} ${c.rollNumber}',
        );
      })
      .toList(growable: false);
});

/// ---------------------------------------------------------------------------
/// Live radar
/// ---------------------------------------------------------------------------

class LiveFeedNotifier extends AsyncNotifier<LiveFeedSnapshot> {
  Timer? _timer;
  AppLifecycleListener? _lifecycle;

  @override
  Future<LiveFeedSnapshot> build() async {
    final repo = ref.watch(liveFeedRepositoryProvider);

    // 1. Instant paint from disk on the very first frame.
    final cached = repo.readCached() ?? repo.emptySnapshot();

    // 2. Refresh in the background; the UI already has something to show.
    unawaited(_refreshInto(repo));

    // 3. Poll only while this notifier is alive, and never faster than the edge
    //    TTL — polling a cached object more often than the cache is useless.
    _startPolling(repo);

    // 4. Stop burning radio time while the app is backgrounded, and catch up
    //    immediately on resume instead of waiting out the rest of the interval.
    _lifecycle?.dispose();
    _lifecycle = AppLifecycleListener(
      onPause: () => _timer?.cancel(),
      onHide: () => _timer?.cancel(),
      onResume: () {
        _startPolling(repo);
        unawaited(_refreshInto(repo));
      },
    );

    ref.onDispose(() {
      _timer?.cancel();
      _lifecycle?.dispose();
    });

    return cached;
  }

  void _startPolling(LiveFeedRepository repo) {
    _timer?.cancel();
    _timer = Timer.periodic(AppConfig.feedPollInterval, (_) {
      unawaited(_refreshInto(repo));
    });
  }

  Future<void> _refreshInto(LiveFeedRepository repo) async {
    final snapshot = await repo.refresh();
    if (!ref.mounted) return;
    state = AsyncData(snapshot);
  }

  /// Pull-to-refresh / manual retry.
  Future<void> refresh({bool force = false}) async {
    final repo = ref.read(liveFeedRepositoryProvider);
    final snapshot = await repo.refresh(force: force);
    // A refresh can outlive the notifier (tab switch); writing `state` after
    // disposal throws. `_refreshInto` already guarded this, `refresh` did not.
    if (!ref.mounted) return;
    state = AsyncData(snapshot);
  }
}

final liveFeedProvider =
    AsyncNotifierProvider<LiveFeedNotifier, LiveFeedSnapshot>(
      LiveFeedNotifier.new,
    );

/// Radar rows after the active category filter.
///
/// [includeExpired] is the opt-in a future "past notices" view can use; the
/// radar itself must never show a row the publisher has already retired.
List<LiveUpdate> filterUpdates(
  LiveFeed? feed,
  ExamCategory? filter, {
  bool includeExpired = false,
  DateTime? now,
  String query = '',
}) {
  if (feed == null) return const [];
  final rows = includeExpired
      ? feed.updates
      : feed.activeAt(now ?? DateTime.now());
  final byCategory = filter == null
      ? rows
      : rows.where((u) => u.category == filter);
  if (query.isEmpty) return byCategory.toList(growable: false);
  return byCategory
      .where((u) => _matchesQuery(query, '${u.examName} ${u.contextLine}'))
      .toList(growable: false);
}

final filteredUpdatesProvider = Provider<List<LiveUpdate>>((ref) {
  final feed = ref.watch(liveFeedProvider).value?.feed;
  final filter = ref.watch(categoryFilterProvider);
  final query = ref.watch(searchQueryProvider);
  // Expired rows used to render as green "RESULT OUT" for months; the publisher
  // already told us when each row stops being useful.
  return filterUpdates(feed, filter, query: query);
});

/// True when a search is running and matched nothing — the UI shows the "no
/// matches" state instead of the empty-feed state.
final searchActiveProvider = Provider<bool>(
  (ref) => ref.watch(searchQueryProvider).isNotEmpty,
);

/// ---------------------------------------------------------------------------
/// Instant result checker
/// ---------------------------------------------------------------------------

class ResultCheckState {
  const ResultCheckState({
    required this.phase,
    this.examId,
    this.result,
    this.indexSource,
    this.error,
  });

  const ResultCheckState.idle()
    : phase = ResultPhase.idle,
      examId = null,
      result = null,
      indexSource = null,
      error = null;

  final ResultPhase phase;

  /// Which exam this verdict belongs to.
  ///
  /// Without it, tapping radar row B kept rendering row A's "Roll X was not
  /// found" under B's title, because the state had no identity to compare.
  final String? examId;
  final RollLookupResult? result;
  final IndexSource? indexSource;
  final String? error;

  bool get isBusy =>
      phase == ResultPhase.downloading || phase == ResultPhase.searching;

  bool get isUnavailable => phase == ResultPhase.unavailable;

  /// True only when this verdict was produced for [examId]; the UI should hide
  /// a stale result rather than re-render another exam's answer.
  bool belongsTo(String examId) => this.examId == examId;
}

enum ResultPhase {
  idle,
  downloading,
  searching,
  done,

  /// The index does not exist yet (or could not be fetched). Distinct from a
  /// completed search that found nothing.
  unavailable,
}

class ResultCheckerNotifier extends Notifier<ResultCheckState> {
  /// Monotonic request token: a slow earlier lookup that resolves after a newer
  /// one must not overwrite it. Without this, A's verdict could land on B.
  int _seq = 0;

  @override
  ResultCheckState build() => const ResultCheckState.idle();

  Future<RollLookupResult?> check({
    required String examId,
    required String rollNumber,
    String? indexVersion,
    bool force = false,
  }) async {
    final seq = ++_seq;
    state = ResultCheckState(phase: ResultPhase.downloading, examId: examId);

    try {
      final repo = ref.read(resultIndexRepositoryProvider);
      final bundle = await repo.load(
        examId: examId,
        version: indexVersion,
        force: force,
      );
      if (seq != _seq) return null; // superseded by a newer check

      // No index means no answer. Never synthesise one — a wrong "selected"
      // is worse than an honest "not published yet".
      if (!bundle.hasData) {
        state = ResultCheckState(
          phase: ResultPhase.unavailable,
          examId: examId,
          indexSource: bundle.source,
          error:
              bundle.reason ??
              'The result for this exam has not been published yet.',
        );
        return null;
      }

      state = ResultCheckState(
        phase: ResultPhase.searching,
        examId: examId,
        indexSource: bundle.source,
      );

      final result = await RollIndexEngine.searchCompressed(
        compressed: bundle.bytes,
        rollNumber: rollNumber,
        // The documented ops escape hatch was dead: the define existed, the
        // engine parameter existed, and nothing connected them. If the edge
        // ever serves Content-Encoding: gzip (transport-decoded by the HTTP
        // stack), flipping EV_ROLLS_TRANSPORT_ENCODED now actually skips the
        // second gunzip instead of silently doing nothing.
        transportEncoded: AppConfig.rollIndexIsTransportEncoded,
      );
      if (seq != _seq) return null;

      state = ResultCheckState(
        phase: result.state == RollLookupState.indexUnavailable
            ? ResultPhase.unavailable
            : ResultPhase.done,
        examId: examId,
        result: result,
        indexSource: bundle.source,
        error: result.errorMessage,
      );
      return result;
    } catch (e, st) {
      if (seq != _seq) return null;
      // Never surface a Dart exception string to a student on exam morning.
      AppLogger.e('checker', 'lookup failed', e, st);
      state = ResultCheckState(
        phase: ResultPhase.unavailable,
        examId: examId,
        error:
            'Could not reach the result index. Check your connection and '
            'tap again — nothing was lost.',
      );
      return null;
    }
  }

  void reset() {
    // Invalidate any in-flight lookup so it cannot repaint after a reset.
    _seq++;
    state = const ResultCheckState.idle();
  }
}

final resultCheckerProvider =
    NotifierProvider<ResultCheckerNotifier, ResultCheckState>(
      ResultCheckerNotifier.new,
    );

/// ---------------------------------------------------------------------------
/// Navigation state shared between screens
/// ---------------------------------------------------------------------------

/// Which vault entry the detail screen is showing.
class SelectedCardIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? id) => state = id;
}

final selectedCardIdProvider =
    NotifierProvider<SelectedCardIdNotifier, String?>(
      SelectedCardIdNotifier.new,
    );

/// The exam whose result the checker should open.
///
/// Tapping a radar row sets this, so the checker never asks the user to pick the
/// exam again — one tap from "UPSC result is out" to "am I selected".
class ResultExamNotifier extends Notifier<LiveUpdate?> {
  @override
  LiveUpdate? build() => null;

  void select(LiveUpdate? update) => state = update;
}

final resultExamIdProvider = NotifierProvider<ResultExamNotifier, LiveUpdate?>(
  ResultExamNotifier.new,
);

/// When the user last opened the alerts inbox.
///
/// The badge used to count every live row and nothing ever cleared it, so it read
/// "9+" permanently and stopped meaning anything. It now counts updates published
/// since the inbox was last opened.
class AlertsSeenNotifier extends Notifier<DateTime> {
  static const _key = 'alerts_seen_at';

  @override
  DateTime build() {
    final box = ref.watch(settingsBoxProvider);
    final raw = box.get(_key);
    final parsed = raw is String ? DateTime.tryParse(raw) : null;
    return parsed ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  Future<void> markSeen([DateTime? at]) async {
    final value = at ?? DateTime.now();
    state = value;
    try {
      await ref.read(settingsBoxProvider).put(_key, value.toIso8601String());
    } catch (_) {
      // A failed write only means the badge reappears; not worth interrupting.
    }
  }
}

final alertsSeenProvider = NotifierProvider<AlertsSeenNotifier, DateTime>(
  AlertsSeenNotifier.new,
);

/// Number shown on the radar tab badge — expired rows do not count.
final liveRadarBadgeProvider = Provider<int>((ref) {
  final feed = ref.watch(liveFeedProvider).value?.feed;
  if (feed == null) return 0;
  final seen = ref.watch(alertsSeenProvider);
  final now = DateTime.now();
  return feed
      .activeAt(now)
      .where(
        (u) =>
            u.publishedAt.isAfter(seen) &&
            (u.status == UpdateStatus.resultOut ||
                u.status == UpdateStatus.admitCardLive ||
                u.status == UpdateStatus.formClosing),
      )
      .length;
});

/// ---------------------------------------------------------------------------
/// Day tick
/// ---------------------------------------------------------------------------

/// Rebuilds watchers once per calendar day, and on every app resume.
///
/// Countdowns ("IN 2 DAYS", "TODAY") are computed from `DateTime.now()` at
/// build time. Screens that live inside the shell's IndexedStack get no other
/// reason to rebuild overnight, so a student who left the app open until exam
/// morning watched a stale "IN 1 DAYS" at 7:40 AM. Watching this provider ties
/// those builds to the date instead of to luck.
class DayTickNotifier extends Notifier<DateTime> {
  Timer? _timer;
  AppLifecycleListener? _lifecycle;

  @override
  DateTime build() {
    ref.onDispose(() {
      _timer?.cancel();
      _lifecycle?.dispose();
    });
    _scheduleMidnight();
    _lifecycle = AppLifecycleListener(
      onResume: () {
        state = DateTime.now();
        _scheduleMidnight();
      },
    );
    return DateTime.now();
  }

  void _scheduleMidnight() {
    _timer?.cancel();
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day + 1);
    _timer = Timer(midnight.difference(now), () {
      if (!ref.mounted) return;
      state = DateTime.now();
      _scheduleMidnight();
    });
  }
}

final dayTickProvider = NotifierProvider<DayTickNotifier, DateTime>(
  DayTickNotifier.new,
);

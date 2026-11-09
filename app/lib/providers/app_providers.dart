import 'dart:async';

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
    final loaded = await repo.load();

    final sub = repo.changes.listen((cards) {
      state = AsyncData(cards);
    });
    ref.onDispose(sub.cancel);

    return loaded;
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

/// Vault cards after the active category filter.
final filteredCardsProvider = Provider<List<AdmitCard>>((ref) {
  final cards = ref.watch(admitCardsProvider).value ?? const [];
  final filter = ref.watch(categoryFilterProvider);
  if (filter == null) return cards;
  return cards.where((c) => c.category == filter).toList(growable: false);
});

/// ---------------------------------------------------------------------------
/// Live radar
/// ---------------------------------------------------------------------------

class LiveFeedNotifier extends AsyncNotifier<LiveFeedSnapshot> {
  Timer? _timer;

  @override
  Future<LiveFeedSnapshot> build() async {
    final repo = ref.watch(liveFeedRepositoryProvider);

    // 1. Instant paint from disk on the very first frame.
    final cached = repo.readCached() ?? repo.emptySnapshot();

    // 2. Refresh in the background; the UI already has something to show.
    unawaited(_refreshInto(repo));

    // 3. Poll only while this notifier is alive, and never faster than the edge
    //    TTL — polling a cached object more often than the cache is useless.
    _timer = Timer.periodic(AppConfig.feedPollInterval, (_) {
      unawaited(_refreshInto(repo));
    });
    ref.onDispose(() => _timer?.cancel());

    return cached;
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
    state = AsyncData(snapshot);
  }
}

final liveFeedProvider =
    AsyncNotifierProvider<LiveFeedNotifier, LiveFeedSnapshot>(
      LiveFeedNotifier.new,
    );

/// Radar rows after the active category filter.
final filteredUpdatesProvider = Provider<List<LiveUpdate>>((ref) {
  final feed = ref.watch(liveFeedProvider).value?.feed;
  if (feed == null) return const [];

  final filter = ref.watch(categoryFilterProvider);
  if (filter == null) return feed.updates;
  return feed.updates
      .where((u) => u.category == filter)
      .toList(growable: false);
});

/// ---------------------------------------------------------------------------
/// Instant result checker
/// ---------------------------------------------------------------------------

class ResultCheckState {
  const ResultCheckState({
    required this.phase,
    this.result,
    this.indexSource,
    this.warmIndex,
    this.error,
  });

  const ResultCheckState.idle()
    : phase = ResultPhase.idle,
      result = null,
      indexSource = null,
      warmIndex = null,
      error = null;

  final ResultPhase phase;
  final RollLookupResult? result;
  final IndexSource? indexSource;

  /// Kept so a second tap is a pure binary search, not a re-download.
  final RollIndex? warmIndex;
  final String? error;

  bool get isBusy =>
      phase == ResultPhase.downloading || phase == ResultPhase.searching;

  bool get isUnavailable => phase == ResultPhase.unavailable;
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
  @override
  ResultCheckState build() => const ResultCheckState.idle();

  Future<RollLookupResult?> check({
    required String examId,
    required String rollNumber,
  }) async {
    state = const ResultCheckState(phase: ResultPhase.downloading);

    try {
      final repo = ref.read(resultIndexRepositoryProvider);
      final bundle = await repo.load(examId: examId);

      // No index means no answer. Never synthesise one — a wrong "selected"
      // is worse than an honest "not published yet".
      if (!bundle.hasData) {
        state = ResultCheckState(
          phase: ResultPhase.unavailable,
          indexSource: bundle.source,
          error:
              bundle.reason ??
              'The result for this exam has not been published yet.',
        );
        return null;
      }

      state = ResultCheckState(
        phase: ResultPhase.searching,
        indexSource: bundle.source,
      );

      final result = await RollIndexEngine.searchCompressed(
        compressed: bundle.bytes,
        rollNumber: rollNumber,
      );

      state = ResultCheckState(
        phase: result.state == RollLookupState.indexUnavailable
            ? ResultPhase.unavailable
            : ResultPhase.done,
        result: result,
        indexSource: bundle.source,
        error: result.errorMessage,
      );
      return result;
    } catch (e, st) {
      // Never surface a Dart exception string to a student on exam morning.
      AppLogger.e('checker', 'lookup failed', e, st);
      state = const ResultCheckState(
        phase: ResultPhase.unavailable,
        error:
            'Could not reach the result index. Check your connection and '
            'tap again — nothing was lost.',
      );
      return null;
    }
  }

  void reset() => state = const ResultCheckState.idle();
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

/// Number shown on the radar tab badge — expired rows do not count.
final liveRadarBadgeProvider = Provider<int>((ref) {
  final feed = ref.watch(liveFeedProvider).value?.feed;
  if (feed == null) return 0;
  final now = DateTime.now();
  return feed
      .activeAt(now)
      .where(
        (u) =>
            u.status == UpdateStatus.resultOut ||
            u.status == UpdateStatus.admitCardLive ||
            u.status == UpdateStatus.formClosing,
      )
      .length;
});

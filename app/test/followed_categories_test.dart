import 'dart:typed_data';

import 'package:examvault/data/services/push_service.dart';
import 'package:examvault/domain/entities/exam_category.dart';
import 'package:examvault/main.dart';
import 'package:examvault/providers/app_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

/// The category picker the About sheet and the privacy policy promised.
///
/// Both documents said the push token was used "for the categories you follow",
/// while `_bootPush` subscribed every device to all five and nothing could be
/// followed. These tests pin the three properties that make the claim true: the
/// stored set is what boot syncs, a toggle persists, and an empty set is a real
/// choice rather than something the app silently repairs back to "everything".
void main() {
  late Box<dynamic> settingsBox;

  setUp(() async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    settingsBox = await Hive.openBox<dynamic>(
      'followed$stamp',
      bytes: Uint8List(0),
    );
  });

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [settingsBoxProvider.overrideWithValue(settingsBox)],
    );
    addTearDown(c.dispose);
    return c;
  }

  group('FollowedCategoriesNotifier', () {
    test('defaults to all five when nothing was ever chosen', () {
      // The key has never existed: every pre-picker install was subscribed to
      // all five, and a fresh install must not silently receive nothing.
      final c = container();
      expect(c.read(followedCategoriesProvider), ExamCategory.values.toSet());
    });

    test('a toggle persists and survives a rebuild', () async {
      final c = container();
      final next = await c
          .read(followedCategoriesProvider.notifier)
          .toggle(ExamCategory.ssc);

      expect(next, isNot(contains(ExamCategory.ssc)));
      expect((settingsBox.get(followedCategoriesSettingKey) as List).toSet(), {
        'upsc',
        'banking',
        'railways',
        'state_psc',
      });

      // A new container over the same box is what a cold start sees.
      final restarted = container();
      expect(restarted.read(followedCategoriesProvider), next);
    });

    test(
      'unknown ids in the stored list are dropped, the rest survive',
      () async {
        // A category removed in a later release must not take the whole list with
        // it — same per-item tolerance as ExamAlertsNotifier.
        await settingsBox.put(followedCategoriesSettingKey, [
          'ssc',
          'retired_category',
          42,
          'railways',
        ]);

        expect(container().read(followedCategoriesProvider), {
          ExamCategory.ssc,
          ExamCategory.railways,
        });
      },
    );

    test(
      'an empty stored set stays empty instead of becoming all five',
      () async {
        // The student turned everything off. Coercing that back to all five would
        // subscribe them to alerts they explicitly refused.
        await settingsBox.put(followedCategoriesSettingKey, <String>[]);

        expect(container().read(followedCategoriesProvider), isEmpty);
      },
    );

    test('turning the last category off persists the empty set', () async {
      final c = container();
      for (final category in ExamCategory.values) {
        await c.read(followedCategoriesProvider.notifier).toggle(category);
      }

      expect(c.read(followedCategoriesProvider), isEmpty);
      expect(settingsBox.get(followedCategoriesSettingKey), isEmpty);
      // And a restart does not resurrect the defaults.
      expect(container().read(followedCategoriesProvider), isEmpty);
    });
  });

  /// The real `_bootPush` path, not a re-implementation of it: what it hands
  /// `syncTopics` is the property the About claim depends on.
  group('boot push sync', () {
    ProviderContainer bootContainer(_SpyPush push) {
      final c = ProviderContainer(
        overrides: [
          settingsBoxProvider.overrideWithValue(settingsBox),
          pushServiceProvider.overrideWithValue(push),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('receives exactly the stored subset', () async {
      await settingsBox.put(followedCategoriesSettingKey, ['ssc', 'railways']);
      final push = _SpyPush();

      await bootPush(bootContainer(push));

      expect(push.topics, {ExamCategory.ssc, ExamCategory.railways});
    });

    test('receives all five when the picker was never used', () async {
      final push = _SpyPush();

      await bootPush(bootContainer(push));

      expect(push.topics, ExamCategory.values.toSet());
    });

    test('receives an empty set when every category was turned off', () async {
      await settingsBox.put(followedCategoriesSettingKey, <String>[]);
      final push = _SpyPush();

      await bootPush(bootContainer(push));

      expect(push.topics, isEmpty);
      expect(push.synced, isTrue, reason: 'boot must still reconcile push');
    });

    test('a disabled provider never syncs', () async {
      final push = _SpyPush(initialProvider: PushProvider.disabled);

      await bootPush(bootContainer(push));

      expect(push.synced, isFalse);
    });
  });

  group('ExamAlertsNotifier rollback', () {
    test(
      'a failed write leaves the bell OFF and returns the stored set',
      () async {
        final c = ProviderContainer(
          overrides: [
            settingsBoxProvider.overrideWithValue(_FailingSettingsBox()),
          ],
        );
        addTearDown(c.dispose);
        expect(c.read(examAlertsProvider), isEmpty);

        final next = await c.read(examAlertsProvider.notifier).toggle('exam_a');

        // The comment always claimed this rollback; the code only logged. A bell
        // left ON over an empty disk shows OFF next launch while alerts keep
        // arriving — the exact failure the comment describes.
        expect(c.read(examAlertsProvider), isEmpty);
        expect(next, isEmpty);
      },
    );

    test('the caller can reconcile push against the rolled-back set', () async {
      // What `_toggleAlert` does: `toggle` then `syncExamAlerts(next)`. On a
      // failed write the returned set must be the one on disk, so push does not
      // subscribe a topic the next launch has no record of.
      final c = ProviderContainer(
        overrides: [
          settingsBoxProvider.overrideWithValue(_FailingSettingsBox()),
        ],
      );
      addTearDown(c.dispose);

      final next = await c.read(examAlertsProvider.notifier).toggle('exam_a');
      expect(next.contains('exam_a'), isFalse);
    });
  });
}

/// A `PushService` that records the topic sync without touching a backend.
class _SpyPush extends PushService {
  _SpyPush({this.initialProvider = PushProvider.fcm});

  final PushProvider initialProvider;

  Set<ExamCategory>? topics;
  bool synced = false;

  @override
  Future<PushProvider> initialise() async => initialProvider;

  @override
  Future<void> syncTopics(Set<ExamCategory> categories) async {
    topics = categories;
    synced = true;
  }

  @override
  Future<void> syncExamAlerts(Set<String> examIds) async {}
}

/// A settings box whose every write fails; reads answer from what "the last
/// successful launch" persisted.
class _FailingSettingsBox implements Box<dynamic> {
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) => defaultValue;

  @override
  Future<void> put(dynamic key, dynamic value) =>
      Future<void>.error(StateError('settings write failed'));

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '${invocation.memberName} is not exercised by this test',
  );
}

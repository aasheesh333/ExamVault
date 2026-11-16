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

  /// The arithmetic FCM used to get wrong: one `_subscribed` set holds both
  /// category topics and per-exam `exam_*` bells, and a diff against the whole
  /// set unsubscribed every bell on boot (and on every chip tap).
  group('category topic diff', () {
    Set<String> topics(Set<ExamCategory> categories) =>
        categories.map((c) => c.fcmTopic).toSet();

    test('a per-exam bell survives a category sync', () {
      final diff = PushService.categoryTopicDiff(
        topics({ExamCategory.ssc, ExamCategory.upsc}),
        {ExamCategory.ssc.fcmTopic, 'exam_ssc_cgl_2026'},
      );

      expect(diff.subscribe, {ExamCategory.upsc.fcmTopic});
      expect(
        diff.unsubscribe,
        isEmpty,
        reason:
            'exam_ssc_cgl_2026 is a bell, not a stale category topic — '
            'unsubscribing it is the boot-time bug',
      );
    });

    test('a removed category is unsubscribed while bells stay untouched', () {
      final diff = PushService.categoryTopicDiff(topics({ExamCategory.ssc}), {
        ExamCategory.ssc.fcmTopic,
        ExamCategory.banking.fcmTopic,
        'exam_ssc_cgl_2026',
        'exam_ibps_po_2026',
      });

      expect(diff.subscribe, isEmpty);
      expect(diff.unsubscribe, {ExamCategory.banking.fcmTopic});
    });

    test('an empty category set clears categories but not bells', () {
      final diff = PushService.categoryTopicDiff(const {}, {
        ExamCategory.ssc.fcmTopic,
        'exam_ssc_cgl_2026',
      });

      expect(diff.subscribe, isEmpty);
      expect(diff.unsubscribe, {ExamCategory.ssc.fcmTopic});
    });

    test('a bell-only set has nothing to reconcile as a category', () {
      // A device whose five category topics were dropped by a Play Services
      // update but whose bells are still live must subscribe all five back and
      // remove nothing.
      final all = topics(ExamCategory.values.toSet());
      final diff = PushService.categoryTopicDiff(all, {'exam_ssc_cgl_2026'});

      expect(diff.subscribe, all);
      expect(diff.unsubscribe, isEmpty);
    });

    test('the diff is idempotent: a second run changes nothing', () {
      final target = topics({ExamCategory.ssc, ExamCategory.railways});
      final subscribed = {
        ExamCategory.ssc.fcmTopic,
        ExamCategory.railways.fcmTopic,
        'exam_x',
      };
      final diff = PushService.categoryTopicDiff(target, subscribed);

      expect(diff.subscribe, isEmpty);
      expect(diff.unsubscribe, isEmpty);
    });

    // The mirror direction: `syncExamAlerts` used to read every `exam_*` topic
    // as a bell, which includes `exam_ssc`, `exam_upsc` and the other category
    // topics. Toggling one bell unsubscribed all five categories.
    test('a category topic is never unsubscribed as a stale bell', () {
      final diff = PushService.bellTopicDiff(
        {'exam_ssc_cgl_2026'},
        {for (final c in ExamCategory.values) c.fcmTopic, 'exam_ssc_cgl_2026'},
      );

      expect(diff.subscribe, isEmpty);
      expect(
        diff.unsubscribe,
        isEmpty,
        reason: 'turning a bell off must not drop the category topics',
      );
    });

    test('a removed bell is unsubscribed while categories stay', () {
      final diff = PushService.bellTopicDiff(
        {'exam_ssc_cgl_2026'},
        {ExamCategory.ssc.fcmTopic, 'exam_ssc_cgl_2026', 'exam_ibps_po_2026'},
      );

      expect(diff.subscribe, isEmpty);
      expect(diff.unsubscribe, {'exam_ibps_po_2026'});
    });
  });

  /// The set a wipe unsubscribes. `unsubscribeAll` takes the bell ids
  /// explicitly because `_subscribed` is in-memory only — a bell subscribed on a
  /// previous launch lives on the backend and nowhere in this process. The FCM
  /// branch used to ignore the parameter and iterate `_subscribed`, so on FCM
  /// delete-all dropped nothing at all in exactly that case while every bell on
  /// screen read OFF.
  group('delete-all topic set', () {
    test('the caller\'s bell ids are included with nothing subscribed', () {
      // A cold process that never ran `syncExamAlerts`: the ids the settings
      // held are the only name these topics have. This is the assertion the FCM
      // branch failed — it iterated `_subscribed`, which is empty here, and so
      // unsubscribed nothing while `exam_alerts` was deleted.
      expect(
        PushService.wipeTopics({'ssc_cgl_2026', 'ibps_po_2026'}, const {}),
        {'exam_ssc_cgl_2026', 'exam_ibps_po_2026'},
      );
    });

    test('bells from this process are added to the caller\'s set', () {
      final topics = PushService.wipeTopics(
        {'previous_launch'},
        {'exam_this_launch'},
      );

      expect(topics, {'exam_previous_launch', 'exam_this_launch'});
    });

    test('category topics are left to the post-wipe re-sync', () {
      final topics = PushService.wipeTopics(
        {'exam_1'},
        {ExamCategory.ssc.fcmTopic, 'exam_ssc_cgl_2026'},
      );

      expect(
        topics,
        {'exam_exam_1', 'exam_ssc_cgl_2026'},
        reason:
            'the category default is re-subscribed immediately afterwards, so '
            'unsubscribing it here would only cost a round trip',
      );
    });

    test('ids that cannot be a topic name are dropped, not sanitised empty', () {
      // `_topicSafe('')` is empty, and `exam_` alone is not a topic the app ever
      // subscribes to — unsubscribing it would be noise on the backend.
      expect(PushService.wipeTopics({'', '   '}, const {}), isEmpty);
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

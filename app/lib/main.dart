import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'data/repositories/admit_card_repository.dart';
import 'data/services/app_logger.dart';
import 'data/services/push_service.dart';
import 'providers/app_providers.dart';

Future<void> main() async {
  // Every plugin channel needs the binding before the first await.
  WidgetsFlutterBinding.ensureInitialized();

  _installCrashGuards();

  // Hive is the cold-boot cache: the radar document and raw HTTP bodies live
  // here. Opening a box is one file read, so first paint never waits on the
  // network — the single most important property on result day.
  await Hive.initFlutter();
  final httpCacheBox = await _openBoxResilient(AppConfig.boxHttpCache);
  final settingsBox = await _openBoxResilient(AppConfig.boxSettings);

  // Must be registered before runApp, or a data-only push that arrives while the
  // app is dead is silently dropped.
  if (AppConfig.pushConfigured) {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  final container = ProviderContainer(
    overrides: [
      httpCacheBoxProvider.overrideWithValue(httpCacheBox),
      settingsBoxProvider.overrideWithValue(settingsBox),
    ],
  );

  // Best-effort migration with a hard outer bound: first paint must never be
  // held hostage by secure storage. (The repository bounds its own reads; this
  // is the belt to that brace — a hung OEM Keystore used to be able to keep
  // the app on the native splash forever, because runApp waited on this.)
  await _purgeLegacySampleCards().timeout(
    const Duration(seconds: 12),
    onTimeout: () => AppLogger.w('boot', 'sample purge timed out; continuing'),
  );

  // Push is best-effort: a failure here must never stop the app from booting.
  unawaited(bootPush(container));

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const ExamVaultApp(),
    ),
  );
}

/// Opens a Hive box, recreating it from scratch when the file is corrupt.
///
/// Both boxes hold only regenerable data (HTTP cache, theme/alert settings).
/// An unguarded `openBox` before `runApp` meant one corrupt file — a process
/// kill during compaction, an OS upgrade, a full disk — threw on every launch,
/// the crash guard swallowed it into a log nobody reads, and the user got a
/// permanent blank splash with no recovery short of reinstalling.
Future<Box<dynamic>> _openBoxResilient(String name) async {
  try {
    return await Hive.openBox<dynamic>(name);
  } catch (e, st) {
    AppLogger.e('boot', 'hive box "$name" unreadable — recreating it', e, st);
    await Hive.deleteBoxFromDisk(name);
    return Hive.openBox<dynamic>(name);
  }
}

/// Routes every uncaught error into the logger instead of a white screen.
///
/// On result day a crash is unrecoverable — the user has one shot to see their
/// roll number. A stale screen is always better than a red one.
void _installCrashGuards() {
  FlutterError.onError = (details) {
    AppLogger.e(
      'crash',
      details.exceptionAsString(),
      details.exception,
      details.stack,
    );
    if (kDebugMode) FlutterError.presentError(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    AppLogger.e('crash', 'uncaught: $error', error, stack);
    return true;
  };
}

/// Removes the sample cards that an earlier build wrote into the encrypted vault.
///
/// Earlier revisions auto-seeded three `sample_*` admit cards on first run. Those
/// look exactly like real saved data — a user would reasonably believe ExamVault
/// had pulled someone else's roll number out of thin air. On upgrade we delete any
/// entry that still carries the `sample_` id prefix, so nobody is left holding a
/// fake admit card.
const _legacySamplePrefix = 'sample_';

Future<void> _purgeLegacySampleCards() async {
  final repo = AdmitCardRepository();
  try {
    final cards = await repo.load(force: true);
    for (final card in cards) {
      // Prefix used by the removed auto-seed. A card whose id starts with
      // this was never entered by the user, so it must go.
      if (card.id.startsWith(_legacySamplePrefix)) {
        await repo.delete(card.id);
        AppLogger.d('boot', 'purged sample card ${card.id}');
      }
    }
  } catch (e, st) {
    AppLogger.e('boot', 'sample purge failed', e, st);
  } finally {
    repo.dispose();
  }
}

/// Reconciles the push backend with what this device stored.
///
/// Public so a test can drive the real boot path: the categories it subscribes
/// to are the user's choice, not a constant, and that is exactly the property
/// worth pinning.
@visibleForTesting
Future<void> bootPush(ProviderContainer container) async {
  final push = container.read(pushServiceProvider);
  final provider = await push.initialise();
  if (provider == PushProvider.disabled) return;

  // Reconcile the student's per-exam bells on every boot: a subscription
  // silently dropped by a Play Services update repairs itself here, and the
  // sync is idempotent.
  await push.syncExamAlerts(container.read(examAlertsProvider));

  // Subscribe to the categories the student follows — not to every category.
  //
  // This used to pass `ExamCategory.values.toSet()`, which made the About
  // sheet's "for the categories you follow" a promise no code kept: every
  // device received all five. The stored set defaults to all five for anyone
  // who never opened the picker, so existing users keep the behaviour they had.
  await push.syncTopics(container.read(followedCategoriesProvider));
}

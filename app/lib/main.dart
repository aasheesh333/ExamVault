import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'data/repositories/admit_card_repository.dart';
import 'data/seed/demo_seed.dart';
import 'data/services/app_logger.dart';
import 'data/services/push_service.dart';
import 'domain/entities/exam_category.dart';
import 'providers/app_providers.dart';

Future<void> main() async {
  // Every plugin channel needs the binding before the first await.
  WidgetsFlutterBinding.ensureInitialized();

  _installCrashGuards();

  // Hive is the cold-boot cache: the radar document and raw HTTP bodies live
  // here. Opening a box is one file read, so first paint never waits on the
  // network — the single most important property on result day.
  await Hive.initFlutter();
  final httpCacheBox = await Hive.openBox<dynamic>(AppConfig.boxHttpCache);
  final settingsBox = await Hive.openBox<dynamic>(AppConfig.boxSettings);

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

  await _purgeLegacySampleCards();

  // Push is best-effort: a failure here must never stop the app from booting.
  unawaited(_bootPush(container));

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const ExamVaultApp(),
    ),
  );
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
Future<void> _purgeLegacySampleCards() async {
  final repo = AdmitCardRepository();
  try {
    final cards = await repo.load(force: true);
    for (final card in cards) {
      if (card.id.startsWith(DemoSeed.sampleMarker)) {
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

Future<void> _bootPush(ProviderContainer container) async {
  final push = container.read(pushServiceProvider);
  final provider = await push.initialise();
  if (provider == PushProvider.disabled) return;

  // Default to the two categories a new aspirant is most likely tracking.
  await push.syncTopics({ExamCategory.ssc, ExamCategory.upsc});
}

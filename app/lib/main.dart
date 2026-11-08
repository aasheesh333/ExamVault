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

  await _firstRunSeed(settingsBox);

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

/// Seeds one realistic vault on a brand-new install.
///
/// A blank vault is a bad first impression and leaves the result checker with
/// nothing to auto-fill. The samples are plain entries the user can delete.
Future<void> _firstRunSeed(Box<dynamic> settings) async {
  const seededKey = 'demo_seeded_v1';
  if (settings.get(seededKey) == true) return;

  final repo = AdmitCardRepository();
  try {
    for (final card in DemoSeed.admitCards()) {
      await repo.save(card);
    }
    await settings.put(seededKey, true);
    AppLogger.d('boot', 'seeded demo vault');
  } catch (e, st) {
    // A Keystore failure on an obscure OEM must not block startup.
    AppLogger.e('boot', 'seed failed', e, st);
  } finally {
    repo.dispose();
  }
}

Future<void> _bootPush(ProviderContainer container) async {
  final push = container.read(pushServiceProvider);
  final ready = await push.initialise();
  if (!ready) return;

  // Default to the two categories a new aspirant is most likely tracking.
  await push.syncTopics({ExamCategory.ssc, ExamCategory.upsc});
}

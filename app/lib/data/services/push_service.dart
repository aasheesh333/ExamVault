import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

import '../../core/config/app_config.dart';
import '../../domain/entities/exam_category.dart';
import 'app_logger.dart';

/// Which push backend is active.
enum PushProvider {
  /// Firebase Cloud Messaging, **topics** only.
  ///
  /// A topic publish is one API call regardless of subscriber count, and topic
  /// messaging is free on the Spark plan. Fanning out 10M per-token messages
  /// would need Blaze plus a queue; `POST messages:send` to `topic/exam_ssc`
  /// does not.
  fcm,

  /// OneSignal. Same idea — segments instead of topics — but with a dashboard,
  /// delivery analytics and a free tier that does not cap topic fan-out.
  oneSignal,

  /// No credentials supplied. Every call is a no-op and the app is unaffected.
  disabled,
}

/// Push notifications, over either backend.
///
/// Contract: **nothing here may ever throw into the caller.** On result day a
/// push failure is cosmetic; a crash is not. Every path is wrapped and degrades
/// to [PushProvider.disabled].
class PushService {
  PushService({
    FirebaseOptions? firebaseOptions,
    bool? fcmEnabled,
    String? oneSignalAppId,
  }) : _firebaseOptions = firebaseOptions,
       fcmEnabled = fcmEnabled ?? AppConfig.pushConfigured,
       oneSignalAppId = oneSignalAppId ?? AppConfig.oneSignalAppId;

  final FirebaseOptions? _firebaseOptions;

  /// Whether an FCM fallback is available (all `EV_FIREBASE_*` values present).
  final bool fcmEnabled;

  /// OneSignal App ID; empty means "not configured".
  final String oneSignalAppId;

  final _messages = StreamController<PushMessage>.broadcast();
  final Set<String> _subscribed = {};

  /// Kept so [dispose] can cancel before closing [_messages]: a foreground
  /// message arriving after close() used to throw inside a platform callback.
  StreamSubscription<RemoteMessage>? _onMessageSub;

  PushProvider _provider = PushProvider.disabled;
  bool _initialised = false;

  /// Foreground pushes, for an in-app banner.
  Stream<PushMessage> get messages => _messages.stream;

  PushProvider get provider => _provider;
  bool get isEnabled => _provider != PushProvider.disabled;
  Set<String> get subscribedTopics => Set.unmodifiable(_subscribed);

  /// OneSignal wins when both are configured: it is the one that still works
  /// without an MFA-gated Firebase project.
  Future<PushProvider> initialise() async {
    if (_initialised) return _provider;
    _initialised = true;

    // OneSignal needs a service worker on the web and a platform config in the
    // OneSignal dashboard. This app's OneSignal app is Android/iOS only, so on
    // web we skip straight to FCM rather than reporting a provider that cannot
    // actually deliver. `kIsWeb` is const, so this branch is tree-shaken away in
    // the mobile builds.
    if (oneSignalAppId.isNotEmpty && !kIsWeb) {
      final ok = await _initOneSignal().timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          AppLogger.w('push', 'OneSignal init timed out');
          return false;
        },
      );
      if (ok) {
        _provider = PushProvider.oneSignal;
        AppLogger.d('push', 'provider=OneSignal');
        return _provider;
      }
    }

    // FCM needs a service worker on the web too; without one the SDK throws.
    if (fcmEnabled && !kIsWeb) {
      final ok = await _initFcm().timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          AppLogger.w('push', 'FCM init timed out');
          return false;
        },
      );
      if (ok) {
        _provider = PushProvider.fcm;
        AppLogger.d('push', 'provider=FCM');
        return _provider;
      }
    }

    _provider = PushProvider.disabled;
    AppLogger.d('push', 'no provider configured — push disabled');
    return _provider;
  }

  // ------------------------------------------------------------- OneSignal

  Future<bool> _initOneSignal() async {
    try {
      OneSignal.initialize(oneSignalAppId);

      // Android 13+ runtime permission. On iOS this shows the system prompt.
      await OneSignal.Notifications.requestPermission(true);

      OneSignal.Notifications.addForegroundWillDisplayListener((event) {
        final data = event.notification.additionalData ?? const {};
        _messages.add(
          PushMessage(
            title: event.notification.title ?? 'ExamVault',
            body: event.notification.body ?? '',
            examId: data['exam_id'] as String?,
            status: data['status'] as String?,
            receivedAt: DateTime.now(),
          ),
        );
      });

      return true;
    } catch (e, st) {
      AppLogger.e('push', 'OneSignal init failed', e, st);
      return false;
    }
  }

  Future<void> _syncOneSignalTags(Set<ExamCategory> categories) async {
    // OneSignal segments are driven by tags, so one tag per category with a
    // boolean value is the cleanest mapping — it also survives the user adding a
    // category later without needing a segment rebuild in the dashboard.
    final tags = <String, dynamic>{
      for (final c in ExamCategory.values)
        'exam_${c.id}': categories.contains(c),
    };
    await OneSignal.User.addTags(tags);
  }

  // ------------------------------------------------------------------- FCM

  Future<bool> _initFcm() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: _buildFirebaseOptions());
      }

      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      AppLogger.d('push', 'FCM permission: ${settings.authorizationStatus}');

      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      _onMessageSub = FirebaseMessaging.onMessage.listen((message) {
        final data = message.data;
        _messages.add(
          PushMessage(
            title: message.notification?.title ?? 'ExamVault',
            body: message.notification?.body ?? '',
            examId: data['exam_id'] as String?,
            status: data['status'] as String?,
            receivedAt: DateTime.now(),
          ),
        );
      });

      // A tap on a cold-start notification must not be lost.
      final initial = await messaging.getInitialMessage();
      if (initial != null) {
        _messages.add(
          PushMessage(
            title: initial.notification?.title ?? 'ExamVault',
            body: initial.notification?.body ?? '',
            examId: initial.data['exam_id'] as String?,
            status: initial.data['status'] as String?,
            receivedAt: DateTime.now(),
          ),
        );
      }

      return true;
    } catch (e, st) {
      AppLogger.e('push', 'FCM init failed', e, st);
      return false;
    }
  }

  FirebaseOptions _buildFirebaseOptions() {
    if (_firebaseOptions != null) return _firebaseOptions;
    return const FirebaseOptions(
      apiKey: AppConfig.firebaseApiKey,
      appId: AppConfig.firebaseAppId,
      messagingSenderId: AppConfig.firebaseMessagingSenderId,
      projectId: AppConfig.firebaseProjectId,
      storageBucket: AppConfig.firebaseStorageBucket,
    );
  }

  // ----------------------------------------------------------- reconciliation

  /// Reconciles subscriptions with the user's chosen categories.
  ///
  /// Idempotent by design, so it is safe to call on every app start — that is
  /// also how a subscription silently dropped by a Play Services update gets
  /// repaired without the user noticing.
  Future<void> syncTopics(Set<ExamCategory> categories) async {
    if (!isEnabled) return;
    try {
      switch (_provider) {
        case PushProvider.oneSignal:
          await _syncOneSignalTags(categories);
          _subscribed
            ..clear()
            ..addAll(categories.map((c) => c.fcmTopic));

        case PushProvider.fcm:
          final target = categories.map((c) => c.fcmTopic).toSet();
          for (final topic in target.difference(_subscribed)) {
            await FirebaseMessaging.instance.subscribeToTopic(topic);
            _subscribed.add(topic);
            AppLogger.d('push', 'subscribed $topic');
          }
          for (final topic in _subscribed.difference(target)) {
            await FirebaseMessaging.instance.unsubscribeFromTopic(topic);
            _subscribed.remove(topic);
            AppLogger.d('push', 'unsubscribed $topic');
          }

        case PushProvider.disabled:
          break;
      }
    } catch (e) {
      AppLogger.w('push', 'topic sync failed: $e');
    }
  }

  Future<void> unsubscribeAll() async {
    if (!isEnabled) return;
    try {
      switch (_provider) {
        case PushProvider.oneSignal:
          await OneSignal.User.addTags({
            for (final c in ExamCategory.values) 'exam_${c.id}': false,
          });
        case PushProvider.fcm:
          for (final topic in [..._subscribed]) {
            await FirebaseMessaging.instance.unsubscribeFromTopic(topic);
          }
        case PushProvider.disabled:
          break;
      }
    } catch (e) {
      AppLogger.w('push', 'unsubscribe failed: $e');
    }
    _subscribed.clear();
  }

  Future<void> dispose() async {
    // Cancel before closing: a foreground message arriving after `close()`
    // used to call `add` on a closed controller — a StateError inside a
    // platform callback, in a class whose contract is "never throws".
    await _onMessageSub?.cancel();
    await _messages.close();
  }
}

@immutable
class PushMessage {
  const PushMessage({
    required this.title,
    required this.body,
    required this.receivedAt,
    this.examId,
    this.status,
  });

  final String title;
  final String body;
  final DateTime receivedAt;
  final String? examId;
  final String? status;
}

/// Handles background pushes in a separate isolate.
///
/// Must be a top-level function annotated `@pragma('vm:entry-point')`, otherwise
/// the AOT compiler strips it and the background isolate crashes on startup — a
/// classic and very hard-to-see production bug.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  AppLogger.d('push', 'background message: ${message.messageId}');
}

import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../core/config/app_config.dart';
import '../../domain/entities/exam_category.dart';
import 'app_logger.dart';

/// Push notifications over FCM **topics**.
///
/// Why topics and not device tokens: a topic publish is a single API call no
/// matter how many subscribers exist, and topic messaging is free on the Spark
/// plan. Fanning out 10M individual token messages would need a paid Blaze
/// account and a queue; one `POST /messages:send` to `topic/exam_ssc` does not.
///
/// Every method degrades to a no-op when Firebase is not configured. That keeps
/// the repository buildable and the app fully functional with no
/// `google-services.json`, which matters for CI and for forks.
class PushService {
  PushService({
    FirebaseOptions? options,
    bool? enabled,
  })  : _options = options,
        enabled = enabled ?? AppConfig.pushConfigured;

  /// False when no Firebase credentials were supplied at build time — every
  /// method then degrades to a no-op instead of throwing.
  final bool enabled;
  final FirebaseOptions? _options;

  final _messages = StreamController<PushMessage>.broadcast();

  bool _initialised = false;
  final Set<String> _subscribed = {};

  /// Foreground pushes, for an in-app banner.
  Stream<PushMessage> get messages => _messages.stream;

  Set<String> get subscribedTopics => Set.unmodifiable(_subscribed);

  Future<bool> initialise() async {
    if (!enabled || _initialised) return enabled;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: _buildOptions());
      }

      final messaging = FirebaseMessaging.instance;

      // Android 13+ requires the runtime POST_NOTIFICATIONS grant.
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      AppLogger.d('push', 'permission: ${settings.authorizationStatus}');

      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      FirebaseMessaging.onMessage.listen(_onMessage);

      // A tap on a cold-start notification must not be lost.
      final initial = await messaging.getInitialMessage();
      if (initial != null) _onMessage(initial);

      _initialised = true;
      return true;
    } catch (e, st) {
      // Never let push take the app down. Result day is the worst time to crash.
      AppLogger.e('push', 'initialise failed', e, st);
      return false;
    }
  }

  FirebaseOptions _buildOptions() {
    if (_options != null) return _options;
    return const FirebaseOptions(
      apiKey: AppConfig.firebaseApiKey,
      appId: AppConfig.firebaseAppId,
      messagingSenderId: AppConfig.firebaseMessagingSenderId,
      projectId: AppConfig.firebaseProjectId,
      storageBucket: AppConfig.firebaseStorageBucket,
    );
  }

  /// Reconciles subscriptions with the user's chosen categories.
  ///
  /// Subscribing is idempotent, so this is safe to call on every app start — it
  /// also repairs the case where the OS silently dropped a subscription during a
  /// Play Services update.
  Future<void> syncTopics(Set<ExamCategory> categories) async {
    if (!_initialised) return;
    try {
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
    } catch (e) {
      AppLogger.w('push', 'topic sync failed: $e');
    }
  }

  Future<void> unsubscribeAll() async {
    if (!_initialised) return;
    for (final topic in [..._subscribed]) {
      try {
        await FirebaseMessaging.instance.unsubscribeFromTopic(topic);
      } catch (_) {}
      _subscribed.remove(topic);
    }
  }

  void _onMessage(RemoteMessage message) {
    final data = message.data;
    final examId = data['exam_id'] as String?;
    final status = data['status'] as String?;

    _messages.add(
      PushMessage(
        title: message.notification?.title ?? 'ExamVault',
        body: message.notification?.body ?? '',
        examId: examId,
        status: status,
        receivedAt: DateTime.now(),
      ),
    );
  }

  Future<void> dispose() async {
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
/// Must be a top-level function with the `@pragma('vm:entry-point')` annotation,
/// otherwise the AOT compiler strips it and the background isolate crashes on
/// startup — a classic and very hard-to-see production bug.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  AppLogger.d('push', 'background message: ${message.messageId}');
}

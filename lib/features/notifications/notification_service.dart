import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../../core/services/supabase_service.dart';

/// Top-level background message handler required by FirebaseMessaging
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('Handling background push notification: ${message.messageId}');

  // If this is an emergency message, show incoming-call style alert even if app is terminated
  final category = message.data['category'] ?? message.data['type'];
  if (category == 'EMERGENCY') {
    final localNotifications = FlutterLocalNotificationsPlugin();
    const androidDetails = AndroidNotificationDetails(
      'unihub_emergency_channel',
      'UniHub Emergency Call Alerts',
      channelDescription: 'High priority full-screen emergency alerts and sirens',
      importance: Importance.max,
      priority: Priority.max,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.call,
      visibility: NotificationVisibility.public,
      color: Color(0xFFD32F2F),
      enableLights: true,
      ledColor: Color(0xFFFF0000),
      ledOnMs: 1000,
      ledOffMs: 500,
    );

    await localNotifications.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: '🚨 ${message.notification?.title ?? message.data['title'] ?? 'EMERGENCY ALERT'}',
      body: message.notification?.body ?? message.data['body'] ?? 'Immediate action required!',
      notificationDetails: const NotificationDetails(android: androidDetails),
      payload: message.data['deep_link'] ?? '/home',
    );
  }
}

class NotificationService {
  FirebaseMessaging? get _fcm {
    try {
      if (Firebase.apps.isNotEmpty) {
        return FirebaseMessaging.instance;
      }
    } catch (_) {}
    return null;
  }

  final _supabase = SupabaseService.client;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  bool _localInitialized = false;

  /// Initializes FCM listeners, permissions, channels and token sync
  Future<void> initialize() async {
    // 1. Initialize Android Local Notifications
    await _initLocalNotifications();

    final fcm = _fcm;
    if (fcm == null) {
      debugPrint('FCM skipped: Firebase is not initialized on this platform.');
      return;
    }

    try {
      // 2. Request user notification permission (Web, Android 13+ & iOS)
      final settings = await fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        debugPrint('Notification permission granted.');

        // 3. Fetch and register token
        await registerDeviceToken();

        // 4. Listen for token refresh events
        fcm.onTokenRefresh.listen((newToken) {
          saveTokenToDatabase(newToken);
        });

        // 5. Foreground message listener
        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
          debugPrint('Received foreground notification: ${message.notification?.title}');
          final category = message.data['category'] ?? message.data['type'];
          final title = message.notification?.title ?? message.data['title'] ?? 'UniHub Alert';
          final body = message.notification?.body ?? message.data['body'] ?? '';

          if (category == 'EMERGENCY') {
            showEmergencyNotification(title: title, body: body, data: message.data);
          } else {
            showStandardNotification(title: title, body: body, data: message.data);
          }
        });

        // 6. Handle app opened from terminated or background state via notification tap
        FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
          handleNotificationNavigation(message);
        });
      }
    } catch (e) {
      debugPrint('FCM initialization warning: $e');
    }
  }

  /// Sets up Android notification channels and local notification system
  Future<void> _initLocalNotifications() async {
    if (kIsWeb || _localInitialized) return;

    try {
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidSettings);

      await _localNotifications.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload != null && payload.isNotEmpty) {
            debugPrint('Local notification clicked with payload: $payload');
          }
        },
      );

      final androidPlugin = _localNotifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        // High-importance Emergency Channel with fullScreenIntent and siren vibration
        await androidPlugin.createNotificationChannel(
          const AndroidNotificationChannel(
            'unihub_emergency_channel',
            'UniHub Emergency Call Alerts',
            description: 'High priority full-screen emergency alerts and sirens',
            importance: Importance.max,
            playSound: true,
            enableVibration: true,
            showBadge: true,
          ),
        );

        // General Channel
        await androidPlugin.createNotificationChannel(
          const AndroidNotificationChannel(
            'unihub_general_channel',
            'UniHub Notifications',
            description: 'Important university notices and routine updates',
            importance: Importance.high,
            playSound: true,
            enableVibration: true,
            showBadge: true,
          ),
        );
      }

      _localInitialized = true;
    } catch (e) {
      debugPrint('Error initializing local notifications: $e');
    }
  }

  /// Dispatches full-screen incoming-call style emergency alert with siren vibration
  Future<void> showEmergencyNotification({
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    if (kIsWeb) return;

    try {
      final vibrationPattern = Int64List.fromList([0, 1000, 500, 1000, 500, 1000]);
      final androidDetails = AndroidNotificationDetails(
        'unihub_emergency_channel',
        'UniHub Emergency Call Alerts',
        channelDescription: 'High priority full-screen emergency alerts and sirens',
        importance: Importance.max,
        priority: Priority.max,
        fullScreenIntent: true,
        category: AndroidNotificationCategory.call,
        visibility: NotificationVisibility.public,
        vibrationPattern: vibrationPattern,
        enableLights: true,
        color: const Color(0xFFD32F2F),
        ledColor: const Color(0xFFFF0000),
        ledOnMs: 1000,
        ledOffMs: 500,
      );

      await _localNotifications.show(
        id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title: '🚨 $title',
        body: body,
        notificationDetails: NotificationDetails(android: androidDetails),
        payload: data?['deep_link'] ?? '/home',
      );
    } catch (e) {
      debugPrint('Error showing emergency notification: $e');
    }
  }

  /// Dispatches standard heads-up notification
  Future<void> showStandardNotification({
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    if (kIsWeb) return;

    try {
      const androidDetails = AndroidNotificationDetails(
        'unihub_general_channel',
        'UniHub Notifications',
        channelDescription: 'Important university notices and routine updates',
        importance: Importance.high,
        priority: Priority.high,
      );

      await _localNotifications.show(
        id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(android: androidDetails),
        payload: data?['deep_link'] ?? '/home',
      );
    } catch (e) {
      debugPrint('Error showing standard notification: $e');
    }
  }

  /// Obtains the current device FCM token and stores it in Supabase
  Future<String?> registerDeviceToken() async {
    final fcm = _fcm;
    if (fcm == null) return null;

    try {
      final token = await fcm.getToken();
      if (token != null) {
        await saveTokenToDatabase(token);
        return token;
      }
    } catch (e) {
      debugPrint('Error getting FCM token: $e');
    }
    return null;
  }

  /// Securely saves/upserts the FCM token in Supabase `notification_tokens` table
  Future<void> saveTokenToDatabase(String token) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      final platform = kIsWeb ? 'web' : 'android';

      await _supabase.from('notification_tokens').upsert(
        {
          'user_id': user.id,
          'fcm_token': token,
          'platform': platform,
          'is_active': true,
          'last_seen_at': DateTime.now().toUtc().toIso8601String(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'fcm_token',
      );
      debugPrint('FCM Token successfully synced to Supabase.');
    } catch (e) {
      debugPrint('Failed to save FCM token to Supabase: $e');
    }
  }

  /// Deactivates token in Supabase when user logs out
  Future<void> deactivateTokenOnLogout() async {
    final fcm = _fcm;
    if (fcm == null) return;

    try {
      final token = await fcm.getToken();
      if (token != null) {
        await _supabase
            .from('notification_tokens')
            .update({'is_active': false})
            .eq('fcm_token', token);
      }
    } catch (e) {
      debugPrint('Error deactivating token on logout: $e');
    }
  }

  /// Handles deep-link routing when a notification is tapped
  void handleNotificationNavigation(RemoteMessage message) {
    final deepLink = message.data['deep_link'];
    debugPrint('Notification tapped with deep link: $deepLink');
  }
}

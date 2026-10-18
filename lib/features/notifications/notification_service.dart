import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../../core/services/supabase_service.dart';

/// Top-level background message handler required by FirebaseMessaging
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('Handling background push notification: ${message.messageId}');
}

class NotificationService {
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final _supabase = SupabaseService.client;

  /// Initializes FCM listeners, permissions, and token sync
  Future<void> initialize() async {
    // 1. Request user notification permission (Android 13+ & iOS)
    final settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional) {
      debugPrint('Notification permission granted.');

      // 2. Fetch and register token
      await registerDeviceToken();

      // 3. Listen for token refresh events
      _fcm.onTokenRefresh.listen((newToken) {
        saveTokenToDatabase(newToken);
      });

      // 4. Foreground message listener
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('Received foreground notification: ${message.notification?.title}');
      });

      // 5. Handle app opened from terminated or background state via notification tap
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        handleNotificationNavigation(message);
      });
    } else {
      debugPrint('Notification permission was declined.');
    }
  }

  /// Obtains the current device FCM token and stores it in Supabase
  Future<String?> registerDeviceToken() async {
    try {
      final token = await _fcm.getToken();
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
      final platform = kIsWeb
          ? 'web'
          : Platform.isAndroid
              ? 'android'
              : Platform.isIOS
                  ? 'ios'
                  : 'web';

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
    try {
      final token = await _fcm.getToken();
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
    // Deep linking route will be processed by AppRouter
  }
}

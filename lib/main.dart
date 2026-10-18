import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'features/notifications/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Load environment variables
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint("Notice: .env file load failed or running with default config: $e");
  }

  // 2. Initialize Supabase
  const defaultSupabaseUrl = 'https://sgsctjaywrhuituohigl.supabase.co';
  const defaultSupabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNnc2N0amF5d3JodWl0dW9oaWdsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTIzMDQ1NzcsImV4cCI6MjEwNzg4MDU3N30.vQkIjjC7x1dtGqCpryrqUeN1MO0Aai3LtgPmH4NJEms';

  final supabaseUrl = (dotenv.env['SUPABASE_URL']?.isNotEmpty ?? false)
      ? dotenv.env['SUPABASE_URL']!
      : defaultSupabaseUrl;
  final supabaseAnonKey = (dotenv.env['SUPABASE_ANON_KEY']?.isNotEmpty ?? false)
      ? dotenv.env['SUPABASE_ANON_KEY']!
      : defaultSupabaseAnonKey;

  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabaseAnonKey,
  );

  // 3. Initialize Firebase (Spark Plan - 100% Free)
  try {
    if (kIsWeb) {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: 'AIzaSyC_oNfk5yizWgVImuR5bYN9YBK1T0mbYvE',
          appId: '1:977867086170:web:1af3d7bd4246d2225e3b63',
          messagingSenderId: '977867086170',
          projectId: 'unihub-5d151',
          storageBucket: 'unihub-5d151.firebasestorage.app',
        ),
      );
    } else {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    }
  } catch (e) {
    debugPrint("Firebase initialization notice: $e");
  }

  // 4. Run UniHub application
  runApp(
    const ProviderScope(
      child: UniHubApp(),
    ),
  );
}

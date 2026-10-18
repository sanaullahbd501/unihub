import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
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
  final supabaseUrl = dotenv.env['SUPABASE_URL'] ?? 'https://sgsctjaywrhuituohigl.supabase.co';
  final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';

  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabaseAnonKey,
  );

  // 3. Initialize Firebase (Spark Plan - 100% Free)
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (e) {
    debugPrint("Firebase initialization warning (safe in non-mobile environments): $e");
  }

  // 4. Run UniHub application
  runApp(
    const ProviderScope(
      child: UniHubApp(),
    ),
  );
}

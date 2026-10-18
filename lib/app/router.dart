import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/supabase_service.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/verify_otp_screen.dart';
import '../features/cr_panel/cr_panel_screen.dart';
import '../features/groups/join_group_screen.dart';
import '../features/home/home_screen.dart';
import '../features/notices/notices_screen.dart';
import '../features/notifications/notification_screen.dart';
import '../features/splash/splash_screen.dart';
import '../features/calling/calling_screen.dart';

/// Helper class to bridge a Dart Stream to Listenable for GoRouter refresh
class GoRouterRefreshStream extends ChangeNotifier {
  late final StreamSubscription<dynamic> _subscription;

  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: '/splash',
    refreshListenable: GoRouterRefreshStream(
      SupabaseService.client.auth.onAuthStateChange,
    ),

    redirect: (context, state) {
      final user = SupabaseService.client.auth.currentUser;
      final isLoggedIn = user != null;
      final location = state.matchedLocation;

      // Unauthenticated users are only allowed on splash, login, or verify
      if (!isLoggedIn &&
          location != '/' &&
          location != '/verify' &&
          location != '/splash') {
        return '/';
      }

      // Authenticated users trying to access login or splash are redirected to home
      if (isLoggedIn && (location == '/' || location == '/splash')) {
        return '/home';
      }

      return null;
    },

    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),

      GoRoute(
        path: '/',
        builder: (context, state) => const LoginScreen(),
      ),

      GoRoute(
        path: '/verify',
        builder: (context, state) {
          final email = state.extra is String ? state.extra as String : '';
          if (email.isEmpty) {
            return const LoginScreen();
          }
          return VerifyOtpScreen(email: email);
        },
      ),

      GoRoute(
        path: '/home',
        builder: (context, state) => const HomeScreen(),
      ),

      GoRoute(
        path: '/notifications',
        builder: (context, state) => const NotificationScreen(),
      ),

      GoRoute(
        path: '/cr-panel',
        builder: (context, state) => const CrPanelScreen(),
      ),

      GoRoute(
        path: '/notices',
        builder: (context, state) => const NoticesScreen(),
      ),

      GoRoute(
        path: '/join-group',
        builder: (context, state) => const JoinGroupScreen(),
      ),

      GoRoute(
        path: '/campus-call',
        builder: (context, state) => const CallingScreen(),
      ),
    ],
  );
}

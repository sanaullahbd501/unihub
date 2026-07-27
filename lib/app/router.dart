import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/auth/login_screen.dart';
import '../features/auth/verify_otp_screen.dart';
import '../features/home/home_screen.dart';
import '../features/splash/splash_screen.dart';

class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: '/splash',

    redirect: (context, state) {
      final user = Supabase.instance.client.auth.currentUser;

      final isLoggedIn = user != null;
      final location = state.matchedLocation;

      if (!isLoggedIn &&
          location != '/' &&
          location != '/verify' &&
          location != '/splash') {
        return '/';
      }

      if (isLoggedIn &&
          (location == '/' || location == '/splash')) {
        return '/home';
      }

      return null;
    },

    routes: [
      GoRoute(
        path: '/splash',
        builder: (_, __) => const SplashScreen(),
      ),

      GoRoute(
        path: '/',
        builder: (_, __) => const LoginScreen(),
      ),

      GoRoute(
        path: '/verify',
        builder: (_, state) {
          final email = state.extra as String;
          return VerifyOtpScreen(email: email);
        },
      ),

      GoRoute(
        path: '/home',
        builder: (_, __) => const HomeScreen(),
      ),
    ],
  );
}
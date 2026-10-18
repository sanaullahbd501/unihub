import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/supabase_service.dart';

class AuthService {
  final SupabaseClient _client = SupabaseService.client;

  User? get currentUser => _client.auth.currentUser;

  Session? get currentSession => _client.auth.currentSession;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  bool get isLoggedIn => currentUser != null;

  /// Check whether an email domain is authorized (@gmail.com or @student.wub.edu.bd)
  static bool isDomainAllowed(String email) {
    final clean = email.trim().toLowerCase();
    return clean.endsWith('@gmail.com') || clean.endsWith('@student.wub.edu.bd');
  }

  /// Sign In with Email & Password
  Future<AuthResponse> signInWithPassword({
    required String email,
    required String password,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    if (!isDomainAllowed(cleanEmail)) {
      throw const AuthException('শুধুমাত্র @gmail.com অথবা @student.wub.edu.bd ইমেইল দিয়ে লগইন করতে পারবেন।');
    }

    return await _client.auth.signInWithPassword(
      email: cleanEmail,
      password: password,
    );
  }

  /// Sign Up with Email, Password & Full Name
  Future<AuthResponse> signUpWithPassword({
    required String email,
    required String password,
    required String fullName,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    if (!isDomainAllowed(cleanEmail)) {
      throw const AuthException('শুধুমাত্র @gmail.com অথবা @student.wub.edu.bd ইমেইল দিয়ে একাউন্ট তৈরি করতে পারবেন।');
    }

    final res = await _client.auth.signUp(
      email: cleanEmail,
      password: password,
      data: {'full_name': fullName.trim()},
    );

    // Ensure profile row exists in public.users
    if (res.user != null) {
      try {
        await _client.from('users').upsert({
          'id': res.user!.id,
          'email': cleanEmail,
          'full_name': fullName.trim(),
          'role': 'student',
        });
      } catch (_) {}
    }

    return res;
  }

  /// Sends a one-time OTP email for login or signup
  Future<void> signInWithEmailOtp(String email) async {
    final cleanEmail = email.trim().toLowerCase();
    if (!isDomainAllowed(cleanEmail)) {
      throw const AuthException('শুধুমাত্র @gmail.com অথবা @student.wub.edu.bd ইমেইল অনুমোদিত।');
    }

    final redirectTo = kIsWeb ? 'http://localhost:8080' : 'io.supabase.unihub://login-callback';
    await _client.auth.signInWithOtp(
      email: cleanEmail,
      shouldCreateUser: true,
      emailRedirectTo: redirectTo,
    );
  }

  /// Verifies the 6-digit OTP code sent to user email
  Future<AuthResponse> verifyOtp({
    required String email,
    required String token,
  }) async {
    return await _client.auth.verifyOTP(
      email: email.trim().toLowerCase(),
      token: token.trim(),
      type: OtpType.email,
    );
  }

  /// Signs out the user and clears session
  Future<void> signOut() async {
    await _client.auth.signOut();
  }
}

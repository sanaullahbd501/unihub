import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/supabase_service.dart';

class AuthService {
  final SupabaseClient _client = SupabaseService.client;

  User? get currentUser => _client.auth.currentUser;

  Session? get currentSession => _client.auth.currentSession;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  bool get isLoggedIn => currentUser != null;

  /// Sends a one-time OTP email for login or signup
  Future<void> signInWithEmailOtp(String email) async {
    await _client.auth.signInWithOtp(
      email: email.trim(),
      shouldCreateUser: true,
    );
  }

  /// Verifies the 6-digit OTP code sent to user email
  Future<AuthResponse> verifyOtp({
    required String email,
    required String token,
  }) async {
    return await _client.auth.verifyOTP(
      email: email.trim(),
      token: token.trim(),
      type: OtpType.email,
    );
  }

  /// Signs out the user and clears session
  Future<void> signOut() async {
    await _client.auth.signOut();
  }
}

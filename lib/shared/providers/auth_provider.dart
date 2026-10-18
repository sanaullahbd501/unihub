import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../features/auth/auth_service.dart';
import '../../features/notifications/notification_service.dart';

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService();
});

final authStateProvider = StreamProvider<AuthState>((ref) {
  final authService = ref.watch(authServiceProvider);
  return authService.authStateChanges;
});

final currentUserProvider = Provider<User?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.value?.session?.user ?? ref.read(authServiceProvider).currentUser;
});

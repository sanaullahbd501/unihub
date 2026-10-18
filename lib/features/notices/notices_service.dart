import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/supabase_service.dart';

final noticesServiceProvider = Provider<NoticesService>((ref) {
  return NoticesService();
});

class NoticesService {
  final _supabase = SupabaseService.client;

  /// Fetches active notices targeted to the current user's enrolled groups or directly to the user (or created by CR)
  Future<List<Map<String, dynamic>>> getNotices() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return [];

    final nowIso = DateTime.now().toUtc().toIso8601String();
    final res = await _supabase
        .from('notices')
        .select('*, notice_target_groups(group_id, class_groups(id, name, invite_code)), notice_target_users(user_id, users(id, full_name, email))')
        .or('is_permanent.eq.true,expires_at.is.null,expires_at.gt.$nowIso')
        .order('created_at', ascending: false);

    final allNotices = List<Map<String, dynamic>>.from(res);

    // Get user profile role
    final profile = await _supabase
        .from('users')
        .select('role')
        .eq('id', user.id)
        .maybeSingle();
    final role = (profile?['role']?.toString().toLowerCase()) ?? 'student';

    // Get groups user is enrolled in
    final enrolledRes = await _supabase
        .from('group_members')
        .select('group_id')
        .eq('user_id', user.id);
    final myGroupIds = (enrolledRes as List)
        .map((m) => m['group_id']?.toString())
        .whereType<String>()
        .toSet();

    return allNotices.where((notice) {
      // 1. Notice creator always sees their notice
      if (notice['created_by'] == user.id) return true;

      // 2. Admins see all notices
      if (role == 'admin') return true;

      final targetUsers = notice['notice_target_users'] as List<dynamic>? ?? [];
      final isDirectlyAssignedToUser = targetUsers.any((u) => u['user_id']?.toString() == user.id);

      // If directly assigned to this user, they always see it
      if (isDirectlyAssignedToUser) return true;

      final targetGroups = notice['notice_target_groups'] as List<dynamic>? ?? [];

      // If the notice is assigned only to specific students (no groups), other students shouldn't see it
      if (targetUsers.isNotEmpty && targetGroups.isEmpty) {
        return false;
      }

      // 3. If notice has no specific target groups and no specific users, it's a general announcement
      if (targetGroups.isEmpty && targetUsers.isEmpty) return true;

      // 4. Otherwise, user must be enrolled in at least one of the target groups
      final noticeTargetGroupIds = targetGroups
          .map((tg) => tg['group_id']?.toString())
          .whereType<String>()
          .toSet();

      return myGroupIds.intersection(noticeTargetGroupIds).isNotEmpty;
    }).toList();
  }

  /// Deletes a notice by ID (allowed for CR / Creator)
  Future<void> deleteNotice(String noticeId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('User not logged in');

    // 1. Delete target group mappings
    await _supabase.from('notice_target_groups').delete().eq('notice_id', noticeId);

    // 2. Delete target user mappings
    try {
      await _supabase.from('notice_target_users').delete().eq('notice_id', noticeId);
    } catch (_) {}

    // 3. Delete related notification records from notifications table if any
    try {
      await _supabase.from('notifications').delete().eq('data->>notice_id', noticeId);
    } catch (_) {}

    // 4. Delete the notice itself
    await _supabase.from('notices').delete().eq('id', noticeId);
  }

  /// Publishes a new notice, associates it with selected groups or individual students, and triggers Push Notification
  Future<Map<String, dynamic>> publishNotice({
    required String title,
    required String content,
    List<String>? targetGroupIds,
    List<String>? targetUserIds,
    String category = 'NOTICE',
    DateTime? eventTime,
    DateTime? customExpiry,
    bool isPermanent = false,
    bool sendPush = true,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    final groupIds = targetGroupIds ?? [];
    final userIds = targetUserIds ?? [];

    if (groupIds.isEmpty && userIds.isEmpty) {
      throw Exception('Please select at least one group or individual student to receive this notice.');
    }

    // Default expiry: 3 months (90 days) for semester cleanup, or custom expiry, unless permanent
    DateTime? calculatedExpiry;
    if (!isPermanent) {
      calculatedExpiry = customExpiry ?? DateTime.now().add(const Duration(days: 90));
    }

    final targetType = (userIds.isNotEmpty && groupIds.isEmpty) ? 'USER' : 'GROUP';

    // 1. Insert notice
    final notice = await _supabase
        .from('notices')
        .insert({
          'title': title.trim(),
          'content': content.trim(),
          'category': category,
          'target_type': targetType,
          'event_time': eventTime?.toUtc().toIso8601String(),
          'expires_at': calculatedExpiry?.toUtc().toIso8601String(),
          'is_permanent': isPermanent,
          'created_by': user.id,
          'is_published': true,
        })
        .select()
        .single();

    final noticeId = notice['id'] as String;

    // 2. Link target groups in notice_target_groups
    if (groupIds.isNotEmpty) {
      final groupMappings = groupIds.map((gid) => {
        'notice_id': noticeId,
        'group_id': gid,
      }).toList();

      await _supabase.from('notice_target_groups').insert(groupMappings);
    }

    // 3. Link target students in notice_target_users
    if (userIds.isNotEmpty) {
      final userMappings = userIds.map((uid) => {
        'notice_id': noticeId,
        'user_id': uid,
      }).toList();

      await _supabase.from('notice_target_users').insert(userMappings);
    }

    // 4. Record into notifications table
    try {
      await _supabase.from('notifications').insert({
        'title': title.trim(),
        'body': content.trim(),
        'type': category == 'EMERGENCY' ? 'EMERGENCY' : (category == 'ROUTINE' ? 'ROUTINE' : 'NOTICE'),
        'target_type': targetType,
        'target_user_id': userIds.length == 1 ? userIds.first : null,
        'priority': category == 'EMERGENCY' ? 'HIGH' : 'NORMAL',
        'deep_link': '/notices',
        'data': {
          'notice_id': noticeId,
          'target_group_ids': groupIds,
          'target_user_ids': userIds,
          'category': category,
        },
        'created_by': user.id,
      });
    } catch (_) {
      // Non-blocking
    }

    // 5. Trigger Supabase Edge Function to dispatch FCM Push Notification
    if (sendPush) {
      try {
        await _supabase.functions.invoke(
          'send-notification',
          body: {
            'title': title.trim(),
            'body': content.trim(),
            'type': category == 'EMERGENCY' ? 'EMERGENCY' : 'NOTICE',
            'deep_link': '/notices',
            'target_group_ids': groupIds,
            'target_user_ids': userIds,
            'notice_id': noticeId,
            'created_by': user.id,
          },
        );
      } catch (_) {
        // Edge function push is non-blocking to notice publication
      }
    }

    return notice;
  }
}

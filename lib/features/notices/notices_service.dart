import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/supabase_service.dart';

final noticesServiceProvider = Provider<NoticesService>((ref) {
  return NoticesService();
});

class NoticesService {
  final _supabase = SupabaseService.client;

  /// Fetches all active notices (excludes expired notices unless permanent)
  Future<List<Map<String, dynamic>>> getNotices() async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final res = await _supabase
        .from('notices')
        .select('*, notice_target_groups(group_id, class_groups(id, name, invite_code))')
        .or('is_permanent.eq.true,expires_at.is.null,expires_at.gt.$nowIso')
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(res);
  }

  /// Deletes a notice by ID (allowed for CR / Creator)
  Future<void> deleteNotice(String noticeId) async {
    await _supabase.from('notice_target_groups').delete().eq('notice_id', noticeId);
    await _supabase.from('notices').delete().eq('id', noticeId);
  }

  /// Publishes a new notice, associates it with selected groups, and triggers Push Notification
  Future<Map<String, dynamic>> publishNotice({
    required String title,
    required String content,
    required List<String> targetGroupIds,
    String category = 'NOTICE',
    DateTime? eventTime,
    DateTime? customExpiry,
    bool isPermanent = false,
    bool sendPush = true,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('User not authenticated');
    if (targetGroupIds.isEmpty) {
      throw Exception('Please select at least one group (e.g. 95B, 95C) to receive this notice.');
    }

    // Default expiry: 3 months (90 days) for semester cleanup, or custom expiry, unless permanent
    DateTime? calculatedExpiry;
    if (!isPermanent) {
      calculatedExpiry = customExpiry ?? DateTime.now().add(const Duration(days: 90));
    }

    // 1. Insert notice
    final notice = await _supabase
        .from('notices')
        .insert({
          'title': title.trim(),
          'content': content.trim(),
          'category': category,
          'target_type': 'GROUP',
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
    final groupMappings = targetGroupIds.map((gid) => {
      'notice_id': noticeId,
      'group_id': gid,
    }).toList();

    await _supabase.from('notice_target_groups').insert(groupMappings);

    // 2.1 Always record into notifications table so all students see it in their Notifications tab
    try {
      await _supabase.from('notifications').insert({
        'title': title.trim(),
        'body': content.trim(),
        'type': category == 'EMERGENCY' ? 'EMERGENCY' : (category == 'ROUTINE' ? 'ROUTINE' : 'NOTICE'),
        'target_type': 'GROUP',
        'priority': category == 'EMERGENCY' ? 'HIGH' : 'NORMAL',
        'deep_link': '/notices',
        'data': {
          'notice_id': noticeId,
          'target_group_ids': targetGroupIds,
          'category': category,
        },
        'created_by': user.id,
      });
    } catch (_) {
      // Non-blocking
    }

    // 3. Trigger Supabase Edge Function to dispatch FCM Push Notification
    if (sendPush) {
      try {
        await _supabase.functions.invoke(
          'send-notification',
          body: {
            'title': title.trim(),
            'body': content.trim(),
            'type': category == 'EMERGENCY' ? 'EMERGENCY' : 'NOTICE',
            'deep_link': '/notices',
            'target_group_ids': targetGroupIds,
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

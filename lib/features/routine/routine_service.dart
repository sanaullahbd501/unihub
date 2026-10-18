import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/supabase_service.dart';

final routineServiceProvider = Provider<RoutineService>((ref) {
  return RoutineService();
});

class RoutineService {
  final _supabase = SupabaseService.client;

  /// Fetches recurring class routine for a specific group or all user's enrolled groups
  Future<List<Map<String, dynamic>>> getRoutines({String? groupId}) async {
    var query = _supabase.from('routines').select('*, class_groups(id, name)');
    if (groupId != null && groupId.isNotEmpty) {
      query = query.eq('group_id', groupId);
    }
    final res = await query.order('day_of_week').order('start_time');
    return List<Map<String, dynamic>>.from(res);
  }

  /// Saves or updates a weekly class routine entry
  Future<void> saveRoutine({
    String? id,
    required String classId,
    required String groupId,
    required String subject,
    String? teacherName,
    required int dayOfWeek, // 1=Mon, 7=Sun
    required String startTime, // HH:mm:ss
    required String endTime, // HH:mm:ss
    required bool isOnline,
    String? roomNumber,
    String? meetingLink,
    bool dispatchInitialAlert = true,
  }) async {
    final payload = {
      'class_id': classId,
      'group_id': groupId,
      'subject': subject.trim(),
      'teacher_name': teacherName?.trim(),
      'day_of_week': dayOfWeek,
      'start_time': startTime,
      'end_time': endTime,
      'is_online': isOnline,
      'room_number': isOnline ? null : roomNumber?.trim(),
      'meeting_link': isOnline ? meetingLink?.trim() : null,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    if (id != null && id.isNotEmpty) {
      await _supabase.from('routines').update(payload).eq('id', id);
    } else {
      await _supabase.from('routines').insert(payload);
    }

    if (dispatchInitialAlert) {
      final days = ['', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
      final dayName = (dayOfWeek >= 1 && dayOfWeek <= 7) ? days[dayOfWeek] : '';
      await sendRoutineReminder(
        groupId: groupId,
        subject: subject,
        intervalLabel: 'Class Scheduled',
        startTime: '$dayName at ${startTime.substring(0, 5)}',
        isOnline: isOnline,
        roomNumber: roomNumber,
        meetingLink: meetingLink,
      );
    }
  }

  /// Deletes a routine entry
  Future<void> deleteRoutine(String id) async {
    await _supabase.from('routines').delete().eq('id', id);
  }

  /// Fetches all active exams (automatically filters out exams that ended 3+ hours ago)
  Future<List<Map<String, dynamic>>> getActiveExams({String? groupId}) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    var query = _supabase
        .from('exams')
        .select('*, class_groups(id, name)')
        .gt('delete_at', nowIso); // Auto-hides 3 hours after exam end

    if (groupId != null && groupId.isNotEmpty) {
      query = query.eq('group_id', groupId);
    }

    final res = await query.order('exam_date').order('start_time');
    return List<Map<String, dynamic>>.from(res);
  }

  /// Adds a new exam with auto-deletion scheduled 3 hours after end_time
  Future<void> saveExam({
    required String classId,
    required String groupId,
    required String subject,
    required String examType, // CT, MID, FINAL, QUIZ
    required DateTime examDate,
    required String startTime, // HH:mm:ss
    required String endTime, // HH:mm:ss
    String? roomNumber,
    bool isOnline = false,
    String? meetingLink,
    bool dispatchAlert = true,
  }) async {
    // Calculate exact end datetime and delete_at = end_time + 3 hours
    final endParts = endTime.split(':');
    final endHour = int.tryParse(endParts[0]) ?? 12;
    final endMin = int.tryParse(endParts[1]) ?? 0;
    final examEndDateTime = DateTime(examDate.year, examDate.month, examDate.day, endHour, endMin);
    final deleteAt = examEndDateTime.add(const Duration(hours: 3));

    final payload = {
      'class_id': classId,
      'group_id': groupId,
      'subject': subject.trim(),
      'exam_type': examType,
      'exam_date': examDate.toIso8601String().substring(0, 10),
      'start_time': startTime,
      'end_time': endTime,
      'room_number': isOnline ? null : roomNumber?.trim(),
      'is_online': isOnline,
      'meeting_link': isOnline ? meetingLink?.trim() : null,
      'delete_at': deleteAt.toUtc().toIso8601String(),
    };

    await _supabase.from('exams').insert(payload);

    if (dispatchAlert) {
      final dateStr = examDate.toIso8601String().substring(0, 10);
      await sendRoutineReminder(
        groupId: groupId,
        subject: '$examType Exam: $subject',
        intervalLabel: 'Exam Alert',
        startTime: '$dateStr at ${startTime.substring(0, 5)}',
        isOnline: isOnline,
        roomNumber: roomNumber,
        meetingLink: meetingLink,
      );
    }
  }

  /// Deletes an exam manually
  Future<void> deleteExam(String id) async {
    await _supabase.from('exams').delete().eq('id', id);
  }

  /// Dispatches a high-priority routine/class countdown reminder to all students in the group
  Future<void> sendRoutineReminder({
    required String groupId,
    required String subject,
    required String intervalLabel, // e.g. "1 Day", "12h", "6h", "3h", "1h", "30m", "10m", "Now!"
    required String startTime,
    required bool isOnline,
    String? roomNumber,
    String? meetingLink,
  }) async {
    final user = _supabase.auth.currentUser;
    final title = '⏰ [$intervalLabel] Class: $subject';
    final locationInfo = isOnline
        ? 'Online Class (${meetingLink != null && meetingLink.isNotEmpty ? 'Meeting Link Attached' : 'Link in Routine'})'
        : 'Room: ${roomNumber ?? "TBA"}';
    final body = '$subject starts at $startTime. Format: $locationInfo. Priority Alert!';

    // 1. Insert into notifications table with HIGH priority
    try {
      await _supabase.from('notifications').insert({
        'title': title,
        'body': body,
        'type': 'ROUTINE',
        'target_type': 'GROUP',
        'priority': 'HIGH',
        'deep_link': '/routine',
        'data': {
          'group_id': groupId,
          'subject': subject,
          'start_time': startTime,
          'is_online': isOnline,
          'meeting_link': meetingLink,
          'room_number': roomNumber,
          'interval': intervalLabel,
        },
        'created_by': user?.id,
      });
    } catch (_) {}

    // 2. Trigger FCM push notification via Supabase Edge Function
    try {
      await _supabase.functions.invoke(
        'send-notification',
        body: {
          'title': title,
          'body': body,
          'type': 'ROUTINE',
          'priority': 'high',
          'deep_link': '/routine',
          'target_group_ids': [groupId],
          'created_by': user?.id,
        },
      );
    } catch (_) {}
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/supabase_service.dart';

final groupsServiceProvider = Provider<GroupsService>((ref) {
  return GroupsService();
});

class GroupsService {
  final _supabase = SupabaseService.client;

  /// Creates a new Class / Batch (e.g. "CSE 95th Batch")
  Future<Map<String, dynamic>> createClass({
    required String name,
    String? universityName,
    String? departmentName,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('User not logged in');

    final data = await _supabase
        .from('classes')
        .insert({
          'name': name.trim(),
          'university_name': universityName?.trim() ?? 'World University of Bangladesh (WUB)',
          'department_name': departmentName?.trim() ?? 'CSE',
          'created_by': user.id,
        })
        .select()
        .single();

    return data;
  }

  /// Creates a new Group / Section inside a class (e.g. "95B", "95C")
  Future<Map<String, dynamic>> createGroup({
    required String classId,
    required String name,
    required String inviteCode,
    String? description,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('User not logged in');

    final normalizedCode = inviteCode.trim().toUpperCase();

    final group = await _supabase
        .from('class_groups')
        .insert({
          'class_id': classId,
          'name': name.trim(),
          'invite_code': normalizedCode,
          'description': description?.trim(),
          'created_by': user.id,
        })
        .select()
        .single();

    return group;
  }

  /// Fetches classes created by user or where user is co-cr, along with groups
  Future<List<Map<String, dynamic>>> getMyManagedClasses() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return [];

    final classes = await _supabase
        .from('classes')
        .select('*, class_groups(*)')
        .eq('created_by', user.id)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(classes);
  }

  /// Deletes a class and all associated groups, routines, and exams (via CASCADE)
  Future<void> deleteClass(String classId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('User not logged in');

    await _supabase
        .from('classes')
        .delete()
        .eq('id', classId)
        .eq('created_by', user.id);
  }

  /// Deletes a group/section
  Future<void> deleteGroup(String groupId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('User not logged in');

    await _supabase
        .from('class_groups')
        .delete()
        .eq('id', groupId);
  }

  /// Fetches groups the current user is enrolled in as a Student
  Future<List<Map<String, dynamic>>> getMyEnrolledGroups() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return [];

    final res = await _supabase
        .from('group_members')
        .select('group_id, role, joined_at, class_groups(id, name, invite_code, class_id, classes(name, department_name, university_name))')
        .eq('user_id', user.id)
        .eq('role', 'student');

    return List<Map<String, dynamic>>.from(res);
  }

  /// Leave an enrolled group
  Future<void> leaveGroup(String groupId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    await _supabase
        .from('group_members')
        .delete()
        .eq('group_id', groupId)
        .eq('user_id', user.id);
  }

  /// Join a group using an invite code (e.g. "95B", "95B-CSE")
  Future<Map<String, dynamic>> joinGroupByCode(String code) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Please log in first');

    final normalized = code.trim().toUpperCase();

    // Find group
    final group = await _supabase
        .from('class_groups')
        .select('id, name, class_id, classes(name)')
        .eq('invite_code', normalized)
        .maybeSingle();

    if (group == null) {
      throw Exception('Invalid invite code: "$code". Please verify with your CR.');
    }

    final groupId = group['id'] as String;

    // Check if already member
    final existing = await _supabase
        .from('group_members')
        .select('id')
        .eq('group_id', groupId)
        .eq('user_id', user.id)
        .maybeSingle();

    if (existing != null) {
      return {'already_joined': true, 'group': group};
    }

    // Join
    await _supabase.from('group_members').insert({
      'group_id': groupId,
      'user_id': user.id,
      'role': 'student',
    });

    return {'already_joined': false, 'group': group};
  }

  /// Add a Co-CR to a class by their email
  Future<void> addCoCr({
    required String classId,
    required String userEmail,
  }) async {
    final currentUser = _supabase.auth.currentUser;
    if (currentUser == null) throw Exception('Not authenticated');

    final targetUser = await _supabase
        .from('users')
        .select('id, email, full_name')
        .eq('email', userEmail.trim().toLowerCase())
        .maybeSingle();

    if (targetUser == null) {
      throw Exception('User with email "$userEmail" is not registered on UniHub yet.');
    }

    final targetUserId = targetUser['id'] as String;

    await _supabase.from('class_co_crs').insert({
      'class_id': classId,
      'user_id': targetUserId,
      'added_by': currentUser.id,
    });
  }

  /// Update user's role and details (e.g. student <-> cr)
  Future<void> updateUserRole({
    required String role,
    String? fullName,
    String? universityName,
    String? departmentName,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    final updatePayload = <String, dynamic>{
      'role': role.toLowerCase().trim(),
    };
    if (fullName != null && fullName.trim().isNotEmpty) {
      updatePayload['full_name'] = fullName.trim();
    }

    await _supabase.from('users').update(updatePayload).eq('id', user.id);
  }
}

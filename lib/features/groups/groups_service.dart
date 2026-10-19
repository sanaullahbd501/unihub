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

    // Check if code is already taken
    final existing = await _supabase
        .from('class_groups')
        .select('id')
        .ilike('invite_code', normalizedCode)
        .maybeSingle();

    if (existing != null) {
      throw Exception('Invite code "$normalizedCode" is already in use by another group. Please choose a different code.');
    }

    final group = await _supabase
        .from('class_groups')
        .insert({
          'class_id': classId,
          'name': name.trim(),
          'invite_code': normalizedCode,
          'description': description?.trim(),
          'is_join_locked': false,
          'created_by': user.id,
        })
        .select()
        .single();

    return group;
  }

  /// Toggles whether students can join this group via invite code
  Future<void> toggleGroupJoinLock({
    required String groupId,
    required bool isLocked,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('User not logged in');

    await _supabase
        .from('class_groups')
        .update({'is_join_locked': isLocked})
        .eq('id', groupId);
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

  /// Fetches members of a specific group (with user profile information)
  Future<List<Map<String, dynamic>>> getGroupMembers(String groupId) async {
    final members = await _supabase
        .from('group_members')
        .select('id, group_id, user_id, role, joined_at, users(id, full_name, email, role, avatar_url)')
        .eq('group_id', groupId)
        .order('joined_at', ascending: true);

    return List<Map<String, dynamic>>.from(members);
  }

  /// Removes an enrolled student/member from a group (can be executed by CR)
  Future<void> removeMember(String memberRecordId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('User not logged in');

    await _supabase
        .from('group_members')
        .delete()
        .eq('id', memberRecordId);
  }

  /// Adds a student directly to a group by their registered email
  Future<void> addMemberDirectly({
    required String groupId,
    required String email,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('User not logged in');

    final targetUser = await _supabase
        .from('users')
        .select('id, full_name, email')
        .eq('email', email.trim().toLowerCase())
        .maybeSingle();

    if (targetUser == null) {
      throw Exception('User with email "$email" is not registered on UniHub yet.');
    }

    final targetUserId = targetUser['id'] as String;

    // Check if already in group
    final existing = await _supabase
        .from('group_members')
        .select('id')
        .eq('group_id', groupId)
        .eq('user_id', targetUserId)
        .maybeSingle();

    if (existing != null) {
      throw Exception('This student is already a member of this section.');
    }

    await _supabase.from('group_members').insert({
      'group_id': groupId,
      'user_id': targetUserId,
      'role': 'student',
    });
  }

  /// Fetches the CRs for a class (Class Creator + Co-CRs)
  Future<Map<String, dynamic>> getClassCRs(String classId) async {
    final cls = await _supabase
        .from('classes')
        .select('id, name, created_by')
        .eq('id', classId)
        .maybeSingle();

    Map<String, dynamic>? creatorUser;
    final createdBy = cls?['created_by']?.toString();
    if (createdBy != null && createdBy.isNotEmpty) {
      try {
        creatorUser = await _supabase
            .from('users')
            .select('id, full_name, email, role, avatar_url')
            .eq('id', createdBy)
            .maybeSingle();
      } catch (_) {}
    }

    List<Map<String, dynamic>> coCrsList = [];
    try {
      final coCrs = await _supabase
          .from('class_co_crs')
          .select('id, user_id, users(id, full_name, email, role, avatar_url)')
          .eq('class_id', classId);
      coCrsList = List<Map<String, dynamic>>.from(coCrs);
    } catch (_) {
      try {
        final coCrs = await _supabase
            .from('class_co_crs')
            .select('id, user_id')
            .eq('class_id', classId);
        for (final item in (coCrs as List)) {
          final uid = item['user_id'];
          final u = await _supabase
              .from('users')
              .select('id, full_name, email, role, avatar_url')
              .eq('id', uid)
              .maybeSingle();
          coCrsList.add({
            'id': item['id'],
            'user_id': uid,
            'users': u,
          });
        }
      } catch (_) {}
    }

    return {
      'creator': creatorUser,
      'co_crs': coCrsList,
    };
  }

  /// Fetches all enrolled students across all managed class groups for notice targeting
  Future<List<Map<String, dynamic>>> getAllStudentsInManagedClasses() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return [];

    final classes = await getMyManagedClasses();
    final allGroupIds = <String>[];
    final groupNameMap = <String, String>{};

    for (final c in classes) {
      final grps = c['class_groups'] as List<dynamic>? ?? [];
      for (final g in grps) {
        final gid = g['id'] as String;
        allGroupIds.add(gid);
        groupNameMap[gid] = '${c['name']} - ${g['name']}';
      }
    }

    if (allGroupIds.isEmpty) return [];

    final res = await _supabase
        .from('group_members')
        .select('id, user_id, group_id, users(id, full_name, email, avatar_url)')
        .inFilter('group_id', allGroupIds);

    final seenUsers = <String, Map<String, dynamic>>{};
    for (final m in res) {
      final u = m['users'] as Map<String, dynamic>?;
      if (u != null) {
        final uid = u['id'] as String;
        final gid = m['group_id'] as String;
        final groupLabel = groupNameMap[gid] ?? 'Section';

        if (seenUsers.containsKey(uid)) {
          final existingGroups = seenUsers[uid]!['groups'] as List<String>;
          if (!existingGroups.contains(groupLabel)) {
            existingGroups.add(groupLabel);
          }
        } else {
          seenUsers[uid] = {
            'id': uid,
            'full_name': u['full_name'] ?? 'Student',
            'email': u['email'] ?? '',
            'avatar_url': u['avatar_url'],
            'groups': [groupLabel],
          };
        }
      }
    }

    return seenUsers.values.toList();
  }

  /// Fetches groups the current user is enrolled in as a Student
  Future<List<Map<String, dynamic>>> getMyEnrolledGroups() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return [];

    final res = await _supabase
        .from('group_members')
        .select('group_id, role, joined_at, class_groups(id, name, invite_code, is_join_locked, class_id, classes(name, department_name, university_name))')
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
        .select('id, name, class_id, is_join_locked, classes(name)')
        .eq('invite_code', normalized)
        .maybeSingle();

    if (group == null) {
      throw Exception('Invalid invite code: "$code". Please verify with your CR.');
    }

    // Check if group is locked by CR
    if (group['is_join_locked'] == true) {
      throw Exception(
        'This section "${group['name']}" is currently LOCKED by the CR. Students cannot join via code. Please contact your CR to add you directly.',
      );
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

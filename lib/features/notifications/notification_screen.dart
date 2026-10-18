import 'package:flutter/material.dart';
import '../../core/services/supabase_service.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  final _supabase = SupabaseService.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _notifications = [];

  @override
  void initState() {
    super.initState();
    _fetchNotifications();
  }

  Future<void> _fetchNotifications() async {
    setState(() => _isLoading = true);
    final user = _supabase.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      // Get user's enrolled group IDs
      final memberRes = await _supabase
          .from('group_members')
          .select('group_id')
          .eq('user_id', user.id);
      final myGroupIds = (memberRes as List)
          .map((m) => m['group_id']?.toString())
          .whereType<String>()
          .toSet();

      // Check user role
      final profile = await _supabase
          .from('users')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();
      final role = (profile?['role']?.toString().toLowerCase()) ?? 'student';
      final isAdmin = role == 'admin';

      final res = await _supabase
          .from('notifications')
          .select('id, title, body, type, created_at, deep_link, data, created_by, target_type')
          .order('created_at', ascending: false)
          .limit(100);

      final filtered = (res as List).where((n) {
        if (isAdmin || n['created_by'] == user.id) return true;
        if (n['target_type'] == 'ALL') return true;

        final data = n['data'] as Map<String, dynamic>?;
        if (data == null) return true;

        // Check target_user_ids (specific student assigned notices)
        if (data.containsKey('target_user_ids')) {
          final tUsers = (data['target_user_ids'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toSet() ?? {};
          if (tUsers.isNotEmpty) {
            if (tUsers.contains(user.id)) return true;
            final tGroups = (data['target_group_ids'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toSet() ?? {};
            if (tGroups.isEmpty) return false;
          }
        }

        // Check target_group_ids list
        if (data.containsKey('target_group_ids')) {
          final tGroups = (data['target_group_ids'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toSet() ?? {};
          if (tGroups.isEmpty) return true;
          return myGroupIds.intersection(tGroups).isNotEmpty;
        }

        // Check single group_id
        if (data.containsKey('group_id')) {
          final gid = data['group_id']?.toString();
          if (gid == null || gid.isEmpty) return true;
          return myGroupIds.contains(gid);
        }

        return true;
      }).toList();

      if (mounted) {
        setState(() {
          _notifications = List<Map<String, dynamic>>.from(filtered);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchNotifications,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.notifications_none_rounded,
                        size: 72,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No notifications yet',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Important notices and routine updates will appear here.',
                        style: TextStyle(fontSize: 14, color: Color(0xFF94A3B8)),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _notifications.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final item = _notifications[index];
                    final title = item['title'] ?? 'Notification';
                    final body = item['body'] ?? '';
                    final type = item['type'] ?? 'GENERAL';

                    IconData iconData = Icons.notifications_rounded;
                    Color iconColor = const Color(0xFF1E3A8A);

                    if (type == 'EMERGENCY') {
                      iconData = Icons.warning_amber_rounded;
                      iconColor = Colors.red.shade600;
                    } else if (type == 'ROUTINE') {
                      iconData = Icons.schedule_rounded;
                      iconColor = Colors.orange.shade700;
                    } else if (type == 'NOTICE') {
                      iconData = Icons.article_rounded;
                      iconColor = Colors.blue.shade700;
                    }

                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: iconColor.withValues(alpha: 0.1),
                          child: Icon(iconData, color: iconColor),
                        ),
                        title: Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(body),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

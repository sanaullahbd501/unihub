import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/supabase_service.dart';
import 'notices_service.dart';

class NoticesScreen extends ConsumerStatefulWidget {
  const NoticesScreen({super.key});

  @override
  ConsumerState<NoticesScreen> createState() => _NoticesScreenState();
}

class _NoticesScreenState extends ConsumerState<NoticesScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _notices = [];
  String _userRole = 'student';

  @override
  void initState() {
    super.initState();
    _loadUserRole();
    _fetchNotices();
  }

  Future<void> _loadUserRole() async {
    final user = SupabaseService.client.auth.currentUser;
    if (user != null) {
      try {
        final profile = await SupabaseService.client
            .from('users')
            .select('role')
            .eq('id', user.id)
            .maybeSingle();
        if (mounted && profile != null) {
          setState(() {
            _userRole = (profile['role'] ?? 'student').toString().toLowerCase();
          });
        }
      } catch (_) {}
    }
  }

  Future<void> _fetchNotices() async {
    setState(() => _isLoading = true);
    try {
      final data = await ref.read(noticesServiceProvider).getNotices();
      if (mounted) {
        setState(() {
          _notices = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load notices: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCr = _userRole == 'cr' || _userRole == 'admin';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notices & Announcements'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchNotices,
            tooltip: 'Refresh',
          ),
          if (isCr)
            IconButton(
              icon: const Icon(Icons.campaign_rounded),
              onPressed: () => context.push('/cr-panel'),
              tooltip: 'CR Panel',
            ),
        ],
      ),
      floatingActionButton: isCr
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/cr-panel'),
              icon: const Icon(Icons.add_alert_rounded),
              label: const Text('New Notice'),
              backgroundColor: const Color(0xFF1E3A8A),
              foregroundColor: Colors.white,
            )
          : null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _notices.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.article_outlined, size: 72, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      const Text(
                        'No notices published yet',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'When your CR publishes an announcement, it will appear here.',
                        style: TextStyle(color: Color(0xFF94A3B8)),
                      ),
                      if (isCr) ...[
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: () => context.push('/cr-panel'),
                          icon: const Icon(Icons.add),
                          label: const Text('Publish First Notice'),
                        ),
                      ],
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _fetchNotices,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _notices.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, idx) {
                      final item = _notices[idx];
                      final title = item['title'] ?? 'Notice';
                      final content = item['content'] ?? '';
                      final category = item['category'] ?? 'NOTICE';
                      final eventTimeStr = item['event_time'] as String?;
                      final createdAtStr = item['created_at'] as String?;
                      final targetGroups = item['notice_target_groups'] as List<dynamic>? ?? [];

                      Color badgeColor = const Color(0xFF1E3A8A);
                      if (category == 'EMERGENCY') badgeColor = Colors.red.shade700;
                      if (category == 'ROUTINE') badgeColor = Colors.orange.shade700;
                      if (category == 'EXAM') badgeColor = Colors.purple.shade700;

                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: badgeColor.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      category,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: badgeColor,
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  if (createdAtStr != null)
                                    Text(
                                      createdAtStr.substring(0, 10),
                                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                title,
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                content,
                                style: const TextStyle(fontSize: 14, color: Color(0xFF334155), height: 1.4),
                              ),
                              if (eventTimeStr != null) ...[
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.amber.shade200),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.schedule_rounded, size: 16, color: Colors.brown),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Class / Event Time: ${DateTime.tryParse(eventTimeStr)?.toLocal().toString().substring(0, 16) ?? eventTimeStr}',
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.brown),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              if (targetGroups.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    const Text('Target: ', style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
                                    Wrap(
                                      spacing: 6,
                                      children: targetGroups.map<Widget>((tg) {
                                        final groupName = tg['class_groups']?['name'] ?? 'Group';
                                        return Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFE2E8F0),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            groupName,
                                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

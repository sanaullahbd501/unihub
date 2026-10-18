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
                      final targetUsers = item['notice_target_users'] as List<dynamic>? ?? [];

                      final isEmergency = category == 'EMERGENCY';
                      final isExam = category == 'EXAM';
                      final isRoutine = category == 'ROUTINE';

                      Color cardBg = Colors.white;
                      Color borderColor = const Color(0xFFE2E8F0);
                      double borderWidth = 1.0;
                      Color badgeBg = const Color(0xFF1E3A8A).withValues(alpha: 0.1);
                      Color badgeText = const Color(0xFF1E3A8A);
                      IconData categoryIcon = Icons.article_rounded;

                      if (isEmergency) {
                        cardBg = const Color(0xFFFEF2F2); // Red emergency tint
                        borderColor = const Color(0xFFEF4444); // Bright Red border
                        borderWidth = 2.0;
                        badgeBg = const Color(0xFFDC2626);
                        badgeText = Colors.white;
                        categoryIcon = Icons.crisis_alert_rounded;
                      } else if (isExam) {
                        cardBg = const Color(0xFFFAF5FF); // Purple tint
                        borderColor = const Color(0xFFC084FC);
                        badgeBg = Colors.purple.shade700;
                        badgeText = Colors.white;
                        categoryIcon = Icons.assignment_late_rounded;
                      } else if (isRoutine) {
                        cardBg = const Color(0xFFFFFBEB); // Amber tint
                        borderColor = const Color(0xFFFCD34D);
                        badgeBg = Colors.amber.shade800;
                        badgeText = Colors.white;
                        categoryIcon = Icons.event_note_rounded;
                      }

                      return Container(
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: borderColor, width: borderWidth),
                          boxShadow: isEmergency
                              ? [
                                  BoxShadow(
                                    color: Colors.red.withValues(alpha: 0.2),
                                    blurRadius: 16,
                                    offset: const Offset(0, 4),
                                  ),
                                ]
                              : [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.04),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Left colored accent indicator bar
                                Container(
                                  width: isEmergency ? 8 : 4,
                                  color: isEmergency
                                      ? const Color(0xFFDC2626)
                                      : (isExam
                                          ? Colors.purple.shade700
                                          : (isRoutine ? Colors.amber.shade800 : const Color(0xFF1E3A8A))),
                                ),

                                // Main Content Body
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Header Row with Badge & Time
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: badgeBg,
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(categoryIcon, size: 14, color: badgeText),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    isEmergency ? '🚨 EMERGENCY ALERT' : category,
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.bold,
                                                      color: badgeText,
                                                      letterSpacing: isEmergency ? 0.5 : 0,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const Spacer(),
                                            if (createdAtStr != null)
                                              Text(
                                                createdAtStr.substring(0, 10),
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: isEmergency ? FontWeight.bold : FontWeight.normal,
                                                  color: isEmergency ? Colors.red.shade800 : Colors.grey,
                                                ),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 12),

                                        // Title
                                        Text(
                                          title,
                                          style: TextStyle(
                                            fontSize: isEmergency ? 20 : 18,
                                            fontWeight: FontWeight.bold,
                                            color: isEmergency ? const Color(0xFF991B1B) : const Color(0xFF0F172A),
                                          ),
                                        ),
                                        const SizedBox(height: 8),

                                        // Content
                                        Text(
                                          content,
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: isEmergency ? const Color(0xFF7F1D1D) : const Color(0xFF334155),
                                            height: 1.45,
                                            fontWeight: isEmergency ? FontWeight.w500 : FontWeight.normal,
                                          ),
                                        ),

                                        // Emergency Urgent Banner Box
                                        if (isEmergency) ...[
                                          const SizedBox(height: 12),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                            decoration: BoxDecoration(
                                              color: Colors.red.shade100,
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: Colors.red.shade300),
                                            ),
                                            child: const Row(
                                              children: [
                                                Icon(Icons.warning_amber_rounded, size: 18, color: Color(0xFF991B1B)),
                                                SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    'High-Priority Notice: Action or immediate attention required.',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.bold,
                                                      color: Color(0xFF991B1B),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],

                                        // Event / Class Time (if present)
                                        if (eventTimeStr != null) ...[
                                          const SizedBox(height: 12),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: isEmergency ? Colors.red.shade50 : Colors.amber.shade50,
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: isEmergency ? Colors.red.shade200 : Colors.amber.shade200),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.schedule_rounded,
                                                  size: 16,
                                                  color: isEmergency ? Colors.red.shade800 : Colors.brown,
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  'Class / Event Time: ${DateTime.tryParse(eventTimeStr)?.toLocal().toString().substring(0, 16) ?? eventTimeStr}',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                    color: isEmergency ? Colors.red.shade900 : Colors.brown,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],

                                        // Target Section Badges and CR Delete Option
                                        const SizedBox(height: 12),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            if (targetGroups.isNotEmpty || targetUsers.isNotEmpty)
                                              Expanded(
                                                child: Row(
                                                  children: [
                                                    const Text('Target: ', style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
                                                    Expanded(
                                                      child: Wrap(
                                                        spacing: 6,
                                                        runSpacing: 4,
                                                        children: [
                                                          ...targetGroups.map<Widget>((tg) {
                                                            final groupName = tg['class_groups']?['name'] ?? 'Group';
                                                            return Container(
                                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                              decoration: BoxDecoration(
                                                                color: isEmergency ? Colors.red.shade100 : const Color(0xFFE2E8F0),
                                                                borderRadius: BorderRadius.circular(4),
                                                              ),
                                                              child: Text(
                                                                groupName,
                                                                style: TextStyle(
                                                                  fontSize: 11,
                                                                  fontWeight: FontWeight.w600,
                                                                  color: isEmergency ? Colors.red.shade900 : const Color(0xFF1E293B),
                                                                ),
                                                              ),
                                                            );
                                                          }),
                                                          ...targetUsers.map<Widget>((tu) {
                                                            final userName = tu['users']?['full_name'] ?? 'Student';
                                                            return Container(
                                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                              decoration: BoxDecoration(
                                                                color: Colors.indigo.shade50,
                                                                borderRadius: BorderRadius.circular(4),
                                                                border: Border.all(color: Colors.indigo.shade200),
                                                              ),
                                                              child: Text(
                                                                '👤 $userName',
                                                                style: TextStyle(
                                                                  fontSize: 11,
                                                                  fontWeight: FontWeight.w600,
                                                                  color: Colors.indigo.shade900,
                                                                ),
                                                              ),
                                                            );
                                                          }),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              )
                                            else
                                              const SizedBox.shrink(),

                                            // Permanent or Expiry Badge
                                            if (item['is_permanent'] == true)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: Colors.blue.shade50,
                                                  borderRadius: BorderRadius.circular(4),
                                                  border: Border.all(color: Colors.blue.shade200),
                                                ),
                                                child: const Text('Permanent', style: TextStyle(fontSize: 10, color: Color(0xFF1E3A8A), fontWeight: FontWeight.bold)),
                                              )
                                            else
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: Colors.grey.shade100,
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  item['expires_at'] != null
                                                      ? 'Expires: ${item['expires_at'].toString().substring(5, 10)}'
                                                      : 'Semester Expiry',
                                                  style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w500),
                                                ),
                                              ),

                                            // Delete Button (visible to CR)
                                            if (isCr)
                                              IconButton(
                                                icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Colors.red),
                                                tooltip: 'Delete Notice',
                                                padding: EdgeInsets.zero,
                                                constraints: const BoxConstraints(),
                                                onPressed: () async {
                                                  final confirm = await showDialog<bool>(
                                                    context: context,
                                                    builder: (ctx) => AlertDialog(
                                                      title: const Text('Delete Notice'),
                                                      content: const Text('Are you sure you want to permanently delete this notice?'),
                                                      actions: [
                                                        TextButton(
                                                          onPressed: () => Navigator.pop(ctx, false),
                                                          child: const Text('Cancel'),
                                                        ),
                                                        TextButton(
                                                          onPressed: () => Navigator.pop(ctx, true),
                                                          child: const Text('Delete', style: TextStyle(color: Colors.red)),
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                  if (confirm == true) {
                                                    try {
                                                      await ref.read(noticesServiceProvider).deleteNotice(item['id']);
                                                      _fetchNotices();
                                                      if (context.mounted) {
                                                        ScaffoldMessenger.of(context).showSnackBar(
                                                          const SnackBar(
                                                            content: Text('Notice deleted successfully.'),
                                                            backgroundColor: Color(0xFFDC2626),
                                                          ),
                                                        );
                                                      }
                                                    } catch (e) {
                                                      if (context.mounted) {
                                                        ScaffoldMessenger.of(context).showSnackBar(
                                                          SnackBar(content: Text('Failed to delete notice: $e')),
                                                        );
                                                      }
                                                    }
                                                  }
                                                },
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

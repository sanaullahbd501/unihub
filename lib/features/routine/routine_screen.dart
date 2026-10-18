import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/services/supabase_service.dart';
import 'routine_service.dart';

class RoutineScreen extends ConsumerStatefulWidget {
  const RoutineScreen({super.key});

  @override
  ConsumerState<RoutineScreen> createState() => _RoutineScreenState();
}

class _RoutineScreenState extends ConsumerState<RoutineScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  List<Map<String, dynamic>> _routines = [];
  List<Map<String, dynamic>> _exams = [];
  bool _isCr = false;

  final List<String> _days = [
    'Sunday',
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final user = SupabaseService.client.auth.currentUser;
    if (user != null) {
      try {
        final profile = await SupabaseService.client
            .from('users')
            .select('role')
            .eq('id', user.id)
            .maybeSingle();

        final role = (profile?['role']?.toString().toUpperCase()) ?? 'STUDENT';
        _isCr = role == 'CR' || role == 'ADMIN';

        final routines = await ref.read(routineServiceProvider).getRoutines();
        final exams = await ref.read(routineServiceProvider).getActiveExams();

        if (mounted) {
          setState(() {
            _routines = routines;
            _exams = exams;
            _isLoading = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Academic Routine & Exams'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.calendar_month_rounded), text: 'Weekly Routine'),
            Tab(icon: Icon(Icons.assignment_late_rounded), text: 'Exams & Quizzes'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildWeeklyRoutineView(),
                _buildExamsView(),
              ],
            ),
    );
  }

  Widget _buildWeeklyRoutineView() {
    if (_routines.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_busy_rounded, size: 72, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text(
              'No class routines scheduled yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 8),
            const Text('Your CR will configure classes and auto-reminders.', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    // Group by day of week
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 7,
        itemBuilder: (context, dayIdx) {
          // dayIdx: 0=Sun (day 7), 1=Mon (day 1), ..., 6=Sat (day 6)
          final dayNum = dayIdx == 0 ? 7 : dayIdx;
          final dayName = _days[dayIdx];
          final dayClasses = _routines.where((r) => r['day_of_week'] == dayNum).toList();

          if (dayClasses.isEmpty) return const SizedBox.shrink();

          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E3A8A),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          dayName,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${dayClasses.length} Classes',
                        style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...dayClasses.map((item) {
                    final subject = item['subject'] ?? 'Subject';
                    final teacher = item['teacher_name'] as String?;
                    final startTime = item['start_time'].toString().substring(0, 5);
                    final endTime = item['end_time'].toString().substring(0, 5);
                    final isOnline = item['is_online'] == true;
                    final room = item['room_number'] as String?;
                    final link = item['meeting_link'] as String?;
                    final group = item['class_groups']?['name'] ?? 'Section';

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isOnline ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isOnline ? const Color(0xFF86EFAC) : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(
                              color: isOnline ? const Color(0xFF16A34A) : const Color(0xFF1E3A8A),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  startTime,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                const Text('to', style: TextStyle(color: Colors.white70, fontSize: 10)),
                                Text(
                                  endTime,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: isOnline ? Colors.green.shade100 : Colors.blue.shade100,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        isOnline ? '🌐 Online Class' : '🏫 Offline ($room)',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: isOnline ? Colors.green.shade900 : Colors.blue.shade900,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text('Section $group', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  subject,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0F172A)),
                                ),
                                if (teacher != null && teacher.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text('Teacher: $teacher', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                                ],
                                if (isOnline && link != null && link.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  InkWell(
                                    onTap: () => _launchUrl(link),
                                    child: const Row(
                                      children: [
                                        Icon(Icons.video_call_rounded, size: 16, color: Color(0xFF16A34A)),
                                        SizedBox(width: 4),
                                        Text(
                                          'Join Meeting (Zoom/Meet)',
                                          style: TextStyle(fontSize: 12, color: Color(0xFF16A34A), fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (_isCr)
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                              onPressed: () async {
                                await ref.read(routineServiceProvider).deleteRoutine(item['id']);
                                _loadData();
                              },
                            ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildExamsView() {
    if (_exams.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.celebration_rounded, size: 72, color: Colors.green.shade300),
            const SizedBox(height: 16),
            const Text(
              'No upcoming exams or quizzes!',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 8),
            const Text('Exams auto-delete 3 hours after finishing.', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _exams.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, idx) {
          final exam = _exams[idx];
          final subject = exam['subject'] ?? 'Subject';
          final type = exam['exam_type'] ?? 'FINAL';
          final date = exam['exam_date'] ?? '';
          final startTime = exam['start_time'].toString().substring(0, 5);
          final endTime = exam['end_time'].toString().substring(0, 5);
          final room = exam['room_number'] as String?;
          final isOnline = exam['is_online'] == true;
          final link = exam['meeting_link'] as String?;
          final group = exam['class_groups']?['name'] ?? 'Section';

          return Container(
            decoration: BoxDecoration(
              color: const Color(0xFFFAF5FF),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFC084FC), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.purple.withValues(alpha: 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.purple.shade700,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$type EXAM',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                    Text(
                      'Exam Date: $date',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF581C87)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  subject,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF3B0764)),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.access_time_rounded, size: 16, color: Color(0xFF6B21A8)),
                    const SizedBox(width: 6),
                    Text(
                      '$startTime - $endTime',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF6B21A8)),
                    ),
                    const SizedBox(width: 14),
                    Icon(isOnline ? Icons.videocam_rounded : Icons.meeting_room_rounded, size: 16, color: const Color(0xFF6B21A8)),
                    const SizedBox(width: 6),
                    Text(
                      isOnline ? 'Online Exam' : 'Room: ${room ?? "TBA"}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF6B21A8)),
                    ),
                  ],
                ),
                if (isOnline && link != null && link.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () => _launchUrl(link),
                    icon: const Icon(Icons.link_rounded, size: 16),
                    label: const Text('Open Exam Meeting Link'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Target: Section $group', style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('Auto-deletes 3h after exam ends', style: TextStyle(fontSize: 10, color: Colors.brown, fontWeight: FontWeight.bold)),
                    ),
                    if (_isCr)
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                        onPressed: () async {
                          await ref.read(routineServiceProvider).deleteExam(exam['id']);
                          _loadData();
                        },
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/supabase_service.dart';
import '../../shared/providers/auth_provider.dart';
import '../groups/groups_service.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  Map<String, dynamic>? _userProfile;
  List<Map<String, dynamic>> _myGroups = [];
  Map<String, dynamic>? _latestEmergencyNotice;
  bool _isLoading = true;
  RealtimeChannel? _emergencyNoticesChannel;
  String? _acknowledgedEmergencyNoticeId;

  @override
  void initState() {
    super.initState();
    _loadData();
    // Initialize push notifications
    ref.read(notificationServiceProvider).initialize();
    _subscribeToEmergencyRealtime();
  }

  @override
  void dispose() {
    _emergencyNoticesChannel?.unsubscribe();
    super.dispose();
  }

  void _subscribeToEmergencyRealtime() {
    try {
      _emergencyNoticesChannel = SupabaseService.client
          .channel('public:notices:emergency')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'notices',
            callback: (payload) async {
              final newRecord = payload.newRecord;
              if (newRecord['category'] == 'EMERGENCY') {
                final user = SupabaseService.client.auth.currentUser;
                final isCreator = user != null && newRecord['created_by'] == user.id;

                // Check target groups
                final tgRes = await SupabaseService.client
                    .from('notice_target_groups')
                    .select('group_id')
                    .eq('notice_id', newRecord['id']);
                final tgIds = (tgRes as List).map((t) => t['group_id']?.toString()).whereType<String>().toSet();
                final myGroupIds = _myGroups.map((g) => g['group_id']?.toString()).whereType<String>().toSet();

                if (isCreator || tgIds.isEmpty || myGroupIds.intersection(tgIds).isNotEmpty) {
                  if (mounted) {
                    setState(() => _latestEmergencyNotice = newRecord);
                    _showEmergencyFullScreenDialog(newRecord);
                  }
                }
              }
            },
          )
          .subscribe();
    } catch (_) {}
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final user = SupabaseService.client.auth.currentUser;
    if (user != null) {
      try {
        final profile = await SupabaseService.client
            .from('users')
            .select()
            .eq('id', user.id)
            .maybeSingle();

        final groups = await ref.read(groupsServiceProvider).getMyEnrolledGroups();

        final emergencyNotices = await SupabaseService.client
            .from('notices')
            .select('id, title, content, created_at, created_by, notice_target_groups(group_id), notice_target_users(user_id)')
            .eq('category', 'EMERGENCY')
            .order('created_at', ascending: false)
            .limit(10);

        final myGroupIds = groups.map((g) => g['group_id']?.toString()).whereType<String>().toSet();
        Map<String, dynamic>? matchingEmergency;
        for (final en in (emergencyNotices as List)) {
          if (en['created_by'] == user.id) {
            matchingEmergency = Map<String, dynamic>.from(en);
            break;
          }
          final tu = en['notice_target_users'] as List<dynamic>? ?? [];
          if (tu.any((u) => u['user_id']?.toString() == user.id)) {
            matchingEmergency = Map<String, dynamic>.from(en);
            break;
          }
          final tg = en['notice_target_groups'] as List<dynamic>? ?? [];
          if (tg.isEmpty && tu.isEmpty) {
            matchingEmergency = Map<String, dynamic>.from(en);
            break;
          }
          final tgIds = tg.map((t) => t['group_id']?.toString()).whereType<String>().toSet();
          if (myGroupIds.intersection(tgIds).isNotEmpty) {
            matchingEmergency = Map<String, dynamic>.from(en);
            break;
          }
        }

        if (mounted) {
          setState(() {
            _userProfile = profile;
            _myGroups = groups;
            _latestEmergencyNotice = matchingEmergency;
            _isLoading = false;
          });

          // Automatically surface screen-filling alert if unacknowledged
          if (matchingEmergency != null && _acknowledgedEmergencyNoticeId != matchingEmergency['id']) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _showEmergencyFullScreenDialog(matchingEmergency!);
              }
            });
          }
        }
      } catch (_) {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _pickAndUploadAvatar(void Function(void Function()) setModalState) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      final user = SupabaseService.client.auth.currentUser;
      if (user == null) return;

      final fileName = '${user.id}.webp';
      await SupabaseService.client.storage
          .from('avatars')
          .uploadBinary(
            fileName,
            bytes,
            fileOptions: const FileOptions(contentType: 'image/webp', upsert: true),
          );

      final publicUrl = SupabaseService.client.storage
          .from('avatars')
          .getPublicUrl(fileName);

      final cacheBustedUrl = '$publicUrl?t=${DateTime.now().millisecondsSinceEpoch}';

      await SupabaseService.client
          .from('users')
          .update({'avatar_url': cacheBustedUrl})
          .eq('id', user.id);

      setModalState(() {
        if (_userProfile != null) {
          _userProfile!['avatar_url'] = cacheBustedUrl;
        }
      });
      setState(() {
        if (_userProfile != null) {
          _userProfile!['avatar_url'] = cacheBustedUrl;
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('প্রোফাইল ছবি সফলভাবে WebP ফরম্যাটে আপলোড হয়েছে!'),
            backgroundColor: Color(0xFF16A34A),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ছবি আপলোড ব্যর্থ: $e')),
        );
      }
    }
  }

  Future<void> _showRoleDialog() async {
    final currentRole = _userProfile?['role']?.toString().toLowerCase() ?? 'student';
    String selectedRole = currentRole;
    final nameCtrl = TextEditingController(text: _userProfile?['full_name'] ?? '');

    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final avatarUrl = _userProfile?['avatar_url'] as String?;

          return AlertDialog(
            title: const Text('Profile & Role Setup'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Avatar with upload button
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 44,
                        backgroundColor: const Color(0xFF1E3A8A).withValues(alpha: 0.1),
                        backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                            ? NetworkImage(avatarUrl)
                            : null,
                        child: avatarUrl == null || avatarUrl.isEmpty
                            ? const Icon(Icons.person, size: 48, color: Color(0xFF1E3A8A))
                            : null,
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: InkWell(
                          onTap: () => _pickAndUploadAvatar(setModalState),
                          child: const CircleAvatar(
                            radius: 16,
                            backgroundColor: Color(0xFF1E3A8A),
                            child: Icon(Icons.camera_alt_rounded, size: 16, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => _pickAndUploadAvatar(setModalState),
                    icon: const Icon(Icons.upload_rounded, size: 16),
                    label: const Text('Change Picture (WebP)'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Full Name',
                      hintText: 'e.g. Sanaullah',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Select Your Primary Role:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                  RadioGroup<String>(
                    groupValue: selectedRole,
                    onChanged: (val) {
                      if (val != null) setModalState(() => selectedRole = val);
                    },
                    child: Column(
                      children: const [
                        RadioListTile<String>(
                          title: Text('CR (Class Representative)'),
                          subtitle: Text('Create classes, manage groups (95B, 95C), add Co-CR, broadcast notices'),
                          value: 'cr',
                        ),
                        RadioListTile<String>(
                          title: Text('Student'),
                          subtitle: Text('Join class groups with invite codes and receive targeted notices'),
                          value: 'student',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  try {
                    await ref.read(groupsServiceProvider).updateUserRole(
                      role: selectedRole,
                      fullName: nameCtrl.text.trim(),
                    );
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  } catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(content: Text('Failed: $e')),
                      );
                    }
                  }
                },
                child: const Text('Save Changes'),
              ),
            ],
          );
        },
      ),
    );

    if (updated == true) {
      _loadData();
    }
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out'),
        content: const Text('Are you sure you want to log out from UniHub?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log out', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(notificationServiceProvider).deactivateTokenOnLogout();
      await ref.read(authServiceProvider).signOut();
      if (!mounted) return;
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final email = user?.email ?? 'Student';
    final role = (_userProfile?['role']?.toString().toUpperCase()) ?? 'STUDENT';
    final isCr = role == 'CR' || role == 'ADMIN';
    final avatarUrl = _userProfile?['avatar_url'] as String?;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.school_rounded, color: Color(0xFF1E3A8A)),
            SizedBox(width: 8),
            Text('UniHub'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.wifi_calling_3_rounded, color: Color(0xFF1E3A8A)),
            onPressed: () => context.push('/campus-call'),
            tooltip: 'Campus WiFi Calling',
          ),
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => context.push('/notifications'),
            tooltip: 'Notifications',
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            onPressed: _handleLogout,
            tooltip: 'Log out',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: RefreshIndicator(
                  onRefresh: _loadData,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Pinned Emergency Alert Banner
                        if (_latestEmergencyNotice != null)
                          _buildEmergencyBanner(_latestEmergencyNotice!),

                        // User Profile Card
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 28,
                                  backgroundColor: const Color(0xFF1E3A8A).withValues(alpha: 0.1),
                                  backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                                      ? NetworkImage(avatarUrl)
                                      : null,
                                  child: avatarUrl == null || avatarUrl.isEmpty
                                      ? Icon(
                                          isCr ? Icons.admin_panel_settings_rounded : Icons.person_outline_rounded,
                                          size: 32,
                                          color: const Color(0xFF1E3A8A),
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _userProfile?['full_name'] ?? email,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF0F172A),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: isCr
                                                  ? Colors.amber.shade100
                                                  : const Color(0xFF0284C7).withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              role,
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: isCr ? Colors.brown.shade800 : const Color(0xFF0284C7),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          InkWell(
                                            onTap: _showRoleDialog,
                                            child: const Text(
                                              'Edit Profile & Photo',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Color(0xFF1E3A8A),
                                                decoration: TextDecoration.underline,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // CR Hero Card (if CR)
                        if (isCr)
                          Card(
                            color: const Color(0xFF1E3A8A),
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.stars_rounded, color: Colors.amber, size: 28),
                                      SizedBox(width: 8),
                                      Text(
                                        'CR Management Portal',
                                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Create batches, manage groups (95B, 95C), assign Co-CRs, and broadcast targeted notices with push alerts.',
                                    style: TextStyle(color: Color(0xFFE2E8F0), fontSize: 13),
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      ElevatedButton.icon(
                                        onPressed: () => context.push('/cr-panel'),
                                        icon: const Icon(Icons.dashboard_customize_rounded, size: 18),
                                        label: const Text('Open CR Panel'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.amber.shade400,
                                          foregroundColor: Colors.brown.shade900,
                                          textStyle: const TextStyle(fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          // Enrolled Groups Card (for Students)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        'My Class Groups',
                                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                      ),
                                      TextButton.icon(
                                        onPressed: () => context.push('/join-group'),
                                        icon: const Icon(Icons.add, size: 16),
                                        label: const Text('Join Group'),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  if (_myGroups.isEmpty)
                                    const Text(
                                      'You are not enrolled in any group yet. Click "Join Group" and enter your section code (e.g. 95B).',
                                      style: TextStyle(color: Colors.grey, fontSize: 13),
                                    )
                                  else
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: _myGroups.map((item) {
                                        final g = item['class_groups'] as Map<String, dynamic>?;
                                        final gId = item['group_id'] as String;
                                        final gName = g?['name'] ?? 'Group';
                                        return Chip(
                                          avatar: const Icon(Icons.group, size: 16, color: Color(0xFF1E3A8A)),
                                          label: Text('Section $gName'),
                                          backgroundColor: const Color(0xFFEFF6FF),
                                          deleteIcon: const Icon(Icons.close, size: 16),
                                          onDeleted: () async {
                                            await ref.read(groupsServiceProvider).leaveGroup(gId);
                                            _loadData();
                                          },
                                        );
                                      }).toList(),
                                    ),
                                ],
                              ),
                            ),
                          ),

                        const SizedBox(height: 24),
                        const Text(
                          'Academic Features',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Features Grid
                        GridView.count(
                          crossAxisCount: MediaQuery.of(context).size.width > 600 ? 4 : 2,
                          childAspectRatio: MediaQuery.of(context).size.width > 600 ? 1.0 : 1.2,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                          children: [
                            _buildFeatureCard(
                              title: 'Notices',
                              subtitle: 'Official announcements',
                              icon: Icons.article_outlined,
                              color: Colors.blue.shade700,
                              onTap: () => context.push('/notices'),
                            ),
                            _buildFeatureCard(
                              title: isCr ? 'CR Panel' : 'Join Class',
                              subtitle: isCr ? 'Manage groups & notices' : 'Enter class code',
                              icon: isCr ? Icons.admin_panel_settings_outlined : Icons.vpn_key_outlined,
                              color: isCr ? Colors.amber.shade800 : Colors.teal.shade700,
                              onTap: () => context.push(isCr ? '/cr-panel' : '/join-group'),
                            ),
                            _buildFeatureCard(
                              title: 'Routine',
                              subtitle: 'Class & exam schedule',
                              icon: Icons.calendar_month_outlined,
                              color: Colors.orange.shade700,
                              onTap: () => context.push('/routine'),
                            ),
                            _buildFeatureCard(
                              title: 'Campus Intercom',
                              subtitle: 'Free P2P WiFi calling',
                              icon: Icons.wifi_calling_3_rounded,
                              color: const Color(0xFF059669),
                              onTap: () => context.push('/campus-call'),
                            ),
                            _buildFeatureCard(
                              title: 'Notifications',
                              subtitle: 'Push alert history',
                              icon: Icons.notifications_active_outlined,
                              color: const Color(0xFF1E3A8A),
                              onTap: () => context.push('/notifications'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildFeatureCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmergencyBanner(Map<String, dynamic> notice) {
    final title = notice['title'] ?? 'Emergency Announcement';
    final content = notice['content'] ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDC2626), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withValues(alpha: 0.25),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showEmergencyFullScreenDialog(notice),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDC2626),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.crisis_alert_rounded, color: Colors.white, size: 28),
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
                              color: const Color(0xFFDC2626),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              '🚨 URGENT',
                              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF991B1B),
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        content,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF7F1D1D),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right_rounded, color: Color(0xFFDC2626)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showEmergencyFullScreenDialog(Map<String, dynamic> notice) async {
    final title = notice['title'] ?? 'জরুরি নোটিশ / EMERGENCY ALERT';
    final content = notice['content'] ?? '';
    final createdAt = notice['created_at'] != null ? DateTime.tryParse(notice['created_at'].toString())?.toLocal() : null;
    final timeStr = createdAt != null
        ? '${createdAt.day}/${createdAt.month}/${createdAt.year} ${createdAt.hour}:${createdAt.minute.toString().padLeft(2, '0')}'
        : '';

    await showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (ctx, anim1, anim2) {
        return Scaffold(
          backgroundColor: const Color(0xFF7F1D1D),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Animated Emergency Icon & Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDC2626),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.red.withValues(alpha: 0.8),
                              blurRadius: 20,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.crisis_alert_rounded, color: Colors.white, size: 38),
                      ),
                      const SizedBox(width: 14),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'EMERGENCY ALERT',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                            ),
                          ),
                          Text(
                            'জরুরি নোটিশ ও নির্দেশনা',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Emergency Content Card
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEE2E2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.priority_high_rounded, color: Color(0xFFDC2626), size: 16),
                                SizedBox(width: 4),
                                Text(
                                  'HIGHEST PRIORITY BROADCAST',
                                  style: TextStyle(color: Color(0xFF991B1B), fontWeight: FontWeight.bold, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E293B),
                              height: 1.3,
                            ),
                          ),
                          if (timeStr.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              'Published: $timeStr',
                              style: const TextStyle(color: Colors.grey, fontSize: 12),
                            ),
                          ],
                          const Divider(height: 24),
                          Expanded(
                            child: SingleChildScrollView(
                              child: Text(
                                content,
                                style: const TextStyle(
                                  fontSize: 16,
                                  height: 1.6,
                                  color: Color(0xFF334155),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFFCA5A5)),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.info_outline_rounded, color: Color(0xFFDC2626), size: 20),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'অনুগ্রহ করে এই নোটিশটি মনোযোগ দিয়ে পড়ুন এবং ক্লাসমেটদের সাথে শেয়ার করুন।',
                                    style: TextStyle(fontSize: 12, color: Color(0xFF7F1D1D), fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Acknowledge Button
                  ElevatedButton.icon(
                    onPressed: () {
                      _acknowledgedEmergencyNoticeId = notice['id'];
                      Navigator.pop(ctx);
                    },
                    icon: const Icon(Icons.check_circle_outline_rounded, size: 24),
                    label: const Text('আমি নোটিশটি পড়েছি (I Understand & Acknowledge)'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFFDC2626),
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

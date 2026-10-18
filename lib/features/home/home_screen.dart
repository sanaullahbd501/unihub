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
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
    // Initialize push notifications
    ref.read(notificationServiceProvider).initialize();
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

        if (mounted) {
          setState(() {
            _userProfile = profile;
            _myGroups = groups;
            _isLoading = false;
          });
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
                              onTap: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Routine module: use notices for routine changes.')),
                                );
                              },
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
}

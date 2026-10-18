import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../groups/groups_service.dart';
import '../notices/notices_service.dart';

class CrPanelScreen extends ConsumerStatefulWidget {
  const CrPanelScreen({super.key});

  @override
  ConsumerState<CrPanelScreen> createState() => _CrPanelScreenState();
}

class _CrPanelScreenState extends ConsumerState<CrPanelScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  List<Map<String, dynamic>> _classes = [];

  // Broadcast Notice Form State
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  String _selectedCategory = 'NOTICE';
  final Set<String> _selectedGroupIds = {};
  DateTime? _selectedEventTime;
  DateTime? _selectedExpiryTime;
  bool _isPermanent = false;
  bool _sendPush = true;
  bool _isPublishing = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final classes = await ref.read(groupsServiceProvider).getMyManagedClasses();
      if (mounted) {
        setState(() {
          _classes = classes;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading classes: $e')),
        );
      }
    }
  }

  // Flatten all groups across managed classes
  List<Map<String, dynamic>> get _allGroups {
    final list = <Map<String, dynamic>>[];
    for (final cls in _classes) {
      final groups = cls['class_groups'] as List<dynamic>? ?? [];
      for (final g in groups) {
        list.add({
          ...Map<String, dynamic>.from(g),
          'class_name': cls['name'],
        });
      }
    }
    return list;
  }

  Future<void> _showCreateClassDialog() async {
    final nameCtrl = TextEditingController(text: 'CSE 95th Batch');
    final deptCtrl = TextEditingController(text: 'CSE');
    final uniCtrl = TextEditingController(text: 'World University of Bangladesh (WUB)');

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create Class / Batch'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Class / Batch Name *',
                  hintText: 'e.g. CSE 95th Batch',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: deptCtrl,
                decoration: const InputDecoration(
                  labelText: 'Department',
                  hintText: 'e.g. CSE',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: uniCtrl,
                decoration: const InputDecoration(
                  labelText: 'University',
                  hintText: 'e.g. WUB / DIU',
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
              if (nameCtrl.text.trim().isEmpty) return;
              try {
                await ref.read(groupsServiceProvider).createClass(
                  name: nameCtrl.text.trim(),
                  departmentName: deptCtrl.text.trim(),
                  universityName: uniCtrl.text.trim(),
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
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (created == true) {
      _loadData();
    }
  }

  Future<void> _showAddGroupDialog(String classId, String className) async {
    final nameCtrl = TextEditingController();
    final codeCtrl = TextEditingController();

    nameCtrl.addListener(() {
      codeCtrl.text = nameCtrl.text.trim().toUpperCase();
    });

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add Group to $className'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Group / Section Name *',
                  hintText: 'e.g. 95B or 95C',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: codeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Invite Code *',
                  hintText: 'e.g. 95B',
                  helperText: 'Students will use this code to join this group',
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
              if (nameCtrl.text.trim().isEmpty || codeCtrl.text.trim().isEmpty) return;
              try {
                await ref.read(groupsServiceProvider).createGroup(
                  classId: classId,
                  name: nameCtrl.text.trim(),
                  inviteCode: codeCtrl.text.trim(),
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
            child: const Text('Add Group'),
          ),
        ],
      ),
    );

    if (created == true) {
      _loadData();
    }
  }

  Future<void> _showAddCoCrDialog(String classId) async {
    final emailCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Co-CR'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter the registered email of the student you want to designate as Co-CR:',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Co-CR Email *',
                hintText: 'student@example.com',
                prefixIcon: Icon(Icons.email_outlined),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (emailCtrl.text.trim().isEmpty) return;
              try {
                await ref.read(groupsServiceProvider).addCoCr(
                  classId: classId,
                  userEmail: emailCtrl.text.trim(),
                );
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Co-CR successfully added!')),
                  );
                }
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickEventTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedEventTime ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null) return;

    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedEventTime ?? now),
    );
    if (time == null) return;

    setState(() {
      _selectedEventTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _pickExpiryTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedExpiryTime ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null) return;

    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedExpiryTime ?? now),
    );
    if (time == null) return;

    setState(() {
      _selectedExpiryTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _handleBroadcast() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a notice title.')),
      );
      return;
    }
    if (_contentController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter notice content.')),
      );
      return;
    }
    if (_selectedGroupIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one group (e.g. 95B, 95C) to target.')),
      );
      return;
    }

    setState(() => _isPublishing = true);
    try {
      await ref.read(noticesServiceProvider).publishNotice(
        title: _titleController.text.trim(),
        content: _contentController.text.trim(),
        category: _selectedCategory,
        targetGroupIds: _selectedGroupIds.toList(),
        eventTime: _selectedEventTime,
        customExpiry: _selectedExpiryTime,
        isPermanent: _isPermanent,
        sendPush: _sendPush,
      );

      if (mounted) {
        setState(() {
          _isPublishing = false;
          _titleController.clear();
          _contentController.clear();
          _selectedGroupIds.clear();
          _selectedEventTime = null;
          _selectedExpiryTime = null;
          _isPermanent = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFF1E3A8A),
            content: Text('Notice published and Push Notifications dispatched successfully!'),
          ),
        );

        // Switch to notices or pop
        context.push('/notices');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isPublishing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to publish notice: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CR Management Panel'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.groups_rounded), text: 'Classes & Groups'),
            Tab(icon: Icon(Icons.campaign_rounded), text: 'Broadcast Notice'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildClassesTab(),
                _buildBroadcastTab(),
              ],
            ),
    );
  }

  // Tab 1: Classes & Groups Management
  Widget _buildClassesTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'My Managed Classes',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              ElevatedButton.icon(
                onPressed: _showCreateClassDialog,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New Class'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_classes.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(Icons.school_outlined, size: 56, color: Colors.grey.shade400),
                    const SizedBox(height: 12),
                    const Text(
                      'No classes created yet',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Create your batch (e.g. CSE 95th Batch) to start adding sections like 95B, 95C and invite students.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _showCreateClassDialog,
                      child: const Text('Create Class Now'),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _classes.length,
              itemBuilder: (context, idx) {
                final cls = _classes[idx];
                final classId = cls['id'] as String;
                final className = cls['name'] ?? 'Class';
                final groups = cls['class_groups'] as List<dynamic>? ?? [];

                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: const Color(0xFF1E3A8A).withValues(alpha: 0.1),
                              child: const Icon(Icons.school, color: Color(0xFF1E3A8A)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    className,
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    '${cls['department_name'] ?? ''} • ${cls['university_name'] ?? ''}',
                                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                            PopupMenuButton<String>(
                              onSelected: (val) {
                                if (val == 'add_group') _showAddGroupDialog(classId, className);
                                if (val == 'add_co_cr') _showAddCoCrDialog(classId);
                              },
                              itemBuilder: (ctx) => [
                                const PopupMenuItem(
                                  value: 'add_group',
                                  child: Row(
                                    children: [
                                      Icon(Icons.add_box_outlined, size: 18),
                                      SizedBox(width: 8),
                                      Text('Add Group / Section'),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'add_co_cr',
                                  child: Row(
                                    children: [
                                      Icon(Icons.person_add_alt, size: 18),
                                      SizedBox(width: 8),
                                      Text('Add Co-CR'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Groups / Sections (${groups.length})',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            TextButton.icon(
                              onPressed: () => _showAddGroupDialog(classId, className),
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('Add Group'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (groups.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'No sections added yet (e.g. 95B, 95C). Click "Add Group" to create one.',
                              style: TextStyle(color: Colors.grey, fontSize: 13),
                            ),
                          )
                        else
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: groups.map<Widget>((g) {
                              final gName = g['name'] ?? '';
                              final code = g['invite_code'] ?? '';
                              return Chip(
                                avatar: const Icon(Icons.group, size: 16, color: Color(0xFF1E3A8A)),
                                label: Text('$gName (Code: $code)'),
                                deleteIcon: const Icon(Icons.copy_rounded, size: 16),
                                onDeleted: () {
                                  Clipboard.setData(ClipboardData(text: code));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Copied invite code: $code')),
                                  );
                                },
                              );
                            }).toList(),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  // Tab 2: Broadcast Notice to Selected Groups
  Widget _buildBroadcastTab() {
    final groups = _allGroups;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Target Groups (Multi-Select)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Select which groups (e.g. 95B, 95C) will receive this notice & push alert:',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  if (groups.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.orange),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Please create at least one class group (e.g. 95B) in the "Classes & Groups" tab first.',
                              style: TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    Row(
                      children: [
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _selectedGroupIds.addAll(groups.map((g) => g['id'] as String));
                            });
                          },
                          child: const Text('Select All'),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _selectedGroupIds.clear();
                            });
                          },
                          child: const Text('Clear All'),
                        ),
                        const Spacer(),
                        Text(
                          '${_selectedGroupIds.length} of ${groups.length} selected',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: groups.map((g) {
                        final gId = g['id'] as String;
                        final gName = g['name'] ?? '';
                        final isSelected = _selectedGroupIds.contains(gId);
                        return FilterChip(
                          selected: isSelected,
                          label: Text(gName),
                          selectedColor: const Color(0xFF1E3A8A).withValues(alpha: 0.2),
                          checkmarkColor: const Color(0xFF1E3A8A),
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                _selectedGroupIds.add(gId);
                              } else {
                                _selectedGroupIds.remove(gId);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Notice Details',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: 'Notice Title *',
                      hintText: 'e.g. Tomorrow Algorithm Class Rescheduled',
                      prefixIcon: Icon(Icons.title_rounded),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _contentController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Notice Content / Description *',
                      hintText: 'Write announcement details, room number, or routine changes...',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedCategory,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      prefixIcon: Icon(Icons.category_outlined),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'NOTICE', child: Text('Official Notice')),
                      DropdownMenuItem(value: 'ROUTINE', child: Text('Routine / Class Update')),
                      DropdownMenuItem(value: 'EXAM', child: Text('Exam / Quiz / CT')),
                      DropdownMenuItem(value: 'EMERGENCY', child: Text('🚨 Emergency Alert')),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedCategory = val);
                    },
                  ),
                  const SizedBox(height: 16),
                  // Event / Class Time Picker
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFF1F5F9),
                      child: Icon(Icons.schedule_rounded, color: Color(0xFF1E3A8A)),
                    ),
                    title: Text(
                      _selectedEventTime == null
                          ? 'Set Class / Event Time (Optional)'
                          : 'Event Time: ${_selectedEventTime!.toLocal().toString().substring(0, 16)}',
                      style: TextStyle(
                        fontWeight: _selectedEventTime != null ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    subtitle: const Text('Specify the exact date & time for this class or deadline'),
                    trailing: _selectedEventTime != null
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () => setState(() => _selectedEventTime = null),
                          )
                        : TextButton(
                            onPressed: _pickEventTime,
                            child: const Text('Pick Time'),
                          ),
                    onTap: _pickEventTime,
                  ),
                  const Divider(),

                  // Notice Lifecycle & Expiry Settings
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Permanent Notice (Never auto-delete)'),
                    subtitle: const Text('For university policies or rules that should stay beyond the 3-month semester'),
                    value: _isPermanent,
                    onChanged: (val) {
                      setState(() {
                        _isPermanent = val ?? false;
                        if (_isPermanent) _selectedExpiryTime = null;
                      });
                    },
                  ),

                  if (!_isPermanent)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFFEFF6FF),
                        child: Icon(Icons.auto_delete_outlined, color: Color(0xFF1E3A8A)),
                      ),
                      title: Text(
                        _selectedExpiryTime == null
                            ? 'Auto-Delete: End of Semester (3 Months Default)'
                            : 'Auto-Delete On: ${_selectedExpiryTime!.toLocal().toString().substring(0, 16)}',
                        style: TextStyle(
                          fontWeight: _selectedExpiryTime != null ? FontWeight.bold : FontWeight.w500,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Text(
                        _selectedExpiryTime == null
                            ? 'Cleaned up automatically after 90 days. Tap to set specific expiry time.'
                            : 'Notice will automatically vanish from students after this date & time.',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: _selectedExpiryTime != null
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () => setState(() => _selectedExpiryTime = null),
                            )
                          : TextButton(
                              onPressed: _pickExpiryTime,
                              child: const Text('Change Date'),
                            ),
                      onTap: _pickExpiryTime,
                    ),

                  const Divider(),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Send Push Notification to all students in selected groups'),
                    subtitle: const Text('Students will receive an immediate mobile push notification alert'),
                    value: _sendPush,
                    onChanged: (val) => setState(() => _sendPush = val),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_selectedCategory == 'EMERGENCY') ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade400, width: 1.5),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          '🚨 Emergency Mode Activated',
                          style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF991B1B), fontSize: 14),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'This notice will appear in bold Red Alert style with high-priority banners for all students in target sections.',
                          style: TextStyle(color: Color(0xFF7F1D1D), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          ElevatedButton.icon(
            onPressed: _isPublishing ? null : _handleBroadcast,
            icon: _isPublishing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Icon(_selectedCategory == 'EMERGENCY' ? Icons.crisis_alert_rounded : Icons.send_rounded),
            label: Text(_isPublishing
                ? 'Publishing & Sending...'
                : (_selectedCategory == 'EMERGENCY'
                    ? '🚨 Broadcast Emergency Alert'
                    : 'Publish Notice & Notify Students')),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: _selectedCategory == 'EMERGENCY' ? const Color(0xFFDC2626) : const Color(0xFF1E3A8A),
              foregroundColor: Colors.white,
              textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }
}

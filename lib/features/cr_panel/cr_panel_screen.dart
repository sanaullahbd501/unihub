import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../groups/groups_service.dart';
import '../notices/notices_service.dart';
import '../routine/routine_service.dart';

class CrPanelScreen extends ConsumerStatefulWidget {
  const CrPanelScreen({super.key});

  @override
  ConsumerState<CrPanelScreen> createState() => _CrPanelScreenState();
}

class _CrPanelScreenState extends ConsumerState<CrPanelScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _routines = [];
  List<Map<String, dynamic>> _exams = [];

  // Broadcast Notice Form State
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  String _selectedCategory = 'NOTICE';
  final Set<String> _selectedGroupIds = {};
  final Set<String> _selectedStudentIds = {};
  List<Map<String, dynamic>> _allStudents = [];
  String _targetMode = 'GROUPS'; // 'GROUPS', 'STUDENTS', 'BOTH'
  DateTime? _selectedEventTime;
  DateTime? _selectedExpiryTime;
  bool _isPermanent = false;
  bool _sendPush = true;
  bool _isPublishing = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
        });
      }
    } catch (e) {
      debugPrint('Error loading classes: $e');
    }

    try {
      final routines = await ref.read(routineServiceProvider).getRoutines();
      final exams = await ref.read(routineServiceProvider).getActiveExams();
      if (mounted) {
        setState(() {
          _routines = routines;
          _exams = exams;
        });
      }
    } catch (e) {
      debugPrint('Error loading routines/exams: $e');
    }

    try {
      final students = await ref.read(groupsServiceProvider).getAllStudentsInManagedClasses();
      if (mounted) {
        setState(() {
          _allStudents = students;
        });
      }
    } catch (e) {
      debugPrint('Error loading students: $e');
    }

    if (mounted) {
      setState(() => _isLoading = false);
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
      if (codeCtrl.text.isEmpty || codeCtrl.text.startsWith(nameCtrl.text.trim().toUpperCase())) {
        codeCtrl.text = nameCtrl.text.trim().toUpperCase();
      }
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
                decoration: InputDecoration(
                  labelText: 'Invite Code *',
                  hintText: 'e.g. 95B or 95B-4819',
                  helperText: 'Students will use this code to join this group',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.shuffle_rounded),
                    tooltip: 'Generate Unique Code (ইউনিক কোড তৈরি করুন)',
                    onPressed: () {
                      final prefix = nameCtrl.text.trim().replaceAll(' ', '').toUpperCase();
                      final pfx = prefix.isEmpty ? 'GRP' : prefix;
                      final rnd = 1000 + Random().nextInt(9000);
                      codeCtrl.text = '$pfx-$rnd';
                    },
                  ),
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

  Future<void> _showGroupMembersDialog(
    String classId,
    String className,
    String groupId,
    String groupName,
    bool initialIsLocked,
  ) async {
    bool isLocked = initialIsLocked;
    final addEmailCtrl = TextEditingController();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          return Container(
            height: MediaQuery.of(sheetCtx).size.height * 0.85,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                  ),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        backgroundColor: Color(0xFFEFF6FF),
                        child: Icon(Icons.groups_rounded, color: Color(0xFF1E3A8A)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$className - Section $groupName',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const Text(
                              'Student Roster & Permissions (ছাত্র তালিকা ও নিয়ন্ত্রণ)',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(sheetCtx),
                      ),
                    ],
                  ),
                ),
                // Lock Toggle Banner
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isLocked ? const Color(0xFFFEF2F2) : const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isLocked ? const Color(0xFFFECACA) : const Color(0xFFBBF7D0)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
                        color: isLocked ? Colors.red.shade700 : Colors.green.shade700,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isLocked
                                  ? 'Joining is LOCKED (লক করা)'
                                  : 'Joining is OPEN (উন্মুক্ত)',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isLocked ? Colors.red.shade900 : Colors.green.shade900,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              isLocked
                                  ? 'Students cannot join via code. Only CR can add students.'
                                  : 'Students can join this section using the invite code.',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: isLocked,
                        activeThumbColor: Colors.red,
                        onChanged: (val) async {
                          try {
                            await ref.read(groupsServiceProvider).toggleGroupJoinLock(
                              groupId: groupId,
                              isLocked: val,
                            );
                            setSheetState(() => isLocked = val);
                            _loadData();
                          } catch (e) {
                            if (sheetCtx.mounted) {
                              ScaffoldMessenger.of(sheetCtx).showSnackBar(SnackBar(content: Text('Failed: $e')));
                            }
                          }
                        },
                      ),
                    ],
                  ),
                ),
                // Direct Add by Email Row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: addEmailCtrl,
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: 'Add student by email (সরাসরি এড করুন)',
                            hintStyle: const TextStyle(fontSize: 13),
                            prefixIcon: const Icon(Icons.person_add_alt_1, size: 18),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () async {
                          if (addEmailCtrl.text.trim().isEmpty) return;
                          try {
                            await ref.read(groupsServiceProvider).addMemberDirectly(
                              groupId: groupId,
                              email: addEmailCtrl.text.trim(),
                            );
                            addEmailCtrl.clear();
                            setSheetState(() {});
                            _loadData();
                            if (sheetCtx.mounted) {
                              ScaffoldMessenger.of(sheetCtx).showSnackBar(
                                const SnackBar(content: Text('Student successfully enrolled!')),
                              );
                            }
                          } catch (e) {
                            if (sheetCtx.mounted) {
                              ScaffoldMessenger.of(sheetCtx).showSnackBar(
                                SnackBar(content: Text('Error: $e')),
                              );
                            }
                          }
                        },
                        child: const Text('Add'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // CRs and Students Lists
                Expanded(
                  child: FutureBuilder<List<dynamic>>(
                    future: Future.wait([
                      ref.read(groupsServiceProvider).getClassCRs(classId),
                      ref.read(groupsServiceProvider).getGroupMembers(groupId),
                    ]),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return Center(child: Text('Error: ${snapshot.error}'));
                      }

                      final crData = snapshot.data![0] as Map<String, dynamic>;
                      final members = snapshot.data![1] as List<Map<String, dynamic>>;

                      final creator = crData['creator'] as Map<String, dynamic>?;
                      final coCrs = crData['co_crs'] as List<Map<String, dynamic>>? ?? [];

                      return ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          // CR Section
                          const Text(
                            'Class Representatives (CR)',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E3A8A)),
                          ),
                          const SizedBox(height: 6),
                          if (creator != null)
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: const CircleAvatar(
                                backgroundColor: Color(0xFF1E3A8A),
                                child: Icon(Icons.star, color: Colors.amber, size: 18),
                              ),
                              title: Text(creator['full_name'] ?? 'CR', style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(creator['email'] ?? ''),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade100,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text('Main CR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.brown)),
                              ),
                            ),
                          ...coCrs.map((cc) {
                            final u = cc['users'] as Map<String, dynamic>?;
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: const CircleAvatar(
                                backgroundColor: Color(0xFFEFF6FF),
                                child: Icon(Icons.shield, color: Color(0xFF1E3A8A), size: 18),
                              ),
                              title: Text(u?['full_name'] ?? 'Co-CR', style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(u?['email'] ?? ''),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade100,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text('Co-CR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A))),
                              ),
                            );
                          }),
                          const Divider(height: 24),
                          // Students Section
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Enrolled Students (${members.length})',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E3A8A)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          if (members.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                children: [
                                  Icon(Icons.person_off_outlined, size: 40, color: Colors.grey.shade400),
                                  const SizedBox(height: 8),
                                  const Text('No students have joined this section yet.', style: TextStyle(color: Colors.grey, fontSize: 13)),
                                ],
                              ),
                            )
                          else
                            ...members.map((m) {
                              final u = m['users'] as Map<String, dynamic>?;
                              final studentName = u?['full_name'] ?? 'Student';
                              final studentEmail = u?['email'] ?? '';
                              final memberId = m['id'] as String;

                              return Card(
                                margin: const EdgeInsets.only(bottom: 6),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  side: BorderSide(color: Colors.grey.shade200),
                                ),
                                child: ListTile(
                                  dense: true,
                                  leading: CircleAvatar(
                                    backgroundColor: const Color(0xFF1E3A8A).withValues(alpha: 0.1),
                                    child: Text(
                                      studentName.isNotEmpty ? studentName[0].toUpperCase() : 'S',
                                      style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A)),
                                    ),
                                  ),
                                  title: Text(studentName, style: const TextStyle(fontWeight: FontWeight.w600)),
                                  subtitle: Text(studentEmail, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.person_remove_rounded, color: Colors.red, size: 20),
                                    tooltip: 'Remove student (রিমুভ করুন)',
                                    onPressed: () async {
                                      final confirm = await showDialog<bool>(
                                        context: sheetCtx,
                                        builder: (c) => AlertDialog(
                                          title: const Text('Remove Student'),
                                          content: Text('Are you sure you want to remove "$studentName" from section "$groupName"?\n\nThey will immediately lose access to this section.'),
                                          actions: [
                                            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                                            ElevatedButton(
                                              onPressed: () => Navigator.pop(c, true),
                                              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                                              child: const Text('Remove'),
                                            ),
                                          ],
                                        ),
                                      );

                                      if (confirm == true) {
                                        try {
                                          await ref.read(groupsServiceProvider).removeMember(memberId);
                                          setSheetState(() {});
                                          _loadData();
                                          if (sheetCtx.mounted) {
                                            ScaffoldMessenger.of(sheetCtx).showSnackBar(
                                              SnackBar(content: Text('Removed "$studentName" from $groupName.')),
                                            );
                                          }
                                        } catch (e) {
                                          if (sheetCtx.mounted) {
                                            ScaffoldMessenger.of(sheetCtx).showSnackBar(SnackBar(content: Text('Failed: $e')));
                                          }
                                        }
                                      }
                                    },
                                  ),
                                ),
                              );
                            }),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
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

  Future<void> _confirmDeleteClass(String classId, String className) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Class / Batch?'),
        content: Text(
          'Are you sure you want to delete "$className"?\n\nAll groups, sections, weekly routines, and scheduled exams belonging to this batch will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ref.read(groupsServiceProvider).deleteClass(classId);
        _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Class "$className" deleted successfully.'),
              backgroundColor: const Color(0xFFDC2626),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete class: $e')),
          );
        }
      }
    }
  }

  Future<void> _confirmDeleteGroup(String groupId, String groupName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Section / Group?'),
        content: Text(
          'Are you sure you want to delete section "$groupName"? All members and routine for this section will be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete Section'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ref.read(groupsServiceProvider).deleteGroup(groupId);
        _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Section "$groupName" deleted.'),
              backgroundColor: const Color(0xFFDC2626),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete section: $e')),
          );
        }
      }
    }
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
    if (_selectedGroupIds.isEmpty && _selectedStudentIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one group or individual student to target.')),
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
        targetUserIds: _selectedStudentIds.toList(),
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
          _selectedStudentIds.clear();
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
            Tab(icon: Icon(Icons.calendar_month_rounded), text: 'Routine & Exams'),
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
                _buildRoutineAndExamsTab(),
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
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 22),
                              tooltip: 'Delete Class / Batch',
                              onPressed: () => _confirmDeleteClass(classId, className),
                            ),
                            PopupMenuButton<String>(
                              onSelected: (val) {
                                if (val == 'add_group') _showAddGroupDialog(classId, className);
                                if (val == 'add_co_cr') _showAddCoCrDialog(classId);
                                if (val == 'delete_class') _confirmDeleteClass(classId, className);
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
                                const PopupMenuItem(
                                  value: 'delete_class',
                                  child: Row(
                                    children: [
                                      Icon(Icons.delete_forever_rounded, color: Colors.red, size: 18),
                                      SizedBox(width: 8),
                                      Text('Delete Class (ক্লাস মুছুন)', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
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
                              final gId = g['id'] as String;
                              final gName = g['name'] ?? '';
                              final code = g['invite_code'] ?? '';
                              final isLocked = g['is_join_locked'] == true;

                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: isLocked ? const Color(0xFFFEF2F2) : const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: isLocked ? const Color(0xFFFECACA) : const Color(0xFFBFDBFE)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
                                      size: 16,
                                      color: isLocked ? Colors.red.shade700 : const Color(0xFF1E3A8A),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '$gName ($code)',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: isLocked ? Colors.red.shade900 : const Color(0xFF1E3A8A),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // Lock / Unlock toggle button
                                    InkWell(
                                      onTap: () async {
                                        final messenger = ScaffoldMessenger.of(context);
                                        try {
                                          await ref.read(groupsServiceProvider).toggleGroupJoinLock(
                                            groupId: gId,
                                            isLocked: !isLocked,
                                          );
                                          _loadData();
                                          if (mounted) {
                                            messenger.showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  !isLocked
                                                      ? 'Section "$gName" is now LOCKED (শুধু CR এড করতে পারবে)'
                                                      : 'Section "$gName" is now OPEN for joining with code',
                                                ),
                                                backgroundColor: !isLocked ? Colors.red.shade800 : Colors.green.shade800,
                                              ),
                                            );
                                          }
                                        } catch (e) {
                                          if (mounted) {
                                            messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
                                          }
                                        }
                                      },
                                      child: Tooltip(
                                        message: isLocked ? 'Locked: Click to open joining' : 'Open: Click to lock joining',
                                        child: Icon(
                                          isLocked ? Icons.lock : Icons.lock_open,
                                          size: 16,
                                          color: isLocked ? Colors.red : Colors.grey.shade600,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // View Members Roster button
                                    InkWell(
                                      onTap: () => _showGroupMembersDialog(classId, className, gId, gName, isLocked),
                                      child: const Tooltip(
                                        message: 'View & Manage Students (ছাত্র তালিকা)',
                                        child: Icon(Icons.people_alt_outlined, size: 16, color: Color(0xFF1E3A8A)),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // Copy invite code button
                                    InkWell(
                                      onTap: () {
                                        Clipboard.setData(ClipboardData(text: code));
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('Copied invite code: $code')),
                                        );
                                      },
                                      child: const Tooltip(
                                        message: 'Copy invite code',
                                        child: Icon(Icons.copy_rounded, size: 16, color: Color(0xFF0284C7)),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // Delete section button
                                    InkWell(
                                      onTap: () => _confirmDeleteGroup(gId, gName),
                                      child: const Tooltip(
                                        message: 'Delete section',
                                        child: Icon(Icons.close_rounded, size: 16, color: Colors.red),
                                      ),
                                    ),
                                  ],
                                ),
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
                    'Target Audience (নোটিশ প্রাপক নির্ধারণ)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Select whether this notice goes to whole groups, specific students by name, or both:',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'GROUPS', label: Text('Groups / Sections')),
                      ButtonSegment(value: 'STUDENTS', label: Text('Specific Students (নির্দিষ্ট ছাত্র-ছাত্রী)')),
                      ButtonSegment(value: 'BOTH', label: Text('Both')),
                    ],
                    selected: {_targetMode},
                    onSelectionChanged: (val) {
                      setState(() => _targetMode = val.first);
                    },
                  ),
                  const SizedBox(height: 16),
                  if (_targetMode == 'GROUPS' || _targetMode == 'BOTH') ...[
                    Row(
                      children: [
                        const Text(
                          'Target Groups (Multi-Select):',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E3A8A)),
                        ),
                        const Spacer(),
                        if (groups.isNotEmpty) ...[
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _selectedGroupIds.addAll(groups.map((g) => g['id'] as String));
                              });
                            },
                            child: const Text('All'),
                          ),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _selectedGroupIds.clear();
                              });
                            },
                            child: const Text('Clear'),
                          ),
                          Text(
                            '(${_selectedGroupIds.length}/${groups.length})',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
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
                                'Please create at least one section in the "Classes & Groups" tab first.',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: groups.map((g) {
                          final gId = g['id'] as String;
                          final gName = g['name'] ?? '';
                          final className = g['class_name'] ?? '';
                          final isSelected = _selectedGroupIds.contains(gId);
                          return FilterChip(
                            selected: isSelected,
                            label: Text('$className - $gName'),
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
                    const SizedBox(height: 12),
                  ],
                  if (_targetMode == 'STUDENTS' || _targetMode == 'BOTH') ...[
                    Row(
                      children: [
                        const Text(
                          'Assign to Specific Students (নাম অনুযায়ী নির্ধারণ):',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E3A8A)),
                        ),
                        const Spacer(),
                        if (_allStudents.isNotEmpty) ...[
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _selectedStudentIds.addAll(_allStudents.map((s) => s['id'] as String));
                              });
                            },
                            child: const Text('All'),
                          ),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _selectedStudentIds.clear();
                              });
                            },
                            child: const Text('Clear'),
                          ),
                          Text(
                            '(${_selectedStudentIds.length}/${_allStudents.length})',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (_allStudents.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline, color: Color(0xFF1E3A8A)),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'No enrolled students found in your managed sections yet. Once students join with invite codes, their names will appear here.',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _allStudents.map((s) {
                          final sId = s['id'] as String;
                          final sName = s['full_name'] ?? 'Student';
                          final isSelected = _selectedStudentIds.contains(sId);
                          final groupsStr = (s['groups'] as List<String>?)?.join(', ') ?? '';

                          return FilterChip(
                            selected: isSelected,
                            avatar: CircleAvatar(
                              backgroundColor: isSelected ? const Color(0xFF1E3A8A) : Colors.grey.shade300,
                              child: Text(
                                sName.isNotEmpty ? sName[0].toUpperCase() : 'S',
                                style: TextStyle(
                                  color: isSelected ? Colors.white : Colors.black87,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            label: Text('$sName ($groupsStr)'),
                            selectedColor: const Color(0xFF1E3A8A).withValues(alpha: 0.2),
                            checkmarkColor: const Color(0xFF1E3A8A),
                            onSelected: (selected) {
                              setState(() {
                                if (selected) {
                                  _selectedStudentIds.add(sId);
                                } else {
                                  _selectedStudentIds.remove(sId);
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

  // Tab 3: Routine & Exams Management
  Widget _buildRoutineAndExamsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            color: const Color(0xFFEFF6FF),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.calendar_month_rounded, color: Color(0xFF1E3A8A)),
                      SizedBox(width: 8),
                      Text(
                        'Academic Schedule Manager',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E3A8A)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Create class routines and exam schedules. Routine notifications automatically alert group students (1 day, 12h, 6h, 3h, 1h, 30m, 10m, and on time). Exams automatically vanish 3 hours after finishing.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF334155)),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _showAddRoutineDialog,
                          icon: const Icon(Icons.add_task_rounded, size: 18),
                          label: const Text('Add Routine'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1E3A8A),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _showAddExamDialog,
                          icon: const Icon(Icons.assignment_add, size: 18),
                          label: const Text('Schedule Exam'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.purple.shade700,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Section 1: Weekly Class Routine
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Weekly Class Routine',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
              ),
              Text(
                '${_routines.length} Classes',
                style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_routines.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.event_note_outlined, size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 8),
                      const Text('No class routine entries added yet.', style: TextStyle(color: Colors.grey)),
                      TextButton.icon(
                        onPressed: _showAddRoutineDialog,
                        icon: const Icon(Icons.add),
                        label: const Text('Add First Class'),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            ..._routines.map((routine) => _buildRoutineItemCard(routine)),

          const SizedBox(height: 24),

          // Section 2: Active Exams & Quizzes
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Upcoming Exams & Quizzes',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('Auto-cleans +3h', style: TextStyle(fontSize: 11, color: Colors.brown, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_exams.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.assignment_turned_in_outlined, size: 48, color: Colors.green.shade300),
                      const SizedBox(height: 8),
                      const Text('No upcoming exams scheduled.', style: TextStyle(color: Colors.grey)),
                      TextButton.icon(
                        onPressed: _showAddExamDialog,
                        icon: const Icon(Icons.add),
                        label: const Text('Schedule Exam / Quiz'),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            ..._exams.map((exam) => _buildExamItemCard(exam)),
        ],
      ),
    );
  }

  Widget _buildRoutineItemCard(Map<String, dynamic> item) {
    final fullDays = ['', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final dayNum = item['day_of_week'] as int? ?? 1;
    final dayName = (dayNum >= 1 && dayNum <= 7) ? fullDays[dayNum] : '';
    final subject = item['subject'] ?? '';
    final teacher = item['teacher_name'] as String?;
    final startTime = item['start_time'].toString().substring(0, 5);
    final endTime = item['end_time'].toString().substring(0, 5);
    final isOnline = item['is_online'] == true;
    final room = item['room_number'] as String?;
    final link = item['meeting_link'] as String?;
    final group = item['class_groups']?['name'] ?? 'Section';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E3A8A),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    dayName,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isOnline ? Colors.green.shade100 : Colors.blue.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isOnline ? '🌐 Online' : '🏫 Room: ${room ?? "TBA"}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isOnline ? Colors.green.shade900 : Colors.blue.shade900,
                    ),
                  ),
                ),
                const Spacer(),
                Text('Section $group', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              subject,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0F172A)),
            ),
            if (teacher != null && teacher.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text('Teacher: $teacher', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
            ],
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.access_time_rounded, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text('$startTime - $endTime', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                if (isOnline && link != null && link.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  const Icon(Icons.link_rounded, size: 14, color: Color(0xFF16A34A)),
                  const SizedBox(width: 4),
                  const Text('Meeting Link Attached', style: TextStyle(fontSize: 12, color: Color(0xFF16A34A), fontWeight: FontWeight.bold)),
                ],
              ],
            ),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _showSendRoutineReminderDialog(item),
                  icon: const Icon(Icons.notifications_active_rounded, size: 16),
                  label: const Text('Send Interval Alert'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                  tooltip: 'Delete Class',
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Delete Routine?'),
                        content: Text('Are you sure you want to delete $subject from weekly routine?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await ref.read(routineServiceProvider).deleteRoutine(item['id']);
                      _loadData();
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExamItemCard(Map<String, dynamic> exam) {
    final subject = exam['subject'] ?? '';
    final type = exam['exam_type'] ?? 'EXAM';
    final date = exam['exam_date'] ?? '';
    final startTime = exam['start_time'].toString().substring(0, 5);
    final endTime = exam['end_time'].toString().substring(0, 5);
    final isOnline = exam['is_online'] == true;
    final room = exam['room_number'] as String?;
    final link = exam['meeting_link'] as String?;
    final group = exam['class_groups']?['name'] ?? 'Section';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFC084FC), width: 1.2),
      ),
      color: const Color(0xFFFAF5FF),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.purple.shade700,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$type EXAM',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ),
                const SizedBox(width: 8),
                Text('Date: $date', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF581C87))),
                const Spacer(),
                Text('Section $group', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              subject,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF3B0764)),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.access_time_rounded, size: 14, color: Color(0xFF6B21A8)),
                const SizedBox(width: 4),
                Text('$startTime - $endTime', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF6B21A8))),
                const SizedBox(width: 12),
                Icon(isOnline ? Icons.videocam_rounded : Icons.meeting_room_rounded, size: 14, color: const Color(0xFF6B21A8)),
                const SizedBox(width: 4),
                Text(isOnline ? 'Online' : 'Room: ${room ?? "TBA"}', style: const TextStyle(fontSize: 12, color: Color(0xFF6B21A8))),
              ],
            ),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ElevatedButton.icon(
                  onPressed: () async {
                    await ref.read(routineServiceProvider).sendRoutineReminder(
                      groupId: exam['group_id'],
                      subject: '$type Exam: $subject',
                      intervalLabel: 'Upcoming Exam',
                      startTime: '$date at $startTime',
                      isOnline: isOnline,
                      roomNumber: room,
                      meetingLink: link,
                    );
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Exam alert sent to Section $group!'), backgroundColor: Colors.purple.shade700),
                      );
                    }
                  },
                  icon: const Icon(Icons.campaign_rounded, size: 16),
                  label: const Text('Send Exam Alert'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                  tooltip: 'Delete Exam',
                  onPressed: () async {
                    await ref.read(routineServiceProvider).deleteExam(exam['id']);
                    _loadData();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSendRoutineReminderDialog(Map<String, dynamic> routine) async {
    final subject = routine['subject'] ?? 'Class';
    final startTime = routine['start_time'].toString().substring(0, 5);
    final groupId = routine['group_id'] as String;
    final isOnline = routine['is_online'] == true;
    final roomNumber = routine['room_number'] as String?;
    final meetingLink = routine['meeting_link'] as String?;
    final groupName = routine['class_groups']?['name'] ?? '';

    final intervals = [
      {'label': '1 Day Before', 'bengali': '১ দিন আগে নোটিফিকেশন', 'icon': Icons.calendar_today_rounded},
      {'label': '12 Hours Before', 'bengali': '১২ ঘণ্টা আগে নোটিফিকেশন', 'icon': Icons.access_time_rounded},
      {'label': '6 Hours Before', 'bengali': '৬ ঘণ্টা আগে নোটিফিকেশন', 'icon': Icons.schedule_rounded},
      {'label': '3 Hours Before', 'bengali': '৩ ঘণ্টা আগে নোটিফিকেশন', 'icon': Icons.alarm_rounded},
      {'label': '1 Hour Before', 'bengali': '১ ঘণ্টা আগে নোটিফিকেশন', 'icon': Icons.hourglass_top_rounded},
      {'label': '30 Min Before', 'bengali': '৩০ মিনিট আগে নোটিফিকেশন', 'icon': Icons.timer_rounded},
      {'label': '10 Min Before', 'bengali': '১০ মিনিট আগে নোটিফিকেশন (Get Ready!)', 'icon': Icons.notification_important_rounded},
      {'label': 'Starting Now!', 'bengali': 'এখনই ক্লাস শুরু! (On Time)', 'icon': Icons.play_circle_fill_rounded},
    ];

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.notifications_active_rounded, color: Color(0xFF1E3A8A)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Send Class Alert: $subject',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        Text(
                          'Target: Section $groupName • Starts at $startTime',
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              const Text(
                'Select Countdown Notification Interval:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 10),
              ...intervals.map((item) {
                final label = item['label'] as String;
                final bengali = item['bengali'] as String;
                final icon = item['icon'] as IconData;
                final isUrgent = label.contains('10 Min') || label.contains('Starting Now');

                return ListTile(
                  dense: true,
                  leading: Icon(icon, color: isUrgent ? const Color(0xFFDC2626) : const Color(0xFF1E3A8A)),
                  title: Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: isUrgent ? const Color(0xFFDC2626) : null)),
                  subtitle: Text(bengali, style: const TextStyle(fontSize: 11)),
                  trailing: const Icon(Icons.send_rounded, size: 16),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await ref.read(routineServiceProvider).sendRoutineReminder(
                      groupId: groupId,
                      subject: subject,
                      intervalLabel: label,
                      startTime: startTime,
                      isOnline: isOnline,
                      roomNumber: roomNumber,
                      meetingLink: meetingLink,
                    );
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('[$label] notification dispatched to Section $groupName!'),
                          backgroundColor: const Color(0xFF1E3A8A),
                        ),
                      );
                    }
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAddRoutineDialog() async {
    if (_allGroups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please create a class and group first before adding routine.')),
      );
      return;
    }

    final Set<String> selectedGroupIds = {_allGroups.first['id']};
    final subjectCtrl = TextEditingController();
    final teacherCtrl = TextEditingController();
    final roomCtrl = TextEditingController(text: 'Room 402');
    final linkCtrl = TextEditingController(text: 'https://meet.google.com/');
    int selectedDay = 7; // Sunday by default
    TimeOfDay startTime = const TimeOfDay(hour: 10, minute: 0);
    TimeOfDay endTime = const TimeOfDay(hour: 11, minute: 30);
    bool isOnline = false;
    bool sendInitialAlert = true;

    final days = [
      {'val': 7, 'label': 'Sunday (রবিবার)'},
      {'val': 1, 'label': 'Monday (সোমবার)'},
      {'val': 2, 'label': 'Tuesday (মঙ্গলবার)'},
      {'val': 3, 'label': 'Wednesday (বুধবার)'},
      {'val': 4, 'label': 'Thursday (বৃহস্পতিবার)'},
      {'val': 5, 'label': 'Friday (শুক্রবার)'},
      {'val': 6, 'label': 'Saturday (শনিবার)'},
    ];

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            title: const Text('Add Class Routine'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Target Sections * (একাধিক সিলেক্ট করুন):',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E3A8A)),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => setModalState(() {
                          selectedGroupIds.addAll(_allGroups.map((g) => g['id'] as String));
                        }),
                        child: const Text('All', style: TextStyle(fontSize: 12)),
                      ),
                      TextButton(
                        onPressed: () => setModalState(() => selectedGroupIds.clear()),
                        child: const Text('Clear', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _allGroups.map((g) {
                      final gId = g['id'] as String;
                      final isSelected = selectedGroupIds.contains(gId);
                      return FilterChip(
                        selected: isSelected,
                        label: Text('${g['class_name']} - ${g['name']}'),
                        selectedColor: const Color(0xFF1E3A8A).withValues(alpha: 0.2),
                        checkmarkColor: const Color(0xFF1E3A8A),
                        onSelected: (val) {
                          setModalState(() {
                            if (val) {
                              selectedGroupIds.add(gId);
                            } else {
                              selectedGroupIds.remove(gId);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: subjectCtrl,
                    decoration: const InputDecoration(labelText: 'Subject Name *', hintText: 'e.g. Data Structures'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: teacherCtrl,
                    decoration: const InputDecoration(labelText: 'Teacher Name (Optional)', hintText: 'e.g. Dr. Sanaullah'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: selectedDay,
                    decoration: const InputDecoration(labelText: 'Day of Week *'),
                    items: days.map((d) {
                      return DropdownMenuItem<int>(
                        value: d['val'] as int,
                        child: Text(d['label'] as String),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setModalState(() => selectedDay = val);
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final picked = await showTimePicker(context: context, initialTime: startTime);
                            if (picked != null) setModalState(() => startTime = picked);
                          },
                          child: Text('Start: ${startTime.format(context)}'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final picked = await showTimePicker(context: context, initialTime: endTime);
                            if (picked != null) setModalState(() => endTime = picked);
                          },
                          child: Text('End: ${endTime.format(context)}'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Online Class (Zoom / Google Meet)'),
                    value: isOnline,
                    onChanged: (val) => setModalState(() => isOnline = val),
                  ),
                  if (isOnline)
                    TextField(
                      controller: linkCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Meeting Link *',
                        hintText: 'https://meet.google.com/xyz',
                        prefixIcon: Icon(Icons.link),
                      ),
                    )
                  else
                    TextField(
                      controller: roomCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Room Number *',
                        hintText: 'e.g. Room 402, Lab 3',
                        prefixIcon: Icon(Icons.room),
                      ),
                    ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Send notification to group now', style: TextStyle(fontSize: 13)),
                    value: sendInitialAlert,
                    onChanged: (v) => setModalState(() => sendInitialAlert = v ?? true),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () async {
                  if (subjectCtrl.text.trim().isEmpty) return;
                  if (selectedGroupIds.isEmpty) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('Please select at least one section for this class routine.')),
                    );
                    return;
                  }
                  final firstMatched = _allGroups.firstWhere((g) => selectedGroupIds.contains(g['id']));
                  final classId = firstMatched['class_id'] as String;
                  final startStr = '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}:00';
                  final endStr = '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}:00';

                  try {
                    await ref.read(routineServiceProvider).saveRoutine(
                      classId: classId,
                      groupIds: selectedGroupIds.toList(),
                      subject: subjectCtrl.text.trim(),
                      teacherName: teacherCtrl.text.trim().isEmpty ? null : teacherCtrl.text.trim(),
                      dayOfWeek: selectedDay,
                      startTime: startStr,
                      endTime: endStr,
                      isOnline: isOnline,
                      roomNumber: isOnline ? null : roomCtrl.text.trim(),
                      meetingLink: isOnline ? linkCtrl.text.trim() : null,
                      dispatchInitialAlert: sendInitialAlert,
                    );
                    if (ctx.mounted) Navigator.pop(ctx);
                    _loadData();
                  } catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Failed: $e')));
                    }
                  }
                },
                child: const Text('Save Routine'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showAddExamDialog() async {
    if (_allGroups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please create a class and group first before scheduling exams.')),
      );
      return;
    }

    final Set<String> selectedGroupIds = {_allGroups.first['id']};
    final subjectCtrl = TextEditingController();
    final roomCtrl = TextEditingController(text: 'Room 501');
    final linkCtrl = TextEditingController(text: 'https://meet.google.com/');
    String examType = 'MID';
    DateTime examDate = DateTime.now().add(const Duration(days: 3));
    TimeOfDay startTime = const TimeOfDay(hour: 10, minute: 0);
    TimeOfDay endTime = const TimeOfDay(hour: 12, minute: 0);
    bool isOnline = false;
    bool sendAlert = true;

    final examTypes = [
      {'val': 'CT', 'label': 'Class Test (CT)'},
      {'val': 'MID', 'label': 'Midterm Exam'},
      {'val': 'FINAL', 'label': 'Final Exam'},
      {'val': 'QUIZ', 'label': 'Quiz'},
    ];

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            title: const Text('Schedule Exam / Quiz'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Target Sections * (একাধিক সিলেক্ট করুন):',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E3A8A)),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => setModalState(() {
                          selectedGroupIds.addAll(_allGroups.map((g) => g['id'] as String));
                        }),
                        child: const Text('All', style: TextStyle(fontSize: 12)),
                      ),
                      TextButton(
                        onPressed: () => setModalState(() => selectedGroupIds.clear()),
                        child: const Text('Clear', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _allGroups.map((g) {
                      final gId = g['id'] as String;
                      final isSelected = selectedGroupIds.contains(gId);
                      return FilterChip(
                        selected: isSelected,
                        label: Text('${g['class_name']} - ${g['name']}'),
                        selectedColor: const Color(0xFF1E3A8A).withValues(alpha: 0.2),
                        checkmarkColor: const Color(0xFF1E3A8A),
                        onSelected: (val) {
                          setModalState(() {
                            if (val) {
                              selectedGroupIds.add(gId);
                            } else {
                              selectedGroupIds.remove(gId);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: subjectCtrl,
                    decoration: const InputDecoration(labelText: 'Subject Name *', hintText: 'e.g. Operating Systems'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: examType,
                    decoration: const InputDecoration(labelText: 'Exam Type *'),
                    items: examTypes.map((t) {
                      return DropdownMenuItem<String>(
                        value: t['val'] as String,
                        child: Text(t['label'] as String),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setModalState(() => examType = val);
                    },
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: examDate,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 180)),
                      );
                      if (picked != null) setModalState(() => examDate = picked);
                    },
                    icon: const Icon(Icons.calendar_today_rounded, size: 16),
                    label: Text('Date: ${examDate.day}/${examDate.month}/${examDate.year}'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final picked = await showTimePicker(context: context, initialTime: startTime);
                            if (picked != null) setModalState(() => startTime = picked);
                          },
                          child: Text('Start: ${startTime.format(context)}'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final picked = await showTimePicker(context: context, initialTime: endTime);
                            if (picked != null) setModalState(() => endTime = picked);
                          },
                          child: Text('End: ${endTime.format(context)}'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Online Exam'),
                    value: isOnline,
                    onChanged: (val) => setModalState(() => isOnline = val),
                  ),
                  if (isOnline)
                    TextField(
                      controller: linkCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Exam Meeting Link *',
                        prefixIcon: Icon(Icons.link),
                      ),
                    )
                  else
                    TextField(
                      controller: roomCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Exam Room Number *',
                        prefixIcon: Icon(Icons.room),
                      ),
                    ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.auto_delete_outlined, size: 18, color: Colors.brown),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Exams automatically clean up from all students 3 hours after end time.',
                            style: TextStyle(fontSize: 11, color: Colors.brown, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Broadcast notification to group students', style: TextStyle(fontSize: 13)),
                    value: sendAlert,
                    onChanged: (v) => setModalState(() => sendAlert = v ?? true),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () async {
                  if (subjectCtrl.text.trim().isEmpty) return;
                  if (selectedGroupIds.isEmpty) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('Please select at least one section for this exam.')),
                    );
                    return;
                  }
                  final firstMatched = _allGroups.firstWhere((g) => selectedGroupIds.contains(g['id']));
                  final classId = firstMatched['class_id'] as String;
                  final startStr = '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}:00';
                  final endStr = '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}:00';

                  try {
                    await ref.read(routineServiceProvider).saveExam(
                      classId: classId,
                      groupIds: selectedGroupIds.toList(),
                      subject: subjectCtrl.text.trim(),
                      examType: examType,
                      examDate: examDate,
                      startTime: startStr,
                      endTime: endStr,
                      isOnline: isOnline,
                      roomNumber: isOnline ? null : roomCtrl.text.trim(),
                      meetingLink: isOnline ? linkCtrl.text.trim() : null,
                      dispatchAlert: sendAlert,
                    );
                    if (ctx.mounted) Navigator.pop(ctx);
                    _loadData();
                  } catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Failed: $e')));
                    }
                  }
                },
                child: const Text('Save Exam Schedule'),
              ),
            ],
          );
        },
      ),
    );
  }
}

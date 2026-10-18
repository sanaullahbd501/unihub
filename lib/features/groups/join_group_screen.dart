import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'groups_service.dart';

class JoinGroupScreen extends ConsumerStatefulWidget {
  const JoinGroupScreen({super.key});

  @override
  ConsumerState<JoinGroupScreen> createState() => _JoinGroupScreenState();
}

class _JoinGroupScreenState extends ConsumerState<JoinGroupScreen> {
  final _codeController = TextEditingController();
  bool _isJoining = false;
  bool _isLoading = true;
  List<Map<String, dynamic>> _myGroups = [];

  @override
  void initState() {
    super.initState();
    _loadMyGroups();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _loadMyGroups() async {
    setState(() => _isLoading = true);
    try {
      final groups = await ref.read(groupsServiceProvider).getMyEnrolledGroups();
      if (mounted) {
        setState(() {
          _myGroups = groups;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleJoin() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an invite code (e.g. 95B)')),
      );
      return;
    }

    setState(() => _isJoining = true);
    try {
      final result = await ref.read(groupsServiceProvider).joinGroupByCode(code);
      final already = result['already_joined'] == true;
      final group = result['group'] as Map<String, dynamic>?;
      final groupName = group?['name'] ?? code;

      if (mounted) {
        setState(() {
          _isJoining = false;
          _codeController.clear();
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF1E3A8A),
            content: Text(
              already
                  ? 'You are already a member of $groupName!'
                  : 'Successfully joined $groupName! You will now receive all notices for this group.',
            ),
          ),
        );

        _loadMyGroups();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isJoining = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Join Class / Group'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: Color(0xFFEFF6FF),
                          child: Icon(Icons.vpn_key_rounded, color: Color(0xFF1E3A8A)),
                        ),
                        SizedBox(width: 12),
                        Text(
                          'Enter Invite Code',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Ask your Class Representative (CR) for your section code (e.g. 95B or 95C) or paste the invite link:',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _codeController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Invite Code *',
                        hintText: 'e.g. 95B',
                        prefixIcon: Icon(Icons.tag_rounded),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _isJoining ? null : _handleJoin,
                      icon: _isJoining
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.login_rounded),
                      label: Text(_isJoining ? 'Joining...' : 'Join Class Group'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: const Color(0xFF1E3A8A),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'My Enrolled Groups',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_myGroups.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(Icons.group_outlined, size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 8),
                      const Text(
                        'Not enrolled in any group yet',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Enter a code above to join your batch or section.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _myGroups.length,
                itemBuilder: (context, idx) {
                  final item = _myGroups[idx];
                  final group = item['class_groups'] as Map<String, dynamic>?;
                  final groupName = group?['name'] ?? 'Group';
                  final code = group?['invite_code'] ?? '';
                  final cls = group?['classes'] as Map<String, dynamic>?;
                  final className = cls?['name'] ?? 'Class';

                  return Card(
                    child: ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFFEFF6FF),
                        child: Icon(Icons.check_circle_rounded, color: Colors.green),
                      ),
                      title: Text(
                        groupName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      subtitle: Text('$className • Code: $code'),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Enrolled',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green),
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

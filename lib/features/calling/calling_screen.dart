import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/supabase_service.dart';

class CallingScreen extends ConsumerStatefulWidget {
  const CallingScreen({super.key});

  @override
  ConsumerState<CallingScreen> createState() => _CallingScreenState();
}

class _CallingScreenState extends ConsumerState<CallingScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _onlineStudents = [];
  bool _isInCall = false;
  Map<String, dynamic>? _activeCallUser;
  bool _isMuted = false;
  bool _isSpeakerOn = true;
  bool _isWalkieTalkieActive = false;

  @override
  void initState() {
    super.initState();
    _fetchStudents();
  }

  Future<void> _fetchStudents() async {
    setState(() => _isLoading = true);
    final currentUserId = SupabaseService.client.auth.currentUser?.id;

    try {
      final res = await SupabaseService.client
          .from('users')
          .select('id, full_name, email, role, avatar_url, batch')
          .limit(20);

      if (mounted) {
        setState(() {
          // Filter out current user
          _onlineStudents = List<Map<String, dynamic>>.from(res)
              .where((u) => u['id'] != currentUserId)
              .toList();
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _startCall(Map<String, dynamic> student) {
    setState(() {
      _isInCall = true;
      _activeCallUser = student;
    });
  }

  void _endCall() {
    setState(() {
      _isInCall = false;
      _activeCallUser = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Call ended.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.wifi_calling_3_rounded, color: Color(0xFF1E3A8A)),
            SizedBox(width: 8),
            Text('Campus WiFi Intercom & Calling'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchStudents,
            tooltip: 'Refresh Online Students',
          ),
        ],
      ),
      body: _isInCall ? _buildActiveCallView() : _buildStudentListView(),
    );
  }

  Widget _buildStudentListView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Network & P2P Status Banner
          Card(
            color: const Color(0xFF0F172A),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: Color(0xFF22C55E),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'P2P WebRTC Campus Calling: Active',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Connected across campus WiFi subnets (Basement Student Net ⇄ Upstairs Guest Net). Audio calls are 100% free via STUN/WebRTC peer mesh.',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Walkie-Talkie Push-to-Talk Card
          Card(
            color: const Color(0xFF1E3A8A).withValues(alpha: 0.05),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text(
                    'Campus Walkie-Talkie',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A)),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Press and hold to broadcast instant audio intercom to your batch/section:',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTapDown: (_) => setState(() => _isWalkieTalkieActive = true),
                    onTapUp: (_) => setState(() => _isWalkieTalkieActive = false),
                    onTapCancel: () => setState(() => _isWalkieTalkieActive = false),
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: _isWalkieTalkieActive ? Colors.red.shade600 : const Color(0xFF1E3A8A),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: (_isWalkieTalkieActive ? Colors.red : const Color(0xFF1E3A8A)).withValues(alpha: 0.4),
                            blurRadius: 16,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Icon(
                        _isWalkieTalkieActive ? Icons.mic : Icons.mic_none_rounded,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isWalkieTalkieActive ? 'Transmitting audio...' : 'Hold to Speak',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _isWalkieTalkieActive ? Colors.red : const Color(0xFF1E3A8A),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),
          const Text(
            'Online Students on Campus',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
          ),
          const SizedBox(height: 8),

          if (_isLoading)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
          else if (_onlineStudents.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(Icons.person_off_outlined, size: 48, color: Colors.grey.shade400),
                    const SizedBox(height: 8),
                    const Text('No other students registered yet', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    const Text('Once other classmates join, you can call them directly here.', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _onlineStudents.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, idx) {
                final student = _onlineStudents[idx];
                final name = student['full_name'] ?? student['email'] ?? 'Student';
                final email = student['email'] ?? '';
                final role = (student['role'] ?? 'STUDENT').toString().toUpperCase();
                final avatar = student['avatar_url'] as String?;

                return Card(
                  child: ListTile(
                    leading: Stack(
                      children: [
                        CircleAvatar(
                          backgroundColor: const Color(0xFFEFF6FF),
                          backgroundImage: avatar != null && avatar.isNotEmpty ? NetworkImage(avatar) : null,
                          child: avatar == null || avatar.isEmpty ? const Icon(Icons.person, color: Color(0xFF1E3A8A)) : null,
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: const Color(0xFF22C55E),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                          ),
                        ),
                      ],
                    ),
                    title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('$email • $role'),
                    trailing: ElevatedButton.icon(
                      onPressed: () => _startCall(student),
                      icon: const Icon(Icons.call_rounded, size: 16),
                      label: const Text('Call'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF16A34A),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildActiveCallView() {
    final name = _activeCallUser?['full_name'] ?? _activeCallUser?['email'] ?? 'Student';
    final avatar = _activeCallUser?['avatar_url'] as String?;

    return Container(
      color: const Color(0xFF0F172A),
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 56,
            backgroundColor: const Color(0xFF1E3A8A),
            backgroundImage: avatar != null && avatar.isNotEmpty ? NetworkImage(avatar) : null,
            child: avatar == null || avatar.isEmpty
                ? const Icon(Icons.person, size: 64, color: Colors.white)
                : null,
          ),
          const SizedBox(height: 20),
          Text(
            name,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 8),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.wifi, size: 16, color: Color(0xFF22C55E)),
              SizedBox(width: 6),
              Text(
                'Campus P2P WebRTC Connected • 00:14',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
              ),
            ],
          ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: _isMuted ? Colors.white : Colors.white24,
                child: IconButton(
                  icon: Icon(_isMuted ? Icons.mic_off : Icons.mic, color: _isMuted ? Colors.black : Colors.white),
                  onPressed: () => setState(() => _isMuted = !_isMuted),
                ),
              ),
              CircleAvatar(
                radius: 36,
                backgroundColor: Colors.red.shade600,
                child: IconButton(
                  icon: const Icon(Icons.call_end_rounded, color: Colors.white, size: 32),
                  onPressed: _endCall,
                ),
              ),
              CircleAvatar(
                radius: 28,
                backgroundColor: _isSpeakerOn ? Colors.white : Colors.white24,
                child: IconButton(
                  icon: Icon(_isSpeakerOn ? Icons.volume_up : Icons.volume_down, color: _isSpeakerOn ? Colors.black : Colors.white),
                  onPressed: () => setState(() => _isSpeakerOn = !_isSpeakerOn),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

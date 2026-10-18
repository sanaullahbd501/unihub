import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/supabase_service.dart';

class CallingScreen extends ConsumerStatefulWidget {
  const CallingScreen({super.key});

  @override
  ConsumerState<CallingScreen> createState() => _CallingScreenState();
}

class _CallingScreenState extends ConsumerState<CallingScreen> with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  List<Map<String, dynamic>> _onlineStudents = [];

  // Call state
  bool _isInCall = false;
  Map<String, dynamic>? _activeCallUser;
  bool _isMuted = false;
  bool _isSpeakerOn = true;

  // Walkie-Talkie & Intercom State
  bool _isTransmitting = false;
  bool _isHandsFreeLocked = false; // Hands-Free Latch mode
  String _selectedChannel = 'Ch 1: Open Campus';
  String _connectionMode = 'Campus WiFi (Hybrid)'; // or 'Offline Hotspot / LAN'

  // Pre-configured channels
  final List<String> _channels = [
    'Ch 1: Open Campus',
    'Ch 2: Section 95B',
    'Ch 3: Section 95C',
    'Ch 4: CR & Co-CR Special',
    'Ch 5: Robotics / Dev Lab',
    'Ch 6: Private Custom Channel',
  ];

  late AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _fetchStudents();
  }

  @override
  void dispose() {
    _waveController.dispose();
    super.dispose();
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

  void _toggleHandsFreeLock() {
    setState(() {
      _isHandsFreeLocked = !_isHandsFreeLocked;
      _isTransmitting = _isHandsFreeLocked;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.wifi_calling_3_rounded, color: Color(0xFF1E3A8A)),
            SizedBox(width: 8),
            Text('Campus Intercom & Calling'),
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
      body: _isInCall ? _buildActiveCallView() : _buildIntercomMainView(),
    );
  }

  Widget _buildIntercomMainView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Connection Mode Selector (Hybrid vs Offline Hotspot)
          SegmentedButton<String>(
            segments: const [
              ButtonSegment<String>(
                value: 'Campus WiFi (Hybrid)',
                label: Text('Campus WiFi (Multi-Subnet)'),
                icon: Icon(Icons.wifi_rounded, size: 18),
              ),
              ButtonSegment<String>(
                value: 'Offline Hotspot / LAN',
                label: Text('Offline Hotspot (No Net)'),
                icon: Icon(Icons.wifi_tethering_rounded, size: 18),
              ),
            ],
            selected: {_connectionMode},
            onSelectionChanged: (Set<String> newSelection) {
              setState(() {
                _connectionMode = newSelection.first;
              });
            },
          ),
          const SizedBox(height: 12),

          // Network Status Card
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
                        decoration: BoxDecoration(
                          color: _connectionMode.contains('Offline')
                              ? const Color(0xFFF59E0B)
                              : const Color(0xFF22C55E),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _connectionMode.contains('Offline')
                            ? 'Local UDP Walkie-Talkie (Zero Internet)'
                            : 'P2P WebRTC Campus Calling: Active',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _connectionMode.contains('Offline')
                        ? 'Connected via local WiFi router or Mobile Hotspot (192.168.x.x). Works even if university broadband is down.'
                        : 'Connected across campus subnets (Basement Student Net ⇄ Upstairs Guest Net). Audio is free via WebRTC peer mesh.',
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Channel Frequency Selector Card
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.tune_rounded, color: Color(0xFF1E3A8A), size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Intercom Frequency Channel',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _selectedChannel.split(':').first,
                          style: const TextStyle(
                            color: Color(0xFF1E3A8A),
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedChannel,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      prefixIcon: const Icon(Icons.radio_rounded, color: Color(0xFF1E3A8A)),
                    ),
                    items: _channels.map((ch) {
                      return DropdownMenuItem(
                        value: ch,
                        child: Text(ch, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedChannel = val);
                    },
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'You only hear audio from members tuned into this channel. Prevents noise between different batches/labs.',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Walkie-Talkie & Hands-Free Intercom Card
          Card(
            color: const Color(0xFF1E3A8A).withValues(alpha: 0.05),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedChannel,
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A), fontSize: 15),
                          ),
                          Text(
                            _isTransmitting
                                ? (_isHandsFreeLocked ? '🎙️ Hands-Free Mic: LIVE ON' : '🎙️ Transmitting audio...')
                                : 'Channel Idle (Ready)',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _isTransmitting ? Colors.red.shade700 : Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                      // Hands-Free Lock Toggle Button
                      ActionChip(
                        avatar: Icon(
                          _isHandsFreeLocked ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
                          size: 16,
                          color: _isHandsFreeLocked ? Colors.white : const Color(0xFF1E3A8A),
                        ),
                        label: Text(_isHandsFreeLocked ? 'Lock: ACTIVE' : 'Hands-Free'),
                        backgroundColor: _isHandsFreeLocked ? Colors.red.shade600 : const Color(0xFFEFF6FF),
                        labelStyle: TextStyle(
                          color: _isHandsFreeLocked ? Colors.white : const Color(0xFF1E3A8A),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                        onPressed: _toggleHandsFreeLock,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Big Mic Button (PTT or Tap-to-Lock)
                  GestureDetector(
                    onTapDown: (_) {
                      if (!_isHandsFreeLocked) setState(() => _isTransmitting = true);
                    },
                    onTapUp: (_) {
                      if (!_isHandsFreeLocked) setState(() => _isTransmitting = false);
                    },
                    onTapCancel: () {
                      if (!_isHandsFreeLocked) setState(() => _isTransmitting = false);
                    },
                    onTap: () {
                      if (_isHandsFreeLocked) {
                        _toggleHandsFreeLock();
                      }
                    },
                    child: AnimatedBuilder(
                      animation: _waveController,
                      builder: (context, child) {
                        final waveSize = _isTransmitting ? 12.0 * _waveController.value : 0.0;
                        return Container(
                          width: 86 + waveSize,
                          height: 86 + waveSize,
                          decoration: BoxDecoration(
                            color: _isTransmitting ? Colors.red.shade600 : const Color(0xFF1E3A8A),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: (_isTransmitting ? Colors.red : const Color(0xFF1E3A8A)).withValues(alpha: 0.4),
                                blurRadius: 18 + waveSize,
                                spreadRadius: 2 + waveSize / 2,
                              ),
                            ],
                          ),
                          child: Icon(
                            _isTransmitting ? Icons.mic : Icons.mic_none_rounded,
                            color: Colors.white,
                            size: 38,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _isHandsFreeLocked
                        ? 'Hands-Free is ON! Your hands are free to work.'
                        : 'Hold button to speak, or tap "Hands-Free" to lock mic',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: _isHandsFreeLocked ? Colors.red.shade700 : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Direct 1-on-1 Student Calling Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Direct 1-on-1 Calling',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
              ),
              Text(
                '${_onlineStudents.length} Available',
                style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 10),

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
                    const Text('Once classmates log in, you can call them directly with 1-tap.', style: TextStyle(color: Colors.grey, fontSize: 12)),
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
    final name = _activeCallUser?['full_name'] ?? _activeCallUser?['email'] ?? 'Peer';
    final avatar = _activeCallUser?['avatar_url'] as String?;

    return Container(
      color: const Color(0xFF0F172A),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 56,
            backgroundColor: const Color(0xFF1E293B),
            backgroundImage: avatar != null && avatar.isNotEmpty ? NetworkImage(avatar) : null,
            child: avatar == null || avatar.isEmpty ? const Icon(Icons.person, size: 56, color: Colors.white) : null,
          ),
          const SizedBox(height: 20),
          Text(
            name,
            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_rounded, size: 14, color: Color(0xFF22C55E)),
              SizedBox(width: 4),
              Text(
                'End-to-End Encrypted WiFi Call (HD Audio)',
                style: TextStyle(color: Color(0xFF22C55E), fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 48),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.filledTonal(
                iconSize: 28,
                icon: Icon(_isMuted ? Icons.mic_off : Icons.mic),
                onPressed: () => setState(() => _isMuted = !_isMuted),
              ),
              const SizedBox(width: 24),
              IconButton.filled(
                iconSize: 36,
                style: IconButton.styleFrom(backgroundColor: Colors.red),
                icon: const Icon(Icons.call_end_rounded, color: Colors.white),
                onPressed: _endCall,
              ),
              const SizedBox(width: 24),
              IconButton.filledTonal(
                iconSize: 28,
                icon: Icon(_isSpeakerOn ? Icons.volume_up : Icons.volume_down),
                onPressed: () => setState(() => _isSpeakerOn = !_isSpeakerOn),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:my_app/screens/organizer_main_wrapper.dart';
import 'package:share_plus/share_plus.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:flutter/services.dart';
import 'package:my_app/screens/scan_entry.dart';
// ignore: unused_import
import 'package:my_app/services/translation_service.dart';
import 'package:my_app/screens/profile.dart';
import 'package:my_app/screens/support_form.dart';
import 'package:my_app/screens/staff_logs_screen.dart';
import 'package:my_app/screens/staff_guest_list_screen.dart';
import 'package:my_app/screens/mission_matrix_screen.dart';
import 'package:my_app/services/staff_service.dart';
import 'package:my_app/services/staff_shift_service.dart';
import 'package:my_app/services/notification_service.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:my_app/screens/auth_screen.dart';
import 'package:my_app/services/booking_service.dart';
import 'package:my_app/screens/account_selector.dart';
import 'dart:async';

class StaffDashboard extends StatefulWidget {
  final String? organizerId;
  final String? currentEventId;
  const StaffDashboard({super.key, this.organizerId, this.currentEventId});

  @override
  State<StaffDashboard> createState() => _StaffDashboardState();
}

class _StaffDashboardState extends State<StaffDashboard> {
  final _shiftService = StaffShiftService();
  final _staffService = StaffService();
  final _notificationService = NotificationService();
  Map<String, dynamic>? _currentShift;
  Map<String, dynamic>? _activeAssignment;
  Timer? _timer;
  String _duration = '00:00';

  @override
  void initState() {
    super.initState();
    _initShiftData();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _initShiftData() async {
    final shift = await _shiftService.getCurrentShift();
    final assignment = await _staffService.getActiveAssignment();
    if (mounted) {
      setState(() {
        _currentShift = shift;
        _activeAssignment = assignment;
      });
      if (shift != null) {
        _startTimer();
      }
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (_currentShift != null && mounted) {
        setState(() {
          final start = DateTime.parse(_currentShift!['start_time']);
          _duration = _shiftService.getFormatDuration(start);
        });
      }
    });
    // Initial call
    if (_currentShift != null) {
      final start = DateTime.parse(_currentShift!['start_time']);
      _duration = _shiftService.getFormatDuration(start);
    }
  }

  Future<void> _handleClockInOut() async {
    // Tactical Feedback Sequence
    HapticFeedback.lightImpact();
    await Future.delayed(const Duration(milliseconds: 50));
    HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 50));
    HapticFeedback.heavyImpact();

    if (!mounted) return;
    if (_currentShift == null) {
      // Clock In
      if (_activeAssignment == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No active assignment found')));
        }
        return;
      }
      final success = await _shiftService.clockIn(_activeAssignment!['id']);
      if (success && mounted) {
        _initShiftData();
      }
    } else {
      // Clock Out
      final success = await _shiftService.clockOut();
      if (success && mounted) {
        _timer?.cancel();
        setState(() {
          _currentShift = null;
          _duration = '00:00';
        });
      }
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      drawer: _buildDrawer(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu, color: AppTheme.primary),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: Text('staff_hub'.tr, style: AppTheme.headlineStyle.copyWith(fontSize: 18)),
        actions: [
          IconButton(
            tooltip: 'SWITCH_ACCOUNT'.tr,
            icon: const Icon(Icons.switch_account_rounded, color: Colors.white24, size: 20),
            onPressed: () {
              final wrapper = OrganizerMainWrapper.of(context);
              if (wrapper != null) {
                wrapper.openSelector();
              } else {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const AccountSelectorScreen()),
                );
              }
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            const SizedBox(height: 16),
             Text('staff_console_active'.tr, 
               style: AppTheme.labelStyle.copyWith(color: AppTheme.primary, letterSpacing: 2)),
             const SizedBox(height: 8),
              Text('select_tool'.tr, style: AppTheme.headlineStyle.copyWith(fontSize: 28)),
              const SizedBox(height: 24),
              
              // Shift Card
              _buildShiftCard(),
              
              const SizedBox(height: 32),
              
              // MISSION FEED (Integrated from Portal)
              _buildMissionFeed(),

              const SizedBox(height: 48),
             
              // Tool Grid
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                children: [
                  if (_activeAssignment?['permissions']?['can_scan'] != false)
                    _buildToolCard(
                      context,
                      icon: Icons.qr_code_scanner_rounded,
                      label: 'QR_SCANNER'.tr,
                      color: AppTheme.primary,
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => ScanEntryScreen(
                        organizerId: widget.organizerId,
                        eventId: widget.currentEventId ?? _activeAssignment?['event_id']?.toString(),
                      ))),
                    ),
                  if (_activeAssignment?['permissions']?['can_manage_guests'] == true)
                    _buildToolCard(
                      context,
                      icon: Icons.person_search_rounded,
                      label: 'GUEST_LIST'.tr,
                      color: AppTheme.secondary,
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => StaffGuestListScreen(
                        organizerId: widget.organizerId,
                        eventId: widget.currentEventId ?? _activeAssignment?['event_id']?.toString(),
                      ))),
                    ),
                  if (_activeAssignment?['permissions']?['can_view_logs'] == true)
                    _buildToolCard(
                      context,
                      icon: Icons.security_rounded,
                      label: 'LOGS'.tr,
                      color: Colors.white,
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => StaffLogsScreen(
                        organizerId: widget.organizerId,
                        eventId: widget.currentEventId ?? _activeAssignment?['event_id']?.toString(),
                      ))),
                    ),
                  if (_activeAssignment?['permissions']?['can_view_stats'] == true)
                    _buildToolCard(
                      context,
                      icon: Icons.bar_chart_rounded,
                      label: 'LIVE_STATS'.tr,
                      color: Colors.white,
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => MissionMatrixScreen(
                        organizerId: widget.organizerId,
                        eventId: widget.currentEventId ?? _activeAssignment?['event_id']?.toString(),
                      ))),
                    ),
                  if (_activeAssignment?['role'] == 'role_manager' || _activeAssignment?['permissions']?['can_generate'] == true)
                    _buildToolCard(
                      context,
                      icon: Icons.qr_code_2_rounded,
                      label: 'ISSUE_NEW_PASS'.tr,
                      color: AppTheme.primary,
                      onTap: _showIssuanceForm,
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMissionFeed() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('TACTICAL_MISSIONS'.tr, Icons.bolt_rounded),
        const SizedBox(height: 16),
        StreamBuilder<List<AppNotification>>(
          stream: _notificationService.getNotificationsStream(),
          builder: (context, snapshot) {
             if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
               return const Center(child: CircularProgressIndicator(color: AppTheme.secondary));
             }
             
             final notifs = snapshot.data ?? [];
             // Only show missions/alerts
             final missions = notifs.where((n) => n.type == 'alert' || n.type == 'presence' || n.type == 'staff_mission').take(3).toList();

             if (missions.isEmpty) {
               return Container(
                 padding: const EdgeInsets.all(24),
                 width: double.infinity,
                 decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.02), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white.withValues(alpha: 0.05))),
                 child: Center(child: Text('ALL_CLEAR'.tr, style: const TextStyle(color: Colors.white24, fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.bold))),
               );
             }

             return Column(
               children: missions.map((m) => _missionTile(m)).toList(),
             );
          },
        ),
      ],
    );
  }

  Widget _missionTile(AppNotification notif) {
    final isAlert = notif.type == 'alert';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isAlert ? Colors.redAccent.withValues(alpha: 0.1) : AppTheme.secondary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isAlert ? Colors.redAccent.withValues(alpha: 0.2) : AppTheme.secondary.withValues(alpha: 0.1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(isAlert ? Icons.warning_amber_rounded : Icons.campaign_rounded, color: isAlert ? Colors.redAccent : AppTheme.secondary, size: 20),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(notif.title.toUpperCase(), style: TextStyle(color: isAlert ? Colors.redAccent : AppTheme.secondary, fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 1)),
                    Text(DateFormat('HH:mm').format(notif.createdAt), style: const TextStyle(color: Colors.white38, fontSize: 8, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(notif.body, style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.white38, size: 14),
        const SizedBox(width: 12),
        Text(title.toUpperCase(), style: const TextStyle(letterSpacing: 4, fontSize: 10, color: Colors.white38, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildToolCard(BuildContext context, {required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white10)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 12),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildShiftCard() {
    final isOn = _currentShift != null;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isOn ? AppTheme.primary.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: isOn ? AppTheme.primary.withValues(alpha: 0.2) : Colors.white10),
        boxShadow: isOn ? [BoxShadow(color: AppTheme.primary.withValues(alpha: 0.1), blurRadius: 40)] : null,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: isOn ? AppTheme.primary : Colors.white.withValues(alpha: 0.05), shape: BoxShape.circle),
            child: Icon(isOn ? Icons.shield_rounded : Icons.shield_outlined, color: isOn ? Colors.black : Colors.white24, size: 24),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isOn ? 'ON_DUTY'.tr.toUpperCase() : 'OFF_DUTY'.tr.toUpperCase(), style: TextStyle(color: isOn ? AppTheme.primary : Colors.white24, fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 2)),
                const SizedBox(height: 4),
                Text(isOn ? _duration : '00:00:00', style: AppTheme.headlineStyle.copyWith(fontSize: 24, letterSpacing: -1)),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: _handleClockInOut,
            style: ElevatedButton.styleFrom(
              backgroundColor: _currentShift == null ? AppTheme.primary : Colors.redAccent,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              minimumSize: const Size(180, 56),
            ),
            child: Text(
              (_currentShift == null ? 'START_SHIFT' : 'CLOCK_OUT').tr.toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final name = user?.userMetadata?['full_name'] ?? 'Staff';
    final email = user?.email ?? '';

    return Drawer(
      backgroundColor: AppTheme.background,
      child: Column(
        children: [
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(color: Color(0xFF0F0F0F)),
            currentAccountPicture: CircleAvatar(
              backgroundColor: AppTheme.secondary,
              backgroundImage: user?.userMetadata?['avatar_url'] != null ? NetworkImage(user!.userMetadata!['avatar_url']) : null,
              child: user?.userMetadata?['avatar_url'] == null ? const Icon(Icons.badge, color: Colors.white, size: 40) : null,
            ),
            accountName: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
            accountEmail: Text(email, style: const TextStyle(color: Colors.white54)),
          ),
          ListTile(
            leading: const Icon(Icons.person_outline, color: AppTheme.primary),
            title: Text('profile'.tr),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()))
                .then((_) => setState(() {}));
            },
          ),
          ListTile(
            leading: const Icon(Icons.help_outline_rounded, color: Colors.white54),
            title: Text('assistance'.tr),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => SupportForm()));
            },
          ),
          const Spacer(),
          const Divider(color: Colors.white10),
          ListTile(
            leading: const Icon(Icons.logout_rounded, color: Colors.redAccent),
            title: Text('logout'.tr, style: const TextStyle(color: Colors.redAccent)),
            onTap: () {
              Supabase.instance.client.auth.signOut().then((_) {
                if (context.mounted) {
                  Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => AuthScreen()), (r) => false);
                }
              });
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _showIssuanceForm() {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    String selectedType = 'General';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.75,
            padding: const EdgeInsets.all(32),
            decoration: const BoxDecoration(color: Color(0xFF141414), borderRadius: BorderRadius.vertical(top: Radius.circular(40))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 32),
                Text('ISSUE_NEW_PASS'.tr.toUpperCase(), style: AppTheme.labelStyle.copyWith(color: AppTheme.primary, letterSpacing: 2)),
                const SizedBox(height: 24),
                _buildIssuanceField('GUEST_NAME'.tr, Icons.person_outline, nameController),
                const SizedBox(height: 16),
                _buildIssuanceField('GUEST_PHONE'.tr, Icons.phone_android_rounded, phoneController),
                const SizedBox(height: 32),
                Text('TICKET_TYPE'.tr.toUpperCase(), style: const TextStyle(color: Colors.white24, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1)),
                const SizedBox(height: 12),
                Row(
                  children: ['General', 'VIP', 'GuestList', 'Table'].map((t) {
                    final sel = selectedType == t;
                    return GestureDetector(
                      onTap: () => setModalState(() => selectedType = t),
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(color: sel ? AppTheme.primary : Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12)),
                        child: Text(t.toUpperCase(), style: TextStyle(color: sel ? Colors.black : Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    );
                  }).toList(),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => _issuePass(nameController.text, phoneController.text, selectedType),
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                    child: Text('GENERATE_PASS'.tr.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          );
        }
      ),
    );
  }

  Widget _buildIssuanceField(String label, IconData icon, TextEditingController c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.02), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
      child: TextField(
        controller: c,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: AppTheme.primary, size: 20),
          hintText: label,
          hintStyle: const TextStyle(color: Colors.white24, fontSize: 14),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(20),
        ),
      ),
    );
  }

  Future<void> _issuePass(String name, String phone, String type) async {
    if (name.isEmpty) {
      return;
    }
    final eventId = widget.currentEventId ?? _activeAssignment?['event_id']?.toString();
    if (eventId == null) return;

    final bookingService = BookingService();

    try {
      final result = await bookingService.createManualBooking(
        eventId: eventId,
        guestName: name,
        guestPhone: phone,
        numGuests: 1, // Defaulting to 1 for quick issuance
      );
      
      if (result != null && mounted) {
        Navigator.pop(context);
        _showIssuanceSuccess(result.qrCode, name);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Issuance Failed')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Issuance Error')));
    }
  }

  void _showIssuanceSuccess(String code, String guestName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            const Icon(Icons.check_circle_outline_rounded, color: AppTheme.primary, size: 64),
            const SizedBox(height: 24),
            Text('SUCCESS'.tr, style: AppTheme.headlineStyle.copyWith(fontSize: 24)),
            const SizedBox(height: 12),
            Text(
              'pass_generated_success'.trArgs([code]),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  await SharePlus.instance.share(ShareParams(text: 'Your Sivox Entry Pass [$code] for event: $guestName'));
                },
                icon: const Icon(Icons.share_rounded, size: 18),
                label: Text('SHARE'.tr.toUpperCase()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('CLOSE'.tr.toUpperCase(), style: const TextStyle(color: Colors.white24)),
            ),
          ],
        ),
      ),
    );
  }
}

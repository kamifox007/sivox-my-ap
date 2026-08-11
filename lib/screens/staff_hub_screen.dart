import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/services/translation_service.dart';
import 'package:my_app/screens/staff_dashboard_screen.dart';
import 'package:my_app/screens/staff_event_selector.dart';
import 'package:my_app/screens/profile.dart';
import 'package:my_app/screens/auth_screen.dart';
import 'package:my_app/screens/support_form.dart';
import 'package:my_app/services/event_service.dart';
import 'package:my_app/services/notification_service.dart';
import 'package:my_app/services/reporting_service.dart';
import 'package:printing/printing.dart';

class StaffHubScreen extends StatefulWidget {
  const StaffHubScreen({super.key});

  @override
  State<StaffHubScreen> createState() => _StaffHubScreenState();
}

class _StaffHubScreenState extends State<StaffHubScreen> {
  final supabase = Supabase.instance.client;
  final _eventService = EventService();
  final _reporting = ReportingService();
  bool _isLoading = true;
  List<dynamic> _assignments = [];
  String? _activeMission;
  String? _activeMissionClub;

  @override
  void initState() {
    super.initState();
    _fetchAssignments();
    _startMissionListener();
  }

  void _startMissionListener() {
     final userId = supabase.auth.currentUser?.id;
     if (userId == null) return;

     supabase
        .channel('public:notifications:user_id=eq.$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
             final type = payload.newRecord['type'];
             if (type == 'staff_mission') {
                final metadata = payload.newRecord['metadata'];
                setState(() {
                   _activeMission = metadata['mission'];
                   _activeMissionClub = metadata['club_name'];
                });
             }
          },
        )
        .subscribe();
  }

  Future<void> _fetchAssignments() async {
    setState(() => _isLoading = true);
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final response = await supabase
          .from('staff_assignments')
          .select('*, club:organizer_profiles(id, bio, rating)')
          .eq('staff_id', userId)
          .order('created_at', ascending: false);

      setState(() {
        _assignments = response as List;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _launchSmartShift(dynamic job, String name) async {
    setState(() => _isLoading = true);
    try {
      final events = await _eventService.getOrganizerEvents(organizerId: job['club_id'] ?? job['organizer_id']);
      final now = DateTime.now();
      
      // Smart Filter: Events happening today
      final todayEvents = events.where((e) {
        if (e.dateTime == null) return false;
        
        // 1. Try ISO parsing
        try {
          final date = DateTime.parse(e.dateTime!);
          if (date.year == now.year && date.month == now.month && date.day == now.day) return true;
        } catch (_) {}

        // 2. Lenient string matching (e.g. "2024-04-11", "11/04", or "Tonight")
        final dStr = e.dateTime!.toLowerCase();
        final isoPrefix = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
        
        if (dStr.contains(isoPrefix)) return true;
        if (dStr.contains('tonight')) return true;
        
        return false;
      }).toList();

      if (mounted) {
        setState(() => _isLoading = false);
        if (todayEvents.length == 1) {
          // Auto-select the only event today
          Navigator.push(context, MaterialPageRoute(builder: (_) => StaffDashboard(
            organizerId: job['organizer_id'],
            currentEventId: todayEvents.first.id,
          )));
        } else {
          // Fallback to manual selection if 0 or >1 events today
          Navigator.push(context, MaterialPageRoute(builder: (_) => StaffEventSelector(
            organizerId: job['organizer_id'],
            organizerName: name,
          )));
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        // Fallback
        Navigator.push(context, MaterialPageRoute(builder: (_) => StaffEventSelector(
          organizerId: job['organizer_id'], 
          organizerName: name
        )));
      }
    }
  }

  Future<void> _updateStatus(dynamic job, String newStatus) async {
    setState(() => _isLoading = true);
    try {
      final String assignmentId = job['id'];
      final String organizerId = job['organizer_id'] ?? job['club_id'];
      final String clubName = job['club_name'] ?? 'Elite Club';
      final String staffName = supabase.auth.currentUser?.userMetadata?['full_name'] ?? 'Assistant';

      await supabase.from('staff_assignments').update({'status': newStatus}).eq('id', assignmentId);
      
      // Send notification back to organizer
      final bool isAccepted = newStatus == 'active';
      final String titleKey = isAccepted ? 'invitation_accepted' : 'invitation_rejected';
      final String bodyKey = isAccepted ? 'staff_accepted_desc' : 'staff_rejected_desc';

      await NotificationService().sendNotificationToUser(
        userId: organizerId,
        title: titleKey.tr,
        body: bodyKey.trArgs([staffName, clubName]),
        type: 'staff_decision',
        metadata: {
          'staff_id': supabase.auth.currentUser?.id,
          'status': newStatus,
          'club_name': clubName
        },
      );

      _fetchAssignments();
    } catch (e) {
      debugPrint('Error updating status: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _exportStaffReport(dynamic job, String name) async {
    setState(() => _isLoading = true);
    try {
      final pdfBytes = await _reporting.generateEventReport(
        userRole: job['role'] ?? 'staff',
        eventTitle: 'Staff Session Log',
        clubName: name,
      );
      await Printing.sharePdf(bytes: pdfBytes, filename: 'Sivox_Staff_${name.replaceAll(' ', '_')}.pdf');
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('error_processing'.tr)));
    }
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      drawer: _buildDrawer(),
      body: Stack(
        children: [
          // Elegant Background Glows
          Positioned(top: -100, left: -50, child: _aura(AppTheme.primary.withValues(alpha: 0.1))),
          Positioned(bottom: -150, right: -50, child: _aura(AppTheme.secondary.withValues(alpha: 0.2))),

          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              _buildAppBar(),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('MISSION CONTROL'.tr.toUpperCase(), style: AppTheme.labelStyle.copyWith(color: AppTheme.primary, letterSpacing: 4, fontSize: 10)),
                      const SizedBox(height: 8),
                      Text('Your Assignments'.tr, style: AppTheme.headlineStyle.copyWith(fontSize: 32)),
                      const SizedBox(height: 12),
                      Text('Manage your roles and club connections globally.'.tr, style: const TextStyle(color: Colors.white24, fontSize: 13)),
                    ],
                  ),
                ),
              ),
              if (_activeMission != null)
                SliverToBoxAdapter(
                  child: _buildActiveMissionCard(),
                ),
              if (_isLoading)
                const SliverFillRemaining(child: Center(child: CircularProgressIndicator(color: AppTheme.primary)))
              else if (_assignments.isEmpty)
                _buildEmptyState()
              else
                _buildList(),
              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _aura(Color c) => Container(width: 400, height: 400, decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: c, blurRadius: 150)]));

  Widget _buildAppBar() {
    return SliverAppBar(
      expandedHeight: 320,
      backgroundColor: Colors.transparent,
      elevation: 0,
      pinned: true,
      leading: Builder(
        builder: (context) => IconButton(
          icon: const Icon(Icons.menu, color: Colors.white),
          onPressed: () => Scaffold.of(context).openDrawer(),
        ),
      ),
      actions: [
        IconButton(icon: const Icon(Icons.refresh, color: Colors.white38), onPressed: _fetchAssignments),
      ],
    );
  }

  Widget _buildDrawer() {
    final user = Supabase.instance.client.auth.currentUser;
    final name = user?.userMetadata?['full_name'] ?? 'Staff Member';
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
              child: user?.userMetadata?['avatar_url'] == null ? const Icon(Icons.assignment_ind_outlined, color: Colors.white, size: 40) : null,
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
                .then((_) => _fetchAssignments());
            },
          ),
          ListTile(
            leading: const Icon(Icons.help_outline_rounded, color: Colors.white54),
            title: Text('assistance'.tr),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SupportForm()));
            },
          ),
          const Spacer(),
          const Divider(color: Colors.white10),
          ListTile(
            leading: const Icon(Icons.logout_rounded, color: Colors.redAccent),
            title: Text('logout'.tr, style: const TextStyle(color: Colors.redAccent)),
            onTap: () {
              Supabase.instance.client.auth.signOut().then((_) {
                if (mounted) Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const AuthScreen()), (r) => false);
              });
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildList() {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) => _jobCard(_assignments[index]), childCount: _assignments.length),
      ),
    );
  }

  Widget _jobCard(dynamic job) {
    final active = job['status'] == 'active';
    final name = (job['club_name'] ?? 'Elite Club').toUpperCase();
    final clubData = job['club'] ?? {};
    final bio = clubData['bio'] ?? '';
    final rating = clubData['rating'] ?? 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: active ? AppTheme.primary.withValues(alpha: 0.1) : Colors.white10),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: AppTheme.surfaceContainer,
                      child: const Icon(Icons.nightlife, color: AppTheme.primary),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: 0.5)),
                              const Spacer(),
                              if (rating > 0) Row(children: [const Icon(Icons.star_rounded, color: Colors.amber, size: 14), const SizedBox(width: 4), Text('$rating', style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold))]),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(job['role'].toString().tr.toUpperCase(), style: const TextStyle(color: AppTheme.primary, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 2)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(bio, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white38, fontSize: 12)),
                const SizedBox(height: 24),
                Row(
                  children: [
                    if (!active)
                      Expanded(
                        child: MaterialButton(
                          onPressed: () => _updateStatus(job, 'active'),
                          color: AppTheme.primary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: Text('accept'.tr.toUpperCase(), style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                        ),
                      )
                    else ...[
                      Expanded(
                        child: MaterialButton(
                          onPressed: () => _launchSmartShift(job, name),
                          color: Colors.white.withValues(alpha: 0.05),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: Text('LOG_SHIFT'.tr, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        onPressed: () => _exportStaffReport(job, name),
                        icon: const Icon(Icons.description_outlined, color: Colors.white38),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveMissionCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: AppTheme.primary, width: 2),
        boxShadow: [
          BoxShadow(color: AppTheme.primary.withValues(alpha: 0.2), blurRadius: 20, spreadRadius: 5)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: AppTheme.primary, size: 28),
              const SizedBox(width: 16),
              Text('ACTIVE_MISSION'.tr, style: AppTheme.headlineStyle.copyWith(fontSize: 20, color: AppTheme.primary)),
            ],
          ),
          const SizedBox(height: 16),
          Text(_activeMissionClub?.toUpperCase() ?? 'COMMAND', style: const TextStyle(color: Colors.white24, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 2)),
          const SizedBox(height: 8),
          Text(_activeMission ?? '', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          MaterialButton(
            onPressed: () => setState(() => _activeMission = null),
            height: 50,
            minWidth: double.infinity,
            color: AppTheme.primary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Text('I_AM_ON_IT'.tr, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return SliverFillRemaining(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.assignment_outlined, color: Colors.white10, size: 80),
            const SizedBox(height: 24),
            Text(
              'no_assignments_yet'.tr,
              style: const TextStyle(color: Colors.white38, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'wait_for_invite'.tr,
              style: const TextStyle(color: Colors.white12, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

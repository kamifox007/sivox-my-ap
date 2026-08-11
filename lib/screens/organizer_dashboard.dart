import 'package:flutter/material.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:my_app/services/notification_service.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/screens/create_event.dart';
import 'package:my_app/models/event.dart';
import 'package:my_app/models/booking.dart';
import 'package:my_app/services/event_service.dart';
// ignore: unused_import
import 'package:my_app/services/translation_service.dart';
import 'package:my_app/services/localization_service.dart';
import 'package:my_app/screens/event_manage_details.dart';
import 'package:my_app/services/follow_service.dart';
import 'package:my_app/services/booking_service.dart';
import 'package:my_app/screens/staff_management_screen.dart';
import 'package:my_app/screens/club_profile.dart';
import 'package:my_app/screens/notifications_screen.dart';
import 'package:my_app/screens/club_management_hub.dart';
import 'package:my_app/screens/organizer_main_wrapper.dart';
import 'package:my_app/screens/booking_management.dart';
import 'package:my_app/screens/marketing_engine_screen.dart';
import 'package:my_app/screens/broadcast_screen.dart';
import 'package:my_app/screens/mission_matrix_screen.dart';
import 'package:my_app/screens/vetting_hub_screen.dart';

import 'package:my_app/screens/audience_screen.dart';

class OrganizerDashboardScreen extends StatefulWidget {
  final String? clubId;
  final String? clubName;
  final String? businessType;
  final VoidCallback? onBack;
  const OrganizerDashboardScreen({super.key, this.clubId, this.clubName, this.businessType, this.onBack});

  @override
  State<OrganizerDashboardScreen> createState() => _OrganizerDashboardScreenState();
}

class _OrganizerDashboardScreenState extends State<OrganizerDashboardScreen> {
  final supabase = Supabase.instance.client;
  final _eventService = EventService();
  final _followService = FollowService();
  final _bookingService = BookingService();
  late Future<Map<String, dynamic>> _statsFuture;
  List<Map<String, dynamic>> _ownedClubs = [];

  @override
  void initState() {
    super.initState();
    _statsFuture = _fetchStats();
    _fetchOwnedClubs();
  }

  Future<void> _fetchOwnedClubs() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final res = await supabase
          .from('organizer_profiles')
          .select('id, name, business_type, avatar_url')
          .eq('owner_id', userId);
      
      if (mounted) {
        setState(() {
          _ownedClubs = List<Map<String, dynamic>>.from(res as List);
        });
      }
    } catch (e) {
      debugPrint('Error fetching owned clubs: $e');
    }
  }

  void _refresh() => setState(() => _statsFuture = _fetchStats());


  void _showToast(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }


  Future<Map<String, dynamic>> _fetchStats() async {
    final targetId = widget.clubId ?? supabase.auth.currentUser?.id;
    if (targetId == null) return {};

    try {
      return await Future.any([
        _fetchStatsLogic(targetId),
        Future.delayed(const Duration(seconds: 15)).then((_) => throw 'Timeout loading stats'),
      ]);
    } catch (e) {
      debugPrint('Error fetching stats: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Load Error: $e')));
      return {'events': <Event>[], 'bookings': <Booking>[], 'followers': 0, 'revenue': 0.0, 'views': 0, 'arrivals': <Booking>[], 'profile': {}, 'staff_stats': {'managers': 0, 'security': 0, 'absent': 0}};
    }
  }

  Future<Map<String, dynamic>> _fetchStatsLogic(String targetId) async {
    try {
      final events = await _eventService.getOrganizerEvents(organizerId: targetId);
      final eventIds = events.map((e) => e.id).toList();
      
      List<Booking> bookings = [];
      if (eventIds.isNotEmpty) {
        final response = await supabase.from('bookings').select('*, events(*)').inFilter('event_id', eventIds);
        bookings = (response as List).map((b) => Booking.fromMap(b)).toList();
      }

      final followers = await _followService.getFollowerCount(targetId);
      double revenue = bookings.where((b) => b.paymentStatus == 'used').fold(0.0, (sum, b) => sum + (b.event?.price ?? 0) * b.numGuests);

      // 1. Fetch info from organizer_profiles (the actual club page)
      final orgRes = await supabase.from('organizer_profiles').select('*, profiles(full_name, avatar_url)').eq('id', targetId).maybeSingle();
      
      final String displayName = orgRes?['name'] ?? orgRes?['profiles']?['full_name'] ?? 'Club Identity';
      final String? avatarUrl = orgRes?['avatar_url'] ?? orgRes?['profiles']?['avatar_url'];

      final staffRes = await supabase.from('staff_assignments').select('role, status').eq('organizer_id', targetId).or('status.eq.active,status.eq.absent');
      final staffList = staffRes as List;
      int managerCount = staffList.where((s) => s['role'] == 'role_manager' && s['status'] == 'active').length;
      int securityCount = staffList.where((s) => s['role'] == 'role_security' && s['status'] == 'active').length;
      int absentCount = staffList.where((s) => s['status'] == 'absent').length;

      int totalViews = events.fold(0, (sum, e) => sum + e.viewCount);

      return {
        'events': events,
        'bookings': bookings,
        'followers': followers,
        'revenue': revenue,
        'views': totalViews,
        'arrivals': bookings.where((b) => b.scannedAt != null).toList()..sort((a,b) => b.scannedAt!.compareTo(a.scannedAt!)),
        'profile': {
          'full_name': displayName,
          'avatar_url': avatarUrl,
          'bio': orgRes?['bio'] ?? '',
          'business_type': orgRes?['business_type']
        },
        'staff_stats': {
          'managers': managerCount,
          'security': securityCount,
          'absent': absentCount,
        },
      };
    } catch (e) {
      return {'events': <Event>[], 'bookings': <Booking>[], 'followers': 0, 'revenue': 0.0, 'views': 0, 'arrivals': <Booking>[], 'profile': {}, 'staff_stats': {'managers': 0, 'security': 0, 'absent': 0}};
    }
  }

  void _showSectionHelp(String section, {String? customDesc}) {
    String desc = customDesc ?? 'providing_details'.tr;
    if (section == 'media_studio'.tr) desc = 'HELP_MEDIA_DESC'.tr;
    if (section == 'FOLLOWER_PERKS'.tr) desc = 'HELP_PERKS_DESC'.tr;
    if (section == 'basic_info'.tr) desc = 'HELP_BASIC_DESC'.tr;
    if (section == 'logistics'.tr) desc = 'HELP_LOGISTICS_DESC'.tr;
    if (section == 'FINANCIAL_INTEL'.tr) desc = 'HELPER_FINANCIAL_INTEL_DESC'.tr;
    if (section == 'MY_EVENTS'.tr) desc = 'HELPER_MY_EVENTS_DESC'.tr;
    if (section == 'FIXED_INFRASTRUCTURE'.tr) desc = 'HELPER_INFRASTRUCTURE_DESC'.tr;
    if (section == 'LIVE_PULSE'.tr) desc = 'HELPER_LIVE_DESC'.tr;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(32),
        decoration: const BoxDecoration(color: Color(0xFF1A1A1A), borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 24),
            const Icon(Icons.info_outline_rounded, color: AppTheme.primary, size: 32),
            const SizedBox(height: 16),
            Text(section.toUpperCase(), style: AppTheme.headlineStyle.copyWith(fontSize: 18)),
            const SizedBox(height: 12),
            Text(desc, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.5)),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildInlineHelp(String title, String descKey, {IconData icon = Icons.info_outline_rounded}) {
    return GestureDetector(
      onTap: () => _showSectionHelp(title, customDesc: descKey.tr),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), shape: BoxShape.circle),
        child: Icon(icon, color: Colors.white24, size: 10),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      drawer: _buildDrawer(),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _statsFuture,
        builder: (context, snapshot) {
          final data = snapshot.data ?? {};
          final isLoading = snapshot.connectionState == ConnectionState.waiting;

          return CustomScrollView(
            slivers: [
              _buildAppBar(),
              if (isLoading)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
                )
              else ...[
                SliverToBoxAdapter(child: _buildClubFixedHeader(data)),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                  sliver: SliverToBoxAdapter(
                    child: _buildOverview(data),
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          );
        },
      ),
      floatingActionButton: FutureBuilder<Map<String, dynamic>>(
        future: _statsFuture,
        builder: (context, snapshot) {
          final data = snapshot.data ?? {};
          final events = data['events'] as List? ?? [];
          final bool isInitial = events.isEmpty;
          final String labelKey = isInitial ? 'create_experience' : 'CREATE_EVENT';

          return FloatingActionButton.extended(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => CreateEventScreen(clubId: widget.clubId, businessType: widget.businessType, isInitial: isInitial)),
            ).then((_) => _refresh()),
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.black,
            icon: const Icon(Icons.add_rounded, size: 28),
            label: Text(labelKey.tr.toUpperCase(),
                style: const TextStyle(
                    fontWeight: FontWeight.w900, letterSpacing: 1.5, fontSize: 13)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          );
        }
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      pinned: true,
      backgroundColor: AppTheme.background.withValues(alpha: 0.8),
      expandedHeight: 0,
      elevation: 0,
      centerTitle: true,
      title: Text('COMMAND CENTER'.tr.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 4, color: Colors.white38)),
      leading: Builder(builder: (ctx) => IconButton(icon: const Icon(Icons.menu_rounded, color: Colors.white54), onPressed: () => Scaffold.of(ctx).openDrawer())),
      actions: [
        if (widget.onBack != null)
          IconButton(
            icon: const Icon(Icons.grid_view_rounded, color: AppTheme.primary),
            tooltip: 'اختر صفحة أخرى',
            onPressed: widget.onBack,
          ),
        IconButton(icon: const Icon(Icons.notifications_none_rounded, color: AppTheme.primary), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen()))),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildClubFixedHeader(Map<String, dynamic> data) {
    final profile = data['profile'] ?? {};
    final eventCount = (data['events'] as List).length;
    final followerCount = data['followers'] ?? 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'GREETING_ORGANIZER'.trArgs([supabase.auth.currentUser?.userMetadata?['full_name'] ?? widget.clubName ?? 'COMMANDER']),
            style: AppTheme.labelStyle.copyWith(
              color: AppTheme.primary,
              letterSpacing: 2,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              CircleAvatar(
                radius: 40,
                backgroundColor: AppTheme.surfaceContainer,
                backgroundImage: profile['avatar_url'] != null ? NetworkImage(profile['avatar_url']) : null,
                child: profile['avatar_url'] == null ? const Icon(Icons.nightlife, color: AppTheme.primary, size: 40) : null,
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _headerStat('$eventCount', 'EVENTS'.tr),
                    _headerStat(
                      '$followerCount', 
                      'FOLLOWERS'.tr,
                      onTap: () {
                        final userId = widget.clubId ?? supabase.auth.currentUser?.id;
                        if (userId != null) Navigator.push(context, MaterialPageRoute(builder: (_) => AudienceScreen(organizerId: userId)));
                      },
                    ),
                    _headerStat('4.9', 'RATING'.tr),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(profile['full_name']?.toString().toUpperCase() ?? 'CLUB IDENTITY', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 0.5)),
                    const SizedBox(width: 8),
                    _buildBrandingBadge(widget.businessType ?? profile['business_type']),
                  ],
                ),
                const SizedBox(height: 6),
                Text(profile['bio'] ?? '', style: const TextStyle(color: Colors.white38, fontSize: 11, height: 1.4)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _headerActionBtn('EDIT_BRANDING'.tr, Icons.edit_note_rounded, () => Navigator.push(context, MaterialPageRoute(builder: (_) => ClubManagementHubScreen(clubId: widget.clubId))).then((_) => _refresh()), isPrimary: true),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _headerActionBtn('PUBLIC_PREVIEW'.tr, Icons.remove_red_eye_outlined, () {
                   final userId = widget.clubId ?? supabase.auth.currentUser?.id;
                   if (userId != null) Navigator.push(context, MaterialPageRoute(builder: (_) => ClubProfileScreen(organizerId: userId, organizerName: profile['full_name'] ?? 'Club')));
                }),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // COMMAND GRID (PREMIUM NAVIGATION)
          _buildCommandGrid(eventCount),
        ],
      ),
    );
  }

  Widget _buildLevelProgressBar(int eventCount, int level) {
    double progress;
    if (level == 1) {
      progress = eventCount / 5.0;
    } else if (level == 2) {
      progress = (eventCount - 5) / 10.0;
    } else {
      progress = 1.0;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ORGANIZER_LEVEL'.tr.toUpperCase(), style: const TextStyle(color: Colors.white38, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 2)),
                  Text('LVL $level', style: AppTheme.headlineStyle.copyWith(fontSize: 18, color: AppTheme.primary)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: Text('XP: $eventCount EVENTS', style: const TextStyle(color: AppTheme.primary, fontSize: 9, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              backgroundColor: Colors.white.withValues(alpha: 0.05),
              color: AppTheme.primary,
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            level == 1 
              ? 'next_level_in'.trArgs(['${5 - eventCount}']) 
              : (level == 2 ? 'next_level_in'.trArgs(['${15 - eventCount}']) : 'MAX_LEVEL_REACHED'.tr),
            style: const TextStyle(color: Colors.white24, fontSize: 9),
          ),
        ],
      ),
    );
  }



  Widget _buildCommandGrid(int eventCount) {
    final int level = (eventCount >= 15) ? 3 : (eventCount >= 5 ? 2 : 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLevelProgressBar(eventCount, level),
        const SizedBox(height: 32),
        
        Text('OPERATIONS'.tr.toUpperCase(), style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 2)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _commandCard(label: 'BOOKINGS'.tr, subtitle: 'Requests', icon: Icons.confirmation_number_outlined, color: AppTheme.secondary, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BookingManagementScreen(clubId: widget.clubId))))),
            const SizedBox(width: 12),
            Expanded(child: _commandCard(label: 'STAFF'.tr, subtitle: 'Crew', icon: Icons.badge_outlined, color: Colors.blueAccent, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StaffManagementScreen(clubId: widget.clubId))))),
          ],
        ),
        const SizedBox(height: 12),
        _commandCard(label: 'VETTING_HUB'.tr, subtitle: 'Approvals & Blacklist', icon: Icons.security_rounded, color: Colors.redAccent, isFullWidth: true, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => VettingHubScreen(clubId: widget.clubId)))),
        
        const SizedBox(height: 32),
        Text('GROWTH_AND_MARKETING'.tr.toUpperCase(), style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 2)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _commandCard(label: 'MARKETING'.tr, subtitle: 'Campaigns', icon: Icons.campaign_rounded, color: Colors.purpleAccent, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MarketingEngineScreen(clubId: widget.clubId ?? supabase.auth.currentUser!.id))))),
            const SizedBox(width: 12),
            Expanded(child: _commandCard(label: 'AUDIENCE'.tr, subtitle: 'Followers', icon: Icons.people_alt_rounded, color: Colors.orangeAccent, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AudienceScreen(organizerId: widget.clubId ?? supabase.auth.currentUser!.id))))),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _commandCard(label: 'BROADCAST'.tr, subtitle: 'Messages', icon: Icons.podcasts_rounded, color: Colors.greenAccent, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BroadcastScreen(organizerId: widget.clubId ?? supabase.auth.currentUser!.id))))),
            const SizedBox(width: 12),
            Expanded(child: _commandCard(label: 'MATRIX'.tr, subtitle: 'Analytics', icon: Icons.analytics_rounded, color: AppTheme.primary, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MissionMatrixScreen(organizerId: widget.clubId ?? supabase.auth.currentUser!.id))))),
          ],
        ),
      ],
    );
  }

  Widget _commandCard({
    required String label,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    bool isFullWidth = false,
    bool isLocked = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        opacity: isLocked ? 0.4 : 1.0,
        child: Container(
          width: isFullWidth ? double.infinity : null,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isLocked ? Colors.white.withValues(alpha: 0.02) : color.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: isLocked ? Colors.white10 : color.withValues(alpha: 0.1)),
            boxShadow: [
              if (!isLocked)
                BoxShadow(
                  color: color.withValues(alpha: 0.02),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                )
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isLocked ? Colors.white10 : color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: isLocked ? Colors.white38 : color, size: 20),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: isLocked ? Colors.white38 : Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  if (isLocked)
                    const Icon(Icons.lock_rounded, color: Colors.white24, size: 12),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  color: isLocked ? Colors.white10 : Colors.white38,
                  fontSize: 9,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerStat(String value, String label, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: onTap != null ? Colors.white.withValues(alpha: 0.03) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: onTap != null ? AppTheme.primary.withValues(alpha: 0.1) : Colors.transparent),
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(color: onTap != null ? AppTheme.primary : Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label.toUpperCase(), style: const TextStyle(color: Colors.white24, fontSize: 7, fontWeight: FontWeight.bold, letterSpacing: 1)),
                if (onTap != null) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_forward_ios_rounded, color: AppTheme.primary, size: 6),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerActionBtn(String label, IconData icon, VoidCallback onTap, {bool isPrimary = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: isPrimary ? AppTheme.primary : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isPrimary ? AppTheme.primary : Colors.white10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: isPrimary ? Colors.black : Colors.white70, size: 18),
            const SizedBox(width: 10),
            Text(label.toUpperCase(), style: TextStyle(color: isPrimary ? Colors.black : Colors.white70, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1)),
          ],
        ),
      ),
    );
  }


  Widget _buildOverview(Map<String, dynamic> data) {
    final arrivals = data['arrivals'] as List<Booking>;
    final events = data['events'] as List<Event>;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildNextEventPulse(events),
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionHeader('FINANCIAL_INTEL'.tr, Icons.analytics_outlined, Colors.greenAccent),
            _buildInlineHelp('FINANCIAL_INTEL'.tr, 'HELPER_FINANCIAL_INTEL_DESC'),
          ],
        ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: () {
            OrganizerMainWrapper.of(context)?.setIndex(2); // Go to Archives
          },
          child: _buildRevenueCard(data['revenue'] as double),
        ),
        const SizedBox(height: 12),
        _buildViewsCard(data['views'] as int),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () {
                  _showToast('SCROLLING_TO_LIVE_FEED'.tr);
                },
                child: _miniStatCard('checked_in'.tr, '${arrivals.length}', Icons.how_to_reg_rounded, AppTheme.primary),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: () {
                   final pending = (data['bookings'] as List<Booking>).where((b) => b.paymentStatus == 'pending' || b.paymentStatus == 'pending_confirmation').toList();
                   if (pending.isNotEmpty) {
                     Navigator.push(context, MaterialPageRoute(builder: (_) => BookingManagementScreen(clubId: widget.clubId)));
                   } else {
                     _showToast('NO_PENDING_REQ'.tr);
                   }
                },
                child: _miniStatCard('PENDING_REQ'.tr, '${(data['bookings'] as List<Booking>).where((b) => b.paymentStatus == 'pending' || b.paymentStatus == 'pending_confirmation').length}', Icons.hourglass_empty_rounded, AppTheme.secondary)
              ),
            ),
          ],
        ),
        const SizedBox(height: 48),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionHeader('MY_EVENTS'.tr, Icons.event_note_rounded, AppTheme.primary),
            _buildInlineHelp('MY_EVENTS'.tr, 'HELPER_MY_EVENTS_DESC'),
          ],
        ),
        const SizedBox(height: 16),
        _buildMyEventsScroller(data['events'] as List<Event>, data['bookings'] as List<Booking>),
        const SizedBox(height: 48),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionHeader('FIXED_INFRASTRUCTURE'.tr, Icons.business_rounded, Colors.white),
            _buildInlineHelp('FIXED_INFRASTRUCTURE'.tr, 'HELPER_INFRASTRUCTURE_DESC'),
          ],
        ),
        const SizedBox(height: 16),
        _buildInfrastructureGrid(data),
        const SizedBox(height: 48),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionHeader('LIVE_PULSE'.tr, Icons.sensors_rounded, AppTheme.primary),
            _buildInlineHelp('LIVE_PULSE'.tr, 'HELPER_LIVE_DESC'),
          ],
        ),
        const SizedBox(height: 16),
        _buildLiveMissionFeed(data),
      ],
    );
  }

  Widget _buildNextEventPulse(List<Event> events) {
    if (events.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [AppTheme.primary.withValues(alpha: 0.1), Colors.transparent]),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            const Icon(Icons.auto_awesome_rounded, color: AppTheme.primary, size: 32),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('KICKSTART_JOURNEY'.tr.toUpperCase(), style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 2)),
                  const SizedBox(height: 4),
                  Text('PUBLISH_FIRST_MSG'.tr, style: const TextStyle(color: Colors.white38, fontSize: 10)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Logic to find the nearest event
    Event? nextEvent;
    Duration? timeRemaining;

    final now = DateTime.now();
    for (var e in events) {
      if (e.isArchived) continue;
      try {
        DateTime? eventDate;
        String dateStr = e.dateTime ?? '';
        
        // Handle ranges or messy strings from manual input
        if (dateStr.contains(' - ')) dateStr = dateStr.split(' - ').first;

        if (dateStr.isEmpty || dateStr.toLowerCase() == 'tonight' || dateStr.toLowerCase() == 'الليلة') {
          // Default to 10 PM today or tomorrow if already late
          eventDate = DateTime(now.year, now.month, now.day, 22, 0);
          if (eventDate.isBefore(now)) {
            eventDate = eventDate.add(const Duration(days: 1));
          }
        } else {
          // Try standard ISO parsing
          eventDate = DateTime.tryParse(dateStr);
          
          // Fallback: If it's just "YYYY-MM-DD", add default time
          if (eventDate != null && dateStr.length <= 10) {
            eventDate = DateTime(eventDate.year, eventDate.month, eventDate.day, 22, 0);
          }
        }

        if (eventDate != null && eventDate.isAfter(now)) {
          final diff = eventDate.difference(now);
          if (timeRemaining == null || diff < timeRemaining) {
            timeRemaining = diff;
            nextEvent = e;
          }
        }
      } catch (_) {}
    }

    if (nextEvent == null) return const SizedBox.shrink();

    // Scheduling an "Instant Alert" for the organizer (Local Notification)
    if (timeRemaining!.inMinutes > 60) {
      NotificationService.scheduleReminder(
        id: nextEvent.id.hashCode,
        title: 'EVENT_START_SOON'.tr,
        body: 'EVENT_START_BODY'.trArgs([nextEvent.title]),
        scheduledDate: now.add(timeRemaining).subtract(const Duration(hours: 1)),
      );
    }

    final hours = timeRemaining.inHours;
    final minutes = timeRemaining.inMinutes % 60;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(color: AppTheme.primary.withValues(alpha: 0.05), blurRadius: 30, spreadRadius: 5),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.sensors_rounded, color: AppTheme.primary, size: 16),
                  const SizedBox(width: 12),
                  Text('LIVE_PULSE'.tr.toUpperCase(), style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 9, letterSpacing: 3)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Colors.redAccent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: Row(
                  children: [
                    Container(width: 6, height: 6, decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text('COUNTDOWN'.tr.toUpperCase(), style: const TextStyle(color: Colors.redAccent, fontSize: 8, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            nextEvent.title.toUpperCase(),
            textAlign: TextAlign.center,
            style: AppTheme.headlineStyle.copyWith(fontSize: 18, letterSpacing: 1),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildTimeUnit(hours.toString().padLeft(2, '0'), 'HRS'),
              const Text(' : ', style: TextStyle(color: Colors.white10, fontSize: 24, fontWeight: FontWeight.bold)),
              _buildTimeUnit(minutes.toString().padLeft(2, '0'), 'MIN'),
            ],
          ),
          const SizedBox(height: 24),
          LinearProgressIndicator(
            value: 1.0 - (timeRemaining.inMinutes / (24 * 60)).clamp(0.0, 1.0),
            backgroundColor: Colors.white.withValues(alpha: 0.05),
            color: AppTheme.primary,
            minHeight: 2,
          ),
        ],
      ),
    );
  }

  Widget _buildTimeUnit(String val, String label) {
    return Column(
      children: [
        Text(val, style: AppTheme.headlineStyle.copyWith(fontSize: 32, color: Colors.white)),
        Text(label, style: const TextStyle(color: Colors.white24, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 1)),
      ],
    );
  }


  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 12),
        Text(title.toUpperCase(), style: AppTheme.labelStyle.copyWith(letterSpacing: 4, fontSize: 10, color: color.withValues(alpha: 0.7))),
      ],
    );
  }

  Widget _buildViewsCard(int views) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: const Icon(Icons.remove_red_eye_outlined, color: AppTheme.primary, size: 20),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('TOTAL_VIEWS'.tr.toUpperCase(), style: const TextStyle(color: Colors.white38, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 1)),
                    const SizedBox(width: 6),
                    _buildInlineHelp('TOTAL_VIEWS'.tr, 'HELP_VIEWS_SHORT', icon: Icons.remove_red_eye_outlined),
                  ],
                ),
                Text('$views', style: AppTheme.headlineStyle.copyWith(fontSize: 24)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRevenueCard(double revenue) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.greenAccent.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('TOTAL_REVENUE'.tr.toUpperCase(), style: const TextStyle(color: Colors.greenAccent, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 2)),
              const SizedBox(width: 6),
              _buildInlineHelp('TOTAL_REVENUE'.tr, 'HELP_REVENUE_SHORT', icon: Icons.payments_outlined),
            ],
          ),
          const SizedBox(height: 12),
          Text(LocalizationService.formatPrice(revenue, 'DZ'), style: AppTheme.headlineStyle.copyWith(fontSize: 32, color: Colors.greenAccent)),
        ],
      ),
    );
  }

  Widget _miniStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 16),
          Text(value, style: AppTheme.headlineStyle.copyWith(fontSize: 20)),
          Row(
            children: [
              Text(label.toUpperCase(), style: TextStyle(color: color.withValues(alpha: 0.6), fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 1)),
              const SizedBox(width: 4),
              _buildInlineHelp(label, label == 'checked_in'.tr ? 'HELP_SCANNED_SHORT' : (label == 'PENDING_REQ'.tr ? 'HELP_PENDING_SHORT' : 'HELP_REFUSALS_SHORT'), icon: label == 'checked_in'.tr ? Icons.qr_code_scanner_rounded : (label == 'PENDING_REQ'.tr ? Icons.hourglass_empty_rounded : Icons.block_flipped)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfrastructureGrid(Map<String, dynamic> data) {
    final staff = data['staff_stats'] ?? {'managers': 0, 'security': 0, 'absent': 0};
    return Row(
      children: [
        Expanded(
          child: _infraTile(
            'MANAGERS',
            '${staff['managers']}',
            Icons.admin_panel_settings_rounded,
            AppTheme.primary,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => StaffManagementScreen(
                  clubId: widget.clubId,
                  clubName: widget.clubName,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _infraTile(
            'SECURITY',
            '${staff['security']}',
            Icons.shield_rounded,
            AppTheme.secondary,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => StaffManagementScreen(
                  clubId: widget.clubId,
                  clubName: widget.clubName,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _infraTile(
            'ABSENT',
            '${staff['absent']}',
            Icons.person_off_rounded,
            Colors.redAccent,
          ),
        ),
      ],
    );
  }

  Widget _infraTile(String label, String val, IconData icon, Color color, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(height: 12),
            Text(val, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label.tr, style: const TextStyle(color: Colors.white24, fontSize: 7, fontWeight: FontWeight.bold)),
                const SizedBox(width: 4),
                _buildInlineHelp(
                  label.tr, 
                  label == 'MANAGERS' ? 'HELP_MANAGERS_SHORT' : label == 'SECURITY' ? 'HELP_SECURITY_SHORT' : 'explaining_role',
                  icon: label == 'MANAGERS' ? Icons.admin_panel_settings_rounded : label == 'SECURITY' ? Icons.shield_outlined : Icons.person_off_rounded,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveMissionFeed(Map<String, dynamic> data) {
    final arrivals = data['arrivals'] as List<Booking>;
    if (arrivals.isEmpty) return _buildEmptyState('NO_RECENT_ARRIVALS'.tr);
    
    return Column(
      children: arrivals.take(5).map((b) => _arrivalTile(b)).toList(),
    );
  }

  Widget _arrivalTile(Booking b) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.02), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withValues(alpha: 0.05))),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, color: AppTheme.primary, size: 16),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(b.userName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                Text(b.event?.title ?? 'Event', style: const TextStyle(color: Colors.white24, fontSize: 10)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (!b.paymentConfirmed)
            TextButton(
              onPressed: () => _handlePaymentCollection(b),
              style: TextButton.styleFrom(
                backgroundColor: AppTheme.secondary.withValues(alpha: 0.1),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                'COLLECT_PAYMENT'.tr.toUpperCase(),
                style: const TextStyle(color: AppTheme.secondary, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 0.5),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: Colors.greenAccent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: Text(
                'PAID'.tr.toUpperCase(),
                style: const TextStyle(color: Colors.greenAccent, fontSize: 8, fontWeight: FontWeight.bold),
              ),
            ),
          const SizedBox(width: 8),
          Text(b.scannedAt != null ? b.scannedAt!.substring(11, 16) : '--:--', style: const TextStyle(color: AppTheme.primary, fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildMyEventsScroller(List<Event> events, List<Booking> allBookings) {
    if (events.isEmpty) return _buildEmptyState('NO_ACTIVE_EVENTS'.tr);
    return SizedBox(
      height: 200,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: events.length,
        itemBuilder: (ctx, i) {
          final e = events[i];
          return GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EventManageDetailsScreen(event: e))),
            child: Container(
              width: 280,
              margin: const EdgeInsets.only(right: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                image: e.imageUrl != null ? DecorationImage(image: NetworkImage(e.imageUrl!), fit: BoxFit.cover) : null,
                color: Colors.white.withValues(alpha: 0.05),
              ),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black.withValues(alpha: 0.8)]),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.title.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1)),
                    Text(e.venue ?? '', style: const TextStyle(color: Colors.white70, fontSize: 10)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(String msg) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.02), borderRadius: BorderRadius.circular(24)),
      child: Center(child: Text(msg, style: const TextStyle(color: Colors.white10, fontSize: 11, letterSpacing: 2))),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFF0F0F0F),
      child: Column(
        children: [
          _drawerHeader(),
          const SizedBox(height: 20),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _drawerSection('modules'.tr),
                _drawerTile(Icons.dashboard_rounded, 'control_center'.tr, () {
                  Navigator.pop(context);
                  OrganizerMainWrapper.of(context)?.setIndex(0);
                }),
                _drawerTile(Icons.inventory_2_outlined, 'operational_archives'.tr, () {
                  Navigator.pop(context);
                  OrganizerMainWrapper.of(context)?.setIndex(2);
                }),
                _drawerTile(Icons.people_alt_rounded, 'manage_staff'.tr, () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => StaffManagementScreen(clubId: widget.clubId, clubName: widget.clubName)));
                }),
                _drawerTile(Icons.storefront_rounded, 'public_profile'.tr, () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => ClubProfileScreen(organizerId: widget.clubId ?? '', organizerName: widget.clubName ?? 'Club')));
                }),
                _drawerTile(Icons.favorite_rounded, 'manage_fans'.tr, () {
                  Navigator.pop(context);
                  final userId = widget.clubId ?? supabase.auth.currentUser?.id;
                  if (userId != null) Navigator.push(context, MaterialPageRoute(builder: (_) => AudienceScreen(organizerId: userId)));
                }),
                
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Divider(color: Colors.white10),
                ),
                
                _drawerSection('account'.tr),
                _drawerTile(Icons.swap_horiz_rounded, 'switch_club'.tr, () {
                  Navigator.pop(context);
                  OrganizerMainWrapper.of(context)?.openSelector();
                }),
                _drawerTile(Icons.logout, 'logout'.tr, () => supabase.auth.signOut(), isDestructive: true),
                
                if (_ownedClubs.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Divider(color: Colors.white10),
                  ),
                  _drawerSection('MY_ENTITIES'.tr),
                  const SizedBox(height: 8),
                  ..._ownedClubs.map((c) {
                    final isSelected = c['id'] == widget.clubId;
                    return _drawerTile(
                      c['business_type'] == 'restaurant' ? Icons.restaurant : Icons.nightlife_rounded,
                      c['name'] ?? 'Club Identity',
                      () {
                        Navigator.pop(context);
                        if (!isSelected) {
                          OrganizerMainWrapper.of(context)?.selectClub(
                            c['id'], 
                            c['name'] ?? 'Club Identity',
                            businessType: c['business_type'] ?? 'club'
                          );
                        }
                      },
                      isSelected: isSelected,
                    );
                  }),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _drawerHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 80, 24, 32),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        border: const Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: const Icon(Icons.nightlife_rounded, color: AppTheme.primary, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.clubName?.toUpperCase() ?? 'CLUB', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1)),
                Text('VERIFIED_ORGANIZER'.tr, style: const TextStyle(color: AppTheme.primary, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _drawerSection(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(title.toUpperCase(), style: const TextStyle(color: Colors.white24, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 2)),
    );
  }

  Widget _drawerTile(IconData icon, String label, VoidCallback onTap, {bool isDestructive = false, bool isSelected = false}) {
    return ListTile(
      leading: Icon(icon, color: isDestructive ? Colors.redAccent : isSelected ? AppTheme.primary : Colors.white70, size: 20),
      title: Text(
        label, 
        style: TextStyle(
          color: isDestructive ? Colors.redAccent : isSelected ? AppTheme.primary : Colors.white, 
          fontSize: 13, 
          fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600
        )
      ),
      onTap: onTap,
      tileColor: isSelected ? AppTheme.primary.withValues(alpha: 0.05) : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  Future<void> _handlePaymentCollection(Booking b) async {
    final success = await _bookingService.confirmManagerPayment(b.id);
    if (success) {
      _showToast('PAYMENT_RECORDED'.tr);
      // Refresh the specific data slice if possible, or reload entire mission stats
      setState(() {}); 
    } else {
      _showToast('err_update'.tr);
    }
  }

  Widget _buildBrandingBadge(String? type) {
    IconData icon = Icons.nightlife;
    String label = 'CLUB_BRAND';
    Color color = AppTheme.primary;

    switch (type?.toLowerCase()) {
      case 'restaurant':
        icon = Icons.restaurant;
        label = 'RESTAURANT_BRAND';
        color = Colors.orangeAccent;
        break;
      case 'cafe':
        icon = Icons.coffee;
        label = 'CAFE_BRAND';
        color = Colors.brown;
        break;
      case 'entertainment':
        icon = Icons.theater_comedy_rounded;
        label = 'ENTERTAINMENT_BRAND';
        color = Colors.purpleAccent;
        break;
      default:
        icon = Icons.nightlife;
        label = 'CLUB_BRAND';
        color = AppTheme.primary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 10),
          const SizedBox(width: 6),
          Text(
            label.tr,
            style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 0.5),
          ),
        ],
      ),
    );
  }
}

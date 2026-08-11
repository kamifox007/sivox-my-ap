import 'package:flutter/material.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/services/translation_service.dart';
import 'package:my_app/screens/staff_management_screen.dart';
import 'package:my_app/screens/club_profile_editor.dart';
import 'package:my_app/screens/master_operational_ledger.dart';
import 'package:my_app/screens/create_event.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:my_app/screens/event_creation_widget.dart';


import 'dart:ui';

class ClubDashboardScreen extends StatefulWidget {
  final String clubId;
  final String clubName;

  const ClubDashboardScreen({
    super.key,
    required this.clubId,
    required this.clubName,
  });

  @override
  State<ClubDashboardScreen> createState() => _ClubDashboardScreenState();
}

class _ClubDashboardScreenState extends State<ClubDashboardScreen> with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  late TabController _tabController;
  
  // Dashboard Stats
  int _totalEvents = 0;
  int _totalFollowers = 0;
  int _activeStaff = 0;
  final double _avgRating = 4.9;
  String _businessType = 'club';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadDashboardData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _supabase.from('events').select('id').eq('organizer_id', widget.clubId).count(CountOption.exact),
        _supabase.from('follows').select('id').eq('organizer_id', widget.clubId).count(CountOption.exact),
        _supabase.from('staff_assignments').select('id').eq('organizer_id', widget.clubId).eq('status', 'active').count(CountOption.exact),
      ]).timeout(const Duration(seconds: 10));

      _totalEvents = results[0].count;
      _totalFollowers = results[1].count;
      _activeStaff = results[2].count;

      // 4. Fetch business type
      final org = await _supabase.from('organizer_profiles').select('business_type').eq('id', widget.clubId).maybeSingle();
      if (org != null) {
        _businessType = org['business_type']?.toString() ?? 'club';
      }
    } catch (e) {
      debugPrint('Error loading dashboard: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          // Tactical Background
          Positioned(
            top: -100, 
            left: -100, 
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
              child: Container(
                width: 400, 
                height: 400, 
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.03), 
                  shape: BoxShape.circle
                )
              ),
            ),
          ),
          
          if (_isLoading)
            const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          else
          NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              _buildHeader(),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12),
                  child: _buildMainStats(),
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _SliverTabDelegate(
                  TabBar(
                    controller: _tabController,
                    indicatorColor: AppTheme.primary,
                    unselectedLabelColor: Colors.white24,
                    labelColor: AppTheme.primary,
                    labelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2),
                    tabs: [
                      Tab(text: 'INSIGHTS'.tr),
                      Tab(text: 'STUDIO'.tr),
                      Tab(text: 'PUBLISH'.tr),
                    ],
                  ),
                ),
              ),
            ],
            body: TabBarView(
              controller: _tabController,
              children: [
                _buildInsightsView(),
                _buildStudioView(),
                EventCreationWidget(clubId: widget.clubId, onCreated: () {
                  _tabController.animateTo(0);
                  _loadDashboardData();
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsightsView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('OPERATIONAL DOMAINS'.tr),
          const SizedBox(height: 20),
          _buildDomainGrid(),
          const SizedBox(height: 40),
          _buildSectionTitle('INTEL FEED'.tr),
          const SizedBox(height: 20),
          _buildTacticalShortcuts(),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildStudioView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          const Icon(Icons.auto_fix_high_rounded, color: Colors.blueAccent, size: 48),
          const SizedBox(height: 24),
          Text('STUDIO_MODE'.tr, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 2)),
          const SizedBox(height: 12),
          Text('branding_desc'.tr, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white24, fontSize: 10)),
          const SizedBox(height: 48),
          _studioAction('EDIT_CLUB_BIO'.tr, Icons.short_text_rounded),
          const SizedBox(height: 12),
          _studioAction('UPDATE_GALLERY'.tr, Icons.photo_library_rounded),
          const SizedBox(height: 12),
          _studioAction('SET_LOCATION'.tr, Icons.location_on_rounded),
        ],
      ),
    );
  }

  Widget _studioAction(String title, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.02), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white.withValues(alpha: 0.05))),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.primary, size: 20),
          const SizedBox(width: 20),
          Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
          const Spacer(),
          const Icon(Icons.edit_rounded, color: Colors.white10, size: 14),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return SliverAppBar(
      expandedHeight: 180,
      backgroundColor: Colors.transparent,
      elevation: 0,
      pinned: true,
      flexibleSpace: FlexibleSpaceBar(
        background: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 40),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2))),
                child: Text('PRO-SUITE COMMAND CENTRE'.tr.toUpperCase(), style: const TextStyle(color: AppTheme.primary, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 3)),
              ),
              const SizedBox(height: 12),
              Text(widget.clubName.toUpperCase(), style: AppTheme.headlineStyle.copyWith(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -1)),
              const SizedBox(height: 4),
              _buildDashboardTypeBadge(),
              const SizedBox(height: 8),
              Text('ID: ${widget.clubId.substring(0, 8)}', style: const TextStyle(color: Colors.white24, fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDashboardTypeBadge() {
    String label = 'CLUB_BRAND'.tr;
    IconData icon = Icons.nightlife;
    if (_businessType == 'restaurant') {
      label = 'RESTAURANT_BRAND'.tr;
      icon = Icons.restaurant;
    } else if (_businessType == 'lounge') {
      label = 'LOUNGE_BRAND'.tr;
      icon = Icons.weekend;
    } else if (_businessType == 'cafe') {
      label = 'CAFE_BRAND'.tr;
      icon = Icons.coffee;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppTheme.primary, size: 10),
          const SizedBox(width: 8),
          Text(label.toUpperCase(), style: const TextStyle(color: AppTheme.primary, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1)),
        ],
      ),
    );
  }

  Widget _buildMainStats() {
    return Row(
      children: [
        _statBox('EVENTS'.tr, _totalEvents.toString(), Icons.event_available_rounded),
        const SizedBox(width: 12),
        _statBox('REACH'.tr, _totalFollowers.toString(), Icons.people_alt_rounded),
        const SizedBox(width: 12),
        _statBox('RATING'.tr, _avgRating.toString(), Icons.star_rounded),
      ],
    );
  }

  Widget _statBox(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppTheme.primary, size: 20),
            const SizedBox(height: 12),
            Text(value, style: AppTheme.headlineStyle.copyWith(fontSize: 24, fontWeight: FontWeight.w900)),
            Text(label, style: const TextStyle(color: Colors.white24, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(title, style: AppTheme.labelStyle.copyWith(color: AppTheme.primary, letterSpacing: 4, fontSize: 10));
  }

  Widget _buildDomainGrid() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: 1.2,
      children: [
        _domainCard('SECURITY_HUB'.tr, '$_activeStaff Active', Icons.security_rounded, AppTheme.secondary, () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => StaffManagementScreen(clubId: widget.clubId)));
        }),
        _domainCard('BRANDING'.tr, 'Edit Hub', Icons.auto_fix_high_rounded, Colors.purpleAccent, () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const ClubProfileEditorScreen()));
        }),
        _domainCard('LEDGER'.tr, 'Tactical Logs', Icons.history_edu_rounded, Colors.orangeAccent, () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => MasterOperationalLedgerScreen(organizerId: widget.clubId)));
        }),
        _domainCard('PUBLISH'.tr, 'New Experience', Icons.add_circle_outline_rounded, Colors.amber, () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => CreateEventScreen(clubId: widget.clubId, businessType: _businessType))).then((_) => _loadDashboardData());
        }),
      ],
    );
  }

  Widget _domainCard(String title, String subtitle, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: color.withValues(alpha: 0.1)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
            Text(subtitle, style: TextStyle(color: color.withValues(alpha: 0.5), fontSize: 9, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildTacticalShortcuts() {
    return Column(
      children: [
        _shortcutTile('MASTER OPERATIONAL LEDGER'.tr, 'The tactical flow of all event entries.'.tr, Colors.greenAccent),
        const SizedBox(height: 12),
        _shortcutTile('CLUB BRADING & IG VIBES'.tr, 'Maintain your professional hub appearance.'.tr, AppTheme.primary),
        const SizedBox(height: 12),
        _shortcutTile('GLOBAL LOCATION SETTINGS'.tr, 'GPS Localization for all cloud events.'.tr, Colors.white),
      ],
    );
  }

  Widget _shortcutTile(String title, String desc, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.03)),
      ),
      child: Row(
        children: [
          Container(width: 4, height: 40, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                Text(desc, style: const TextStyle(color: Colors.white24, fontSize: 10)),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white10, size: 14),
        ],
      ),
    );
  }

}

class _SliverTabDelegate extends SliverPersistentHeaderDelegate {
  _SliverTabDelegate(this._tabBar);
  final TabBar _tabBar;

  @override
  double get minExtent => _tabBar.preferredSize.height + 20;
  @override
  double get maxExtent => _tabBar.preferredSize.height + 20;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: AppTheme.background,
      child: _tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverTabDelegate oldDelegate) => false;
}

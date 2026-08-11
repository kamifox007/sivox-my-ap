import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/services/translation_service.dart';
import 'package:my_app/screens/club_profile_editor.dart';
import 'package:my_app/screens/staff_management_screen.dart';
import 'package:my_app/models/club.dart';


class ClubManagementHubScreen extends StatefulWidget {
  final String? clubId;
  const ClubManagementHubScreen({super.key, this.clubId});

  @override
  State<ClubManagementHubScreen> createState() =>
      _ClubManagementHubScreenState();
}

class _ClubManagementHubScreenState extends State<ClubManagementHubScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  Club? _club;
  Map<String, int> _staffStats = {'managers': 0, 'security': 0};

  @override
  void initState() {
    super.initState();
    _loadHubData();
  }

  Future<void> _loadHubData() async {
    setState(() => _isLoading = true);
    final targetId = widget.clubId ?? _supabase.auth.currentUser?.id;
    if (targetId == null) return;

    try {
      // 1. Fetch Club Data (from organizer_profiles)
      final orgRes = await _supabase
          .from('organizer_profiles')
          .select('*, profiles(full_name)')
          .eq('id', targetId)
          .maybeSingle();

      if (orgRes != null) {
        final mergedData = Map<String, dynamic>.from(orgRes);
        mergedData['name'] = orgRes['name'] ?? orgRes['profiles']?['full_name'] ?? 'Club';
        _club = Club.fromMap(mergedData);
      }

      // 2. Fetch Staff Stats
      final staffRes = await _supabase
          .from('staff_assignments')
          .select('role')
          .eq('organizer_id', targetId);
      final staffList = staffRes as List;
      _staffStats = {
        'managers': staffList.where((s) => s['role'] == 'role_manager').length,
        'security': staffList.where((s) => s['role'] == 'role_security').length,
      };
    } catch (e) {
      debugPrint('Error loading hub: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'CLUB_HUB'.tr.toUpperCase(),
          style: AppTheme.headlineStyle.copyWith(
            fontSize: 16,
            letterSpacing: 3,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: Colors.white,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_note_rounded, color: AppTheme.primary),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ClubProfileEditorScreen(clubId: widget.clubId),
              ),
            ).then((_) => _loadHubData()),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            )
          : _club == null
          ? _buildInitializationState()
          : _buildHubContent(),
    );
  }

  Widget _buildInitializationState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.business_rounded, color: Colors.white10, size: 80),
          const SizedBox(height: 24),
          Text(
            'NO_CLUB_IDENTITY'.tr,
            style: const TextStyle(color: Colors.white24),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ClubProfileEditorScreen(isNew: true),
              ),
            ).then((_) => _loadHubData()),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.black,
            ),
            child: Text('CREATE_CLUB_IDENTITY'.tr),
          ),
        ],
      ),
    );
  }

  Widget _buildHubContent() {
    return Stack(
      children: [
        // Decorative Glows
        Positioned(
          top: -100,
          left: -100,
          child: _glow(AppTheme.primary.withValues(alpha: 0.05)),
        ),
        Positioned(
          bottom: -150,
          right: -100,
          child: _glow(AppTheme.secondary.withValues(alpha: 0.05)),
        ),

        SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 140, 24, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildIdentityCard(),
              const SizedBox(height: 32),
              _buildSectionHeader('INSTITUTIONAL_SITE'.tr),
              _buildSiteMapTile(),
              const SizedBox(height: 32),
              _buildSectionHeader('STAFF_Roster'.tr),
              _buildStaffRosterRow(),
              const SizedBox(height: 32),
              _buildSectionHeader('BRANDING_STORAGE'.tr),
              _buildBrandingGallery(),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildIdentityCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(24),
              image: _club!.permanentGallery.isNotEmpty
                  ? DecorationImage(
                      image: NetworkImage(_club!.permanentGallery[0]),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: _club!.permanentGallery.isEmpty
                ? const Icon(Icons.business, color: Colors.white24, size: 32)
                : null,
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _club!.name,
                  style: AppTheme.headlineStyle.copyWith(fontSize: 22),
                ),
                const SizedBox(height: 4),
                Text(
                  _club!.bio ?? 'INSTITUTIONAL_IDENTITY'.tr,
                  style: const TextStyle(color: Colors.white24, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSiteMapTile() {
    return Container(
      height: 200,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white10),
        image: const DecorationImage(
          image: AssetImage(
            'assets/images/map_placeholder.png',
          ), // Placeholder or static map
          fit: BoxFit.cover,
          opacity: 0.3,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: Stack(
          alignment: Alignment.center,
          children: [
              Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.location_on_rounded, color: AppTheme.primary, size: 36),
                ),
              ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
                ),
              ),
            ),
            Positioned(
              bottom: 20,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ClubProfileEditorScreen(clubId: widget.clubId),
                  ),
                ).then((_) => _loadHubData()),
                icon: const Icon(Icons.map_rounded, size: 16),
                label: Text(
                  'UPDATE_PERMANENT_SITE'.tr.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStaffRosterRow() {
    return Row(
      children: [
        Expanded(
          child: _staffActionCard(
            Icons.admin_panel_settings_rounded,
            'MANAGERS'.tr,
            '${_staffStats['managers']}',
            AppTheme.secondary,
            () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const StaffManagementScreen(),
                ),
              ).then((_) => _loadHubData());
            },
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _staffActionCard(
            Icons.security_rounded,
            'SECURITY'.tr,
            '${_staffStats['security']}',
            Colors.white70,
            () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => StaffManagementScreen(clubId: widget.clubId),
                ),
              ).then((_) => _loadHubData());
            },
          ),
        ),
      ],
    );
  }

  Widget _staffActionCard(
    IconData icon,
    String label,
    String count,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: color.withValues(alpha: 0.1)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 16),
            Text(count, style: AppTheme.headlineStyle.copyWith(fontSize: 24)),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                color: color.withValues(alpha: 0.6),
                fontSize: 8,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBrandingGallery() {
    return SizedBox(
      height: 100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: 5,
        itemBuilder: (ctx, idx) {
          final hasImg = idx < _club!.permanentGallery.length;
          return Container(
            width: 100,
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.02),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              image: hasImg
                  ? DecorationImage(
                      image: NetworkImage(_club!.permanentGallery[idx]),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: !hasImg
                ? const Icon(
                    Icons.add_photo_alternate_outlined,
                    color: Colors.white10,
                    size: 20,
                  )
                : null,
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20, left: 4),
      child: Text(
        title,
        style: AppTheme.labelStyle.copyWith(
          letterSpacing: 2,
          fontSize: 11,
          color: AppTheme.primary,
        ),
      ),
    );
  }

  Widget _glow(Color color) => Container(
    width: 300,
    height: 300,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: color,
      boxShadow: [BoxShadow(color: color, blurRadius: 100, spreadRadius: 50)],
    ),
  );
}

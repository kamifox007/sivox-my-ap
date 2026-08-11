import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/services/performance_service.dart';
import 'package:my_app/services/translation_service.dart';
import 'package:my_app/screens/organizer_main_wrapper.dart';
import 'package:my_app/screens/club_profile_editor.dart';
import 'package:my_app/services/staff_service.dart';

class AccountSelectorScreen extends StatefulWidget {
  const AccountSelectorScreen({super.key});

  @override
  State<AccountSelectorScreen> createState() => _AccountSelectorScreenState();
}

class _AccountSelectorScreenState extends State<AccountSelectorScreen> {
  final _supabase = Supabase.instance.client;
  late Future<List<Map<String, dynamic>>> _accountsFuture;

  @override
  void initState() {
    super.initState();
    _accountsFuture = _fetchAccounts();
    _checkPendingInvites();
  }

  Future<void> _checkPendingInvites() async {
    final accounts = await _accountsFuture;
    final invite = accounts.firstWhere((a) => a['identity_type'] == 'INVITE', orElse: () => {});
    if (invite.isNotEmpty && mounted) {
      _showInvitationModal(invite);
    }
  }

  Future<List<Map<String, dynamic>>> _fetchAccounts() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return [];

    try {
      // 1. Fetch Owned Clubs
      final ownerRes = await _supabase
          .from('organizer_profiles')
          .select('*, profiles(full_name, avatar_url)')
          .eq('owner_id', userId);

      List<Map<String, dynamic>> owned = [];
      for (var row in (ownerRes as List)) {
        final profile = row['profiles'];
        owned.add({
          'id': row['id'],
          'name': row['name'] ?? (profile is Map ? profile['full_name'] : null) ?? 'Club Identity',
          'bio': row['bio'] ?? '',
          'avatar_url': row['avatar_url'] ?? (profile is Map ? profile['avatar_url'] : null),
          'identity_type': 'OWNER',
          'business_type': row['business_type'] ?? 'club',
        });
      }

      // 2. Fetch Staff Missions & Transitions
      final staffRes = await _supabase
          .from('staff_assignments')
          .select('*, organizer_profiles(name, avatar_url, business_type, profiles(full_name, avatar_url))')
          .eq('staff_id', userId)
          .or('status.eq.active,status.eq.pending');

      List<Map<String, dynamic>> missions = [];
      for (var s in (staffRes as List)) {
        final clubProfile = s['organizer_profiles'];
        final clubId = s['organizer_id'] ?? '';
        final status = s['status'];
        
        missions.add({
          'id': clubId,
          'name': clubProfile?['name'] ?? clubProfile?['profiles']?['full_name'] ?? 'Club Identity',
          'bio': status == 'pending' ? 'JOIN_REQUEST'.tr : 'ACTIVE_MISSION'.tr,
          'avatar_url': clubProfile?['avatar_url'] ?? clubProfile?['profiles']?['avatar_url'],
          'identity_type': status == 'pending' ? 'INVITE' : 'STAFF',
          'role': s['role'] ?? 'Staff',
          'assignment_id': s['id'],
          'status': s['status'],
          'business_type': clubProfile?['business_type'] ?? 'club',
        });
      }

      // Merge avoiding duplicates
      final seenIds = <String>{};
      final List<Map<String, dynamic>> finalAccounts = [...owned];
      for (var a in finalAccounts) {
        seenIds.add(a['id']);
      }
      
      for (var m in missions) {
        if (!seenIds.contains(m['id'])) {
          finalAccounts.add(m);
          seenIds.add(m['id']);
        }
      }

      return finalAccounts;
    } catch (e) {
      debugPrint('Error fetching accounts: $e');
      return [];
    }
  }

  void _refresh() {
    setState(() {
      _accountsFuture = _fetchAccounts();
    });
  }

  bool _isAssistantView = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          if (PerformanceService.useBlur)
            Positioned(
              top: -100,
              right: -100,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
                child: Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    color: (_isAssistantView ? AppTheme.secondary : AppTheme.primary).withValues(alpha: 0.05),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _accountsFuture,
            builder: (fbContext, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
              }

              final allItems = snapshot.data ?? [];
              final accounts = allItems.where((a) {
                if (_isAssistantView) return a['identity_type'] == 'STAFF' || a['identity_type'] == 'INVITE';
                return a['identity_type'] == 'OWNER';
              }).toList();

              return CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  _buildSlimAppBar(),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('management_console'.tr.toUpperCase(), style: AppTheme.labelStyle.copyWith(color: _isAssistantView ? AppTheme.secondary : AppTheme.primary, letterSpacing: 4, fontSize: 10)),
                          const SizedBox(height: 12),
                          
                          // NAVIGATION TABS
                          Row(
                            children: [
                              // 1. My Clubs Tab
                              _buildHubButton(
                                label: 'YOUR_CLUBS'.tr,
                                sub: 'manage_properties'.tr,
                                icon: Icons.business_center_rounded,
                                color: AppTheme.primary,
                                isSelected: !_isAssistantView,
                                onTap: () => setState(() => _isAssistantView = false),
                              ),
                              const SizedBox(width: 12),
                              // 2. Assistant / Missions Tab
                              _buildHubButton(
                                label: 'ASSISTANTS'.tr,
                                sub: 'discover_missions'.tr,
                                icon: Icons.assignment_ind_rounded,
                                color: AppTheme.secondary,
                                isSelected: _isAssistantView,
                                onTap: () => setState(() => _isAssistantView = true),
                              ),
                            ],
                          ),
                          
                          const SizedBox(height: 16),
                          
                          // ACTION BUTTON: Create New Club
                          if (!_isAssistantView)
                            _portalActionBtn(
                              label: 'NEW_CLUB'.tr.toUpperCase(),
                              icon: Icons.add_business_rounded,
                              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ClubProfileEditorScreen(isNew: true))).then((_) => _refresh()),
                            ),
                          
                          const SizedBox(height: 32),
                          if (accounts.isNotEmpty)
                             Text((_isAssistantView ? 'ACTIVE_MISSIONS' : 'YOUR_CLUBS').tr.toUpperCase(), style: AppTheme.labelStyle.copyWith(color: Colors.white24, letterSpacing: 2, fontSize: 10)),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ),
                  if (accounts.isEmpty)
                    SliverToBoxAdapter(child: _buildEmptyState())
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => _buildPremiumAccountCard(accounts[index]),
                          childCount: accounts.length,
                        ),
                      ),
                    ),
                  
                  // Removed redundant 'Add' button below list as it's now in the header

                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8),
                      child: _buildIdentityDiscoveryButton(),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 100)),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHubButton({
    required String label, 
    required String sub, 
    required IconData icon, 
    required Color color, 
    required bool isSelected, 
    required VoidCallback onTap
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          height: 100,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: isSelected ? color.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.05)),
            boxShadow: [
              if (isSelected) BoxShadow(color: color.withValues(alpha: 0.1), blurRadius: 20, spreadRadius: -5),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: isSelected ? color : Colors.white24, size: 24),
              const SizedBox(height: 12),
              Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.white38, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1)),
              Text(sub, style: TextStyle(color: isSelected ? color.withValues(alpha: 0.6) : Colors.white10, fontSize: 8, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSlimAppBar() {
    return SliverAppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      leadingWidth: 80,
      leading: Center(
        child: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.primary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      title: Text('EXIT_TO_CITIZEN'.tr.toUpperCase(), style: AppTheme.labelStyle.copyWith(fontSize: 9, color: Colors.white24, letterSpacing: 2)),
      centerTitle: false,
      actions: [
        IconButton(icon: const Icon(Icons.refresh, color: Colors.white38), onPressed: _refresh),
        const SizedBox(width: 20),
      ],
    );
  }



  Widget _buildPremiumAccountCard(Map<String, dynamic> account) {
    final isOwner = account['identity_type'] == 'OWNER';
    final isInvite = account['identity_type'] == 'INVITE';

    return GestureDetector(
      onTap: () {
        if (isInvite) {
          _showInvitationModal(account);
        } else {
          OrganizerMainWrapper.of(context)?.selectClub(
            account['id'], 
            account['name'], 
            role: account['identity_type'] == 'OWNER' ? 'OWNER' : 'STAFF',
            businessType: account['business_type'] ?? 'club'
          );
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: isInvite ? 0.12 : 0.08),
              Colors.white.withValues(alpha: 0.03),
            ],
          ),
          boxShadow: [
            BoxShadow(color: (isInvite ? AppTheme.secondary : Colors.black).withValues(alpha: 0.2), blurRadius: 20, offset: const Offset(0, 10)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Row(
                children: [
                   // CLUB LOGO HUB
                  Hero(
                    tag: 'club_avatar_${account['id']}',
                    child: Container(
                      width: 70, height: 70,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: isOwner ? AppTheme.primary : AppTheme.secondary, width: 2),
                        image: account['avatar_url'] != null ? DecorationImage(image: NetworkImage(account['avatar_url']), fit: BoxFit.cover) : null,
                      ),
                      child: account['avatar_url'] == null ? Icon(Icons.nightlife, color: isOwner ? AppTheme.primary : AppTheme.secondary, size: 24) : null,
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: (isOwner ? AppTheme.primary : AppTheme.secondary).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: (isOwner ? AppTheme.primary : AppTheme.secondary).withValues(alpha: 0.2)),
                              ),
                              child: Text(
                                (isOwner ? 'OWNER' : 'STAFF').tr.toUpperCase(),
                                style: TextStyle(color: isOwner ? AppTheme.primary : AppTheme.secondary, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1.5),
                              ),
                            ),
                            if (!isOwner) ...[
                              const SizedBox(width: 8),
                              Text(account['role']?.toString().toUpperCase() ?? '', style: const TextStyle(color: Colors.white38, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 1)),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(account['name']?.toUpperCase() ?? 'CLUB IDENTITY', style: AppTheme.headlineStyle.copyWith(fontSize: 18, letterSpacing: -0.5, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 4),
                        Text(account['bio'] ?? '', style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 10, height: 1.2), maxLines: 2, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  const Icon(Icons.keyboard_arrow_right_rounded, color: AppTheme.primary, size: 28),
                  if (!isOwner && !isInvite) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.tune_rounded, color: AppTheme.secondary, size: 22),
                      onPressed: () => _showMissionOptions(account),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showMissionOptions(Map<String, dynamic> account) {
    final assignmentId = account['assignment_id'];
    if (assignmentId == null) return;

    final isAbsent = account['status'] == 'absent';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF141414).withValues(alpha: 0.95),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 32),
              Text(account['name']?.toString().toUpperCase() ?? '', style: AppTheme.headlineStyle.copyWith(fontSize: 18)),
              Text(account['role']?.toString().toUpperCase() ?? 'STAFF', style: const TextStyle(color: AppTheme.secondary, letterSpacing: 2, fontSize: 10, fontWeight: FontWeight.bold)),
              const SizedBox(height: 32),
              
              // ABSENCE TOGGLE
              ListTile(
                leading: Icon(isAbsent ? Icons.check_circle : Icons.person_off_rounded, color: isAbsent ? Colors.greenAccent : Colors.amber),
                title: Text(isAbsent ? 'status_return_active'.tr : 'REPORT_ABSENCE'.tr, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: Text(isAbsent ? 'You are currently marked as absent' : 'Signal your unavailability for this session', style: const TextStyle(color: Colors.white24, fontSize: 11)),
                onTap: () async {
                  final navigator = Navigator.of(ctx);
                  final success = await StaffService().toggleAbsence(assignmentId, !isAbsent);
                  if (success && mounted) {
                    navigator.pop();
                    _refresh();
                  }
                },
              ),
              const Divider(color: Colors.white10),
              
              // RESIGNATION
              ListTile(
                 leading: const Icon(Icons.exit_to_app_rounded, color: Colors.redAccent),
                 title: Text('RESIGN_FROM_CLUB'.tr, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                 subtitle: const Text('Remove yourself from this club\'s staff list permanently', style: TextStyle(color: Colors.white24, fontSize: 11)),
                 onTap: () => _confirmResignation(assignmentId, account['name'] ?? 'Club'),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmResignation(String assignmentId, String clubName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141414),
        title: Text('RESIGN'.tr),
        content: Text('mission_reject_desc'.trArgs([clubName])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('cancel'.tr, style: const TextStyle(color: Colors.white24))),
          TextButton(
            onPressed: () async {
              final navigator = Navigator.of(ctx);
              final parentNavigator = Navigator.of(context);
              final success = await StaffService().resignFromClub(assignmentId);
              if (success && mounted) {
                navigator.pop(); // Close dialog
                parentNavigator.pop(); // Close bottom sheet
                _refresh();
              }
            },
            child: Text('confirm'.tr, style: const TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  Widget _buildIdentityDiscoveryButton() {
    bool isScanning = false;
    return StatefulBuilder(
      builder: (ctx, setLocalState) => GestureDetector(
        onTap: () async {
          setLocalState(() => isScanning = true);
          await Future.delayed(const Duration(seconds: 2)); // Simulate deep scan
          if (mounted) {
            setLocalState(() => isScanning = false);
            _refresh();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('ASSIGNMENTS_SYNCED'.tr),
                backgroundColor: AppTheme.secondary,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 500),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isScanning ? AppTheme.secondary.withValues(alpha: 0.05) : AppTheme.secondary.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: isScanning ? AppTheme.secondary : AppTheme.secondary.withValues(alpha: 0.1)),
          ),
          child: Row(
            children: [
              isScanning 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.secondary))
                : const Icon(Icons.help_center_outlined, color: AppTheme.secondary, size: 20),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(isScanning ? 'SEARCHING_MISSIONS...'.tr : 'identity_discovery_title'.tr.toUpperCase(), style: const TextStyle(color: AppTheme.secondary, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 1)),
                    const SizedBox(height: 4),
                    Text(isScanning ? 'CHECKING_STAFF_LEDGER'.tr : 'did_you_forget_desc'.tr, style: const TextStyle(color: Colors.white24, fontSize: 10)),
                  ],
                ),
              ),
              if (!isScanning) const Icon(Icons.flash_on_rounded, color: AppTheme.secondary, size: 16),
            ],
          ),
        ),
      ),
    );
  }



  void _showInvitationModal(Map<String, dynamic> invite) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(40),
              border: Border.all(color: AppTheme.secondary.withValues(alpha: 0.2)),
              boxShadow: [
                BoxShadow(color: AppTheme.secondary.withValues(alpha: 0.15), blurRadius: 40, spreadRadius: 10)
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(color: AppTheme.secondary.withValues(alpha: 0.1), shape: BoxShape.circle),
                      child: const Icon(Icons.mark_email_unread_rounded, color: AppTheme.secondary, size: 40),
                    ),
                    const SizedBox(height: 24),
                    Text('NEW_INVITATION'.tr.toUpperCase(), style: AppTheme.labelStyle.copyWith(color: AppTheme.secondary, letterSpacing: 4, fontSize: 10)),
                    const SizedBox(height: 12),
                    Text(invite['name'] ?? 'Club Identity', style: AppTheme.headlineStyle.copyWith(fontSize: 24, fontWeight: FontWeight.w900), textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    Text('invitation_to_join'.trArgs([invite['role'] ?? 'Staff']), style: const TextStyle(color: Colors.white60, fontSize: 14), textAlign: TextAlign.center),
                    const SizedBox(height: 32),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () async {
                              final navigator = Navigator.of(ctx);
                              final success = await StaffService().rejectAssignment(invite['assignment_id']);
                              if (success && mounted) {
                                navigator.pop();
                                _refresh();
                              }
                            },
                            child: Text('REJECT'.tr, style: const TextStyle(color: Colors.white24, fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              final navigator = Navigator.of(ctx);
                              final success = await StaffService().acceptAssignment(invite['assignment_id']);
                              if (success && mounted) {
                                navigator.pop();
                                _refresh();
                                if (mounted) {
                                  OrganizerMainWrapper.of(context)?.selectClub(invite['id'], invite['name'], role: 'STAFF');
                                }
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.secondary,
                              foregroundColor: Colors.black,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            child: Text('ACCEPT'.tr, style: const TextStyle(fontWeight: FontWeight.w900)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
     return Center(
       child: Column(
         children: [
           const SizedBox(height: 80),
           Icon(_isAssistantView ? Icons.assignment_late_rounded : Icons.auto_awesome_motion_rounded, size: 60, color: Colors.white.withValues(alpha: 0.05)),
           const SizedBox(height: 20),
           Text((_isAssistantView ? 'no_missions_found' : 'no_clubs_found').tr, style: const TextStyle(color: Colors.white24, fontSize: 12, letterSpacing: 1)),
         ],
       ),
     );
  }

  Widget _portalActionBtn({required String label, required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppTheme.primary, size: 20),
            const SizedBox(width: 12),
            Text(label, style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1)),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:my_app/theme/app_theme.dart';
// ignore: unused_import
import 'package:my_app/services/translation_service.dart';
import 'package:my_app/services/staff_service.dart';
import 'package:my_app/screens/organizer_main_wrapper.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:ui';

class StaffInvitationsScreen extends StatefulWidget {
  const StaffInvitationsScreen({super.key});

  @override
  State<StaffInvitationsScreen> createState() => _StaffInvitationsScreenState();
}

class _StaffInvitationsScreenState extends State<StaffInvitationsScreen> {
  final _staffService = StaffService();
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _invitations = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadInvitations();
  }

  Future<void> _loadInvitations() async {
    setState(() => _isLoading = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      final response = await _supabase
          .from('staff_assignments')
          .select('*, organizer_profiles(bio, profiles(full_name, avatar_url))')
          .eq('staff_id', userId)
          .eq('status', 'pending');

      setState(() {
        _invitations = (response as List).map((res) {
          final clubProfile = res['organizer_profiles'];
          return {
            'id': res['id'],
            'role': res['role'] ?? 'Staff',
            'club_name': clubProfile?['profiles']?['full_name'] ?? 'Official Club',
            'avatar_url': clubProfile?['profiles']?['avatar_url'],
            'bio': clubProfile?['bio'] ?? '',
            'organizer_id': res['organizer_id'] ?? clubProfile?['id'],
          };
        }).toList();
      });
    } catch (e) {
      debugPrint('Error loading invitations: $e');
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
          // Tactical Glow (Fixed: Removed filter from BoxDecoration)
          Positioned(
            top: -150, 
            right: -150, 
            child: Container(
              width: 400, 
              height: 400, 
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.secondary.withValues(alpha: 0.15),
                    blurRadius: 100,
                    spreadRadius: 50,
                  ),
                ],
              ),
            ),
          ),

          CustomScrollView(
            slivers: [
              _buildAppBar(),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'mission_control'.tr.toUpperCase(),
                        style: AppTheme.labelStyle.copyWith(
                          color: AppTheme.secondary,
                          letterSpacing: 4,
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'pending_invites'.tr,
                        style: AppTheme.headlineStyle.copyWith(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_isLoading)
                const SliverFillRemaining(
                  child: Center(
                    child: CircularProgressIndicator(color: AppTheme.secondary),
                  ),
                )
              else if (_invitations.isEmpty)
                SliverFillRemaining(child: _buildEmptyState())
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _buildInvitationCard(_invitations[index]),
                      childCount: _invitations.length,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.close_rounded, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
    );
  }

  Widget _buildInvitationCard(Map<String, dynamic> invite) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: AppTheme.secondary.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: AppTheme.surface,
                  backgroundImage: invite['avatar_url'] != null ? NetworkImage(invite['avatar_url']) : null,
                  child: invite['avatar_url'] == null ? const Icon(Icons.nightlife, color: AppTheme.secondary) : null,
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.secondary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          invite['role'].toString().toUpperCase(),
                          style: const TextStyle(
                            color: AppTheme.secondary,
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        invite['club_name'],
                        style: AppTheme.headlineStyle.copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white10, height: 1),
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => _handleAction(invite, false),
                    style: TextButton.styleFrom(foregroundColor: Colors.white38),
                    child: Text(
                      'reject'.tr.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _handleAction(invite, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.secondary,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(
                      'ACCEPT'.tr.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _handleAction(Map<String, dynamic> invite, bool accept) {
    showDialog(
      context: context,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AlertDialog(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
          title: Text(
            accept ? 'CONFIRM_MISSION'.tr : 'REJECT_MISSION'.tr,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
          ),
          content: Text(
            accept
                ? 'mission_accept_desc'.trArgs([invite['role'], invite['club_name']])
                : 'mission_reject_desc'.trArgs([invite['club_name']]),
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('CANCEL'.tr, style: const TextStyle(color: Colors.white24)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final res = accept 
                   ? await _staffService.acceptAssignment(invite['id'])
                   : await _staffService.rejectAssignment(invite['id']);

                if (res && mounted) {
                  if (accept) {
                    _handleRedirection(invite);
                  } else {
                    _loadInvitations();
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: accept ? AppTheme.secondary : Colors.redAccent,
              ),
              child: Text(
                accept ? 'PROCEED'.tr : 'CONFIRM'.tr,
                style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleRedirection(Map<String, dynamic> invite) {
    // Strategic Routing
    final role = invite['role'].toString().toLowerCase();

    // Switch Identity
    OrganizerMainWrapper.of(context)?.selectClub(invite['organizer_id'], invite['club_name']);

    // Manual Push to specific interface if needed
    if (role == 'security' || role == 'scanner') {
      Navigator.pushReplacementNamed(context, '/scanner');
    } else {
      Navigator.pop(context); // Go back to dashboard through wrapper selectClub
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.mail_outline_rounded,
            size: 64,
            color: AppTheme.secondary.withValues(alpha: 0.1),
          ),
          const SizedBox(height: 24),
          Text(
            'no_pending_mission'.tr,
            style: const TextStyle(color: Colors.white24, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

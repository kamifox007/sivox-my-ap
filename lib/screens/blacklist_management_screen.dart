import 'package:flutter/material.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/services/enforcement_service.dart';
import 'package:my_app/services/translation_service.dart';
import 'package:my_app/services/audit_service.dart';
import 'dart:ui';

class BlacklistManagementScreen extends StatefulWidget {
  final String clubId;
  const BlacklistManagementScreen({super.key, required this.clubId});

  @override
  State<BlacklistManagementScreen> createState() => _BlacklistManagementScreenState();
}

class _BlacklistManagementScreenState extends State<BlacklistManagementScreen> {
  final _enforcementService = EnforcementService();
  final _auditService = AuditService();
  bool _isLoading = true;
  List<Map<String, dynamic>> _blacklist = [];

  @override
  void initState() {
    super.initState();
    _loadBlacklist();
  }

  Future<void> _loadBlacklist() async {
    setState(() => _isLoading = true);
    final list = await _enforcementService.getBlacklist(widget.clubId);
    if (mounted) {
      setState(() {
        _blacklist = list;
        _isLoading = false;
      });
    }
  }

  Future<void> _pardonUser(Map<String, dynamic> entry) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text('PARDON_USER'.tr, style: const TextStyle(color: Colors.white)),
        content: Text('PARDON_CONFIRM_DESC'.tr, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('CANCEL'.tr)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('CONFIRM_PARDON'.tr, style: const TextStyle(color: AppTheme.primary)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await _enforcementService.removeFromBlacklist(entry['id']);
      if (success) {
        await _auditService.logAction(
          actionType: 'SECURITY_PARDON',
          description: 'User ${entry['profiles']?['full_name'] ?? entry['phone_number']} removed from blacklist.',
          relatedEventId: null,
        );
        _loadBlacklist();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          _buildBackground(),
          CustomScrollView(
            slivers: [
              _buildAppBar(),
              if (_isLoading)
                const SliverFillRemaining(child: Center(child: CircularProgressIndicator(color: Colors.redAccent)))
              else if (_blacklist.isEmpty)
                _buildEmptyState()
              else
                SliverPadding(
                  padding: const EdgeInsets.all(24),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) => _buildBlacklistCard(_blacklist[i]),
                      childCount: _blacklist.length,
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
      pinned: true,
      backgroundColor: AppTheme.background.withValues(alpha: 0.8),
      expandedHeight: 120,
      centerTitle: true,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
        onPressed: () => Navigator.pop(context),
      ),
      flexibleSpace: FlexibleSpaceBar(
        title: Text('THE_VAULT'.tr.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 4, color: Colors.redAccent)),
        background: ClipRRect(child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10), child: Container(color: Colors.transparent))),
      ),
    );
  }

  Widget _buildBlacklistCard(Map<String, dynamic> entry) {
    final profile = entry['profiles'] ?? {};
    final name = profile['full_name'] ?? entry['phone_number'] ?? 'Unknown Member';
    final reason = entry['reason'] ?? 'Security Policy';
    final date = DateTime.tryParse(entry['created_at'] ?? '');

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: Colors.redAccent.withValues(alpha: 0.1),
            backgroundImage: profile['avatar_url'] != null ? NetworkImage(profile['avatar_url']) : null,
            child: profile['avatar_url'] == null ? const Icon(Icons.person_off_rounded, color: Colors.redAccent, size: 20) : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 4),
                Text(reason, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                if (date != null) ...[
                  const SizedBox(height: 8),
                  Text('BANNED_ON'.trArgs([date.toLocal().toString().substring(0, 10)]), style: const TextStyle(color: Colors.white10, fontSize: 9, fontWeight: FontWeight.bold)),
                ],
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.verified_user_rounded, color: Colors.greenAccent, size: 22),
            tooltip: 'REMOVE_BAN'.tr,
            onPressed: () => _pardonUser(entry),
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
            const Icon(Icons.shield_outlined, color: Colors.white10, size: 64),
            const SizedBox(height: 24),
            Text('VAULT_EMPTY'.tr, style: const TextStyle(color: Colors.white24, fontSize: 12, letterSpacing: 2)),
          ],
        ),
      ),
    );
  }

  Widget _buildBackground() {
    return Positioned.fill(
      child: Stack(
        children: [
          Positioned(top: 100, left: -100, child: _glow(Colors.redAccent.withValues(alpha: 0.05))),
        ],
      ),
    );
  }

  Widget _glow(Color color) => Container(
    width: 300, height: 300,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color, boxShadow: [BoxShadow(color: color, blurRadius: 100, spreadRadius: 50)]),
  );
}

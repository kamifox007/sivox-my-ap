import 'package:flutter/material.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/services/translation_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AudienceScreen extends StatefulWidget {
  final String organizerId;
  const AudienceScreen({super.key, required this.organizerId});

  @override
  State<AudienceScreen> createState() => _AudienceScreenState();
}

class _AudienceScreenState extends State<AudienceScreen> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _followers = [];

  @override
  void initState() {
    super.initState();
    _fetchFollowers();
  }

  Future<void> _fetchFollowers() async {
    setState(() => _isLoading = true);
    try {
      // Robust join logic
      final response = await supabase
          .from('follows')
          .select('user_id, profiles!inner(full_name, avatar_url, phone_number)')
          .eq('organizer_id', widget.organizerId);

      if (mounted) {
        setState(() {
          _followers = (response as List).map((f) {
            final p = f['profiles'] as Map<String, dynamic>?;
            return {
              'id': f['user_id'],
              'name': p?['full_name'] ?? 'Visitor'.tr,
              'avatar': p?['avatar_url'],
              'phone': p?['phone_number'],
            };
          }).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Followers Fetch Error: $e');
      // Fallback if profiles!inner fails due to missing profile
      try {
         final simpleRes = await supabase.from('follows').select('user_id').eq('organizer_id', widget.organizerId);
         if (mounted) {
           setState(() {
             _followers = (simpleRes as List).map((f) => {'id': f['user_id'], 'name': 'Anonymous Member'.tr}).toList();
             _isLoading = false;
           });
         }
      } catch (_) {
         if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  void _showHelp(String title, String desc) {
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
            const Icon(Icons.lightbulb_outline_rounded, color: AppTheme.primary, size: 32),
            const SizedBox(height: 16),
            Text(title.toUpperCase(), style: AppTheme.headlineStyle.copyWith(fontSize: 18)),
            const SizedBox(height: 12),
            Text(desc, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.5)),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('FAN_BASE'.tr.toUpperCase(), style: AppTheme.headlineStyle.copyWith(fontSize: 16)),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _showHelp('FAN_BASE'.tr, 'HELPER_AUDIENCE_DESC'.tr),
              child: Tooltip(
                message: 'MORE_INFO'.tr,
                child: const Icon(Icons.help_outline_rounded, color: Colors.white24, size: 10),
              ),
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
        : _followers.isEmpty
          ? _buildEmptyState()
          : _buildFollowersList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.favorite_border_rounded, color: Colors.white10, size: 80),
          const SizedBox(height: 24),
          Text('no_followers_yet'.tr, style: const TextStyle(color: Colors.white24, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildFollowersList() {
    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: _followers.length,
      itemBuilder: (context, index) {
        final f = _followers[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            leading: CircleAvatar(
              radius: 24,
              backgroundImage: f['avatar'] != null ? NetworkImage(f['avatar']) : null,
              backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
              child: f['avatar'] == null ? const Icon(Icons.person_rounded, color: AppTheme.primary) : null,
            ),
            title: Text(f['name'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
            subtitle: Text(f['phone'] ?? 'Verified Member', style: const TextStyle(color: Colors.white24, fontSize: 11)),
            trailing: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.05), shape: BoxShape.circle),
              child: const Icon(Icons.verified_rounded, color: AppTheme.primary, size: 16),
            ),
          )
        );
      },
    );
  }
}

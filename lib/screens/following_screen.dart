import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/services/follow_service.dart';
import 'package:my_app/services/translation_service.dart';

class FollowingScreen extends StatefulWidget {
  const FollowingScreen({super.key});

  @override
  State<FollowingScreen> createState() => _FollowingScreenState();
}

class _FollowingScreenState extends State<FollowingScreen> {
  final _followService = FollowService();
  bool _isLoading = true;
  List<String> _followedOrganizers = [];

  @override
  void initState() {
    super.initState();
    _loadFollowing();
  }

  Future<void> _loadFollowing() async {
    setState(() => _isLoading = true);
    try {
      final list = await _followService.getFollowedOrganizers();
      if (mounted) {
        setState(() {
          _followedOrganizers = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _unfollow(String id) async {
    final success = await _followService.toggleFollow(id);
    if (success) {
      setState(() => _followedOrganizers.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          // Background Glows for Aura
          Positioned(top: -100, left: -100, child: _aura(AppTheme.primary)),
          Positioned(bottom: -100, right: -100, child: _aura(AppTheme.secondary)),

          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              _buildAppBar(context),
              if (_isLoading)
                const SliverFillRemaining(child: Center(child: CircularProgressIndicator(color: AppTheme.primary)))
              else if (_followedOrganizers.isEmpty)
                _buildEmptyState()
              else
                _buildList(),
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _aura(Color c) => Container(width: 300, height: 300, decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: c.withValues(alpha: 0.08), blurRadius: 150)]));

  Widget _buildAppBar(BuildContext context) {
    return SliverAppBar(
      backgroundColor: Colors.transparent,
      pinned: true,
      elevation: 0,
      centerTitle: true,
      leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18), onPressed: () => Navigator.pop(context)),
      title: Text('Following'.tr.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 4)),
      flexibleSpace: ClipRRect(child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10), child: Container(color: Colors.transparent))),
    );
  }

  Widget _buildList() {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => _buildOrganizerCard(_followedOrganizers[index]),
          childCount: _followedOrganizers.length,
        ),
      ),
    );
  }

  Widget _buildOrganizerCard(String id) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Row(
              children: [
                _avatar(id),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ORGANIZER'.tr, style: TextStyle(color: AppTheme.primary, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 1)),
                      const SizedBox(height: 4),
                      Text('Club Elite'.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1)),
                      const Text('Official Partner', style: TextStyle(color: Colors.white24, fontSize: 10)),
                    ],
                  ),
                ),
                _unfollowBtn(id),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _avatar(String id) {
    return Container(
      width: 56, height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
        image: const DecorationImage(image: NetworkImage('https://images.unsplash.com/photo-1549490349-8643362247b5?q=80&w=2574'), fit: BoxFit.cover),
      ),
    );
  }

  Widget _unfollowBtn(String id) {
    return GestureDetector(
      onTap: () => _unfollow(id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)), borderRadius: BorderRadius.circular(12)),
        child: const Text('UNFOLLOW', style: TextStyle(color: Colors.redAccent, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1)),
      ),
    );
  }

  Widget _buildEmptyState() {
    return SliverFillRemaining(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 80, color: Colors.white10),
            const SizedBox(height: 24),
            Text('No followed organizers yet.'.tr.toUpperCase(), style: const TextStyle(color: Colors.white24, fontSize: 12, letterSpacing: 2)),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: const Text('EXPLORE CLUBS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
            ),
          ],
        ),
      ),
    );
  }
}

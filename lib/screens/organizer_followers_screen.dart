import 'package:flutter/material.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/services/follow_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OrganizerFollowersScreen extends StatefulWidget {
  const OrganizerFollowersScreen({super.key});

  @override
  State<OrganizerFollowersScreen> createState() => _OrganizerFollowersScreenState();
}

class _OrganizerFollowersScreenState extends State<OrganizerFollowersScreen> {
  final _followService = FollowService();
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _followers = [];

  @override
  void initState() {
    super.initState();
    _loadFollowers();
  }

  Future<void> _loadFollowers() async {
    setState(() => _isLoading = true);
    try {
      final organizerId = _supabase.auth.currentUser?.id;
      if (organizerId == null) return;

      final followerIds = await _followService.getFollowers(organizerId);
      
      // Fetch user details for these IDs from profiles or profiles mock
      // For this implementation, we will mock the profiles based on IDs
      setState(() {
        _followers = followerIds.map((id) => {
          'id': id,
          'name': 'Nocturnal User',
          'avatar': 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?q=80&w=200',
        }).toList();
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('MY AUDIENCE', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 2)),
        centerTitle: true,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
        : _followers.isEmpty
            ? _buildEmpty()
            : _buildFollowersList(),
    );
  }

  Widget _buildEmpty() {
    return const Center(child: Text('No followers yet.', style: TextStyle(color: Colors.white24)));
  }

  Widget _buildFollowersList() {
    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: _followers.length,
      itemBuilder: (context, index) {
        final f = _followers[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(20)),
          child: Row(
            children: [
              CircleAvatar(backgroundImage: NetworkImage(f['avatar'])),
              const SizedBox(width: 16),
              Expanded(child: Text('${f['id'].toString().substring(0, 12)}...', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
              const Icon(Icons.verified_user, color: AppTheme.primary, size: 14),
            ],
          ),
        );
      },
    );
  }
}

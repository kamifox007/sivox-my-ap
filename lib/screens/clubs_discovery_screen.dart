import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/services/translation_service.dart';
import 'package:my_app/services/follow_service.dart';
import 'package:my_app/screens/club_profile.dart';
import 'package:cached_network_image/cached_network_image.dart';

class ClubsDiscoveryScreen extends StatefulWidget {
  const ClubsDiscoveryScreen({super.key});

  @override
  State<ClubsDiscoveryScreen> createState() => _ClubsDiscoveryScreenState();
}

class _ClubsDiscoveryScreenState extends State<ClubsDiscoveryScreen> {
  final supabase = Supabase.instance.client;
  final _followService = FollowService();
  List<dynamic> _allClubs = [];
  List<String> _followedIds = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      final clubs = await supabase.from('organizer_profiles').select('*, profiles(full_name, avatar_url)');
      final followed = await _followService.getFollowedOrganizers();
      
      if (mounted) {
        setState(() {
          _allClubs = clubs as List;
          _followedIds = followed;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleFollow(String orgId) async {
    final isFollowing = _followedIds.contains(orgId);
    bool success;
    if (isFollowing) {
      success = await _followService.unfollowOrganizer(orgId);
      if (success) setState(() => _followedIds.remove(orgId));
    } else {
      success = await _followService.followOrganizer(orgId);
      if (success) setState(() => _followedIds.add(orgId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _allClubs.where((c) {
      final name = (c['name'] ?? c['profiles']?['full_name'] ?? '').toString().toLowerCase();
      return name.contains(_searchQuery.toLowerCase());
    }).toList();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('EXPLORE_CLUBS'.tr.toUpperCase(), style: AppTheme.labelStyle.copyWith(letterSpacing: 2)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'search_club_hint'.tr,
                hintStyle: const TextStyle(color: Colors.white24),
                prefixIcon: const Icon(Icons.search, color: AppTheme.primary),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
              : filtered.isEmpty 
                ? Center(child: Text('NO_CLUBS_FOUND'.tr, style: const TextStyle(color: Colors.white24)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      final club = filtered[i];
                      final id = club['id'].toString();
                      final isFollowing = _followedIds.contains(id);
                      final name = club['name'] ?? club['profiles']?['full_name'] ?? 'Club';
                      final avatar = club['avatar_url'] ?? club['profiles']?['avatar_url'];
                      final type = club['business_type'] ?? 'club';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                        ),
                        child: Row(
                          children: [
                            GestureDetector(
                              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ClubProfileScreen(organizerId: id, organizerName: name))),
                              child: CircleAvatar(
                                radius: 30,
                                backgroundColor: AppTheme.surfaceContainer,
                                backgroundImage: avatar != null ? CachedNetworkImageProvider(avatar) : null,
                                child: avatar == null ? const Icon(Icons.nightlife, color: AppTheme.primary) : null,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ClubProfileScreen(organizerId: id, organizerName: name))),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(name.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                                    const SizedBox(height: 4),
                                    Text(type.toString().toUpperCase(), style: const TextStyle(color: AppTheme.primary, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1)),
                                  ],
                                ),
                              ),
                            ),
                            ElevatedButton(
                              onPressed: () => _toggleFollow(id),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isFollowing ? Colors.transparent : AppTheme.primary,
                                foregroundColor: isFollowing ? Colors.white : Colors.black,
                                elevation: 0,
                                side: isFollowing ? const BorderSide(color: Colors.white24) : null,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                              ),
                              child: Text(isFollowing ? 'FOLLOWING'.tr : 'FOLLOW'.tr, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

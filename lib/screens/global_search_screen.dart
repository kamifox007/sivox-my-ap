import 'package:flutter/material.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/models/event.dart';
import 'package:my_app/screens/club_profile_viewer.dart';
import 'package:my_app/screens/event_details.dart';
import 'package:my_app/screens/map_discovery.dart';
import 'package:my_app/services/translation_service.dart';
import 'package:cached_network_image/cached_network_image.dart';

class GlobalSearchScreen extends StatefulWidget {
  final List<dynamic> allClubs;
  final List<Event>? allEvents;

  const GlobalSearchScreen({
    super.key,
    required this.allClubs,
    required this.allEvents,
  });

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> _filteredClubs = [];
  List<Event> _filteredEvents = [];
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
  }

  void _onSearchChanged(String query) {
    if (query.isEmpty) {
      setState(() {
        _filteredClubs = [];
        _filteredEvents = [];
      });
      return;
    }

    final lowerQuery = query.toLowerCase();

    setState(() {
      _filteredClubs = widget.allClubs.where((c) {
        final name = (c['name'] ?? c['profiles']?['full_name'] ?? '').toString().toLowerCase();
        return name.contains(lowerQuery);
      }).toList();

      if (widget.allEvents != null) {
        _filteredEvents = widget.allEvents!.where((e) {
          final title = e.title.toLowerCase();
          final venue = (e.venue ?? "").toLowerCase();
          return title.contains(lowerQuery) || venue.contains(lowerQuery);
        }).toList();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Widget _glow(Color color) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Container(
          width: 300,
          height: 300,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.15 + (_pulseController.value * 0.1)),
                blurRadius: 100,
                spreadRadius: 20,
              )
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          Positioned(top: -100, right: -100, child: _glow(AppTheme.primary)),
          Positioned(bottom: -150, left: -150, child: _glow(AppTheme.secondary)),
          
          SafeArea(
            child: Column(
              children: [
                _buildSearchHeader(),
                Expanded(
                  child: _searchController.text.isEmpty
                      ? _buildEmptyState()
                      : _buildResults(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      decoration: BoxDecoration(
        color: AppTheme.background.withValues(alpha: 0.8),
        border: const Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Hero(
              tag: 'search_bar_hero',
              child: Container(
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(color: AppTheme.primary.withValues(alpha: 0.5)),
                  boxShadow: [
                    BoxShadow(color: AppTheme.primary.withValues(alpha: 0.1), blurRadius: 15, spreadRadius: -5)
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: TextField(
                    controller: _searchController,
                    autofocus: true,
                    onChanged: _onSearchChanged,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    decoration: InputDecoration(
                      hintText: 'search_hint'.tr,
                      hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
                      prefixIcon: IconButton(
                        icon: const Icon(Icons.map_rounded, color: AppTheme.primary, size: 20),
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MapDiscoveryScreen())),
                      ),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_searchController.text.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 20),
                              onPressed: () {
                                _searchController.clear();
                                _onSearchChanged('');
                              },
                            ),
                        ],
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.search_rounded, color: AppTheme.primary, size: 48),
          ),
          const SizedBox(height: 24),
          Text('explore_the_city'.tr, style: AppTheme.headlineStyle.copyWith(fontSize: 22)),
          const SizedBox(height: 12),
          Text('search_hint'.tr, style: const TextStyle(color: Colors.white38, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildResults() {
    if (_filteredClubs.isEmpty && _filteredEvents.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.location_off_rounded, color: Colors.white24, size: 48),
            const SizedBox(height: 16),
            Text('NO_RESULTS_FOUND'.tr, style: const TextStyle(color: Colors.white54, fontSize: 16)),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(24),
      physics: const BouncingScrollPhysics(),
      children: [
        if (_filteredClubs.isNotEmpty) ...[
          Row(
            children: [
              const Icon(Icons.nightlife_rounded, color: AppTheme.secondary, size: 18),
              const SizedBox(width: 8),
              Text('CLUBS_FOUND'.tr.toUpperCase(), style: AppTheme.labelStyle.copyWith(letterSpacing: 2, color: AppTheme.secondary, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 16),
          ..._filteredClubs.asMap().entries.map((entry) {
            final idx = entry.key;
            final club = entry.value;
            final name = (club['name'] ?? club['profiles']?['full_name'] ?? 'Club').toString();
            final avatar = club['avatar_url'] as String?;
            final bType = (club['business_type'] ?? 'club').toString().toUpperCase();

            return GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ClubProfileViewer(
                      followedClubs: _filteredClubs,
                      initialIndex: idx,
                    ),
                  ),
                );
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: AppTheme.primary.withValues(alpha: 0.2),
                      backgroundImage: avatar != null ? CachedNetworkImageProvider(avatar) : null,
                      child: avatar == null ? const Icon(Icons.nightlife, color: AppTheme.primary, size: 24) : null,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 0.5)),
                          const SizedBox(height: 4),
                          Text(bType, style: const TextStyle(color: AppTheme.primary, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: Colors.white24),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 32),
        ],

        if (_filteredEvents.isNotEmpty) ...[
          Row(
            children: [
              const Icon(Icons.event_rounded, color: AppTheme.primary, size: 18),
              const SizedBox(width: 8),
              Text('EVENTS_FOUND'.tr.toUpperCase(), style: AppTheme.labelStyle.copyWith(letterSpacing: 2, color: AppTheme.primary, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 16),
          ..._filteredEvents.map((event) {
            return GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EventDetailsScreen(event: event),
                  ),
                );
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), bottomLeft: Radius.circular(24)),
                        image: event.imageUrl != null
                            ? DecorationImage(image: CachedNetworkImageProvider(event.imageUrl!), fit: BoxFit.cover)
                            : null,
                        color: AppTheme.primary.withValues(alpha: 0.2),
                      ),
                      child: event.imageUrl == null ? const Icon(Icons.event, color: AppTheme.primary, size: 32) : null,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(event.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(Icons.location_on_rounded, color: AppTheme.secondary, size: 12),
                                const SizedBox(width: 4),
                                Expanded(child: Text(event.venue ?? '', style: const TextStyle(color: Colors.white54, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(right: 16),
                      child: Icon(Icons.chevron_right_rounded, color: Colors.white24),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ],
    );
  }
}

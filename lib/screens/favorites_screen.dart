import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/screens/event_details.dart';
import 'package:my_app/models/event.dart';
import 'package:my_app/services/event_service.dart';
import 'package:my_app/services/favorite_service.dart';
import 'package:my_app/services/translation_service.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  final _favoriteService = FavoriteService();
  final _eventService = EventService();
  bool _isLoading = true;
  List<Event> _faveEvents = [];

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    setState(() => _isLoading = true);
    try {
      final faveIds = await _favoriteService.getFavoriteEventIds();
      final allEvents = await _eventService.getAllEvents();
      
      if (mounted) {
        setState(() {
          _faveEvents = allEvents.where((e) => faveIds.contains(e.id)).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          // Background Glow
          Positioned(top: -50, left: -50, child: Container(width: 250, height: 250, decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: AppTheme.primary.withValues(alpha: 0.15), blurRadius: 80)]))),
          
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              _buildAppBar(),
              if (_isLoading)
                const SliverFillRemaining(child: Center(child: CircularProgressIndicator(color: AppTheme.primary)))
              else if (_faveEvents.isEmpty)
                _buildEmptyState()
              else
                _buildGrid(),
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      backgroundColor: AppTheme.background.withValues(alpha: 0.8),
      floating: true,
      pinned: true,
      expandedHeight: 120,
      centerTitle: false,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.only(left: 60, bottom: 16),
        title: Text('MY WISHLIST'.tr, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 2, color: AppTheme.primary)),
      ),
    );
  }

  Widget _buildGrid() {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => _buildFaveCard(_faveEvents[index]),
          childCount: _faveEvents.length,
        ),
      ),
    );
  }

  Widget _buildFaveCard(Event e) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: GestureDetector(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EventDetailsScreen(event: e))),
        child: Container(
          height: 180,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            image: DecorationImage(image: NetworkImage(e.imageUrl ?? ''), fit: BoxFit.cover),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 10, spreadRadius: -2),
            ],
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.8)],
                  ),
                ),
              ),
              Positioned(
                bottom: 16, left: 16, right: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                     Text(e.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16), maxLines: 2, overflow: TextOverflow.ellipsis),
                     const SizedBox(height: 4),
                     Text(e.venue ?? '', style: const TextStyle(color: AppTheme.primary, fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              Positioned(
                top: 12, right: 12,
                child: GestureDetector(
                  onTap: () async {
                    // Optimistic Update!
                    setState(() {
                      _faveEvents.remove(e);
                    });
                    await _favoriteService.toggleFavorite(e);
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), shape: BoxShape.circle),
                        child: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent, size: 20),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return SliverFillRemaining(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.favorite_border, size: 80, color: Colors.white.withValues(alpha: 0.1)),
          const SizedBox(height: 24),
          Text('Nothing here yet'.tr, style: const TextStyle(color: Colors.white38, fontSize: 18)),
          const SizedBox(height: 12),
          Text('Explore and save your favorite events'.tr, style: const TextStyle(color: Colors.white24, fontSize: 12)),
        ],
      ),
    );
  }
}

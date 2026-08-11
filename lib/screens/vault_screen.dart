import 'package:flutter/material.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/services/translation_service.dart';
import 'package:my_app/services/booking_service.dart';
import 'package:my_app/models/booking.dart';
import 'package:my_app/services/favorite_service.dart';
import 'package:my_app/services/interaction_service.dart';
import 'package:my_app/services/event_service.dart';
import 'package:my_app/models/event.dart';
import 'package:my_app/screens/event_details.dart';
import 'package:my_app/screens/ticket.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:ui';

class VaultScreen extends StatefulWidget {
  final int initialIndex;
  const VaultScreen({super.key, this.initialIndex = 0});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _bookingService = BookingService();
  final _favoriteService = FavoriteService();
  final _interactionService = InteractionService();
  final _eventService = EventService();

  bool _isLoading = true;
  List<Booking> _bookings = [];
  List<Event> _favorites = [];
  List<Event> _likes = [];
  List<Map<String, dynamic>> _shares = [];
  List<Event> _allEvents = [];

  @override
  void initState() {
    super.initState();
    // 6 Tabs: ALL, PASSES, FAVORITES, LIKES, SHARES, GIFTS
    _tabController = TabController(length: 6, vsync: this, initialIndex: widget.initialIndex + 1);
    _loadVaultData();
  }

  Future<void> _loadVaultData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final results = await Future.wait([
        _eventService.getAllEvents(),
        _bookingService.getUserBookings(),
        _favoriteService.getFavoriteEventIds(),
        _interactionService.getLikes(),
        _interactionService.getShares(),
      ]);

      _allEvents = results[0] as List<Event>;
      _bookings = results[1] as List<Booking>;
      final faveIds = results[2] as List<String>;
      final likesData = results[3] as List<Map<String, dynamic>>;
      _shares = results[4] as List<Map<String, dynamic>>;

      _favorites = _allEvents.where((e) => faveIds.contains(e.id)).toList();
      final likeIds = likesData.map((l) => l['event_id'].toString()).toList();
      _likes = _allEvents.where((e) => likeIds.contains(e.id)).toList();

      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading vault: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          // PREMIUM BACKGROUND AMBIENT
          Positioned(
            top: -150,
            right: -100,
            child: _glow(AppTheme.primary.withValues(alpha: 0.08)),
          ),
          Positioned(
            bottom: -150,
            left: -100,
            child: _glow(AppTheme.secondary.withValues(alpha: 0.08)),
          ),

          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              _buildAppBar(),
              _buildTabs(),
              if (user == null)
                SliverToBoxAdapter(child: _buildGuestPrompt())
              else if (_isLoading)
                const SliverFillRemaining(child: Center(child: CircularProgressIndicator(color: AppTheme.primary)))
              else
                SliverFillRemaining(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildAllHistoryList(),
                      _buildBookingsList(),
                      _buildFavoritesList(),
                      _buildLikesList(),
                      _buildSharesList(),
                      _buildGiftsList(),
                    ],
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
      elevation: 0,
      expandedHeight: 120,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
        onPressed: () => Navigator.pop(context),
      ),
      flexibleSpace: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: FlexibleSpaceBar(
            titlePadding: const EdgeInsets.only(left: 60, bottom: 16),
            title: Text(
              'THE_VAULT'.tr.toUpperCase(),
              style: const TextStyle(
                color: AppTheme.primary,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 4,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabs() {
    return SliverPersistentHeader(
      pinned: true,
      delegate: _SliverAppBarDelegate(
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              color: AppTheme.background.withValues(alpha: 0.7),
              child: TabBar(
                controller: _tabController,
                indicatorColor: AppTheme.primary,
                indicatorWeight: 3,
                dividerColor: Colors.white10,
                labelColor: AppTheme.primary,
                unselectedLabelColor: Colors.white24,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 1),
                tabs: [
                  Tab(text: 'ALL_ARCHIVE'.tr.toUpperCase()),
                  Tab(text: 'passes'.tr.toUpperCase()),
                  Tab(text: 'favorites'.tr.toUpperCase()),
                  Tab(text: 'LIKES'.tr.toUpperCase()),
                  Tab(text: 'SHARES'.tr.toUpperCase()),
                  Tab(text: 'GIFTS'.tr.toUpperCase()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGuestPrompt() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.1)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.auto_awesome_rounded, color: AppTheme.primary, size: 32),
            ),
            const SizedBox(height: 24),
            Text(
              'vault_guest_title'.tr,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18),
            ),
            const SizedBox(height: 12),
            Text(
              'vault_guest_subtitle'.tr,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white38, fontSize: 13, height: 1.6),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 64,
              child: ElevatedButton(
                onPressed: () => Navigator.pushNamed(context, '/login'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: Text('SIGN_UP'.tr.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAllHistoryList() {
    // Combine all and sort by date if possible
    // For now just show counts or a merged list
    if (_bookings.isEmpty && _favorites.isEmpty && _likes.isEmpty && _shares.isEmpty) {
      return _emptyState(Icons.archive_outlined, 'no_history_yet'.tr);
    }
    
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (_bookings.isNotEmpty) ...[
          _sectionHeader('PASSES'.tr, _bookings.length),
          ..._bookings.take(3).map((b) => _vaultCard(
            title: b.event?.title ?? 'Event',
            subtitle: b.paymentStatus.toUpperCase(),
            imageUrl: b.event?.imageUrl,
            icon: Icons.confirmation_number_rounded,
            color: AppTheme.primary,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TicketScreen(booking: b))),
          )),
          const SizedBox(height: 24),
        ],
        if (_favorites.isNotEmpty) ...[
          _sectionHeader('FAVORITES'.tr, _favorites.length),
          ..._favorites.take(3).map((e) => _vaultCard(
            title: e.title,
            subtitle: e.venue ?? 'Club',
            imageUrl: e.imageUrl,
            icon: Icons.favorite_rounded,
            color: Colors.redAccent,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EventDetailsScreen(event: e))),
          )),
          const SizedBox(height: 24),
        ],
        if (_likes.isNotEmpty) ...[
          _sectionHeader('LIKES'.tr, _likes.length),
          ..._likes.take(3).map((e) => _vaultCard(
            title: e.title,
            subtitle: e.venue ?? 'Club',
            imageUrl: e.imageUrl,
            icon: Icons.celebration_rounded,
            color: Colors.orangeAccent,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EventDetailsScreen(event: e))),
          )),
          const SizedBox(height: 24),
        ],
      ],
    );
  }

  Widget _sectionHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, left: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title.toUpperCase(), style: const TextStyle(color: Colors.white24, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(10)),
            child: Text(count.toString(), style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildBookingsList() {
    if (_bookings.isEmpty) return _emptyState(Icons.confirmation_number_outlined, 'no_passes_yet'.tr);
    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: _bookings.length,
      itemBuilder: (ctx, i) => _vaultCard(
        title: _bookings[i].event?.title ?? 'Event',
        subtitle: _bookings[i].paymentStatus.toUpperCase(),
        imageUrl: _bookings[i].event?.imageUrl,
        icon: Icons.qr_code_2_rounded,
        color: AppTheme.primary,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TicketScreen(booking: _bookings[i]))),
      ),
    );
  }

  Widget _buildFavoritesList() {
    if (_favorites.isEmpty) return _emptyState(Icons.favorite_border_rounded, 'no_favorites_yet'.tr);
    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: _favorites.length,
      itemBuilder: (ctx, i) => _vaultCard(
        title: _favorites[i].title,
        subtitle: _favorites[i].venue ?? 'Club',
        imageUrl: _favorites[i].imageUrl,
        icon: Icons.favorite,
        color: Colors.redAccent,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EventDetailsScreen(event: _favorites[i]))),
      ),
    );
  }

  Widget _buildLikesList() {
    if (_likes.isEmpty) return _emptyState(Icons.thumb_up_alt_outlined, 'no_likes_yet'.tr);
    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: _likes.length,
      itemBuilder: (ctx, i) => _vaultCard(
        title: _likes[i].title,
        subtitle: _likes[i].venue ?? 'Club',
        imageUrl: _likes[i].imageUrl,
        icon: Icons.celebration_rounded,
        color: Colors.orangeAccent,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EventDetailsScreen(event: _likes[i]))),
      ),
    );
  }

  Widget _buildSharesList() {
    if (_shares.isEmpty) return _emptyState(Icons.ios_share_rounded, 'no_shares_yet'.tr);
    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: _shares.length,
      itemBuilder: (ctx, i) {
        final eventId = _shares[i]['event_id'];
        final event = _allEvents.firstWhere((e) => e.id == eventId, orElse: () => Event(id: '', title: 'Unknown', price: 0));
        return _vaultCard(
          title: event.title,
          subtitle: 'Shared via ${_shares[i]['platform'] ?? 'Sivox'}',
          imageUrl: event.imageUrl,
          icon: Icons.link_rounded,
          color: AppTheme.secondary,
          onTap: event.id.isNotEmpty ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => EventDetailsScreen(event: event))) : null,
        );
      },
    );
  }

  Widget _buildGiftsList() {
    final giftBookings = _bookings.where((b) => b.appliedPerk != null && b.appliedPerk!.isNotEmpty).toList();
    if (giftBookings.isEmpty) return _emptyState(Icons.card_giftcard_rounded, 'no_gifts_yet'.tr);
    
    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: giftBookings.length,
      itemBuilder: (ctx, i) => _vaultCard(
        title: giftBookings[i].appliedPerk!,
        subtitle: giftBookings[i].event?.title ?? 'Event',
        imageUrl: giftBookings[i].event?.imageUrl,
        icon: Icons.card_giftcard_rounded,
        color: Colors.pinkAccent,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TicketScreen(booking: giftBookings[i]))),
      ),
    );
  }

  Widget _vaultCard({
    required String title,
    required String subtitle,
    String? imageUrl,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Row(
          children: [
            Container(
              width: 60, height: 60,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                image: imageUrl != null ? DecorationImage(image: NetworkImage(imageUrl), fit: BoxFit.cover) : null,
                color: Colors.white.withValues(alpha: 0.05),
              ),
              child: imageUrl == null ? const Icon(Icons.image_not_supported_outlined, color: Colors.white10) : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(IconData icon, String msg) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.white.withValues(alpha: 0.02)),
          const SizedBox(height: 24),
          Text(msg, style: const TextStyle(color: Colors.white24, fontSize: 14, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _glow(Color color) {
    return Container(
      width: 400, height: 400,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [BoxShadow(color: color, blurRadius: 200, spreadRadius: 50)],
      ),
    );
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverAppBarDelegate({required this.child});
  final Widget child;

  @override
  double get minExtent => 60;
  @override
  double get maxExtent => 60;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return child;
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) => false;
}

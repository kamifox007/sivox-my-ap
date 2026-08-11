import 'package:flutter/material.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/models/event.dart';
import 'package:my_app/services/booking_service.dart';
import 'package:my_app/screens/ticket.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:my_app/services/notification_service.dart';
import 'package:my_app/services/follow_service.dart';
import 'package:my_app/services/block_service.dart';
// ignore: unused_import
import 'package:my_app/services/translation_service.dart';
import 'package:my_app/services/localization_service.dart';
import 'package:my_app/models/booking.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:my_app/services/event_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:my_app/screens/event_manage_details.dart';
import 'package:my_app/services/favorite_service.dart';
import 'package:share_plus/share_plus.dart';
import 'package:my_app/screens/booking_success.dart';

import 'package:my_app/screens/club_profile.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:my_app/services/interaction_service.dart';
import 'package:my_app/screens/scan_entry.dart';
import 'dart:ui';
import 'package:my_app/screens/marketing_engine_screen.dart';
import 'package:my_app/screens/broadcast_screen.dart';

class EventDetailsScreen extends StatefulWidget {
  final Event event;
  final bool fromMap;
  const EventDetailsScreen({super.key, required this.event, this.fromMap = false});

  @override
  State<EventDetailsScreen> createState() => _EventDetailsScreenState();
}

class _EventDetailsScreenState extends State<EventDetailsScreen>
    with WidgetsBindingObserver {
  final _bookingService = BookingService();
  final _followService = FollowService();
  final _blockService = BlockService();
  final _favoriteService = FavoriteService();
  final _interactionService = InteractionService();

  int guestCount = 1;
  String selectedTier = 'Standard';
  bool isBooking = false;
  bool isFollowing = false;
  bool isFavorited = false;
  bool _isWaitingReturn = false;
  double? _distanceInKm;
  bool _isOwner = false;
  Booking? _existingBooking;
  int _likesCount = 0;
  bool _isLiked = false;
  int _pendingCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkFollowing();
    _checkFavorite();
    _initDistance();
    _checkOwnership();
    _checkExistingBooking();
    _fetchLikesData();
    _trackView();
    _fetchOrganizerProfile();
    _fetchPendingCount();
  }

  Future<void> _fetchPendingCount() async {
    try {
      final res = await Supabase.instance.client
          .from('bookings')
          .select('id')
          .eq('event_id', widget.event.id)
          .eq('payment_status', 'pending');
      if (mounted) setState(() => _pendingCount = (res as List).length);
    } catch (_) {}
  }

  double? fallbackLat;
  double? fallbackLng;
  String? fallbackVenue;
  String? fallbackPhone;

  Future<void> _fetchOrganizerProfile() async {
    try {
      if (widget.event.organizerId == null) return;
      final profile = await Supabase.instance.client
          .from('organizer_profiles')
          .select('latitude, longitude, location_address, contact_phone')
          .eq('id', widget.event.organizerId!)
          .maybeSingle();
      
      if (profile != null && mounted) {
        setState(() {
          fallbackLat = profile['latitude'];
          fallbackLng = profile['longitude'];
          fallbackVenue = profile['location_address'];
          fallbackPhone = profile['contact_phone'];
          // Recalculate distance with fallback if needed
          if (widget.event.latitude == null && fallbackLat != null) {
            _initDistance();
          }
        });
      }
    } catch (e) {
      debugPrint('Error fetching organizer profile: $e');
    }
  }

  Future<void> _fetchLikesData() async {
    final count = await _interactionService.getEventLikesCount(widget.event.id);
    final liked = await _interactionService.isEventLiked(widget.event.id);
    if (mounted) {
      setState(() {
        _likesCount = count;
        _isLiked = liked;
      });
    }
  }

  Future<void> _toggleLike() async {
    await _interactionService.toggleLike(widget.event.id);
    _fetchLikesData();
  }

  void _trackView() {
    EventService().incrementViewCount(widget.event.id);
  }

  Future<void> _checkFavorite() async {
    final list = await _favoriteService.getFavoriteEventIds();
    if (mounted) setState(() => isFavorited = list.contains(widget.event.id));
  }

  Future<void> _toggleFavorite() async {
    final res = await _favoriteService.toggleFavorite(widget.event);
    if (res) {
      if (mounted) {
        setState(() => isFavorited = res);
        _interactionService.recordLike(widget.event.id);
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('please_login_first'.tr),
            backgroundColor: AppTheme.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _checkOwnership() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null && user.id == widget.event.organizerId) {
      setState(() => _isOwner = true);
    }
  }

  Future<void> _initDistance() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        final pos = await Geolocator.getCurrentPosition();
        final lat = widget.event.latitude ?? fallbackLat;
        final lng = widget.event.longitude ?? fallbackLng;
        if (lat != null && lng != null) {
          final dist = Geolocator.distanceBetween(
            pos.latitude,
            pos.longitude,
            lat,
            lng,
          );
          if (mounted) setState(() => _distanceInKm = dist / 1000);
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _shareEvent() {
    _interactionService.recordShare(widget.event.id, platform: 'Native Share');
    SharePlus.instance.share(
      ShareParams(text: 'share_event_msg'.trArgs([widget.event.title, widget.event.id])),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isWaitingReturn) {
      _showWelcomeBack();
      setState(() => _isWaitingReturn = false);
    }
  }

  void _showWelcomeBack() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.celebration, color: AppTheme.primary, size: 20),
            const SizedBox(width: 12),
            Text(
              'welcome_back'.tr,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        backgroundColor: AppTheme.surface,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  Future<void> _checkFollowing() async {
    if (widget.event.organizerId != null) {
      final res = await _followService.isFollowing(widget.event.organizerId!);
      if (mounted) setState(() => isFollowing = res);
    }
  }

  Future<void> _checkExistingBooking() async {
    final bookings = await _bookingService.getUserBookings();
    final match = bookings.where((b) => b.eventId == widget.event.id).toList();
    if (match.isNotEmpty && mounted) {
      setState(() => _existingBooking = match.first);
    }
  }

  Future<void> _handleFollow() async {
    if (widget.event.organizerId != null) {
      final res = await _followService.toggleFollow(widget.event.organizerId!);
      if (mounted) setState(() => isFollowing = res);
    }
  }

  Future<void> _handleBooking() async {
    setState(() => isBooking = true);

    // Calculate final price based on tier logic
    double basePrice = widget.event.price;
    double multiplier = 1.0;
    if (selectedTier == 'VIP') multiplier = 1.75;
    if (selectedTier == 'Diamond') multiplier = 3.2;

    double tieredPrice = basePrice * multiplier;

    // Apply discounts
    double finalPrice = tieredPrice;
    
    // Global discount applies to everyone (Priority)
    if (widget.event.globalDiscount > 0) {
      finalPrice *= (1 - widget.event.globalDiscount / 100);
    }
    
    // Follower discount is separate or additive? 
    // In Sivox, if both exist, we apply both to reward loyal followers even during flash sales
    if (isFollowing && widget.event.followerDiscount > 0) {
      finalPrice *= (1 - widget.event.followerDiscount / 100);
    }

    if (widget.event.promoDiscount > 0) {
      finalPrice -= widget.event.promoDiscount;
    }
    
    final totalPrice = (finalPrice * guestCount).clamp(0.0, double.infinity);

    // Dynamic processing message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
            ),
            const SizedBox(width: 16),
            Text('PROCESSING_BOOKING'.tr, style: const TextStyle(fontSize: 12)),
          ],
        ),
        backgroundColor: const Color(0xFF1A1A1A),
        duration: const Duration(seconds: 2),
      ),
    );

    try {
      final booking = await _bookingService.createBooking(
        eventId: widget.event.id,
        numGuests: guestCount,
        ticketType: selectedTier,
        totalPricePaid: totalPrice,
        paymentStatus: 'pending',
      );

      if (mounted) {
        setState(() => isBooking = false);
        if (booking != null) {
          final ns = NotificationService();
          if (!widget.event.requireCallConfirmation) {
            await ns.sendMockNotification(
              'INSTANT_CONFIRM'.tr,
              '${'secured_spot'.tr} - ${selectedTier.toUpperCase()}',
            );
            if (!mounted || !context.mounted) return;
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => BookingSuccessScreen(booking: booking)),
            );
          } else {
            await ns.sendMockNotification(
              'REQUEST_SENT'.tr,
              'Your request for ${widget.event.title} is being reviewed.'.tr,
            );
            _showRequestSentSheet();
            if (widget.event.organizerId != null) {
              final userName = Supabase.instance.client.auth.currentUser
                      ?.userMetadata?['full_name'] ?? 'Guest';
              await ns.sendNotificationToUser(
                userId: widget.event.organizerId!,
                title: 'NEW_BOOKING_REQUEST'.tr,
                body: '$userName has requested $guestCount spots ($selectedTier) for ${widget.event.title}'.tr,
                type: 'booking_request',
                metadata: {'booking_id': booking.id},
              );
            }
          }
        }
      }
    } catch (e) {
      if (mounted && context.mounted) {
        setState(() => isBooking = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('err_booking'.tr), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  void _showRequestSentSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.mark_email_read_outlined,
              size: 80,
              color: AppTheme.secondary,
            ),
            const SizedBox(height: 24),
            Text(
              'REQUEST_SENT'.tr,
              style: AppTheme.headlineStyle.copyWith(fontSize: 24),
            ),
            const SizedBox(height: 12),
            Text(
              'REQUEST_QUEUED_DESC'.tr,
              textAlign: TextAlign.center,
              style: AppTheme.bodyStyle.copyWith(
                color: AppTheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 56),
                backgroundColor: AppTheme.secondary,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                'OK'.tr.toUpperCase(),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleOption(String choice) async {
    if (choice == 'Block') {
      if (widget.event.organizerId != null) {
        await _blockService.blockOrganizer(widget.event.organizerId!);
        if (mounted && context.mounted) Navigator.pop(context);
      }
    } else if (choice == 'Report') {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('report_sent'.tr)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
        slivers: [
          _buildSliverHeader(),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildOrganizerHeader(),
                  const SizedBox(height: 32),
                  
                  if (_isOwner) ...[
                    _buildOwnerManagementPanel(),
                    const SizedBox(height: 40),
                    _buildSectionDivider(),
                    const SizedBox(height: 40),
                  ],

                  if (widget.event.isUrgent) ...[
                    _buildUrgencyBanner(),
                    const SizedBox(height: 32),
                  ],

                  _buildEventBentoGrid(),
                  const SizedBox(height: 40),
                  _buildSectionDivider(),
                  const SizedBox(height: 40),

                  if (widget.event.followerDiscount > 0 || widget.event.followerPerk != null) ...[
                    _buildVipPerkSection(),
                    const SizedBox(height: 40),
                    _buildSectionDivider(),
                    const SizedBox(height: 40),
                  ],

                  _buildDescriptionSection(),
                  const SizedBox(height: 40),

                  _buildLocationCard(),
                  
                  if (widget.event.rules != null && widget.event.rules!.isNotEmpty) ...[
                    const SizedBox(height: 40),
                    _buildSectionDivider(),
                    const SizedBox(height: 40),
                    _buildRulesSection(),
                  ],
                  
                  const SizedBox(height: 120),
                ],
              ),
            ),
          ),
        ],
      ),
      _buildSideStrip(),
    ],
  ),
  bottomNavigationBar: _buildBottomBookingBar(),
);
  }

  Widget _buildSectionDivider() {
    return Container(
      height: 1,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.0),
            Colors.white.withValues(alpha: 0.05),
            Colors.white.withValues(alpha: 0.0),
          ],
        ),
      ),
    );
  }

  Widget _buildOwnerManagementPanel() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.primary.withValues(alpha: 0.1), Colors.transparent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.shield_rounded, color: AppTheme.primary, size: 20),
              const SizedBox(width: 12),
              Text(
                'OWNER_CONTROLS'.tr.toUpperCase(),
                style: const TextStyle(color: AppTheme.primary, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 2),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _buildManagementTile(Icons.confirmation_number_rounded, 'APPROVED'.tr, () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => EventManageDetailsScreen(event: widget.event)));
                }, value: '${widget.event.totalBookedCount}'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildManagementTile(Icons.hourglass_bottom_rounded, 'PENDING'.tr, () {
                   Navigator.push(context, MaterialPageRoute(builder: (_) => EventManageDetailsScreen(event: widget.event, showRequestsInitially: true)));
                }, value: '$_pendingCount', highlight: _pendingCount > 0), 
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildManagementTile(Icons.qr_code_scanner_rounded, 'SCAN'.tr, () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => ScanEntryScreen(organizerId: widget.event.organizerId, eventId: widget.event.id)));
                }, value: 'Entry'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EventManageDetailsScreen(event: widget.event))),
            icon: const Icon(Icons.settings_suggest_rounded, size: 18),
            label: Text('OPEN_TACTICAL_OPS'.tr.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.black,
              minimumSize: const Size.fromHeight(56),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ],
      ),
    );
  }

  void _showQuickStats(String title, String value) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(title.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(value, style: const TextStyle(color: AppTheme.primary, fontSize: 48, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text('LIVE_DATA'.tr, style: const TextStyle(color: Colors.white24, fontSize: 10)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('close'.tr),
          ),
        ],
      ),
    );
  }

  Widget _buildManagementTile(IconData icon, String label, VoidCallback onTap, {String? value, bool highlight = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: highlight ? Colors.orangeAccent.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: highlight ? Colors.orangeAccent.withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.05)),
          boxShadow: highlight ? [BoxShadow(color: Colors.orangeAccent.withValues(alpha: 0.15), blurRadius: 12)] : [],
        ),
        child: Column(
          children: [
            Icon(icon, color: highlight ? Colors.orangeAccent : AppTheme.primary, size: 24),
            const SizedBox(height: 8),
            Text(label, textAlign: TextAlign.center, style: TextStyle(color: highlight ? Colors.orangeAccent.withValues(alpha: 0.8) : Colors.white54, fontSize: 9, fontWeight: FontWeight.bold)),
            if (value != null) ...[
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(value, style: TextStyle(color: highlight ? Colors.orangeAccent : Colors.white, fontSize: 14, fontWeight: FontWeight.w900)),
                  if (highlight) ...[
                    const SizedBox(width: 4),
                    Container(width: 6, height: 6, decoration: const BoxDecoration(color: Colors.orangeAccent, shape: BoxShape.circle)),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLocationCard() {
    final lat = widget.event.latitude ?? fallbackLat;
    final lng = widget.event.longitude ?? fallbackLng;
    final venue = widget.event.venue ?? fallbackVenue;

    if (lat == null || lng == null) {
      return const SizedBox.shrink();
    }

    // Using a reliable static map provider that looks professional
    final staticMapUrl = 'https://static-maps.yandex.ru/1.x/?ll=$lng,$lat&z=13&l=map&size=600,300&pt=$lng,$lat,pm2rdl';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'VENUE_LOCATION'.tr.toUpperCase(),
              style: AppTheme.labelStyle.copyWith(
                letterSpacing: 2,
                fontSize: 10,
                color: AppTheme.primary,
              ),
            ),
            if (_distanceInKm != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${_distanceInKm!.toStringAsFixed(1)} KM AWAY',
                  style: const TextStyle(
                    color: AppTheme.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: _openMap,
          child: Container(
            height: 220,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 40,
                  offset: const Offset(0, 20),
                )
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(32),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // STATIC MAP IMAGE
                  CachedNetworkImage(
                    imageUrl: staticMapUrl,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      color: const Color(0xFF151515),
                      child: const Center(child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2)),
                    ),
                    errorWidget: (context, url, error) => Container(
                      color: const Color(0xFF151515),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                           const Icon(Icons.map_outlined, color: Colors.white24, size: 40),
                           const SizedBox(height: 12),
                           Text('MAP_PREVIEW'.tr, style: const TextStyle(color: Colors.white24, fontSize: 10)),
                        ],
                      ),
                    ),
                  ),
                  
                  // VIGNETTE & OVERLAY
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.3),
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.7),
                        ],
                      ),
                    ),
                  ),

                  // MARKETPLACE STYLE PIN OVERLAY
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppTheme.primary.withValues(alpha: 0.2),
                                boxShadow: [
                                  BoxShadow(color: AppTheme.primary.withValues(alpha: 0.3), blurRadius: 20, spreadRadius: 2),
                                ],
                              ),
                            ),
                            const Icon(Icons.location_on_rounded, color: AppTheme.primary, size: 40),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Text(
                            venue?.toUpperCase() ?? 'EVENT_VENUE'.tr,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // NAVIGATION HINT
                  Positioned(
                    bottom: 0, left: 0, right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.8)],
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.near_me_rounded, color: AppTheme.primary, size: 14),
                          const SizedBox(width: 8),
                          Text(
                            'CLICK_TO_NAVIGATE'.tr.toUpperCase(),
                            style: const TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.5),
                          ),
                          const Spacer(),
                          const Icon(Icons.open_in_new_rounded, color: Colors.white38, size: 12),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _bentoBox(
    IconData icon,
    String label,
    String value, {
    int flex = 1,
    VoidCallback? onTap,
    Color? highlightColor,
  }) {
    return Expanded(
      flex: flex,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: highlightColor?.withValues(alpha: 0.3) ?? Colors.white.withValues(alpha: 0.05),
              width: highlightColor != null ? 1.5 : 1,
            ),
            boxShadow: [
              if (highlightColor != null)
                BoxShadow(
                  color: highlightColor.withValues(alpha: 0.1),
                  blurRadius: 20,
                  spreadRadius: -5,
                ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (highlightColor ?? AppTheme.primary).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: highlightColor ?? AppTheme.primary, size: 14),
              ),
              const SizedBox(height: 20),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white24,
                  fontSize: 7,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: TextStyle(
                  color: highlightColor ?? Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  letterSpacing: 0.5,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openMap() {
    if (widget.event.latitude == null || widget.event.longitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('location_not_set'.tr),
          backgroundColor: Colors.orangeAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(32),
        decoration: const BoxDecoration(
          color: Color(0xFF161616),
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 24),
            Text('CHOOSE_NAVIGATION'.tr.toUpperCase(), style: AppTheme.labelStyle),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _navOption('Google Maps', Icons.map_rounded, Colors.greenAccent, () => _launchNav('google')),
                _navOption('Waze', Icons.navigation_rounded, Colors.blueAccent, () => _launchNav('waze')),
                if (Theme.of(context).platform == TargetPlatform.iOS)
                  _navOption('Apple Maps', Icons.apple_rounded, Colors.white, () => _launchNav('apple')),
              ],
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _navOption(String name, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withValues(alpha: 0.2)),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 12),
          Text(name, style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  void _launchNav(String type) async {
    final lat = widget.event.latitude;
    final lng = widget.event.longitude;
    Uri url;

    if (type == 'waze') {
      url = Uri.parse('waze://?ll=$lat,$lng&navigate=yes');
    } else if (type == 'apple') {
      url = Uri.parse('maps://?q=$lat,$lng');
    } else {
      url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    }

    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else if (type == 'google') {
      // Fallback for google maps in browser if app not installed
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('app_not_installed'.tr)));
    }
  }



  Widget _buildOrganizerHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.015),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.03)),
      ),
      child: Row(
        children: [
          _organizerAvatar(),
          const SizedBox(width: 16),
          Expanded(child: _organizerInfo()),
          _followActionButton(),
        ],
      ),
    );
  }

  Widget _organizerAvatar() {
    final avatar = widget.event.organizerAvatar;
    return GestureDetector(
      onTap: () => widget.event.organizerId != null ? _showQuickClubPeek() : null,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppTheme.surface,
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3), width: 1.5),
          boxShadow: [
            BoxShadow(color: AppTheme.primary.withValues(alpha: 0.1), blurRadius: 10, spreadRadius: 1),
          ],
          image: avatar != null ? DecorationImage(image: CachedNetworkImageProvider(avatar), fit: BoxFit.cover) : null,
        ),
        child: avatar == null ? const Icon(Icons.nightlife, color: AppTheme.primary, size: 24) : null,
      ),
    );
  }

  Widget _organizerInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.event.organizerName ?? 'OFFICIAL CLUB',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        Row(
          children: [
            const Icon(Icons.star_rounded, color: Colors.amber, size: 12),
            const SizedBox(width: 4),
            const Text(
              '4.9',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'verified_publisher'.tr,
              style: const TextStyle(color: Colors.white24, fontSize: 10),
            ),
            const SizedBox(width: 8),
            _buildInlineHelp('verified_publisher'.tr, 'HELP_VERIFIED_USER_SHORT', icon: Icons.verified_user_rounded),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: AppTheme.tertiary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
              child: Row(
                children: [
                  const Icon(Icons.favorite_rounded, color: AppTheme.tertiary, size: 10),
                  const SizedBox(width: 4),
                  Text('1.2K', style: TextStyle(color: AppTheme.tertiary, fontSize: 9, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showSectionHelp(String section, {String? customDesc}) {
    String desc = customDesc ?? 'providing_details'.tr;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(32),
        decoration: const BoxDecoration(color: Color(0xFF161616), borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 24),
            const Icon(Icons.info_outline_rounded, color: AppTheme.primary, size: 32),
            const SizedBox(height: 16),
            Text(section.toUpperCase(), style: AppTheme.headlineStyle.copyWith(fontSize: 18)),
            const SizedBox(height: 12),
            Text(desc, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.5)),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildInlineHelp(String title, String descKey, {IconData icon = Icons.info_outline_rounded}) {
    return GestureDetector(
      onTap: () => _showSectionHelp(title, customDesc: descKey.tr),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), shape: BoxShape.circle),
        child: Icon(icon, color: Colors.white24, size: 10),
      ),
    );
  }

  Widget _followActionButton() {
    final accent = isFollowing ? AppTheme.secondary : AppTheme.primary;
    return GestureDetector(
      onTap: _handleFollow,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isFollowing ? Colors.transparent : accent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accent.withValues(alpha: 0.4)),
        ),
        child: Text(
          (isFollowing ? 'following' : 'follow').tr.toUpperCase(),
          style: TextStyle(
            color: accent,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }

  Widget _buildRulesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'house_rules'.tr.toUpperCase(),
          style: AppTheme.labelStyle.copyWith(
            letterSpacing: 2,
            fontSize: 10,
            color: AppTheme.secondary,
          ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppTheme.secondary.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppTheme.secondary.withValues(alpha: 0.1)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.gavel_rounded,
                color: AppTheme.secondary,
                size: 20,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  widget.event.rules!,
                  style: const TextStyle(
                    color: Colors.white70,
                    height: 1.8,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSliverHeader() {
    final hasImg =
        widget.event.imageUrl != null && widget.event.imageUrl!.isNotEmpty;
    return SliverAppBar(
      expandedHeight: 440,
      pinned: true,
      backgroundColor: AppTheme.background,
      leading: IconButton(
        icon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 16),
            if (widget.fromMap) ...[
              const SizedBox(width: 4),
              const Icon(Icons.map_outlined, color: AppTheme.primary, size: 16),
            ]
          ],
        ),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        IconButton(
          icon: Icon(
            isFavorited ? Icons.favorite : Icons.favorite_border_rounded,
            color: isFavorited ? AppTheme.tertiary : Colors.white,
            size: 24,
          ),
          onPressed: _toggleFavorite,
        ),
        IconButton(
          icon: const Icon(Icons.share_rounded, color: Colors.white),
          onPressed: _shareEvent,
        ),
        if (_isOwner) ...[
          IconButton(
            icon: const Icon(
              Icons.qr_code_scanner_rounded,
              color: AppTheme.primary,
              size: 24,
            ),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ScanEntryScreen(organizerId: widget.event.organizerId, eventId: widget.event.id))),
          ),
          IconButton(
            icon: const Icon(
              Icons.auto_graph_rounded,
              color: AppTheme.secondary,
            ),
            tooltip: 'manage_event'.tr,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => EventManageDetailsScreen(event: widget.event),
              ),
            ),
          ),
        ],
        _actionsMenu(),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            Hero(
              tag: 'home-event-${widget.event.id}',
              child: hasImg
                  ? CachedNetworkImage(
                      imageUrl: widget.event.imageUrl!,
                      fit: BoxFit.cover,
                      placeholder: (context, url) =>
                          Container(color: Colors.white.withValues(alpha: 0.05)),
                      errorWidget: (context, url, error) =>
                          const Icon(Icons.error),
                    )
                  : Container(color: Colors.white.withValues(alpha: 0.05)),
            ),
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black54,
                    Colors.transparent,
                    Colors.transparent,
                    AppTheme.background,
                  ],
                ),
              ),
            ),
            (() {
              final booked = widget.event.totalBookedCount;
              final max = widget.event.maxCapacity;
              bool autoScarcity = false;
              if (max != null && max > 0) {
                autoScarcity = (booked / max) >= 0.6;
              }
              
              if (widget.event.isUrgent || autoScarcity) {
                return Positioned(
                  top: 100,
                  right: -10,
                  child: RotationTransition(
                    turns: const AlwaysStoppedAnimation(-15 / 360),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.redAccent,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(color: Colors.redAccent.withValues(alpha: 0.5), blurRadius: 20, spreadRadius: 5)
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.local_fire_department_rounded, color: Colors.white, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            'FEW_SPOTS_LEFT'.tr,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }
              return const SizedBox.shrink();
            })(),

            // CLUB IDENTITY BUTTON (Sequential Button on the right)
            Positioned(
              top: 160,
              right: 20,
              child: _buildClubIdentityFloatingAction(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClubIdentityFloatingAction() {
    return Column(
      children: [
        GestureDetector(
          onTap: () {
            if (widget.event.organizerId != null) {
               _showQuickClubPeek();
            }
          },
          child: Container(
            width: 50, height: 50,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.background,
              border: Border.all(color: AppTheme.primary, width: 2),
              boxShadow: [
                BoxShadow(color: AppTheme.primary.withValues(alpha: 0.2), blurRadius: 15, spreadRadius: 2)
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(25),
              child: widget.event.organizerAvatar != null 
                ? CachedNetworkImage(imageUrl: widget.event.organizerAvatar!, fit: BoxFit.cover)
                : const Icon(Icons.nightlife, color: AppTheme.primary, size: 24),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildIdentityActionIcon(Icons.share_rounded, () {
           // Share logic
        }),
        const SizedBox(height: 12),
        _buildIdentityActionIcon(Icons.near_me_rounded, _openMap),
      ],
    );
  }

  Widget _buildIdentityActionIcon(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.4),
          border: Border.all(color: Colors.white10),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }

  void _showQuickClubPeek() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: 240,
        padding: const EdgeInsets.all(32),
        decoration: const BoxDecoration(
          color: Color(0xFF161616),
          borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
        ),
        child: Row(
          children: [
            Container(
              width: 90, height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.surface,
                border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
                image: widget.event.organizerAvatar != null ? DecorationImage(image: CachedNetworkImageProvider(widget.event.organizerAvatar!), fit: BoxFit.cover) : null,
              ),
              child: widget.event.organizerAvatar == null ? const Icon(Icons.nightlife, color: AppTheme.primary, size: 36) : null,
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(widget.event.organizerName ?? 'Club', style: AppTheme.headlineStyle.copyWith(fontSize: 20)),
                  const SizedBox(height: 8),
                  Text('verified_publisher'.tr, style: const TextStyle(color: Colors.white38, fontSize: 13)),
                  const SizedBox(height: 24),
                  MaterialButton(
                    onPressed: () {
                       if (widget.event.organizerId != null) {
                         Navigator.pop(ctx);
                         Navigator.push(context, MaterialPageRoute(builder: (_) => ClubProfileScreen(
                           organizerId: widget.event.organizerId!, 
                           organizerName: widget.event.organizerName ?? 'Club'
                         )));
                       } else {
                         ScaffoldMessenger.of(context).showSnackBar(
                           SnackBar(content: Text('club_info_missing'.tr))
                         );
                       }
                    },
                    height: 50,
                    minWidth: double.infinity,
                    color: AppTheme.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Text('VIEW_PROFILE'.tr, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionsMenu() {
    return PopupMenuButton<String>(
      onSelected: _handleOption,
      color: Color(0xFF1A1A1A),
      icon: const Icon(Icons.more_vert, color: Colors.white),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'Report',
          child: Text(
            'report_event'.tr,
            style: const TextStyle(color: Colors.white70),
          ),
        ),
        PopupMenuItem(
          value: 'Block',
          child: Text(
            'block_publisher'.tr,
            style: const TextStyle(color: Colors.redAccent),
          ),
        ),
      ],
    );
  }



  Widget _buildEventBentoGrid() {
    return Column(
      children: [
        Row(
          children: [
            _bentoBox(
              Icons.calendar_today_rounded,
              'DATE'.tr,
              widget.event.dateTime ?? 'TBA',
              flex: 2,
            ),
            const SizedBox(width: 12),
            _bentoBox(
              Icons.location_on_outlined,
              'VENUE'.tr,
              '${widget.event.venue ?? 'TBA'}${_distanceInKm != null ? " (${_distanceInKm!.toStringAsFixed(1)} KM)" : ""}',
              flex: 3,
              onTap: () => _openMap(),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _buildDetailedPriceBox(),
            const SizedBox(width: 12),
            _bentoBox(
              widget.event.price == 0 ? Icons.card_giftcard_rounded : Icons.door_front_door_rounded,
              'PAYMENT_MODE'.tr,
              widget.event.price == 0 ? 'FREE_ENTRY_MODE'.tr : 'PAY_AT_VENUE'.tr,
              flex: 2,
              highlightColor: widget.event.price == 0 ? AppTheme.secondary : null,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDescriptionSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'about_event'.tr.toUpperCase(),
          style: AppTheme.labelStyle.copyWith(
            letterSpacing: 2,
            fontSize: 10,
            color: AppTheme.primary,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          widget.event.description ?? 'no_description'.tr,
          style: const TextStyle(
            color: Colors.white70,
            height: 1.8,
            fontSize: 15,
          ),
        ),
      ],
    );
  }

  Widget _buildBottomBookingBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainer,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        border: Border.all(color: Colors.white10),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 40),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // LEFT SIDE: SHARE & SAVE
                  Row(
                    children: [
                      _interactionCircleButton(
                        icon: Icons.share_rounded,
                        color: Colors.white60,
                        onTap: _shareEvent,
                      ),
                      const SizedBox(width: 12),
                      _interactionCircleButton(
                        icon: isFavorited ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                        color: isFavorited ? AppTheme.primary : Colors.white60,
                        onTap: _toggleFavorite,
                      ),
                    ],
                  ),
                  
                  // RIGHT SIDE: LIKES (HYPE)
                  _interactionCircleButton(
                    icon: _isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    color: _isLiked ? AppTheme.tertiary : Colors.white60,
                    onTap: _toggleLike,
                    label: _likesCount.toString(),
                    isLarge: true,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _bookingActionButton(),
            ],
        ),
      );
  }

  Widget _interactionCircleButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    String? label,
    bool isLarge = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: EdgeInsets.all(isLarge ? 14 : 12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.2), width: isLarge ? 2 : 1),
              boxShadow: [
                if (color != Colors.white60)
                  BoxShadow(
                    color: color.withValues(alpha: 0.2), 
                    blurRadius: isLarge ? 15 : 10,
                    spreadRadius: isLarge ? 2 : 0,
                  )
              ],
            ),
            child: Icon(icon, color: color, size: isLarge ? 24 : 20),
          ),
          if (label != null) ...[
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: isLarge ? 12 : 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _bookingActionButton() => GestureDetector(
    onTap: () => _showBookingSheet(),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: widget.event.requireCallConfirmation
            ? AppTheme.secondary
            : AppTheme.primary,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color:
                (widget.event.requireCallConfirmation
                        ? AppTheme.secondary
                        : AppTheme.primary)
                    .withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Text(
        (_existingBooking != null 
            ? 'VIEW_TICKET'.tr
            : widget.event.requireCallConfirmation
                ? 'REQUEST_ENTRY'.tr
                : 'secure_entry'.tr)
            .toUpperCase(),
        style: const TextStyle(
          color: Colors.black,
          fontWeight: FontWeight.w900,
          fontSize: 13,
          letterSpacing: 1,
        ),
      ),
    ),
  );

  void _showBookingSheet() {
    if (_existingBooking != null) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => TicketScreen(booking: _existingBooking!)),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          // Tier Multipliers Logic
          double tierMultiplier = 1.0;
          String tierLabel = 'STANDARD_TICKET'.tr;
          IconData tierIcon = Icons.confirmation_number_outlined;
          Color tierColor = AppTheme.primary;

          if (selectedTier == 'VIP') {
            tierMultiplier = 1.75;
            tierLabel = 'VIP_TICKET'.tr;
            tierIcon = Icons.stars_rounded;
            tierColor = AppTheme.secondary;
          } else if (selectedTier == 'Diamond') {
            tierMultiplier = 3.2;
            tierLabel = 'DIAMOND_TICKET'.tr;
            tierIcon = Icons.diamond_rounded;
            tierColor = const Color(0xFF00E5FF);
          }

          final unitPrice = widget.event.price * tierMultiplier;
          double finalUnitPrice = unitPrice;

          if (widget.event.promoDiscount > 0) {
            finalUnitPrice -= widget.event.promoDiscount;
          } else if (isFollowing && widget.event.followerDiscount > 0) {
            finalUnitPrice *= (1 - widget.event.followerDiscount / 100);
          }

          final total = finalUnitPrice * guestCount;
          final savings = (unitPrice * guestCount) - total;

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            decoration: BoxDecoration(
              color: const Color(0xFF0D0D0D),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.8), blurRadius: 40),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 48,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(2.5),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                
                // HEADER
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: tierColor.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(tierIcon, color: tierColor, size: 20),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SELECT_CATEGORY'.tr.toUpperCase(),
                          style: AppTheme.labelStyle.copyWith(
                            color: tierColor,
                            letterSpacing: 2,
                            fontSize: 10,
                          ),
                        ),
                        Row(
                          children: [
                            Text(
                              tierLabel,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _buildInlineHelp(
                              tierLabel, 
                              tierLabel == 'VIP_TICKET'.tr ? 'HELP_TIER_VIP_SHORT' : tierLabel == 'DIAMOND_TICKET'.tr ? 'HELP_TIER_DIAMOND_SHORT' : 'HELP_TIER_STANDARD_SHORT',
                              icon: tierLabel == 'VIP_TICKET'.tr ? Icons.stars_rounded : tierLabel == 'DIAMOND_TICKET'.tr ? Icons.diamond_rounded : Icons.confirmation_number_outlined,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 40),

                // TIER SELECTOR (Premium Pills)
                Row(
                  children: [
                    _tierButton(context, setModalState, 'Standard', Icons.person_outline, AppTheme.primary),
                    const SizedBox(width: 12),
                    _tierButton(context, setModalState, 'VIP', Icons.auto_awesome_outlined, AppTheme.secondary),
                    const SizedBox(width: 12),
                    _tierButton(context, setModalState, 'Diamond', Icons.diamond_outlined, const Color(0xFF00E5FF)),
                  ],
                ),

                const SizedBox(height: 48),

                // GUEST STEPPER
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'NUMBER_OF_GUESTS'.tr,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          'max_10_guests'.tr,
                          style: const TextStyle(color: Colors.white24, fontSize: 10),
                        ),
                      ],
                    ),
                    Container(
                      height: 50,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove, color: Colors.white54, size: 18),
                            onPressed: () {
                              if (guestCount > 1) {
                                setModalState(() => guestCount--);
                                setState(() {});
                              }
                            },
                          ),
                          Container(
                            width: 1,
                            height: 20,
                            color: Colors.white10,
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              '$guestCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                              ),
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 20,
                            color: Colors.white10,
                          ),
                          IconButton(
                            icon: Icon(Icons.add, color: tierColor, size: 18),
                            onPressed: () {
                              if (guestCount < 10) {
                                setModalState(() => guestCount++);
                                setState(() {});
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 40),
                
                // PAYMENT METHOD SECTION
                if (widget.event.payAtDoor) ...[
                  Text(
                    'PAYMENT_METHOD'.tr.toUpperCase(),
                    style: AppTheme.labelStyle.copyWith(
                      color: Colors.white38,
                      letterSpacing: 2,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      // ACTIVE: PAY AT DOOR
                      Expanded(
                        child: _hypePaymentCard(
                          title: 'PAY_AT_DOOR'.tr,
                          icon: Icons.payments_outlined,
                          isActive: true,
                          isSelected: true,
                          onTap: () {}, // Already selected
                        ),
                      ),
                      const SizedBox(width: 12),
                      // FROZEN: PAY ONLINE
                      Expanded(
                        child: _hypePaymentCard(
                          title: 'PAY_NOW_ONLINE'.tr,
                          icon: Icons.account_balance_wallet_outlined,
                          isActive: false,
                          isSelected: false,
                          badge: 'LOCKED_COMING_SOON'.tr,
                          showLogos: true,
                          onTap: () {
                            _showToast('LOCKED_COMING_SOON'.tr);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                ],

                const Divider(color: Colors.white10),
                const SizedBox(height: 32),

                // INVOICE BOX
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.02),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                  ),
                  child: Column(
                    children: [
                      _invoiceRow('BOOKING_PAYMENT_METHOD'.tr, widget.event.price == 0 ? 'FREE_ENTRY_MODE'.tr : 'PAY_AT_VENUE'.tr, AppTheme.primary),
                      const SizedBox(height: 12),
                      _invoiceRow('YOUR_SELECTION'.tr, '$guestCount x $tierLabel', Colors.white38),
                      const SizedBox(height: 12),
                      if (savings > 0)
                        _invoiceRow('DISCOUNT'.tr, '-${LocalizationService.formatPrice(savings, widget.event.countryCode)}', AppTheme.secondary),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'TOTAL_DUE'.tr,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              if (widget.event.price > 0 && widget.event.payAtDoor)
                                Text(
                                  'DUE_AT_ARRIVAL'.tr,
                                  style: const TextStyle(
                                    color: Colors.white24,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              if (widget.event.price == 0)
                                Text(
                                  'FREE_BOOKING_NOTICE'.tr,
                                  style: const TextStyle(
                                    color: Colors.tealAccent,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                            ],
                          ),
                          Text(
                            LocalizationService.formatPrice(total, widget.event.countryCode),
                            style: TextStyle(
                              color: tierColor,
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // RULES ACKNOWLEDGMENT
                if (widget.event.rules != null && widget.event.rules!.isNotEmpty)
                  GestureDetector(
                    onTap: () => _showSectionHelp('house_rules'.tr, customDesc: widget.event.rules),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppTheme.secondary.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.secondary.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.gavel_rounded, color: AppTheme.secondary, size: 16),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'I_AGREE_TO_RULES'.tr,
                              style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const Icon(Icons.info_outline_rounded, color: AppTheme.secondary, size: 14),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 32),

                // ACTION BUTTON
                GestureDetector(
                  onTap: isBooking
                      ? null
                      : () {
                          Navigator.pop(ctx);
                          _handleBooking();
                        },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 64,
                    width: double.infinity,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: tierColor,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: tierColor.withValues(alpha: 0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: isBooking
                        ? const CircularProgressIndicator(color: Colors.black)
                        : Text(
                            'CONFIRM_BOOKING'.tr.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2,
                              fontSize: 14,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }


  Widget _hypePaymentCard({
    required String title,
    required IconData icon,
    required bool isActive,
    required bool isSelected,
    required VoidCallback onTap,
    String? badge,
    bool showLogos = false,
  }) {
    final color = isSelected ? AppTheme.primary : Colors.white38;
    return GestureDetector(
      onTap: onTap,
      child: Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
      decoration: BoxDecoration(
        color: isSelected ? AppTheme.primary.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSelected ? AppTheme.primary.withValues(alpha: 0.3) : Colors.white12,
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: Opacity(
        opacity: isActive ? 1.0 : 0.6, // Increased slightly for visibility
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, color: color, size: 24),
                if (badge != null)
                  Positioned(
                    top: -24,
                    right: -20,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.secondary,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        badge,
                        style: const TextStyle(color: Colors.black, fontSize: 6, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white24,
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
            if (showLogos) ...[
              const SizedBox(height: 12),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(FontAwesomeIcons.ccVisa, color: Colors.white10, size: 10),
                  SizedBox(width: 4),
                  Icon(FontAwesomeIcons.ccMastercard, color: Colors.white10, size: 10),
                  SizedBox(width: 4),
                  Icon(FontAwesomeIcons.applePay, color: Colors.white10, size: 14),
                ],
              ),
            ],
          ],
        ),
      ),
    ),
  );
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppTheme.surfaceContainer,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _invoiceRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white24, fontSize: 11, fontWeight: FontWeight.bold)),
        Text(value, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _tierButton(BuildContext context, StateSetter setModalState, String tier, IconData icon, Color color) {
    final bool isSelected = selectedTier == tier;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setModalState(() => selectedTier = tier);
          setState(() {}); // Sync main screen
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? color.withValues(alpha: 0.4) : Colors.white12,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, color: isSelected ? color : Colors.white24, size: 24),
              const SizedBox(height: 10),
              Text(
                tier.toUpperCase(),
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white24,
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailedPriceBox() {
    bool hasDiscount = false;
    double originalPrice = widget.event.price;
    double finalPrice = originalPrice;
    String discountLabel = '';

    if (widget.event.globalDiscount > 0) {
      hasDiscount = true;
      finalPrice = (originalPrice * (1 - widget.event.globalDiscount / 100)).clamp(0, double.infinity);
      discountLabel = '${'FLASH_OFFER'.tr} -${widget.event.globalDiscount.toInt()}%';
    } else if (widget.event.promoDiscount > 0) {
      hasDiscount = true;
      finalPrice -= widget.event.promoDiscount;
      discountLabel = '-${((widget.event.promoDiscount / originalPrice) * 100).toStringAsFixed(0)}%';
    } else if (isFollowing && widget.event.followerDiscount > 0) {
      hasDiscount = true;
      finalPrice = (originalPrice * (1 - widget.event.followerDiscount / 100)).clamp(0, double.infinity);
      discountLabel = '-${widget.event.followerDiscount.toInt()}%';
    }

    return Expanded(
      flex: 3,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: hasDiscount ? AppTheme.primary.withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.05),
            width: hasDiscount ? 1.5 : 1,
          ),
          boxShadow: [
            if (hasDiscount)
              BoxShadow(
                color: AppTheme.primary.withValues(alpha: 0.1),
                blurRadius: 20,
                spreadRadius: -5,
              ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Icon(
                  Icons.payments_outlined,
                  color: AppTheme.primary,
                  size: 14,
                ),
                if (hasDiscount)
                   Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          discountLabel,
                          style: const TextStyle(
                            color: AppTheme.primary,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      _buildInlineHelp('DISCOUNT'.tr, 'HELP_LOYALTY_USER_SHORT', icon: Icons.loyalty_rounded),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'PRICE'.tr,
              style: const TextStyle(
                color: Colors.white24,
                fontSize: 8,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 6),
            if (hasDiscount)
              Text(
                LocalizationService.formatPrice(
                  originalPrice,
                  widget.event.countryCode,
                ),
                style: const TextStyle(
                  color: Colors.white24,
                  fontSize: 11,
                  decoration: TextDecoration.lineThrough,
                  fontWeight: FontWeight.bold,
                ),
              ),
            Text(
              LocalizationService.formatPrice(
                hasDiscount ? finalPrice : originalPrice,
                widget.event.countryCode,
              ),
              style: TextStyle(
                color: hasDiscount ? AppTheme.secondary : Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVipPerkSection() {
    final hasDiscount = widget.event.followerDiscount > 0;
    final hasPerk = widget.event.followerPerk != null;

    // Glow/Hype colors
    final Color highlightColor = isFollowing
        ? AppTheme.secondary
        : const Color(0xFFFFD700).withValues(alpha: 0.8);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            isFollowing
                ? AppTheme.secondary.withValues(alpha: 0.15)
                : const Color(0xFFFFD700).withValues(alpha: 0.08),
            Colors.black.withValues(alpha: 0.4),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
          color: isFollowing
              ? AppTheme.secondary.withValues(alpha: 0.5)
              : const Color(0xFFFFD700).withValues(alpha: 0.2),
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: isFollowing
                ? AppTheme.secondary.withValues(alpha: 0.08)
                : const Color(0xFFFFD700).withValues(alpha: 0.05),
            blurRadius: 30,
            spreadRadius: -10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: highlightColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isFollowing
                      ? Icons.verified_user_rounded
                      : Icons.auto_awesome_rounded,
                  color: highlightColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          isFollowing
                              ? 'FOLLOWER_ADVANTAGE_ACTIVE'.tr.toUpperCase()
                              : 'hype_teaser'.tr.toUpperCase(),
                          style: AppTheme.labelStyle.copyWith(
                            color: highlightColor,
                            letterSpacing: 2,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildInlineHelp('EXCLUSIVE_PERK'.tr, 'HELP_LOYALTY_USER_SHORT', icon: Icons.auto_awesome_rounded),
                      ],
                    ),
                    if (!isFollowing)
                      Text(
                        'unlock_massive_savings'.tr,
                        style: const TextStyle(
                          color: Colors.white24,
                          fontSize: 10,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),

          if (hasDiscount)
            _perkItem(
              Icons.payments_outlined,
              'FOLLOWER_DISCOUNT'.tr,
              '-${widget.event.followerDiscount.toInt()}%',
              highlightColor,
            ),
          if (hasDiscount && hasPerk) const SizedBox(height: 16),
          if (hasPerk)
            _perkItem(
              Icons.redeem_rounded,
              'EXCLUSIVE_PERK'.tr,
              widget.event.followerPerk!,
              highlightColor,
            ),

          if (!isFollowing) ...[
            const SizedBox(height: 28),
            GestureDetector(
              onTap: _handleFollow,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [highlightColor, highlightColor.withValues(alpha: 0.7)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: highlightColor.withValues(alpha: 0.3),
                      blurRadius: 20,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.flash_on_rounded,
                      color: Colors.black,
                      size: 18,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'join_exclusive_club'.tr.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _perkItem(IconData icon, String label, String value, Color accent) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isFollowing
                ? Colors.white.withValues(alpha: 0.05)
                : accent.withValues(alpha: 0.05),
            shape: BoxShape.circle,
            border: Border.all(
              color: isFollowing ? Colors.white10 : accent.withValues(alpha: 0.1),
            ),
          ),
          child: Icon(
            icon,
            color: isFollowing ? Colors.white : accent,
            size: 16,
          ),
        ),
        const SizedBox(width: 18),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isFollowing ? Colors.white38 : accent.withValues(alpha: 0.4),
                fontSize: 9,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            Text(
              value,
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildUrgencyBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.redAccent.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: const Icon(Icons.local_fire_department_rounded, color: Colors.redAccent, size: 24),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ACT_FAST'.tr.toUpperCase(), style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1)),
                const SizedBox(height: 4),
                Text('FEW_SPOTS_LEFT'.tr, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSideStrip() {
    return _isOwner ? _buildSideAdminStrip() : _buildSideVisitorStrip();
  }

  Widget _buildSideAdminStrip() {
    return Positioned(
      right: 0,
      top: 150,
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(32),
          bottomLeft: Radius.circular(32),
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            width: 54,
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 6),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.15),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(32),
                bottomLeft: Radius.circular(32),
              ),
              border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3), width: 1.5),
              boxShadow: [BoxShadow(color: AppTheme.primary.withValues(alpha: 0.1), blurRadius: 40)],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSideIcon(Icons.auto_graph_rounded, () => _handleSideAction('manage'), color: AppTheme.secondary),
                _buildSideDivider(),
                _buildSideIcon(Icons.analytics_rounded, () => _handleSideAction('stats')),
                _buildSideIcon(Icons.qr_code_scanner_rounded, () => _handleSideAction('scan')),
                _buildSideIcon(Icons.campaign_rounded, () => _handleSideAction('marketing')),
                _buildSideDivider(),
                _buildSideIcon(Icons.live_tv_rounded, () => _handleSideAction('broadcast')),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSideVisitorStrip() {
    return Positioned(
      right: 0,
      top: 200,
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(32),
          bottomLeft: Radius.circular(32),
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            width: 54,
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(32),
                bottomLeft: Radius.circular(32),
              ),
              border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 1),
            ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSideIcon(isFavorited ? Icons.favorite_rounded : Icons.favorite_border_rounded, _toggleFavorite, 
              color: isFavorited ? AppTheme.tertiary : Colors.white70),
            _buildSideDivider(),
            _buildSideIcon(Icons.share_rounded, _shareEvent),
            _buildSideIcon(Icons.map_rounded, _openMap),
            _buildSideIcon(Icons.chat_bubble_outline_rounded, () => _handleSideAction('chat')),
          ],
        ),
      ),
      ),
      ),
    );
  }

  Widget _buildSideIcon(IconData icon, VoidCallback onTap, {Color? color}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: (color != null && color != Colors.white70) ? color.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.05),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color ?? Colors.white70, size: 20),
      ),
    );
  }

  Widget _buildSideDivider() {
    return Container(
      height: 1,
      width: 20,
      margin: const EdgeInsets.symmetric(vertical: 12),
      color: Colors.white.withValues(alpha: 0.05),
    );
  }


  void _handleSideAction(String action) {
    switch (action) {
      case 'manage':
        Navigator.push(context, MaterialPageRoute(builder: (_) => EventManageDetailsScreen(event: widget.event)));
        break;
      case 'stats':
        _showQuickStats('event_stats'.tr, '${widget.event.viewCount}');
        break;
      case 'scan':
        Navigator.push(context, MaterialPageRoute(builder: (_) => ScanEntryScreen(organizerId: widget.event.organizerId, eventId: widget.event.id)));
        break;
      case 'marketing':
        Navigator.push(context, MaterialPageRoute(builder: (_) => MarketingEngineScreen(clubId: widget.event.organizerId ?? Supabase.instance.client.auth.currentUser!.id)));
        break;
      case 'broadcast':
        Navigator.push(context, MaterialPageRoute(builder: (_) => BroadcastScreen(organizerId: widget.event.organizerId ?? Supabase.instance.client.auth.currentUser!.id)));
        break;
      case 'chat':
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('chat_coming_soon'.tr)));
        break;
    }
  }
}

class MapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.03)
      ..strokeWidth = 1.0;

    const double step = 20.0;

    for (double i = 0; i < size.width; i += step) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }

    for (double i = 0; i < size.height; i += step) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
    
    // Add some diagonal interest
    final accentPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.01)
      ..strokeWidth = 0.5;
      
    for (double i = -size.height; i < size.width; i += step * 4) {
      canvas.drawLine(Offset(i, 0), Offset(i + size.height, size.height), accentPaint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

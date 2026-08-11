import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
// ignore_for_file: deprecated_member_use
// ignore: unused_import
import 'package:my_app/services/translation_service.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/models/event.dart';
import 'package:my_app/services/event_service.dart';
import 'package:my_app/services/follow_service.dart';
import 'package:my_app/services/favorite_service.dart';
import 'package:my_app/screens/staff_management_screen.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:my_app/services/localization_service.dart';
import 'package:my_app/screens/club_dashboard.dart';
import 'package:my_app/screens/club_profile_editor.dart';
import 'package:my_app/screens/marketing_engine_screen.dart';
import 'package:my_app/screens/booking_management.dart';
import 'package:my_app/screens/audience_screen.dart';
import 'package:my_app/screens/master_operational_ledger.dart';
import 'package:my_app/screens/create_event.dart';
import 'package:my_app/screens/map_discovery.dart';
import 'package:my_app/screens/event_manage_details.dart';
import 'package:my_app/screens/event_details.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:my_app/screens/mission_matrix_screen.dart';
import 'package:my_app/services/social_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:my_app/services/storage_service.dart';
import 'package:my_app/screens/scan_entry.dart';
import 'dart:io';
import 'package:my_app/screens/broadcast_screen.dart';
import 'package:my_app/screens/my_events_screen.dart';
import 'package:my_app/services/review_service.dart';

class ClubProfileScreen extends StatefulWidget {
  final String organizerId;
  final String organizerName;
  final bool fromMap;

  const ClubProfileScreen({
    super.key,
    required this.organizerId,
    required this.organizerName,
    this.fromMap = false,
  });

  @override
  State<ClubProfileScreen> createState() => _ClubProfileScreenState();
}

class _ClubProfileScreenState extends State<ClubProfileScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _supabase = Supabase.instance.client;
  final _eventService = EventService();
  final _followService = FollowService();
  final _storage = StorageService();
  final _picker = ImagePicker();
  final _socialService = SocialService();
  final _reviewService = ReviewService();


  List<String> _permanentImages = [];
  List<Event> _activeEvents = [];
  String? _bio;
  double? _lat;
  double? _lng;
  int _followerCount = 0;
  int _totalEventCount = 0;
  bool _isFollowing = false;
  bool _isFollowingLoading = false;
  String _businessType = 'nightlife';
  bool _isFavorited = false;
  Set<String> _favoritedEventIds = {};
  double _avgRating = 0.0;
  int _reviewCount = 0;
  int? _userRating;

  bool _previewAsVisitor = false;

  bool get isOwner => _previewAsVisitor ? false : isActualOwner;
  bool get isActualOwner => _supabase.auth.currentUser?.id == widget.organizerId;
  String _searchQuery = "";
  final _searchController = TextEditingController();
  int _selectedTab = 0; // 0: Events Grid, 1: Gallery Grid
  bool _isLoading = true;
  String? _avatarUrl;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() => _selectedTab = _tabController.index);
    });
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // 1. Data Loading (PARALLEL for speed)
      final results = await Future.wait<dynamic>([
        _supabase
            .from('organizer_profiles')
            .select('name, avatar_url, permanent_gallery, bio, latitude, longitude, business_type, profiles(avatar_url, full_name)')
            .eq('id', widget.organizerId)
            .maybeSingle(),
        _followService.getFollowerCount(widget.organizerId),
        _followService.isFollowing(widget.organizerId),
        _eventService.getOrganizerEvents(organizerId: widget.organizerId),
        FavoriteService().isFavorited(clubId: widget.organizerId),
        FavoriteService().getFavoriteEvents(),
        _reviewService.getOrganizerRating(widget.organizerId),
        _reviewService.getUserReview(widget.organizerId),
      ]);

      final profileRes = results[0] as Map<String, dynamic>?;
      _followerCount = results[1] as int;
      _isFollowing = results[2] as bool;
      _activeEvents = results[3] as List<Event>;
      _totalEventCount = _activeEvents.length;
      _isFavorited = results[4] as bool;
      final favoriteEvents = results[5] as List<Map<String, dynamic>>;
      
      final ratingData = results[6] as Map<String, dynamic>;
      _avgRating = ratingData['avg'] as double;
      _reviewCount = ratingData['count'] as int;
      _userRating = results[7] as int?;
      _favoritedEventIds = favoriteEvents.map((e) => e['event_id']?.toString() ?? '').toSet();

      if (profileRes != null) {
        _bio = profileRes['bio'];
        _lat = profileRes['latitude'];
        _lng = profileRes['longitude'];
        _businessType = profileRes['business_type']?.toString() ?? 'club';
        
        // Brand Identity Prioritization
        _avatarUrl = profileRes['avatar_url'] ?? profileRes['profiles']?['avatar_url'];
        
        final gallery = profileRes['permanent_gallery'] as List?;
        if (gallery != null && gallery.isNotEmpty) {
          _permanentImages = List<String>.from(gallery);
          // Fallback if no dedicated avatar: use first gallery image
          _avatarUrl ??= _permanentImages.first;
        }
      }

      if (_permanentImages.isEmpty) {
        // MOCK DATA fallback for brand consistency
        _permanentImages = [
          'https://images.unsplash.com/photo-1566737236500-c8ac43014a67',
          'https://images.unsplash.com/photo-1514525253361-bee8718a7412',
          'https://images.unsplash.com/photo-1517457373958-b7bdd458ad20',
        ];
      }
    } catch (e) {
      debugPrint('Error loading club profile: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }



  List<Event> get _filteredEvents {
    List<Event> list = _activeEvents;
    if (_searchQuery.isNotEmpty) {
      list = list
          .where(
            (e) =>
                e.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                (e.venue ?? "").toLowerCase().contains(
                  _searchQuery.toLowerCase(),
                ),
          )
          .toList();
    }

    // 1. PINNED first, then DATE (Newest first)
    list.sort((a, b) {
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      // If both same pin status, sort by date/ID (simulating date if not available)
      return b.id.compareTo(a.id);
    });

    return list;
  }

  // Deleted unreferenced _togglePin and _toggleArchive


  void _shareClub() {
    SharePlus.instance.share(
      ShareParams(text: 'share_club_msg'.trArgs([widget.organizerName, widget.organizerId])),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            ) 
          : Stack(
              children: [
                CustomScrollView(
                  physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                  slivers: [
                    _buildAppBar(),
                    SliverToBoxAdapter(
                      child: Column(
                        children: [
                          _buildHeader(),
                          const SizedBox(height: 8),
                          _buildDynamicRatingBar(),
                          const SizedBox(height: 16),
                          _buildCreateEventButton(),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _SliverAppBarDelegate(
                        minHeight: 60,
                        maxHeight: 60,
                        child: Container(
                          color: AppTheme.background,
                          child: _buildIGTabs(),
                        ),
                      ),
                    ),

                    if (_selectedTab == 0) ...[
                      if (_activeEvents.isNotEmpty) ...[
                         _buildSearchBar(),
                        ..._buildActiveEventSlivers(),
                      ] else ...[
                        SliverToBoxAdapter(child: _buildEmptyEventsState()),
                      ],
                    ] else ...[
                      if (_permanentImages.isNotEmpty || (isOwner)) ...[
                        _buildPermanentGallery(),
                      ] else ...[
                        SliverToBoxAdapter(child: _buildEmptyGalleryState()),
                      ],
                    ],

                    SliverToBoxAdapter(child: _buildClubFooter()),
                    const SliverToBoxAdapter(child: SizedBox(height: 100)),
                  ],
                ),
                _buildBottomFloatingStrip(),
              ],
            ),
    );
  }

  Future<void> _editField(String field, String currentVal) async {
    final controller = TextEditingController(text: currentVal);
    final newVal = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceContainer,
        title: Text(
          'Edit ${field.tr}',
          style: const TextStyle(color: AppTheme.primary),
        ),
        content: TextField(
          controller: controller,
          maxLines: field == 'bio' ? 3 : 1,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            hintText: 'Enter new ${field.tr}',
            hintStyle: const TextStyle(color: Colors.white24),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('cancel'.tr),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text('save'.tr),
          ),
        ],
      ),
    );

    if (newVal != null && newVal != currentVal) {
      final success = await _saveIndividualField(field, newVal);
      if (success) {
        setState(() {
          if (field == 'bio') _bio = newVal;
        });
      }
    }
  }

  Widget _buildDynamicRatingBar() {
    return GestureDetector(
      onTap: isOwner ? null : _showRatingDialog,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.1)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...List.generate(5, (index) {
              return Icon(
                index < _avgRating.floor() ? Icons.star_rounded : Icons.star_outline_rounded,
                color: index < _avgRating.floor() ? AppTheme.secondary : Colors.white12,
                size: 20,
              );
            }),
            const SizedBox(width: 12),
            Text(
              _avgRating.toStringAsFixed(1),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
            ),
            const SizedBox(width: 8),
            Text(
              '($_reviewCount ${'TOTAL_REVIEWS'.tr})',
              style: const TextStyle(color: Colors.white24, fontSize: 10),
            ),
            if (!isOwner) ...[
              const SizedBox(width: 12),
              const Icon(Icons.edit_note_rounded, color: AppTheme.primary, size: 16),
            ],
          ],
        ),
      ),
    );
  }

  void _showRatingDialog() {
    int tempRating = _userRating ?? 5;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: AppTheme.background,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('RATE_CLUB'.tr.toUpperCase(), style: AppTheme.headlineStyle.copyWith(fontSize: 20)),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  return IconButton(
                    icon: Icon(
                      index < tempRating ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: index < tempRating ? AppTheme.secondary : Colors.white12,
                      size: 40,
                    ),
                    onPressed: () => setModalState(() => tempRating = index + 1),
                  );
                }),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final success = await _reviewService.submitReview(widget.organizerId, tempRating);
                    if (success) {
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                      }
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('REVIEW_SUCCESS'.tr), backgroundColor: AppTheme.secondary),
                        );
                        _loadData(); // Refresh
                      }
                    }
                  },
                  child: Text('SUBMIT_REVIEW'.tr.toUpperCase()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomFloatingStrip() {
    return isOwner ? _buildBottomOrganizerStrip() : _buildBottomVisitorStrip();
  }

  Widget _buildBottomOrganizerStrip() {
    return Positioned(
      bottom: 24,
      right: 24,
      left: 24,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildSideIcon(Icons.phone_rounded, _handleCallClub, label: 'CALL'.tr),
                _buildSideIcon(Icons.share_rounded, _handleShare, label: 'SHARE'.tr),
                _buildSideIcon(Icons.map_rounded, () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const MapDiscoveryScreen()));
                }, label: 'EXPLORE_NEARBY'.tr),
                _buildSideIcon(Icons.dashboard_rounded, _showManagementBottomSheet, label: 'MANAGE'.tr, color: AppTheme.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomVisitorStrip() {
    return Positioned(
      bottom: 24,
      right: 24,
      left: 24,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildSideIcon(Icons.phone_rounded, _handleCallClub, label: 'CALL'.tr),
                _buildSideIcon(_isFavorited ? Icons.favorite_rounded : Icons.favorite_border_rounded, _handleToggleFavorite, 
                  color: _isFavorited ? Colors.redAccent : Colors.white70, label: 'FAVORITE'.tr),
                _buildSideIcon(Icons.share_rounded, _handleShare, label: 'SHARE'.tr),
                _buildSideIcon(Icons.map_rounded, () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const MapDiscoveryScreen()));
                }, label: 'EXPLORE_NEARBY'.tr),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showManagementBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppTheme.surfaceContainer.withValues(alpha: 0.98),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primary.withValues(alpha: 0.1),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 24),
            Text('MANAGEMENT'.tr, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 3,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 1.0,
              children: [
                _managementGridItem('edit_profile'.tr, Icons.edit_rounded, () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => ClubProfileEditorScreen(clubId: widget.organizerId)));
                }),
              ],
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
  Widget _managementGridItem(String label, IconData icon, VoidCallback onTap, {Color color = Colors.white}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color == Colors.white ? AppTheme.primary : color, size: 24),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }



  Widget _buildCreateEventButton() {
    if (!isOwner) return const SizedBox.shrink();
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: GestureDetector(
        onTap: () => _handleOwnerOptions('create'),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppTheme.primary, Colors.purpleAccent],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withValues(alpha: 0.3),
                blurRadius: 10,
                spreadRadius: 2,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_circle_outline_rounded, color: Colors.white, size: 24),
              SizedBox(width: 12),
              Text(
                'إنشاء فعالية جديدة',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }



  void _handleCallClub() async {
    final uri = Uri.parse('tel:+213555123456'); // Mock number
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح تطبيق الاتصال')),
      );
    }
  }

  void _handleToggleFavorite() async {
    setState(() {
      _isFavorited = !_isFavorited;
    });
    
    final favoriteService = FavoriteService();
    bool success = false;
    if (_isFavorited) {
      success = await favoriteService.addFavorite(clubId: widget.organizerId);
    } else {
      success = await favoriteService.removeFavorite(clubId: widget.organizerId);
    }
    
    if (!success) {
      setState(() {
        _isFavorited = !_isFavorited;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر تحديث المفضلة')),
        );
      }
      return;
    }
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isFavorited ? 'تمت الإضافة إلى المفضلة' : 'تم الحذف من المفضلة'),
          backgroundColor: _isFavorited ? Colors.green : Colors.grey,
        ),
      );
    }
  }


  Widget _buildIGTabs() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          _tabItem(0, Icons.grid_on_rounded, 'الفعاليات'),
          _tabItem(1, Icons.photo_library_rounded, 'المعرض'),
        ],
      ),
    );
  }

  Widget _tabItem(int index, IconData icon, String label) {
    final isSel = _selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          _tabController.animateTo(index);
          setState(() => _selectedTab = index);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSel ? AppTheme.primary.withValues(alpha: 0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isSel ? AppTheme.primary.withValues(alpha: 0.2) : Colors.transparent),
            boxShadow: isSel ? [
              BoxShadow(
                color: AppTheme.primary.withValues(alpha: 0.05),
                blurRadius: 10,
                spreadRadius: -2,
              )
            ] : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: isSel ? AppTheme.primary : Colors.white24,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: isSel ? Colors.white : Colors.white24,
                  fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                  fontSize: 12,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyGalleryState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40.0),
        child: Column(
          children: [
            const Icon(
              Icons.photo_album_outlined,
              color: Colors.white10,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              'No photos uploaded'.tr,
              style: const TextStyle(color: Colors.white24),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClubFooter() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          const Divider(color: Colors.white10),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.phone, color: AppTheme.primary, size: 20),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () {
                  if (isOwner) _editField('phone', '+213 555 123 456');
                },
                child: Text(
                  '+213 555 123 456',
                  style: AppTheme.headlineStyle.copyWith(fontSize: 18),
                ),
              ),
              if (_supabase.auth.currentUser?.id == widget.organizerId) ...[
                const SizedBox(width: 8),
                // Removed small edit pen
              ],
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.star, color: Colors.amber, size: 20),
              const SizedBox(width: 8),
              Text('4.9', style: AppTheme.headlineStyle.copyWith(fontSize: 18)),
              const SizedBox(width: 4),
              Text(
                '(128 reviews)',
                style: AppTheme.bodyStyle.copyWith(
                  color: AppTheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Text(
            widget.organizerName.toUpperCase(),
            style: AppTheme.labelStyle.copyWith(
              color: Colors.white24,
              letterSpacing: 4,
            ),
          ),
          const SizedBox(height: 48),
          const Divider(color: Colors.white10),
          const SizedBox(height: 48),
          _buildOrganizerRecruitmentSection(),
        ],
      ),
    );
  }

  Widget _buildOrganizerRecruitmentSection() {
    if (isOwner) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'JOIN_ORGANIZERS_TEASER'.tr.toUpperCase(),
                style: const TextStyle(
                  color: AppTheme.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(width: 8),
              _buildInlineHelp('organize'.tr, 'HELP_BECOME_ORGANIZER_USER_SHORT', icon: Icons.auto_awesome_rounded),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'HELP_BECOME_ORGANIZER_USER_SHORT'.tr,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white24, fontSize: 11, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      expandedHeight: 280,
      backgroundColor: AppTheme.background,
      elevation: 0,
      pinned: true,
      stretch: true,
      leading: Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: Colors.black38, shape: BoxShape.circle),
        child: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 14),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        stretchModes: const [StretchMode.zoomBackground, StretchMode.blurBackground],
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (_permanentImages.isNotEmpty)
              Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: _permanentImages.first,
                    fit: BoxFit.cover,
                  ),
                  if (isOwner)
                    Positioned(
                      bottom: 20,
                      right: 20,
                      child: GestureDetector(
                        onTap: _changeCoverPhoto,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                          child: const Row(
                            children: [
                              Icon(Icons.camera_alt_outlined, color: Colors.white, size: 16),
                              SizedBox(width: 4),
                              Text('تغيير الغلاف', style: TextStyle(color: Colors.white, fontSize: 10)),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              )
            else
              Container(color: AppTheme.surfaceContainer),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.4),
                    Colors.transparent,
                    AppTheme.background,
                  ],
                  stops: const [0.0, 0.4, 1.0],
                ),
              ),
            ),
            Positioned(
              bottom: 60,
              left: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(4)),
                        child: Text(_businessType.toUpperCase(), style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 8, letterSpacing: 1)),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.verified, color: Colors.blueAccent, size: 16),
                      const SizedBox(width: 6),
                      _buildLevelBar(),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.organizerName.toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 28, letterSpacing: -1),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (isActualOwner)
          _buildAppBarAction(
            _previewAsVisitor ? Icons.visibility_off_rounded : Icons.visibility_rounded,
            () {
              setState(() {
                _previewAsVisitor = !_previewAsVisitor;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(_previewAsVisitor ? 'PREVIEW_MODE_ACTIVE'.tr : 'OWNER_MODE_ACTIVE'.tr),
                  duration: const Duration(seconds: 1),
                  backgroundColor: AppTheme.primary,
                ),
              );
            },
            color: _previewAsVisitor ? AppTheme.primary : Colors.white,
          ),
        if (isOwner)
          _buildAppBarAction(Icons.edit_note_rounded, () => _handleOwnerOptions('edit')),
        _buildAppBarAction(Icons.more_vert_rounded, () => _showMoreOptions()),
      ],
    );
  }

  Widget _buildAppBarAction(IconData icon, VoidCallback onTap, {Color color = Colors.white}) {
    return Container(
      margin: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: IconButton(
              icon: Icon(icon, color: color, size: 16),
              onPressed: onTap,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLevelBar() {
    // Simulation of level based on follower count
    final level = (_followerCount / 10).floor() + 1;
    final progress = (_followerCount % 10) / 10;

    return Row(
      children: [
        Text(
          'LVL $level'.toUpperCase(),
          style: const TextStyle(
            color: AppTheme.primary,
            fontSize: 7,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
          ),
        ),
        if (isOwner)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Icon(Icons.edit_rounded, color: AppTheme.primary.withValues(alpha: 0.5), size: 6),
          ),
        const SizedBox(width: 6),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 2,
              backgroundColor: Colors.white10,
              valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
            ),
          ),
        ),
        const SizedBox(width: 40), // Gap before notification bell
      ],
    );
  }

  void _handleOwnerOptions(String choice) {
    switch (choice) {
      case 'my_events':
        Navigator.push(context, MaterialPageRoute(builder: (_) => MyEventsScreen(organizerId: widget.organizerId))).then((_) => _loadData());
        break;
      case 'create':
        Navigator.push(context, MaterialPageRoute(builder: (_) => CreateEventScreen(clubId: widget.organizerId, businessType: _businessType))).then((_) => _loadData());
        break;
      case 'edit':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const ClubProfileEditorScreen())).then((_) => _loadData());
        break;
      case 'dashboard':
        Navigator.push(context, MaterialPageRoute(builder: (_) => ClubDashboardScreen(clubId: widget.organizerId, clubName: widget.organizerName)));
        break;
      case 'staff':
        Navigator.push(context, MaterialPageRoute(builder: (_) => StaffManagementScreen(clubId: widget.organizerId, clubName: widget.organizerName)));
        break;
      case 'marketing':
        Navigator.push(context, MaterialPageRoute(builder: (_) => MarketingEngineScreen(clubId: widget.organizerId)));
        break;
      case 'archive':
        Navigator.push(context, MaterialPageRoute(builder: (_) => MissionMatrixScreen(organizerId: widget.organizerId, clubName: widget.organizerName)));
        break;
      case 'broadcast':
        Navigator.push(context, MaterialPageRoute(builder: (_) => BroadcastScreen(organizerId: widget.organizerId)));
        break;
      case 'scan':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const ScanEntryScreen()));
        break;
      case 'stats':
        Navigator.push(context, MaterialPageRoute(builder: (_) => MissionMatrixScreen(organizerId: widget.organizerId)));
        break;
      case 'bookings':
        Navigator.push(context, MaterialPageRoute(builder: (_) => BookingManagementScreen(clubId: widget.organizerId)));
        break;
      case 'logs':
        Navigator.push(context, MaterialPageRoute(builder: (_) => MasterOperationalLedgerScreen(organizerId: widget.organizerId)));
        break;
      case 'fans':
        Navigator.push(context, MaterialPageRoute(builder: (_) => AudienceScreen(organizerId: widget.organizerId)));
        break;
    }
  }

  void _editBio() async {
    final controller = TextEditingController(text: _bio);
    final newBio = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('تعديل النبذة التعريفية', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          maxLines: 4,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'اكتب نبذة عن النادي...',
            hintStyle: TextStyle(color: Colors.white24),
            border: InputBorder.none,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('حفظ', style: TextStyle(color: AppTheme.primary)),
          ),
        ],
      ),
    );

    if (newBio != null) {
      try {
        await _supabase.from('organizer_profiles').update({'bio': newBio}).eq('id', widget.organizerId);
        setState(() => _bio = newBio);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر حفظ التعديلات')),
        );
      }
    }
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 20),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildHeaderStat(_followerCount.toString(), 'FOLLOWERS'),
                    _buildStatDivider(),
                    _buildHeaderStat(_totalEventCount.toString(), 'EVENTS'),
                    _buildStatDivider(),
                    _buildHeaderStat(_avgRating.toStringAsFixed(1), 'RATING'),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: isOwner ? _editBio : null,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.02),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _bio ?? 'THE_VIBE_IS_HERE'.tr,
                      style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.6, letterSpacing: 0.2),
                    ),
                  ),
                  if (isOwner)
                    const Padding(
                      padding: EdgeInsets.only(left: 8.0),
                      child: Icon(Icons.edit_outlined, color: AppTheme.primary, size: 18),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: isOwner ? [
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _handleOwnerOptions('edit'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(54),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Text('EDIT_PROFILE'.tr.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [AppTheme.primary, AppTheme.primary.withValues(alpha: 0.7)]),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: AppTheme.primary.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))],
                  ),
                  child: ElevatedButton(
                    onPressed: () => _handleOwnerOptions('dashboard'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: Colors.black,
                      shadowColor: Colors.transparent,
                      minimumSize: const Size.fromHeight(54),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Text('DASHBOARD'.tr.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _buildCircleAction(Icons.share_rounded, _shareClub),
            ] : [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: _isFollowing ? null : LinearGradient(colors: [AppTheme.primary, AppTheme.primary.withValues(alpha: 0.7)]),
                    color: _isFollowing ? Colors.white.withValues(alpha: 0.1) : null,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: _isFollowing ? [] : [BoxShadow(color: AppTheme.primary.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))],
                  ),
                  child: ElevatedButton(
                    onPressed: _handleToggleFollow,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: _isFollowing ? Colors.white : Colors.black,
                      shadowColor: Colors.transparent,
                      minimumSize: const Size.fromHeight(54),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Text(
                      _isFollowing ? 'FOLLOWING' : 'FOLLOW',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _buildCircleAction(Icons.directions_rounded, _handleOpenMap),
              const SizedBox(width: 12),
              _buildCircleAction(Icons.share_rounded, _shareClub),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderStat(String value, String label) {
    return Expanded(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 800),
        curve: Curves.elasticOut,
        builder: (context, val, child) {
          return Transform.scale(
            scale: 0.5 + (0.5 * val),
            child: Opacity(
              opacity: val.clamp(0.0, 1.0),
              child: child,
            ),
          );
        },
        child: Column(
          children: [
            Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 22)),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 9, letterSpacing: 1.5)),
          ],
        ),
      ),
    );
  }

  Widget _buildStatDivider() {
    return Container(height: 20, width: 1, color: Colors.white10);
  }

  Widget _buildCircleAction(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 50, width: 50,
        decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withValues(alpha: 0.05))),
        child: Icon(icon, color: Colors.white70, size: 20),
      ),
    );
  }

  void _openGalleryViewer(String url) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black.withValues(alpha: 0.8),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (ctx, anim1, anim2) => GestureDetector(
        onTap: () => Navigator.pop(ctx),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Center(
              child: InteractiveViewer(
                child: Hero(
                  tag: 'gallery_$url',
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Image.network(url, fit: BoxFit.contain),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }


  Widget _buildPremiumEventCard(Event e, bool isOwner) {
    final date = e.dateTime?.split('|').first.trim() ?? '';
    final time = e.dateTime?.split('|').last.trim() ?? '';

    return GestureDetector(
      onTap: () {
        if (e.isArchived) {
          if (isOwner) {
            Navigator.push(context, MaterialPageRoute(builder: (_) => EventManageDetailsScreen(event: e))).then((_) => _loadData());
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('هذه الفعالية قد انتهت ولا يمكن الحجز فيها')),
            );
          }
          return;
        }
        Navigator.push(context, MaterialPageRoute(builder: (_) => EventDetailsScreen(event: e, fromMap: false))).then((_) => _loadData());
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        height: 280,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 15,
              spreadRadius: -5,
            )
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Story-like progress bars at the top
            Positioned(
              top: 12, left: 16, right: 16,
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 3,
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Container(
                      height: 3,
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                ],
              ),
            ),
            Hero(
              tag: 'event-${e.id}',
              child: ColorFiltered(
                colorFilter: e.isArchived 
                  ? const ColorFilter.mode(Colors.grey, BlendMode.saturation)
                  : const ColorFilter.mode(Colors.transparent, BlendMode.multiply),
                child: CachedNetworkImage(
                  imageUrl: e.imageUrl ?? '',
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(color: Colors.white.withValues(alpha: 0.05)),
                ),
              ),
            ),
            if (e.isArchived)
              Container(color: Colors.black.withValues(alpha: 0.4)), // Darken expired events
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.3),
                    Colors.black.withValues(alpha: 0.95),
                  ],
                  stops: const [0.0, 0.4, 1.0],
                ),
              ),
            ),
            Positioned(
              top: 16, right: 16,
              child: e.isArchived 
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                    child: const Text('انتهت', style: TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold)),
                  )
                : _buildUrgencyTag(e),
            ),
            Positioned(
              top: 16, left: 16,
              child: PopupMenuButton<String>(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                  child: const Icon(Icons.more_vert_rounded, color: Colors.white70, size: 16),
                ),
                color: AppTheme.surfaceContainer,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                onSelected: (value) async {
                  if (value == 'edit') {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => CreateEventScreen(event: e)));
                  } else if (value == 'delete') {
                    _deleteEventFromCard(e);
                  } else if (value == 'share') {
                    Share.share('Check out this event: ${e.title} at ${e.venue ?? "TBA"}');
                  } else if (value == 'favorite') {
                    _toggleFavoriteEvent(e);
                  }
                },
                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                  if (isOwner) ...[
                    const PopupMenuItem<String>(
                      value: 'edit',
                      child: ListTile(
                        leading: Icon(Icons.edit_note_rounded, color: AppTheme.primary),
                        title: Text('تعديل', style: TextStyle(color: Colors.white)),
                      ),
                    ),
                    const PopupMenuItem<String>(
                      value: 'delete',
                      child: ListTile(
                        leading: Icon(Icons.delete_forever_rounded, color: Colors.redAccent),
                        title: Text('حذف', style: TextStyle(color: Colors.white)),
                      ),
                    ),
                  ],
                  const PopupMenuItem<String>(
                    value: 'share',
                    child: ListTile(
                      leading: Icon(Icons.share_rounded, color: Colors.white70),
                      title: Text('مشاركة', style: TextStyle(color: Colors.white)),
                    ),
                  ),
                  if (!isOwner)
                    PopupMenuItem<String>(
                      value: 'favorite',
                      child: ListTile(
                        leading: Icon(
                          _favoritedEventIds.contains(e.id) ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          color: _favoritedEventIds.contains(e.id) ? Colors.redAccent : Colors.white70,
                        ),
                        title: Text(_favoritedEventIds.contains(e.id) ? 'إزالة من المفضلة' : 'حفظ في المفضلة', style: const TextStyle(color: Colors.white)),
                      ),
                    ),
                ],
              ),
            ),
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: ClipRRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.3),
                          Colors.black.withValues(alpha: 0.7),
                        ],
                      ),
                      border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.calendar_today_rounded, color: AppTheme.primary, size: 10),
                                  const SizedBox(width: 4),
                                  Text(date, style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 10)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Icon(Icons.access_time_rounded, color: Colors.white60, size: 12),
                            const SizedBox(width: 4),
                            Text(time, style: const TextStyle(color: Colors.white60, fontSize: 10)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          e.title.toUpperCase(),
                          maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 22, letterSpacing: -0.5),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.location_on_outlined, color: Colors.white38, size: 14),
                                const SizedBox(width: 4),
                                Text(e.venue ?? 'TBA', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                              ],
                            ),
                            Row(
                              children: [
                                // VIEW EVENT badge
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.open_in_new_rounded, color: Colors.white54, size: 11),
                                      const SizedBox(width: 4),
                                      Text('VIEW'.tr, style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // BOOK / PRICE badge
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary,
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [BoxShadow(color: AppTheme.primary.withValues(alpha: 0.3), blurRadius: 10)],
                                  ),
                                  child: Text(
                                    e.price > 0 ? LocalizationService.formatPrice(e.price, e.countryCode) : 'FREE'.tr,
                                    style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteEventFromCard(Event e) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('حذف الفعالية', style: TextStyle(color: Colors.white)),
        content: const Text('هل أنت متأكد من حذف هذه الفعالية نهائياً؟ سيتم حذف جميع الحجوزات المرتبطة بها أيضاً.', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _supabase.from('bookings').delete().eq('event_id', e.id);
        await _supabase.from('events').delete().eq('id', e.id);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم حذف الفعالية بنجاح')),
          );
          _loadData(); // Refresh list
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تعذر حذف الفعالية')),
          );
        }
      }
    }
  }

  void _toggleFavoriteEvent(Event e) async {
    final isFavorited = _favoritedEventIds.contains(e.id);
    
    setState(() {
      if (isFavorited) {
        _favoritedEventIds.remove(e.id);
      } else {
        _favoritedEventIds.add(e.id);
      }
    });
    
    final favoriteService = FavoriteService();
    bool success = false;
    if (!isFavorited) {
      success = await favoriteService.addFavorite(eventId: e.id);
    } else {
      success = await favoriteService.removeFavorite(eventId: e.id);
    }
    
    if (!success) {
      setState(() {
        if (isFavorited) {
          _favoritedEventIds.add(e.id);
        } else {
          _favoritedEventIds.remove(e.id);
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر تحديث المفضلة')),
        );
      }
      return;
    }
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(!isFavorited ? 'تم حفظ الفعالية في المفضلة' : 'تم الحذف من المفضلة'),
          backgroundColor: !isFavorited ? Colors.green : Colors.grey,
        ),
      );
    }
  }

  Widget _buildUrgencyTag(Event e) {
    bool isFewLeft = (e.maxCapacity != null && e.maxCapacity! > 0 && e.totalBookedCount / e.maxCapacity! >= 0.7);
    if (!isFewLeft && !e.isUrgent) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(10), boxShadow: [BoxShadow(color: Colors.redAccent.withValues(alpha: 0.3), blurRadius: 10)]),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_fire_department_rounded, color: Colors.white, size: 12),
          const SizedBox(width: 4),
          Text('FEW SPOTS'.tr.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10)),
        ],
      ),
    );
  }

  void _handleOpenMap() async {
    final url = 'https://www.google.com/maps/search/?api=1&query=$_lat,$_lng';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _handleToggleFollow() async {
    if (_isFollowingLoading) return;
    
    setState(() {
      _isFollowingLoading = true;
      // Optimistic update for UI feel
      _isFollowing = !_isFollowing;
      _followerCount += _isFollowing ? 1 : -1;
    });
    
    final changed = await _followService.toggleFollow(widget.organizerId);
    
    // Refetch the real count to be accurate
    final realCount = await _followService.getFollowerCount(widget.organizerId);
    
    if (mounted) {
      setState(() {
        _isFollowing = changed;
        _followerCount = realCount;
        _isFollowingLoading = false;
      });
    }
  }

  void _showBlockConfirm() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceContainer.withValues(alpha: 0.95),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.2))),
        title: Row(
          children: [
            const Icon(Icons.block_rounded, color: Colors.redAccent, size: 20),
            const SizedBox(width: 10),
            Text('BLOCK_CLUB'.tr, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text('block_confirm_msg'.tr, style: const TextStyle(color: Colors.white70, fontSize: 14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('cancel'.tr, style: const TextStyle(color: Colors.white54))),
          Container(
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('club_blocked_success'.tr),
                    backgroundColor: Colors.redAccent,
                  ),
                );
              },
              child: Text('block'.tr, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  void _showMoreOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppTheme.surfaceContainer.withValues(alpha: 0.98),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 40,
              spreadRadius: 10,
            )
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 24),
            if (isOwner) ...[
              _buildIGActionSmall(Icons.dashboard_rounded, 'DASHBOARD'.tr, () {
                Navigator.pop(context);
                _handleOwnerOptions('dashboard');
              }),
              _buildIGActionSmall(Icons.analytics_rounded, 'MARKETING'.tr, () {
                Navigator.pop(context);
                _handleOwnerOptions('marketing');
              }),
              _buildIGActionSmall(Icons.people_rounded, 'STAFF'.tr, () {
                Navigator.pop(context);
                _handleOwnerOptions('staff');
              }),
              _buildIGActionSmall(Icons.archive_rounded, 'ARCHIVES'.tr, () {
                Navigator.pop(context);
                _handleOwnerOptions('archive');
              }),
            ] else ...[
              _buildIGActionSmall(Icons.report_problem_rounded, 'REPORT'.tr, () {
                Navigator.pop(context);
                _showReportDialog();
              }, color: Colors.orangeAccent),
              const SizedBox(height: 12),
              _buildIGActionSmall(Icons.block_rounded, 'BLOCK'.tr, () {
                Navigator.pop(context);
                _showBlockConfirm();
              }, color: Colors.redAccent),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  void _showReportDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceContainer.withValues(alpha: 0.95),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: BorderSide(color: Colors.orangeAccent.withValues(alpha: 0.2))),
        title: Row(
          children: [
            const Icon(Icons.report_problem_rounded, color: Colors.orangeAccent, size: 20),
            const SizedBox(width: 10),
            Text('report_club'.tr, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              maxLines: 3,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'reason_details'.tr,
                hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.03),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Colors.orangeAccent, width: 1)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('cancel'.tr, style: const TextStyle(color: Colors.white54))),
          Container(
            decoration: BoxDecoration(
              color: Colors.orangeAccent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextButton(
              onPressed: () async {
                await _socialService.reportClub(organizerId: widget.organizerId, reason: 'user_reported', details: controller.text);
                if (mounted && ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('report_sent'.tr),
                      backgroundColor: Colors.orangeAccent,
                    ),
                  );
                }
              },
              child: Text('send'.tr, style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  void _handleShare() {
    SharePlus.instance.share(ShareParams(text: 'Check out ${widget.organizerName} on Sivox! 👋'));
  }

  Future<bool> _saveIndividualField(String field, dynamic val) async {
    try {
      if (field == 'bio') {
        await _supabase.from('organizer_profiles').update({'bio': val}).eq('id', widget.organizerId);
      } else {
        await _supabase.from('organizer_profiles').update({field: val}).eq('id', widget.organizerId);
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  List<Widget> _buildActiveEventSlivers() {
    return [
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => _buildPremiumEventCard(_filteredEvents[index], isOwner),
          childCount: _filteredEvents.length,
        ),
      ),
    ];
  }

  Widget _buildPermanentGallery() {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 1,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            if (isOwner && index == 0) return _buildAddGalleryButton();
            final imgIndex = isOwner ? index - 1 : index;
            final url = _permanentImages[imgIndex];
            return _buildIGGalleryItem(url, index: imgIndex);
          },
          childCount: isOwner ? _permanentImages.length + 1 : _permanentImages.length,
        ),
      ),
    );
  }

  Widget _buildAddGalleryButton() {
    return GestureDetector(
      onTap: _handleAddGalleryImage,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_a_photo_outlined, color: AppTheme.primary, size: 28),
              SizedBox(height: 8),
              Text('إضافة صورة', style: TextStyle(color: Colors.white24, fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleAddGalleryImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (image != null) {
      final url = await _storage.uploadImage(File(image.path), bucket: 'organizer-assets');
      if (url != null) {
        List<String> newGallery = List.from(_permanentImages);
        newGallery.insert(0, url);
        final success = await _updateGalleryData(newGallery);
        if (success) setState(() => _permanentImages = newGallery);
      }
    }
  }

  Future<bool> _updateGalleryData(List<String> newGallery) async {
    try {
      await _supabase.from('organizer_profiles').update({'permanent_gallery': newGallery}).eq('id', widget.organizerId);
      return true;
    } catch (e) {
      return false;
    }
  }

  Widget _buildIGGalleryItem(String url, {required int index}) {
    return GestureDetector(
      onTap: () => _openGalleryViewer(url),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 10,
              spreadRadius: -2,
            )
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(imageUrl: url, fit: BoxFit.cover),
            if (isOwner)
              Positioned(
                top: 8, right: 8,
                child: GestureDetector(
                  onTap: () => _deleteGalleryImage(index),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                    child: const Icon(Icons.close, color: Colors.white, size: 14),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _deleteGalleryImage(int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('حذف الصورة', style: TextStyle(color: Colors.white)),
        content: const Text('هل تريد حذف هذه الصورة من المعرض؟', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      List<String> newGallery = List.from(_permanentImages);
      newGallery.removeAt(index);
      final success = await _updateGalleryData(newGallery);
      if (success) setState(() => _permanentImages = newGallery);
    }
  }

  Future<void> _changeCoverPhoto() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (image != null) {
      final url = await _storage.uploadImage(File(image.path), bucket: 'organizer-assets');
      if (url != null) {
        List<String> newGallery = List.from(_permanentImages);
        if (newGallery.isNotEmpty) {
          newGallery[0] = url; // Replace cover photo
        } else {
          newGallery.add(url);
        }
        final success = await _updateGalleryData(newGallery);
        if (success) setState(() => _permanentImages = newGallery);
      }
    }
  }

  Widget _buildIGActionSmall(IconData icon, String label, VoidCallback onTap, {Color? color}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)))),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: (color ?? AppTheme.primary).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color ?? Colors.white, size: 20),
            ),
            const SizedBox(width: 16),
            Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            const Spacer(),
            const Icon(Icons.chevron_right_rounded, color: Colors.white24),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
          ),
          child: TextField(
            controller: _searchController,
            onChanged: (val) => setState(() => _searchQuery = val),
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'search_events_hint'.tr,
              hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
              prefixIcon: const Icon(Icons.search, color: AppTheme.primary, size: 18),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyEventsState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40.0),
        child: Column(
          children: [
            const Icon(Icons.event_busy, color: Colors.white10, size: 48),
            const SizedBox(height: 16),
            Text('no_active_events'.tr, style: const TextStyle(color: Colors.white24)),
          ],
        ),
      ),
    );
  }



  void _showSectionHelp(String section, {String? customDesc}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (context) => Container(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 24),
            const Icon(Icons.verified_user_rounded, color: AppTheme.primary, size: 32),
            const SizedBox(height: 16),
            Text(section.toUpperCase(), style: AppTheme.headlineStyle.copyWith(fontSize: 18)),
            const SizedBox(height: 12),
            Text(customDesc ?? 'Help content...'.tr, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.5)),
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

  Widget _buildSideIcon(IconData icon, VoidCallback onTap, {Color? color, String? label}) {
    final bool isSpecial = color != null && color != Colors.white70;
    return Tooltip(
      message: label ?? '',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                isSpecial ? color.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
                isSpecial ? color.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.01),
              ],
            ),
            shape: BoxShape.circle,
            border: Border.all(
              color: isSpecial ? color.withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.1),
              width: 1,
            ),
            boxShadow: [
              if (isSpecial)
                BoxShadow(
                  color: color.withValues(alpha: 0.2),
                  blurRadius: 8,
                  spreadRadius: 1,
                )
            ],
          ),
          child: Icon(
            icon, 
            color: color ?? Colors.white.withValues(alpha: 0.7), 
            size: 20
          ),
        ),
      ),
    );
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverAppBarDelegate({required this.minHeight, required this.maxHeight, required this.child});
  final double minHeight, maxHeight;
  final Widget child;
  @override double get minExtent => minHeight;
  @override double get maxExtent => math.max(maxHeight, minExtent);
  @override Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => SizedBox.expand(child: child);
  @override bool shouldRebuild(_SliverAppBarDelegate oldDelegate) => maxHeight != oldDelegate.maxHeight || minHeight != oldDelegate.minHeight || child != oldDelegate.child;
}

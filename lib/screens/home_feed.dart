import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:flutter/rendering.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:my_app/services/performance_service.dart';
import 'package:flutter/services.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/models/event.dart';
import 'package:my_app/services/event_service.dart';
import 'package:my_app/services/review_service.dart';
import 'package:my_app/services/localization_service.dart';
import 'package:my_app/services/translation_service.dart';
import 'package:my_app/services/notification_service.dart';
import 'package:my_app/services/favorite_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';

import 'package:my_app/screens/event_details.dart';
import 'package:my_app/screens/profile.dart';
import 'package:my_app/screens/tickets_list_screen.dart';
import 'package:my_app/screens/organizer_dashboard.dart';
import 'package:my_app/screens/organizer_main_wrapper.dart';
import 'package:my_app/widgets/home/home_app_bar.dart';
import 'package:my_app/widgets/home/home_search_bar.dart';
import 'package:my_app/widgets/home/bento_grid_widget.dart';
import 'package:my_app/widgets/home/home_bottom_nav.dart';
import 'package:my_app/screens/story_viewer_screen.dart';

import 'package:my_app/screens/club_profile_editor.dart';
import 'package:my_app/screens/map_discovery.dart';
import 'package:my_app/services/staff_service.dart';
import 'package:my_app/services/follow_service.dart';
import 'package:my_app/services/social_service.dart';


import 'package:my_app/screens/auth_screen.dart';
import 'package:my_app/services/feed_cache_service.dart';

class HomeFeedScreen extends StatefulWidget {
  const HomeFeedScreen({super.key});

  @override
  State<HomeFeedScreen> createState() => _HomeFeedScreenState();
}

class _HomeFeedScreenState extends State<HomeFeedScreen> with SingleTickerProviderStateMixin {
  final _eventService = EventService();
  final _favoriteService = FavoriteService();
  final _cacheService = FeedCacheService();
  final _followService = FollowService();
  final _searchController = TextEditingController();
  final _supabase = Supabase.instance.client;
  
  List<Event>? _allEvents;
  List<Event> _filteredEvents = [];
  List<dynamic> _allClubs = [];
  List<dynamic> _filteredClubs = [];
  
  Set<String> _faveIds = {};
  List<String> _followedOrganizerIds = [];
  List<String> _blockedOrganizerIds = [];
  final _socialService = SocialService();
  int _currentIndex = 0;
  bool _isLoading = true;
  DateTime? _lastBackPressTime;
  
  int _currentPage = 0;
  static const int _pageSize = 8;
  bool _hasMore = true;
  bool _isFetchingMore = false;
  bool _isHeaderVisible = true;
  final ScrollController _scrollController = ScrollController();

  static Position? _currentPosition;
  Map<String, double> _distances = {};
  String _selectedCategory = 'all';
  String _selectedCountryCode = 'DZ';
  List<Map<String, dynamic>> _myClubs = [];
  List<Map<String, dynamic>> _staffAssignments = [];
  late AnimationController _pulseController;
  RealtimeChannel? _eventsSubscription;
  final List<Map<String, dynamic>> _categories = [
    {'id': 'all', 'label': 'ALL'.tr, 'icon': FontAwesomeIcons.fireFlameCurved},
    {'id': 'nearest', 'label': 'near_you'.tr, 'icon': FontAwesomeIcons.locationCrosshairs},
    {'id': 'club', 'label': 'CLUB_BRAND'.tr, 'icon': FontAwesomeIcons.champagneGlasses},
    {'id': 'restaurant', 'label': 'RESTAURANT_BRAND'.tr, 'icon': FontAwesomeIcons.utensils},
    {'id': 'cafe', 'label': 'CAFE_BRAND'.tr, 'icon': FontAwesomeIcons.mugHot},
    {'id': 'entertainment', 'label': 'ENTERTAINMENT_BRAND'.tr, 'icon': FontAwesomeIcons.masksTheater},
  ];

  final _reviewService = ReviewService();
  bool _reviewCheckDone = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    NotificationService().startRealtimeListener();
    _setupRealtimeSync();
    _scrollController.addListener(_onScroll);
    _initSequence();
    _checkPendingReview();
  }

  Future<void> _checkPendingReview() async {
    if (_reviewCheckDone) return;
    _reviewCheckDone = true;

    await Future.delayed(const Duration(seconds: 3));
    final pending = await _reviewService.getPendingReviewEvent();
    if (pending != null && mounted) {
      _showCentralRatingDialog(pending);
    }
  }

  void _showCentralRatingDialog(Map<String, dynamic> data) {
    int currentRating = 5;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 40),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
              boxShadow: [
                BoxShadow(color: AppTheme.primary.withValues(alpha: 0.1), blurRadius: 40, spreadRadius: 10),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
                  child: const Icon(Icons.stars_rounded, color: AppTheme.primary, size: 40),
                ),
                const SizedBox(height: 20),
                Text(
                  'HOW_WAS_IT'.tr.toUpperCase(),
                  style: AppTheme.headlineStyle.copyWith(fontSize: 20),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'RATE_MESSAGE'.trArgs([data['club_name']]),
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) {
                    return GestureDetector(
                      onTap: () => setModalState(() => currentRating = index + 1),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(
                          index < currentRating ? Icons.star_rounded : Icons.star_outline_rounded,
                          color: index < currentRating ? AppTheme.secondary : Colors.white12,
                          size: 32,
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: () async {
                      final ok = await _reviewService.submitReview(data['organizer_id'], currentRating);
                      if (ok) {
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                        }
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('REVIEW_SUCCESS'.tr), backgroundColor: AppTheme.secondary),
                          );
                        }
                      }
                    },
                    child: Text('SUBMIT_REVIEW'.tr.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('LATER'.tr, style: const TextStyle(color: Colors.white24, fontSize: 11)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (_hasMore && !_isFetchingMore && !_isLoading) {
        _loadMore();
      }
    }

    final direction = _scrollController.position.userScrollDirection;
    if (direction == ScrollDirection.reverse && _isHeaderVisible) {
      setState(() => _isHeaderVisible = false);
    } else if (direction == ScrollDirection.forward && !_isHeaderVisible) {
      setState(() => _isHeaderVisible = true);
    }
  }

  Future<bool> _handlePop() async {
    final now = DateTime.now();
    if (_lastBackPressTime == null || now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
      _lastBackPressTime = now;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('PRESS_BACK_AGAIN'.tr, style: const TextStyle(color: Colors.white)),
          backgroundColor: AppTheme.surface,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          width: 200,
        ),
      );
      return false;
    }
    return true;
  }

  void _setupRealtimeSync() {
    _eventsSubscription = _supabase
        .channel('public:events_feed')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'events',
          callback: (payload) {
            if (mounted) {
              _initSequence();
            }
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _eventsSubscription?.unsubscribe();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _initSequence() async {
    if (!mounted) return;
    if (_allEvents == null || _allEvents!.isEmpty) {
      setState(() => _isLoading = true);
    }
    
    setState(() {
      _currentPage = 0;
      _hasMore = true;
      _isFetchingMore = false;
    });

    final cached = await _cacheService.getCachedEvents();
    if (cached.isNotEmpty && mounted) {
      setState(() {
        _allEvents = cached;
        _filteredEvents = cached;
        _isLoading = false;
      });
    }

    try {
    if (_currentPosition == null) {
      _updateLocationAutomatically(silent: true);
    } else {
      _sortEventsByDistance();
    }

      final events = await _eventService.getPaginatedEvents(from: 0, to: _pageSize - 1, countryCode: _selectedCountryCode);
      
      if (events.isNotEmpty) {
        _cacheService.saveEvents(events);
      }
      final clubs = await _supabase.from('organizer_profiles').select('*, profiles(full_name, avatar_url)');
      final favorites = await _favoriteService.getFavoriteEventIds();
      final followed = await _followService.getFollowedOrganizers();
      final blocked = await _socialService.getBlockedIds();
      
      if (mounted) {
        setState(() {
          _allEvents = events;
          _allClubs = clubs as List;
          _faveIds = favorites.toSet();
          _followedOrganizerIds = followed;
          _blockedOrganizerIds = blocked;
          _isLoading = false;
        });

        final uId = _supabase.auth.currentUser?.id;
        if (uId != null) {
          final myClubsRes = await _supabase.from('organizer_profiles').select().eq('owner_id', uId);
          if (mounted) {
            setState(() {
              _myClubs = List<Map<String, dynamic>>.from(myClubsRes);
            });
          }
        }

        final assignments = await StaffService().getActiveAssignments();
        if (mounted) {
          setState(() => _staffAssignments = assignments);
        }

        _applyFilters();
        if (_currentPosition != null) {
          _sortEventsByDistance();
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_isFetchingMore || !_hasMore) return;
    setState(() => _isFetchingMore = true);
    
    try {
      final nextPage = _currentPage + 1;
      final from = nextPage * _pageSize;
      final to = from + _pageSize - 1;
      
      final moreEvents = await _eventService.getPaginatedEvents(from: from, to: to, countryCode: _selectedCountryCode);
      
      if (mounted) {
        setState(() {
          if (moreEvents.isEmpty) {
            _hasMore = false;
          } else {
            _allEvents?.addAll(moreEvents);
            _currentPage = nextPage;
            if (moreEvents.length < _pageSize) _hasMore = false;
          }
          _isFetchingMore = false;
          _applyFilters();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isFetchingMore = false);
    }
  }

  Future<void> _updateLocationAutomatically({bool silent = false}) async {
    final pos = await _determinePosition(silent: silent);
    if (pos != null) {
      if (mounted) setState(() => _currentPosition = pos);
      _sortEventsByDistance();

      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (placemarks.isNotEmpty) {
          String? countryCode = placemarks.first.isoCountryCode;
          if (countryCode != null) {
            final isSupported = LocalizationService.supportedCountries.any((c) => c.code == countryCode);
            if (isSupported && mounted) {
              setState(() => _selectedCountryCode = countryCode);
              _applyFilters();
            }
          }
        }
      } catch (e) {
        debugPrint('Error reverse geocoding: $e');
      }

      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('location_synced'.tr),
          backgroundColor: AppTheme.secondary,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  Future<Position?> _determinePosition({bool silent = false}) async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!silent && mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: AppTheme.surfaceContainer,
              title: Text('location_services_disabled'.tr, style: const TextStyle(color: Colors.white)),
              content: Text('enable_location_msg'.tr, style: const TextStyle(color: Colors.white70)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('cancel'.tr, style: const TextStyle(color: Colors.white38)),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Geolocator.openLocationSettings();
                  },
                  child: Text('settings'.tr, style: const TextStyle(color: AppTheme.primary)),
                ),
              ],
            ),
          );
        }
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (!silent && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('location_permission_denied'.tr)));
          return null;
        }
      }
      
        if (permission == LocationPermission.deniedForever) {
        if (!silent && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('location_permission_denied_forever'.tr),
            action: SnackBarAction(
              label: 'settings'.tr,
              onPressed: () => Geolocator.openAppSettings(),
            ),
          ));
        }
        return null;
      }

      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${'locating'.tr}...'),
          duration: const Duration(seconds: 2),
        ));
      }

      Position? lastPos = await Geolocator.getLastKnownPosition();
      if (lastPos != null) return lastPos;

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (e.toString().contains('TimeoutException')) {
        debugPrint('Location fetch timed out');
        return null;
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      return null;
    }
  }

  void _sortEventsByDistance() {
    if (_currentPosition == null) return;

    final Map<String, double> tempDistances = {};
    
    if (_allEvents != null) {
      for (var e in _allEvents!) {
        if (e.latitude != null && e.longitude != null) {
          final dist = Geolocator.distanceBetween(_currentPosition!.latitude, _currentPosition!.longitude, e.latitude!, e.longitude!);
          tempDistances[e.id] = dist / 1000;
        }
      }
      _allEvents!.sort((a, b) {
        final dA = tempDistances[a.id] ?? 999999.0;
        final dB = tempDistances[b.id] ?? 999999.0;
        return dA.compareTo(dB);
      });
    }

    _allClubs.sort((a, b) {
      final latA = a['latitude'] as double?;
      final lngA = a['longitude'] as double?;
      final latB = b['latitude'] as double?;
      final lngB = b['longitude'] as double?;
      
      double dA = 999999.0;
      double dB = 999999.0;
      
      if (latA != null && lngA != null) {
        dA = Geolocator.distanceBetween(_currentPosition!.latitude, _currentPosition!.longitude, latA, lngA);
        tempDistances[a['id']] = dA / 1000;
      }
      if (latB != null && lngB != null) {
        dB = Geolocator.distanceBetween(_currentPosition!.latitude, _currentPosition!.longitude, latB, lngB);
        tempDistances[b['id']] = dB / 1000;
      }
      return dA.compareTo(dB);
    });

    setState(() {
      _distances = tempDistances;
      _applyFilters();
    });
  }

  void _applyFilters() {
    if (_allEvents == null) return;
    final query = _searchController.text.toLowerCase();
    
    setState(() {
      _filteredEvents = _allEvents!.where((e) {
        if (_blockedOrganizerIds.contains(e.organizerId)) return false;
        if (e.countryCode != _selectedCountryCode) return false;
        
        bool matchesCat = false;
        if (_selectedCategory == 'all' || _selectedCategory == 'nearest') {
          matchesCat = true;
        } else if (_selectedCategory == 'following') {
          matchesCat = _followedOrganizerIds.contains(e.organizerId);
        } else if (_selectedCategory == 'favorites') {
          matchesCat = _faveIds.contains(e.id);
        } else {
          matchesCat = e.category?.toLowerCase().contains(_selectedCategory) ?? false;
        }

        bool matchesQuery = true;
        if (query.isNotEmpty) {
          final title = e.title.toLowerCase();
          final venue = (e.venue ?? "").toLowerCase();
          matchesQuery = title.contains(query) || venue.contains(query);
        }
        
        return matchesCat && matchesQuery;
      }).toList();

      _filteredClubs = _allClubs.where((c) {
        final id = c['id'].toString();
        if (_blockedOrganizerIds.contains(id)) return false;
        final name = (c['name'] ?? c['profiles']?['full_name'] ?? '').toString().toLowerCase();
        final matchesQuery = name.contains(query);
        
        bool matchesType = true;
        if (['club', 'restaurant', 'cafe', 'entertainment'].contains(_selectedCategory)) {
          matchesType = (c['business_type'] ?? 'club') == _selectedCategory;
        }
        
        return matchesQuery && matchesType;
      }).toList();

      _filteredClubs.sort((a, b) {
        final aF = _followedOrganizerIds.contains(a['id'].toString());
        final bF = _followedOrganizerIds.contains(b['id'].toString());
        if (aF && !bF) return -1;
        if (!aF && bF) return 1;
        return 0;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final role = (user?.userMetadata?['role']?.toString() ?? 'attendee').toLowerCase();
    final isAuthorized = role == 'organizer' || role == 'manager' || role == 'owner' || role == 'admin' || role == 'staff' || _myClubs.isNotEmpty || _staffAssignments.isNotEmpty;
    
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _handlePop();
        if (shouldPop && mounted) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: _buildCurrentPage(isAuthorized),
        floatingActionButton: _currentIndex == 0 ? _buildFABStack() : null,
        bottomNavigationBar: HomeBottomNav(
          isHeaderVisible: _isHeaderVisible,
          currentIndex: _currentIndex,
          onTabSelected: (index) {
            setState(() => _currentIndex = index);
            if (index == 0) _initSequence();
          },
        ),
      ),
    );
  }

  Widget _buildCurrentPage(bool isAuthorized) {
    switch (_currentIndex) {
      case 0:
        if (_isLoading) return _buildHomeShimmer();
        return _buildMainContent(isAuthorized);
      case 1:
        return const MapDiscoveryScreen();
      case 2:
        return const TicketsListScreen();
      case 3:
        return const ProfileScreen();
      default:
        if (_isLoading) return _buildHomeShimmer();
        return _buildMainContent(isAuthorized);
    }
  }

  Widget _buildMainContent(bool isAuthorized) {
    return Stack(
      children: [
        if (PerformanceService.useBlur) ...[
          Positioned(top: -100, right: -100, child: _glow(AppTheme.primary.withValues(alpha: 0.06))),
          Positioned(bottom: -150, left: -150, child: _glow(AppTheme.secondary.withValues(alpha: 0.06))),
        ],

        SafeArea(
          child: RefreshIndicator(
            onRefresh: _initSequence,
            color: AppTheme.primary,
            child: _buildHomeContent(),
          ),
        ),
      ],
    );
  }



  Widget _buildHomeContent() {
    final country = LocalizationService.getCountryByCode(_selectedCountryCode);
    return CustomScrollView(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      slivers: [
        HomeSliverAppBar(
          selectedCountryCode: _selectedCountryCode,
          onCountryChanged: (code) {
            setState(() => _selectedCountryCode = code);
            _applyFilters();
          },
        ),
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              HomeSearchBar(
                searchController: _searchController,
                onChanged: _applyFilters,
              ),
              const SizedBox(height: 24),
              _buildDynamicHero(country.name),
              const SizedBox(height: 32),
              _buildCategoryStrip(),
              const SizedBox(height: 32),
              
              if (_allClubs.any((c) => _hasActiveEvents(c['id'].toString())))
                _buildActiveClubsStories(),
              
              const SizedBox(height: 32),
              _buildSectionHeader('NOW_TRENDING'.tr, 'TONIGHT'.tr, showSeeAll: true),
              const SizedBox(height: 24),
              BentoGridWidget(events: _allEvents ?? [], onEventTap: _goDetails),
              const SizedBox(height: 48),
              _buildSectionHeader('DISCOVER'.tr, 'NEAR_YOU'.tr),
              const SizedBox(height: 24),
              _buildNearYouScroller(),
              const SizedBox(height: 48),
              _buildSectionHeader('CITIES'.tr, 'CITY_PULSE'.tr),
              const SizedBox(height: 16),
              _buildCityPulse(),
              const SizedBox(height: 48),
              _buildSectionHeader('FEED'.tr, 'ALL_EVENTS'.tr),
              const SizedBox(height: 16),
            ],
          ),
        ),
        
        if (_filteredEvents.isEmpty)
           SliverToBoxAdapter(child: _buildEmptyState())
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _buildEventCard(_filteredEvents[index]),
                childCount: _filteredEvents.length,
              ),
            ),
          ),
          
        if (_isFetchingMore)
          SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: const CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2),
              ),
            ),
          ),
          
        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ],
    );
  }



  bool _hasActiveEvents(String clubId) {
    if (_allEvents == null) return false;
    return _allEvents!.any((e) => e.organizerId == clubId && _isEventActiveForStory(e));
  }

  bool _isEventActiveForStory(Event e) {
    if (e.isArchived) return false;
    
    // Check if the event date has passed (add 24h buffer for late night events)
    if ((e.dateTime ?? '').isNotEmpty) {
      try {
        // Try parsing, assuming format is sortable like YYYY-MM-DD
        String dateStr = e.dateTime!;
        // Handle formats like DD/MM/YYYY manually if needed, but standard is YYYY-MM-DD
        if (dateStr.contains('/')) {
           final parts = dateStr.split(' ')[0].split('/');
           if (parts.length == 3) {
             dateStr = '${parts[2]}-${parts[1]}-${parts[0]}';
           }
        }
        final eventDate = DateTime.parse(dateStr);
        if (eventDate.add(const Duration(hours: 24)).isBefore(DateTime.now())) {
          return false;
        }
      } catch (_) {
        // If parsing fails, default to showing it
      }
    }
    return true;
  }

  Widget _buildActiveClubsStories() {
    // 1. Group events by organizerId
    Map<String, List<Event>> clubEvents = {};
    if (_allEvents != null) {
      for (var e in _allEvents!) {
        if (e.organizerId != null && _isEventActiveForStory(e)) {
          clubEvents.putIfAbsent(e.organizerId!, () => []).add(e);
        }
      }
    }

    // 2. Filter ALL clubs to ONLY those that have active events
    final clubsWithStories = _allClubs.where((c) {
      final id = c['id'].toString();
      return clubEvents.containsKey(id) && clubEvents[id]!.isNotEmpty;
    }).toList();

    // 3. Optional: Sort so followed clubs with stories appear first
    clubsWithStories.sort((a, b) {
      final bool aFollowed = _followedOrganizerIds.contains(a['id'].toString());
      final bool bFollowed = _followedOrganizerIds.contains(b['id'].toString());
      if (aFollowed && !bFollowed) return -1;
      if (!aFollowed && bFollowed) return 1;
      return 0;
    });

    if (clubsWithStories.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text('DISCOVER'.tr.toUpperCase(), style: AppTheme.labelStyle.copyWith(letterSpacing: 2, fontSize: 10, color: AppTheme.secondary)),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 110,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            physics: const BouncingScrollPhysics(),
            itemCount: clubsWithStories.length,
            itemBuilder: (ctx, idx) {
              final club = clubsWithStories[idx];
              final hasNewStories = true; // In the future, check seen status
              return _buildStoryCircle(
                club,
                hasUnseen: hasNewStories,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StoryViewerScreen(
                      clubs: clubsWithStories.cast<Map<String, dynamic>>(),
                      clubEvents: clubEvents,
                      initialIndex: idx,
                    ),
                  ),
                ),
              );
            }
          ),
        ),
      ],
    );
  }

  Widget _buildStoryCircle(dynamic club, {required bool hasUnseen, required VoidCallback onTap}) {
    final String name = club['name'] ?? club['profiles']?['full_name'] ?? 'Club';
    final String? avatarUrl = club['avatar_url'] ?? club['profiles']?['avatar_url'];

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 80,
        margin: const EdgeInsets.only(right: 14),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: hasUnseen ? const LinearGradient(
                  colors: [AppTheme.primary, AppTheme.secondary, Colors.blueAccent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ) : null,
                border: !hasUnseen ? Border.all(color: Colors.white12, width: 1.5) : null,
                boxShadow: hasUnseen ? [BoxShadow(color: AppTheme.primary.withValues(alpha: 0.3), blurRadius: 12, spreadRadius: 1)] : null,
              ),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.background,
                ),
                child: CircleAvatar(
                  radius: 32,
                  backgroundColor: AppTheme.surfaceContainer,
                  backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                  child: avatarUrl == null
                      ? Text(name.substring(0, 1).toUpperCase(), style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 22))
                      : null,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              name,
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDynamicHero(String countryName) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Background subtle glow
          Positioned(
            right: -20,
            top: 10,
            child: Container(
              width: 150,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.primary.withValues(alpha: 0.15),
                boxShadow: [
                  BoxShadow(color: AppTheme.primary.withValues(alpha: 0.35), blurRadius: 60, spreadRadius: 30)
                ]
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3), width: 1.5),
                  boxShadow: [BoxShadow(color: AppTheme.primary.withValues(alpha: 0.1), blurRadius: 10)],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.location_on_rounded, color: AppTheme.primary, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      countryName.toUpperCase(),
                      style: AppTheme.labelStyle.copyWith(color: AppTheme.primary, fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: 'DISCOVER_THE\n'.tr,
                      style: AppTheme.headlineStyle.copyWith(fontSize: 34, height: 1.1, color: Colors.white70),
                    ),
                    TextSpan(
                      text: 'NIGHTLIFE'.tr,
                      style: AppTheme.headlineStyle.copyWith(
                        fontSize: 58, 
                        height: 1.0, 
                        color: Colors.white,
                        letterSpacing: -1,
                        shadows: [
                          Shadow(color: AppTheme.primary.withValues(alpha: 0.5), blurRadius: 30, offset: const Offset(0, 4)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCityPulse() {
    final cities = LocalizationService.getCitiesByCountry(_selectedCountryCode);
    return SizedBox(
      height: 45,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        itemCount: cities.length,
        itemBuilder: (context, index) {
          return Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Center(
              child: Text(
                cities[index].toUpperCase(),
                style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1),
              ),
            ),
          );
        },
      ),
    );
  }




  Widget _buildSectionHeader(String label, String title, {bool showSeeAll = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 28,
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: [BoxShadow(color: AppTheme.primary.withValues(alpha: 0.4), blurRadius: 8)],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label.toUpperCase(),
                    style: AppTheme.labelStyle.copyWith(color: AppTheme.secondary, fontSize: 9, letterSpacing: 2.5),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    title.toUpperCase(),
                    style: AppTheme.headlineStyle.copyWith(fontSize: 26, letterSpacing: -1, height: 1),
                  ),
                ],
              ),
            ],
          ),
          const Spacer(),
          if (showSeeAll)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: Text(
                'SEE ALL',
                style: AppTheme.labelStyle.copyWith(fontSize: 9, color: Colors.white38, letterSpacing: 1),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCategoryStrip() {
    return SizedBox(
      height: 54,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        physics: const BouncingScrollPhysics(),
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final cat = _categories[index];
          final catId = cat['id'] as String;
          final catLabel = cat['label'] as String? ?? catId;
          final catIcon = cat['icon'] as IconData?;
          final sel = _selectedCategory == catId;
          return GestureDetector(
            onTap: () async {
              setState(() => _selectedCategory = catId);
              if (catId == 'nearest' && _currentPosition == null) {
                await _updateLocationAutomatically(silent: true);
              }
              _applyFilters();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: sel ? const LinearGradient(
                  colors: [AppTheme.primary, AppTheme.secondary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ) : LinearGradient(
                  colors: [Colors.white.withValues(alpha: 0.1), Colors.white.withValues(alpha: 0.02)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: sel ? AppTheme.primary : Colors.white.withValues(alpha: 0.15),
                  width: sel ? 1.5 : 1,
                ),
                boxShadow: sel
                    ? [
                        BoxShadow(color: AppTheme.primary.withValues(alpha: 0.4), blurRadius: 20, spreadRadius: -2, offset: const Offset(0, 8)),
                        BoxShadow(color: AppTheme.secondary.withValues(alpha: 0.2), blurRadius: 10, spreadRadius: 2),
                      ]
                    : [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 10, offset: const Offset(0, 4)),
                      ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (catIcon != null) ...[
                    FaIcon(
                      catIcon,
                      size: 13,
                      color: sel ? Colors.black : Colors.white54,
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    catLabel.toUpperCase(),
                    style: TextStyle(
                      color: sel ? Colors.black : Colors.white70,
                      fontSize: 11,
                      fontWeight: sel ? FontWeight.w900 : FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildNearYouScroller() {
    if (_allEvents == null || _allEvents!.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 380,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        itemCount: _allEvents!.length,
        itemBuilder: (context, index) {
          final e = _allEvents![index];
          return Container(
            width: 280,
            margin: const EdgeInsets.only(right: 20),
            child: _buildNearYouCard(e),
          );
        },
      ),
    );
  }

  Widget _buildNearYouCard(Event e) {
    final isFave = _faveIds.contains(e.id);
    final hasImg = e.imageUrl != null && e.imageUrl!.isNotEmpty;
    return GestureDetector(
      onTap: () => _goDetails(e),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1.5),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 25, offset: const Offset(0, 10)),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: hasImg
                          ? CachedNetworkImage(imageUrl: e.imageUrl!, fit: BoxFit.cover)
                          : Container(color: const Color(0xFF1A1A1A)),
                    ),
                    // تدرج الأسفل
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: const [0.3, 1.0],
                            colors: [Colors.transparent, Colors.black.withValues(alpha: 0.85)],
                          ),
                        ),
                      ),
                    ),
                    // زر المفضلة
                    Positioned(
                      top: 14, right: 14,
                      child: GestureDetector(
                        onTap: () async {
                          await _favoriteService.toggleFavorite(e);
                          if (mounted) {
                            setState(() {
                              if (_faveIds.contains(e.id)) {
                                _faveIds.remove(e.id);
                              } else {
                                _faveIds.add(e.id);
                              }
                            });
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.4),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                          ),
                          child: Icon(
                            isFave ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded,
                            color: isFave ? AppTheme.primary : Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                    // التاريخ في أسفل الصورة
                    if ((e.dateTime ?? '').isNotEmpty)
                      Positioned(
                        bottom: 14, left: 14,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                          ),
                          child: Text(
                            (e.dateTime ?? '').length > 10 ? (e.dateTime!).substring(0, 10) : (e.dateTime ?? ''),
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            e.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.5),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(Icons.location_on_rounded, color: AppTheme.primary, size: 14),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        e.venue?.toUpperCase() ?? 'VENUE',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
              if (!e.hidePrice)
                Text(
                  e.price == 0 ? 'FREE'.tr : LocalizationService.formatPrice(e.price, e.countryCode),
                  style: TextStyle(
                    color: e.price == 0 ? Colors.tealAccent : AppTheme.secondary,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }



  Widget _buildFABStack() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _buildPulseNeonFAB(),
        const SizedBox(height: 16),
        _buildOrganizeFAB(),
      ],
    );
  }

  Widget _buildOrganizeFAB() {
    final hasClub = _myClubs.isNotEmpty;
    final isStaff = _staffAssignments.isNotEmpty;
    final hasMultiple = _myClubs.length > 1 || (_myClubs.isNotEmpty && isStaff);

    // Determine label & icon based on state
    IconData fabIcon;
    String fabLabel;
    if (!hasClub && !isStaff) {
      fabIcon = Icons.add_business_rounded;
      fabLabel = 'أنشئ صفحتك';
    } else if (hasMultiple) {
      fabIcon = Icons.dashboard_rounded;
      fabLabel = 'لوحة التحكم';
    } else {
      fabIcon = Icons.add_circle_rounded;
      fabLabel = 'نشر فعالية';
    }

    return FloatingActionButton.extended(
      onPressed: () {
        if (_supabase.auth.currentUser == null) {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const AuthScreen()));
        } else if (_myClubs.length == 1 && _staffAssignments.isEmpty) {
          final club = _myClubs.first;
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => OrganizerDashboardScreen(
              clubId: club['id'],
              clubName: club['name'],
              businessType: club['business_type'],
            ),
          )).then((_) => _initSequence());
        } else if (_myClubs.isNotEmpty || _staffAssignments.isNotEmpty) {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => const OrganizerMainWrapper(),
          )).then((_) => _initSequence());
        } else {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const ClubProfileEditorScreen(isNew: true))).then((_) => _initSequence());
        }
      },
      heroTag: 'fab_organize',
      backgroundColor: AppTheme.primary,
      icon: Icon(fabIcon, color: Colors.black),
      label: Text(fabLabel, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 1)),
    );
  }

  Widget _buildPulseNeonFAB() {
    return AnimatedScale(
      duration: const Duration(milliseconds: 300),
      scale: _isHeaderVisible ? 1.0 : 0.0,
      curve: Curves.easeOutCubic,
      child: ScaleTransition(
        scale: Tween(begin: 1.0, end: 1.1).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut)),
        child: GestureDetector(
          onTap: () async {
            setState(() => _selectedCategory = 'nearest');
            await _updateLocationAutomatically(silent: false);
            _initSequence();
          },
          child: Container(
            width: 50, height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _selectedCategory == 'nearest' ? AppTheme.secondary : Colors.black,
              border: Border.all(color: AppTheme.secondary, width: 2),
              boxShadow: [
                BoxShadow(color: AppTheme.secondary.withValues(alpha: 0.5 * _pulseController.value), blurRadius: 20, spreadRadius: 2),
              ],
            ),
            child: Icon(Icons.near_me_rounded, color: _selectedCategory == 'nearest' ? Colors.black : AppTheme.secondary, size: 24),
          ),
        ),
      ),
    );
  }






  Widget _buildEventCard(Event e) {
    final isFave = _faveIds.contains(e.id);
    final hasImg = e.imageUrl != null && e.imageUrl!.isNotEmpty;
    final dist = _distances[e.id];
    
    return GestureDetector(
      onTap: () => _goDetails(e),
      child: Container(
        margin: const EdgeInsets.only(bottom: 24),
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1.5),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 25, offset: const Offset(0, 10))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // قسم الصورة
            Hero(
              tag: 'home-event-${e.id}',
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
                child: SizedBox(
                  height: 230,
                  width: double.infinity,
                  child: Stack(
                    children: [
                      // الصورة
                      Positioned.fill(
                        child: hasImg
                            ? CachedNetworkImage(
                                imageUrl: e.imageUrl!,
                                fit: BoxFit.cover,
                                placeholder: (ctx, url) => Container(color: const Color(0xFF1A1A1A)),
                              )
                            : Container(
                                color: const Color(0xFF1A1A1A),
                                child: const Icon(Icons.image_not_supported_rounded, color: Colors.white12, size: 48),
                              ),
                      ),
                      // تدرج الأسفل للحد الفاصل
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              stops: const [0.4, 1.0],
                              colors: [Colors.transparent, const Color(0xFF141414)],
                            ),
                          ),
                        ),
                      ),
                      // شارة المسافة (أعلى يسار)
                      if (dist != null)
                        Positioned(
                          top: 14, left: 14,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.near_me_rounded, color: AppTheme.primary, size: 12),
                                const SizedBox(width: 6),
                                Text('${dist.toStringAsFixed(1)} KM', style: const TextStyle(color: AppTheme.primary, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                              ],
                            ),
                          ),
                        ),
                      // زر المفضلة (أعلى يمين)
                      Positioned(
                        top: 14, right: 14,
                        child: GestureDetector(
                          onTap: () async {
                            await _favoriteService.toggleFavorite(e);
                            if (mounted) {
                              setState(() {
                                if (_faveIds.contains(e.id)) {
                                  _faveIds.remove(e.id);
                                } else {
                                  _faveIds.add(e.id);
                                }
                              });
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.4),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                            ),
                            child: Icon(
                              isFave ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded,
                              color: isFave ? AppTheme.primary : Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // قسم المعلومات
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 19,
                                letterSpacing: -0.5,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                const Icon(Icons.location_on_rounded, color: AppTheme.primary, size: 14),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    e.venue?.toUpperCase() ?? 'VENUE',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      if (!e.hidePrice) _buildPriceTag(e),
                    ],
                  ),
                  if ((e.dateTime ?? '').isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      height: 1,
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Icon(Icons.calendar_today_rounded, color: Colors.white38, size: 14),
                        const SizedBox(width: 8),
                        Text(
                          (e.dateTime ?? '').length > 16 ? e.dateTime!.substring(0, 16) : (e.dateTime ?? ''),
                          style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        const Spacer(),
                        if (e.category != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              e.category!.toUpperCase(),
                              style: const TextStyle(color: AppTheme.primary, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriceTag(Event e) {
    if (e.hidePrice) return _buildPriceChip('RSVP', AppTheme.secondary);
    if (e.price == 0) return _buildPriceChip('FREE_ENTRY'.tr, Colors.tealAccent);
    
    final bool hasFollowerDisc = e.followerDiscount > 0;
    final bool hasGlobalDisc = e.globalDiscount > 0;
    final bool hasAnyDisc = hasFollowerDisc || hasGlobalDisc;
    
    final double totalDiscPerc = (e.followerDiscount + e.globalDiscount).clamp(0.0, 90.0);
    final double finalPrice = e.price * (1 - totalDiscPerc / 100);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: (hasGlobalDisc ? Colors.redAccent : AppTheme.primary).withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: (hasGlobalDisc ? Colors.redAccent : AppTheme.primary).withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(color: (hasGlobalDisc ? Colors.redAccent : AppTheme.primary).withValues(alpha: 0.1), blurRadius: 10, spreadRadius: 1),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (hasAnyDisc)
            Text(
              LocalizationService.formatPrice(e.price, e.countryCode),
              style: const TextStyle(color: Colors.white24, fontSize: 10, decoration: TextDecoration.lineThrough),
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasGlobalDisc)
                const Icon(Icons.bolt_rounded, color: Colors.redAccent, size: 12),
              if (hasFollowerDisc && !hasGlobalDisc)
                const Icon(Icons.lock_outline_rounded, color: AppTheme.secondary, size: 10),
              if (hasAnyDisc)
                const SizedBox(width: 4),
              Text(
                LocalizationService.formatPrice(finalPrice, e.countryCode),
                style: AppTheme.labelStyle.copyWith(
                  color: hasGlobalDisc ? Colors.redAccent : (hasFollowerDisc ? AppTheme.secondary : AppTheme.primary), 
                  fontWeight: FontWeight.bold, 
                  fontSize: 14
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPriceChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label, style: AppTheme.labelStyle.copyWith(color: color, fontWeight: FontWeight.bold, fontSize: 14)),
    );
  }

  Widget _buildEmptyState() {
    final bool isFollowingTab = _selectedCategory == 'following';
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.event_busy_rounded, color: Colors.white12, size: 64),
          const SizedBox(height: 16),
          Text(
            isFollowingTab ? 'discover_clubs'.tr : 'NO_EVENTS_YET'.tr,
            style: const TextStyle(color: Colors.white24, fontSize: 14),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _initSequence,
            child: Text('retry'.tr, style: const TextStyle(color: AppTheme.primary)),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeShimmer() {
    return Shimmer.fromColors(
      baseColor: Colors.white.withValues(alpha: 0.05),
      highlightColor: Colors.white.withValues(alpha: 0.1),
      child: ListView.builder(
        padding: const EdgeInsets.all(24),
        itemCount: 5,
        itemBuilder: (context, index) => Container(
          margin: const EdgeInsets.only(bottom: 24),
          height: 180,
          decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(32)),
        ),
      ),
    );
  }








  void _goDetails(Event e) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.9,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
          child: EventDetailsScreen(event: e),
        ),
      ),
    ).then((_) => _initSequence());
  }




  Widget _glow(Color color) {
    if (!PerformanceService.useBlur) return const SizedBox.shrink();
    return Container(
      width: 400,
      height: 400,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          BoxShadow(
            color: color,
            blurRadius: 200,
            spreadRadius: 50,
          ),
        ],
      ),
    );
  }

}

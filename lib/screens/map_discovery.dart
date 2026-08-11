import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:my_app/models/event.dart';
import 'package:my_app/services/event_service.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/screens/event_details.dart';
import 'package:my_app/screens/club_profile.dart';
import 'package:geolocator/geolocator.dart';
import 'package:my_app/services/translation_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MapDiscoveryScreen extends StatefulWidget {
  const MapDiscoveryScreen({super.key});

  @override
  State<MapDiscoveryScreen> createState() => _MapDiscoveryScreenState();
}

class _MapDiscoveryScreenState extends State<MapDiscoveryScreen> {
  GoogleMapController? _mapController;
  final _eventService = EventService();
  List<Event> _allEvents = [];
  List<Event> _filteredEvents = [];
  Set<Marker> _markers = {};
  bool _isLoading = true;
  String _selectedFilter = 'all';
  final LatLng _initialPosition = const LatLng(36.7538, 3.0588); // Default to Algiers
  
  final PageController _pageController = PageController(viewportFraction: 0.88);
  Map<String, BitmapDescriptor> _customIcons = {};

  final List<Map<String, dynamic>> _filterOptions = [
    {'id': 'all', 'icon': FontAwesomeIcons.fireFlameCurved, 'label': 'ALL'},
    {'id': 'club', 'icon': FontAwesomeIcons.champagneGlasses, 'label': 'CLUB'},
    {'id': 'restaurant', 'icon': FontAwesomeIcons.utensils, 'label': 'DINE'},
    {'id': 'cafe', 'icon': FontAwesomeIcons.mugHot, 'label': 'CAFE'},
    {'id': 'entertainment', 'icon': FontAwesomeIcons.masksTheater, 'label': 'FUN'},
  ];

  @override
  void initState() {
    super.initState();
    _initCustomIcons().catchError((e) {
      debugPrint('Error init markers: $e');
    }).whenComplete(() {
      _loadData();
    });
  }

  Future<void> _initCustomIcons() async {
    final clubIcon = await _createCustomMarker(Icons.nightlife, AppTheme.primary, hasMusic: true);
    final dineIcon = await _createCustomMarker(Icons.restaurant, Colors.orangeAccent);
    final cafeIcon = await _createCustomMarker(Icons.local_cafe_rounded, Colors.brown);
    final funIcon = await _createCustomMarker(Icons.theater_comedy_rounded, Colors.lightBlueAccent);
    final allIcon = await _createCustomMarker(Icons.grid_view_rounded, Colors.white);

    if (mounted) {
      setState(() {
        _customIcons = {
          'club': clubIcon,
          'restaurant': dineIcon,
          'cafe': cafeIcon,
          'entertainment': funIcon,
          'all': allIcon,
        };
      });
    }
  }

  Future<BitmapDescriptor> _createCustomMarker(IconData iconData, Color color, {bool hasMusic = false, String? label}) async {
    try {
      final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(pictureRecorder);
      const double size = 180.0; // Increased size to accommodate label
      const double radius = 50.0;
      const double centerX = 90.0;
      const double centerY = 60.0;
      canvas.scale(0.66, 0.66);

      // 1. Draw Glow
      final Paint glowPaint = Paint()
        ..color = color.withValues(alpha: 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
      canvas.drawCircle(const Offset(centerX, centerY), radius - 5, glowPaint);

      // 2. Draw Main Circle (Solid Color matching category)
      final Paint circlePaint = Paint()..color = color;
      canvas.drawCircle(const Offset(centerX, centerY), radius - 10, circlePaint);

      // 3. Draw Border
      final Paint borderPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      canvas.drawCircle(const Offset(centerX, centerY), radius - 10, borderPaint);

      // 4. Draw Icon(s)
      TextPainter painter = TextPainter(textDirection: TextDirection.ltr);
      
      if (hasMusic) {
        painter.text = TextSpan(
          text: String.fromCharCode(Icons.local_bar_rounded.codePoint),
          style: TextStyle(fontSize: 40, fontFamily: Icons.local_bar_rounded.fontFamily, color: const Color(0xFF1A1A1A)),
        );
        painter.layout();
        painter.paint(canvas, const Offset(centerX - 25, centerY - 20));

        painter.text = TextSpan(
          text: String.fromCharCode(Icons.music_note_rounded.codePoint),
          style: TextStyle(fontSize: 30, fontFamily: Icons.music_note_rounded.fontFamily, color: const Color(0xFF1A1A1A)),
        );
        painter.layout();
        painter.paint(canvas, const Offset(centerX + 5, centerY - 5));
      } else {
        painter.text = TextSpan(
          text: String.fromCharCode(iconData.codePoint),
          style: TextStyle(fontSize: 45, fontFamily: iconData.fontFamily, color: color == Colors.brown ? Colors.white : const Color(0xFF1A1A1A)),
        );
        painter.layout();
        painter.paint(canvas, Offset(centerX - painter.width / 2, centerY - painter.height / 2));
      }

      // 5. Draw Label if provided
      if (label != null && label.isNotEmpty) {
        final String displayLabel = label.length > 12 ? '${label.substring(0, 10)}..' : label;
        TextPainter labelPainter = TextPainter(textDirection: TextDirection.ltr);
        labelPainter.text = TextSpan(
          text: displayLabel.toUpperCase(),
          style: TextStyle(
            fontSize: 18, 
            color: Colors.white, 
            fontWeight: FontWeight.bold, 
            letterSpacing: 1,
            shadows: [
              Shadow(color: Colors.black, blurRadius: 4, offset: const Offset(2, 2)),
            ],
          ),
        );
        labelPainter.layout();

        // Label Background (Pill shape)
        final double labelWidth = labelPainter.width + 20;
        final RRect labelRect = RRect.fromLTRBR(
          centerX - labelWidth / 2, 
          centerY + radius + 5, 
          centerX + labelWidth / 2, 
          centerY + radius + 35, 
          const Radius.circular(10)
        );
        
        final Paint labelBgPaint = Paint()..color = Colors.black.withValues(alpha: 0.7);
        canvas.drawRRect(labelRect, labelBgPaint);
        
        final Paint labelBorderPaint = Paint()
          ..color = color.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
        canvas.drawRRect(labelRect, labelBorderPaint);

        labelPainter.paint(canvas, Offset(centerX - labelPainter.width / 2, centerY + radius + 10));
      }

      final ui.Image image = await pictureRecorder.endRecording().toImage(size.toInt(), size.toInt());
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return BitmapDescriptor.bytes(byteData!.buffer.asUint8List());
    } catch (e) {
      debugPrint('Bitmap generation failed: $e');
      return BitmapDescriptor.defaultMarker;
    }
  }

  Future<void> _loadData() async {
    // 1. Show map immediately with default position
    setState(() => _isLoading = false);

    // 2. Fetch events in background
    // 2. Fetch events and clubs in parallel
    Future.wait<dynamic>([
      _eventService.getAllEvents(),
      Supabase.instance.client.from('organizer_profiles').select().not('latitude', 'is', null),
    ]).then((results) {
      if (mounted) {
        final List<Event> events = results[0] as List<Event>;
        final List<dynamic> clubs = results[1] as List<dynamic>;

        List<Event> allCombined = [...events];
        
        // Add clubs that don't have events active on the map already (optional deduplication)
        for (var c in clubs) {
          final clubId = c['id'].toString();
          // Avoid double markers if event already exists for this club at same location
          bool exists = events.any((e) => e.organizerId == clubId);
          if (!exists) {
            allCombined.add(Event(
              id: 'club_$clubId',
              title: c['name'] ?? 'Elite Club',
              imageUrl: c['avatar_url'],
              venue: c['name'],
              category: (c['business_type'] ?? 'club').toString().toLowerCase(),
              latitude: (c['latitude'] as num).toDouble(),
              longitude: (c['longitude'] as num).toDouble(),
              organizerId: clubId,
              price: 0,
              countryCode: 'DZ',
            ));
          }
        }

        setState(() {
          _allEvents = allCombined;
          _applyFilters();
        });
      }
    });

    // 3. Update to current location if available (background)
    Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.low))
      .then((position) {
        if (mounted) {
          _mapController?.animateCamera(
            CameraUpdate.newLatLng(LatLng(position.latitude, position.longitude))
          );
        }
      }).catchError((_) {});
  }

  void _applyFilters() {
    _generateMarkers();
  }

  Future<void> _generateMarkers() async {
    final query = _selectedFilter;
    final List<Event> filtered = _allEvents.where((e) {
      if (query == 'all') return true;
      return e.category?.toLowerCase() == query;
    }).toList();

    List<Marker> markers = [];
    for (var e in filtered) {
      final isClub = e.id.startsWith('club_');
      
      // Determine the correct category key
      String catKey;
      if (isClub) {
        catKey = 'club';
      } else {
        final cat = (e.category ?? 'club').toLowerCase();
        if (cat.contains('restaurant') || cat.contains('dine')) {
          catKey = 'restaurant';
        } else if (cat.contains('cafe') || cat.contains('coffee')) {
          catKey = 'cafe';
        } else if (cat.contains('entertainment') || cat.contains('fun')) {
          catKey = 'entertainment';
        } else {
          catKey = 'club';
        }
      }

      final BitmapDescriptor icon = _customIcons[catKey] ?? BitmapDescriptor.defaultMarker;

      markers.add(Marker(
        markerId: MarkerId(e.id),
        position: LatLng(e.latitude!, e.longitude!),
        icon: icon,
        anchor: const Offset(0.33, 0.22),
        onTap: () {
          _mapController?.animateCamera(CameraUpdate.newLatLng(LatLng(e.latitude!, e.longitude!)));
          final index = filtered.indexWhere((event) => event.id == e.id);
          if (index != -1 && _pageController.hasClients) {
            _pageController.animateToPage(index, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
          }
        },
      ));
    }

    if (mounted) {
      setState(() {
        _filteredEvents = filtered;
        _markers = markers.toSet();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: ClipRRect(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: AppBar(
              backgroundColor: Colors.black.withValues(alpha: 0.5),
              elevation: 0,
              centerTitle: true,
              title: Text('EXPLORE_NEARBY'.tr.toUpperCase(), 
                style: AppTheme.labelStyle.copyWith(color: AppTheme.primary, letterSpacing: 3)),
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _initialPosition,
                    zoom: 12,
                  ),
                  markers: _markers,
                  onMapCreated: (controller) => _mapController = controller,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                  compassEnabled: false,
                  style: AppTheme.mapDarkStyle,
                ),

                // 1. FLOATING FILTER BAR
                Positioned(
                  top: 100, left: 0, right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(32),
                        border: Border.all(color: Colors.white10),
                        boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 20)],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: _filterOptions.map((opt) {
                          final isSel = _selectedFilter == opt['id'];
                          return GestureDetector(
                            onTap: () {
                              setState(() => _selectedFilter = opt['id']);
                              _applyFilters();
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              decoration: BoxDecoration(
                                color: isSel ? AppTheme.primary : Colors.transparent,
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: Row(
                                children: [
                                  Icon(opt['icon'], color: isSel ? Colors.black : Colors.white60, size: 18),
                                  if (isSel) ...[
                                    const SizedBox(width: 8),
                                    Text(opt['label'].toString().tr, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11)),
                                  ]
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
                
                // 2. LOCATION BUTTON
                Positioned(
                  top: 170, right: 16,
                  child: FloatingActionButton.small(
                    onPressed: () async {
                      try {
                        final pos = await Geolocator.getCurrentPosition(
                          locationSettings: const LocationSettings(
                            accuracy: LocationAccuracy.low,
                            timeLimit: Duration(seconds: 5),
                          ),
                        );
                        _mapController?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 14));
                      } catch (e) {
                        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('location_services_disabled'.tr)));
                      }
                    },
                    backgroundColor: Colors.black.withValues(alpha: 0.8),
                    child: const Icon(Icons.my_location_rounded, color: AppTheme.primary, size: 20),
                  ),
                ),

                // Bottom Gradient for contrast
                Positioned(
                  bottom: 0, left: 0, right: 0,
                  height: 300,
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.black,
                            Colors.black.withValues(alpha: 0.8),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Overlayed Cards for quick preview
                Positioned(
                  bottom: 30,
                  left: 0,
                  right: 0,
                  height: 160,
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: _filteredEvents.length,
                    physics: const BouncingScrollPhysics(),
                    onPageChanged: (index) {
                      final e = _filteredEvents[index];
                      if (e.latitude != null) {
                        _mapController?.animateCamera(
                          CameraUpdate.newCameraPosition(
                            CameraPosition(target: LatLng(e.latitude!, e.longitude!), zoom: 15, tilt: 30)
                          )
                        );
                      }
                    },
                    itemBuilder: (context, index) {
                      final e = _filteredEvents[index];
                      return _buildEventPreviewCard(e);
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildEventPreviewCard(Event e) {
    final isClub = e.id.startsWith('club_');
    return GestureDetector(
      onTap: () {
        if (isClub) {
          Navigator.push(context, MaterialPageRoute(
            builder: (context) => ClubProfileScreen(organizerId: e.organizerId!, organizerName: e.title, fromMap: true),
          ));
        } else {
          Navigator.push(context, MaterialPageRoute(
            builder: (context) => EventDetailsScreen(event: e, fromMap: true),
          ));
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          boxShadow: [BoxShadow(color: AppTheme.primary.withValues(alpha: 0.12), blurRadius: 20, offset: const Offset(0, 8))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Stack(
            children: [
              // Background image
              if (e.imageUrl != null)
                Positioned.fill(
                  child: Image.network(e.imageUrl!, fit: BoxFit.cover),
                ),
              // Dark gradient overlay
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerRight,
                      end: Alignment.centerLeft,
                      colors: [
                        Colors.black.withValues(alpha: 0.85),
                        Colors.black.withValues(alpha: 0.3),
                      ],
                    ),
                  ),
                ),
              ),
              // Content
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppTheme.primary.withValues(alpha: 0.5)),
                              ),
                              child: Text(
                                isClub ? 'CLUB'.tr : (e.category?.toUpperCase() ?? 'EVENT'),
                                style: const TextStyle(color: AppTheme.primary, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.5),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              e.title,
                              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (e.venue != null) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.location_on_rounded, color: Colors.white54, size: 12),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(e.venue!, style: const TextStyle(color: Colors.white54, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      // CTA Button
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (!isClub && e.price > 0) ...[
                            Text(
                              '${e.price.toStringAsFixed(0)} DZ',
                              style: const TextStyle(color: AppTheme.primary, fontSize: 13, fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 8),
                          ],
                          Container(
                            decoration: BoxDecoration(
                              color: AppTheme.primary,
                              shape: BoxShape.circle,
                              boxShadow: [BoxShadow(color: AppTheme.primary.withValues(alpha: 0.4), blurRadius: 12)],
                            ),
                            child: IconButton(
                              icon: const Icon(Icons.arrow_forward_rounded, color: Colors.black),
                              onPressed: () {
                                if (isClub) {
                                  Navigator.push(context, MaterialPageRoute(
                                    builder: (context) => ClubProfileScreen(organizerId: e.organizerId!, organizerName: e.title, fromMap: true),
                                  ));
                                } else {
                                  Navigator.push(context, MaterialPageRoute(
                                    builder: (context) => EventDetailsScreen(event: e, fromMap: true),
                                  ));
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/services/translation_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

class PremiumLocationPicker extends StatefulWidget {
  final LatLng initialLocation;
  final String? initialAddress;

  const PremiumLocationPicker({
    super.key, 
    required this.initialLocation,
    this.initialAddress,
  });

  @override
  State<PremiumLocationPicker> createState() => _PremiumLocationPickerState();
}

class _PremiumLocationPickerState extends State<PremiumLocationPicker> with SingleTickerProviderStateMixin {
  late LatLng _currentLocation;
  String _address = '';
  bool _isMoving = false;
  bool _isLocating = false;
  GoogleMapController? _mapController;
  
  late AnimationController _pinController;
  late Animation<double> _pinAnimation;

  @override
  void initState() {
    super.initState();
    _currentLocation = widget.initialLocation;
    _address = widget.initialAddress ?? '';
    
    _pinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _pinAnimation = Tween<double>(begin: 0.0, end: -15.0).animate(
      CurvedAnimation(parent: _pinController, curve: Curves.easeOut),
    );
    
    // Do not block initState with geocoding
    if (_address.isEmpty) {
      _reverseGeocode(_currentLocation);
    }
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _reverseGeocode(LatLng loc) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(loc.latitude, loc.longitude);
      if (placemarks.isNotEmpty && mounted) {
        setState(() {
          final p = placemarks.first;
          _address = '${p.street ?? ""}, ${p.subLocality ?? ""}, ${p.locality ?? ""}';
        });
      }
    } catch (_) {}
  }

  Future<void> _goToMyLocation() async {
    setState(() => _isLocating = true);
    try {
      final pos = await Geolocator.getCurrentPosition();
      final newLoc = LatLng(pos.latitude, pos.longitude);
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(newLoc, 16));
      _currentLocation = newLoc;
      _reverseGeocode(newLoc);
    } catch (_) {}
    setState(() => _isLocating = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // The Map
          GoogleMap(
            initialCameraPosition: CameraPosition(target: _currentLocation, zoom: 15),
            onMapCreated: (c) => _mapController = c,
            onTap: (latLng) {
              _mapController?.animateCamera(CameraUpdate.newLatLng(latLng));
            },
            onCameraMoveStarted: () {
              setState(() => _isMoving = true);
              _pinController.forward();
            },
            onCameraMove: (pos) {
              _currentLocation = pos.target;
            },
            onCameraIdle: () {
              setState(() => _isMoving = false);
              _pinController.reverse();
              _reverseGeocode(_currentLocation);
            },
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            style: AppTheme.mapDarkStyle,
          ),

          // Custom Pin in center
          Center(
            child: AnimatedBuilder(
              animation: _pinAnimation,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(0, _pinAnimation.value - 20), // -20 to center the tip
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // The Pin
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primary.withValues(alpha: 0.4),
                              blurRadius: 15,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.location_on, color: Colors.black, size: 28),
                      ),
                      // Small shadow dot on the map
                      const SizedBox(height: 4),
                      Container(
                        width: 8,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // Header with back button and Search UI
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 20, right: 20,
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
                    child: const Icon(Icons.close, color: Colors.white, size: 20),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    height: 52,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
                    child: Row(
                      children: [
                        const Icon(Icons.search, color: Colors.white38, size: 18),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _address.isEmpty ? 'SEARCH_LOCATION'.tr : _address,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Floating Action Buttons (Bottom Right)
          Positioned(
            bottom: 120,
            right: 20,
            child: Column(
              children: [
                _buildMapFab(
                  icon: Icons.my_location,
                  onTap: _goToMyLocation,
                  isLoading: _isLocating,
                ),
                const SizedBox(height: 12),
                _buildMapFab(
                  icon: Icons.add,
                  onTap: () => _mapController?.animateCamera(CameraUpdate.zoomIn()),
                ),
                const SizedBox(height: 8),
                _buildMapFab(
                  icon: Icons.remove,
                  onTap: () => _mapController?.animateCamera(CameraUpdate.zoomOut()),
                ),
              ],
            ),
          ),

          // Bottom Selection Card
          Positioned(
            bottom: 32,
            left: 24, right: 24,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF121212),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 40)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
                        child: const Icon(Icons.map_rounded, color: AppTheme.primary, size: 20),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('SELECTED_LOCATION'.tr.toUpperCase(), style: AppTheme.labelStyle.copyWith(fontSize: 10, color: AppTheme.primary)),
                            const SizedBox(height: 4),
                            Text(
                              _address.isEmpty ? 'POINTING_ON_MAP'.tr : _address,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _isMoving ? null : () {
                      Navigator.pop(context, {
                        'lat': _currentLocation.latitude,
                        'lng': _currentLocation.longitude,
                        'address': _address,
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.black,
                      minimumSize: const Size(double.infinity, 56),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      elevation: 0,
                    ),
                    child: Text('CONFIRM_LOCATION'.tr.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapFab({required IconData icon, required VoidCallback onTap, bool isLoading = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48, height: 48,
        decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
        child: Center(
          child: isLoading 
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary))
            : Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

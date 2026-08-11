import 'dart:io';
import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/services/translation_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:my_app/services/storage_service.dart';
import 'package:my_app/services/audit_service.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:my_app/widgets/premium_location_picker.dart';
import 'package:my_app/services/localization_service.dart';
import 'package:my_app/screens/organizer_dashboard.dart';

class ClubProfileEditorScreen extends StatefulWidget {
  final bool isNew;
  final String? clubId;
  const ClubProfileEditorScreen({super.key, this.isNew = false, this.clubId});

  @override
  State<ClubProfileEditorScreen> createState() => _ClubProfileEditorScreenState();
}

class _ClubProfileEditorScreenState extends State<ClubProfileEditorScreen> with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  late TabController _tabController;
  
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _perkController = TextEditingController();
  final _amenitiesController = TextEditingController();
  double? _lat;
  double? _lng;
  String _businessType = 'club';
  String _countryCode = 'DZ';
  
  final _storage = StorageService();
  final _picker = ImagePicker();
  
  List<String> _currentGallery = []; 
  final List<File?> _newImages = List.generate(5, (_) => null);
  File? _logoFile;
  String? _currentLogoUrl;
  
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isLocating = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _addressController.addListener(_onAddressChanged);
    _loadProfile();
  }

  void _onAddressChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 1500), () async {
      final address = _addressController.text;
      if (address.length > 5) {
        try {
          List<Location> locations = await locationFromAddress(address);
          if (locations.isNotEmpty && mounted) {
            final loc = locations.first;
            setState(() {
              _lat = loc.latitude;
              _lng = loc.longitude;
            });
          }
        } catch (_) {}
      }
    });
  }

  Future<void> _loadProfile() async {
    if (widget.isNew) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    final targetId = widget.clubId ?? userId;

    try {
      // 1. Load data from organizer_profiles (the club table)
      final orgRes = await _supabase.from('organizer_profiles').select('*, profiles(full_name)').eq('id', targetId).maybeSingle();
      
      if (orgRes != null) {
        _nameController.text = orgRes['name'] ?? orgRes['profiles']?['full_name'] ?? '';
        _bioController.text = orgRes['bio'] ?? '';
        _phoneController.text = orgRes['contact_phone'] ?? '';
        _addressController.text = orgRes['location_address'] ?? '';
        _currentGallery = List<String>.from(orgRes['permanent_gallery'] ?? []);
        _lat = orgRes['latitude'];
        _lng = orgRes['longitude'];
        _businessType = orgRes['business_type']?.toString() ?? 'club';
        _countryCode = orgRes['country_code']?.toString() ?? 'DZ';
        _perkController.text = orgRes['follower_perk'] ?? '';
        _amenitiesController.text = orgRes['amenities'] ?? '';
        _currentLogoUrl = orgRes['avatar_url'];
      } else {
        // Fallback for new users/old structure: get personal name
        final userRes = await _supabase.from('profiles').select('full_name').eq('id', userId).maybeSingle();
        if (userRes != null) _nameController.text = userRes['full_name'] ?? '';
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _debounce?.cancel();
    _addressController.removeListener(_onAddressChanged);
    _nameController.dispose();
    _bioController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _perkController.dispose();
    _amenitiesController.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 50);
    if (image != null) setState(() => _logoFile = File(image.path));
  }

  Future<void> _pickImage(int index) async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
      maxWidth: 1080,
      maxHeight: 1080,
    );
    if (image != null) {
      setState(() {
        _newImages[index] = File(image.path);
      });
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isSaving = true);
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      // 0. Upload Logo if changed
      String? logoUrl = _currentLogoUrl;
      if (_logoFile != null) {
        logoUrl = await _storage.uploadImage(_logoFile!, bucket: 'organizer-assets');
      }

      // 1. Upload new images
      List<String> updatedGallery = List.from(_currentGallery);
      
      for (int i = 0; i < 5; i++) {
        if (_newImages[i] != null) {
          final url = await _storage.uploadImage(_newImages[i]!, bucket: 'organizer-assets');
          if (url != null) {
            if (i < updatedGallery.length) {
              updatedGallery[i] = url;
            } else {
              updatedGallery.add(url);
            }
          }
        }
      }

      // 2. Prepare Data for organizer_profiles
      final Map<String, dynamic> clubData = {
        'owner_id': userId,
        'name': _nameController.text,
        'avatar_url': logoUrl,
        'bio': _bioController.text,
        'contact_phone': _phoneController.text,
        'permanent_gallery': updatedGallery.take(5).toList(),
        'latitude': _lat,
        'longitude': _lng,
        'location_address': _addressController.text,
        'business_type': _businessType,
        'country_code': _countryCode,
        'follower_perk': _perkController.text,
        // 'amenities': _amenitiesController.text, // commented out to avoid postgres error
        'updated_at': DateTime.now().toIso8601String(),
      };

      String? newClubId;
      if (widget.isNew && widget.clubId == null) {
        // Create new club and capture its generated ID
        final res = await _supabase.from('organizer_profiles').insert(clubData).select('id, name, business_type').single();
        newClubId = res['id'] as String?;
      } else {
        // Update existing club
        final targetId = widget.clubId ?? userId;
        await _supabase.from('organizer_profiles').update(clubData).eq('id', targetId);
      }

      // 5. Log action
      await AuditService().logAction(
        actionType: widget.isNew ? 'CLUB_CREATED' : 'CLUB_UPDATED',
        description: '${widget.isNew ? "Created" : "Updated"} brand profile: ${_nameController.text}',
      );

      if (mounted) {
        if (widget.isNew && newClubId != null) {
          // ✅ انتقال تلقائي للوحة تحكم النادي بعد الإنشاء
          _showNewClubSuccessDialog(newClubId);
        } else {
          _showSuccessDialog();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: Colors.white, size: 16),
                const SizedBox(width: 8),
                Text('${'error_saving_profile'.tr}: $e', style: const TextStyle(fontSize: 10)),
              ],
            ),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showNewClubSuccessDialog(String clubId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(32), 
            side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.2)),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: const Icon(Icons.rocket_launch_rounded, color: AppTheme.primary, size: 48),
              ),
              const SizedBox(height: 24),
              Text('🎉 تم إنشاء صفحتك!', style: AppTheme.headlineStyle.copyWith(fontSize: 20, letterSpacing: 1)),
              const SizedBox(height: 12),
              Text(
                'صفحتك الآن جاهزة وموجودة على الشبكة. انتقل الآن للوحة التحكم لنشر أول فعالية!',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.pop(context);
                  // ✅ انتقال مباشر للوحة التحكم
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => OrganizerDashboardScreen(
                        clubId: clubId,
                        clubName: _nameController.text,
                        businessType: _businessType,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.dashboard_rounded, color: Colors.black, size: 20),
                label: Text('انشر أول فعالية الآن', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, letterSpacing: 1, fontSize: 14)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  minimumSize: const Size(double.infinity, 54),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.pop(context);
                },
                child: Text('لاحقاً', style: const TextStyle(color: Colors.white38, fontSize: 12)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(32), 
            side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.2)),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: const Icon(Icons.verified_rounded, color: AppTheme.primary, size: 48),
              ),
              const SizedBox(height: 24),
              Text('BRAND_IDENTITY_LIVE'.tr.toUpperCase(), style: AppTheme.headlineStyle.copyWith(fontSize: 18, letterSpacing: 2)),
              const SizedBox(height: 12),
              Text('Your professional club profile is now deployed to the Sivox network.'.tr, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, fontSize: 13)),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.black,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: Text('VIEW_MY_PAGE'.tr.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSectionHelp(String section) {
    String title = section.toUpperCase();
    String desc = 'providing_details'.tr;
    if (section == 'BASIC IDENTITY'.tr) desc = 'HELPER_BASIC_DESC'.tr;
    if (section == 'PERMANENT GALLERY (VIBES)'.tr) desc = 'HELPER_GALLERY_DESC'.tr;
    if (section == 'CONTACT INFO'.tr) desc = 'HELPER_CONTACT_DESC'.tr;
    if (section == 'LOGISTICS & PERKS'.tr) desc = 'HELPER_LOGISTICS_DESC'.tr;
    if (section == 'BRAND_LOGO'.tr) desc = 'HELPER_LOGO_DESC'.tr;
    if (section == 'ENTITY_TYPE'.tr) desc = 'HELPER_ENTITY_DESC'.tr;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(32),
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 24),
            Icon(Icons.auto_awesome_rounded, color: AppTheme.primary, size: 32),
            const SizedBox(height: 16),
            Text(title.tr, style: AppTheme.headlineStyle.copyWith(fontSize: 18)),
            const SizedBox(height: 12),
            Text(desc, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.5)),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('MANAGE BRAND'.tr, style: AppTheme.headlineStyle.copyWith(fontSize: 16)),
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'الهوية والمعلومات'),
            Tab(text: 'الصور والموقع'),
          ],
          labelColor: AppTheme.primary,
          unselectedLabelColor: Colors.white38,
          indicatorColor: AppTheme.primary,
          indicatorSize: TabBarIndicatorSize.label,
        ),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
        : Form(
            key: _formKey,
            child: TabBarView(
              controller: _tabController,
              children: [
                // TAB 1: IDENTITY & INFO
                  ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      _buildLogoSection(),
                      const SizedBox(height: 32),
                      _buildSectionTitle('BASIC IDENTITY'.tr),
                      _buildTextField('CLUB NAME'.tr, _nameController, hint: 'Club Name...', isRequired: true),
                      const SizedBox(height: 20),
                      _buildTextField('BIO / SLOGAN'.tr, _bioController, hint: 'The best night in town...', maxLines: 3),
                      const SizedBox(height: 32),
                      _buildSectionTitle('ENTITY_TYPE'.tr),
                      _buildTypeSelector(),
                      const SizedBox(height: 32),
                      _buildCountrySelector(),
                      const SizedBox(height: 32),
                      _buildSectionTitle('CONTACT INFO'.tr),
                      _buildTextField('OFFICIAL PHONE'.tr, _phoneController, hint: '+213...', isRequired: true),
                      const SizedBox(height: 100),
                    ],
                  ),
                  
                  // TAB 2: GALLERY & LOCATION
                  ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      _buildSectionTitle('PERMANENT GALLERY (VIBES)'.tr),
                      Text('Add up to 5 images to showcase your club\'s atmosphere.'.tr, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                      const SizedBox(height: 24),
                      SizedBox(
                        height: 120,
                        child: Builder(
                          builder: (context) {
                            int filledCount = 0;
                            for (int i = 0; i < 5; i++) {
                              if (i < _currentGallery.length || _newImages[i] != null) {
                                filledCount++;
                              }
                            }
                            int displayCount = filledCount < 5 ? filledCount + 1 : 5;
                            
                            return ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: displayCount,
                              itemBuilder: (ctx, index) {
                                final hasNew = _newImages[index] != null;
                                final hasCurrent = index < _currentGallery.length;
                                
                                return GestureDetector(
                                  onTap: () => _pickImage(index),
                                  child: Stack(
                                    children: [
                                      Container(
                                        width: 100,
                                        margin: const EdgeInsets.only(right: 12),
                                        decoration: BoxDecoration(
                                          color: (hasNew || hasCurrent) ? Colors.white.withValues(alpha: 0.03) : AppTheme.primary.withValues(alpha: 0.08),
                                          borderRadius: BorderRadius.circular(16),
                                          border: Border.all(color: (hasNew || hasCurrent) ? Colors.white.withValues(alpha: 0.05) : AppTheme.primary.withValues(alpha: 0.3), width: 1.5),
                                          image: hasNew 
                                            ? DecorationImage(image: FileImage(_newImages[index]!), fit: BoxFit.cover)
                                            : (hasCurrent ? DecorationImage(image: NetworkImage(_currentGallery[index]), fit: BoxFit.cover) : null),
                                        ),
                                        child: (hasNew || hasCurrent) ? null : Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.add_a_photo_rounded, color: AppTheme.primary.withValues(alpha: 0.8), size: 28),
                                            const SizedBox(height: 6),
                                            Text('أضف صورة', style: TextStyle(color: AppTheme.primary, fontSize: 11, fontWeight: FontWeight.bold)),
                                          ],
                                        ),
                                      ),
                                  if (hasNew || hasCurrent)
                                    Positioned(
                                      top: 4,
                                      right: 16,
                                      child: GestureDetector(
                                        onTap: () {
                                          setState(() {
                                            if (hasNew) {
                                              _newImages[index] = null;
                                            } else if (hasCurrent) {
                                              _currentGallery.removeAt(index);
                                              // Shift new images so UI matches structure
                                              for(int i = index; i < 4; i++) {
                                                _newImages[i] = _newImages[i+1];
                                              }
                                              _newImages[4] = null;
                                            }
                                          });
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                                          child: const Icon(Icons.close_rounded, size: 12, color: Colors.white),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                      const SizedBox(height: 40),
                      
                      const SizedBox(height: 32),
                      
                      _buildSectionTitle('LOCATION'.tr),
                      _buildTextField('CLUB_LOCATION_ADDRESS'.tr, _addressController, hint: 'e.g. 123 Street, Hydra, Algiers...'),
                      const SizedBox(height: 16),
                      _buildLocationPicker(),
                      const SizedBox(height: 100),
                    ],
                  ),
                ],
              ),
            ),
        bottomSheet: _buildSaveButton(),
      );
  }


  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Text(title, style: AppTheme.labelStyle.copyWith(color: AppTheme.primary, letterSpacing: 2)),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _showSectionHelp(title),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), shape: BoxShape.circle),
              child: const Icon(Icons.help_outline_rounded, color: Colors.white24, size: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, {String? hint, int maxLines = 1, bool isRequired = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          style: const TextStyle(color: Colors.white),
          validator: isRequired ? (val) => val == null || val.trim().isEmpty ? 'Please fill this field' : null : null,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white10),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.03),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.all(16),
          ),
        ),
      ],
    );
  }

  Widget _buildSaveButton() {
    final bool isLastTab = _tabController.index == 1;
    return Container(
      width: double.infinity,
      color: AppTheme.background,
      padding: const EdgeInsets.all(24),
      child: ElevatedButton(
        onPressed: _isSaving 
          ? null 
          : (isLastTab ? _saveProfile : () => _tabController.animateTo(1)),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        child: _isSaving 
          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
          : (isLastTab 
              ? Text('PUBLISH UPDATES'.tr, style: const TextStyle(fontWeight: FontWeight.bold))
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('التالي (الصور والموقع)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward_rounded, size: 20),
                  ],
                )),
      ),
    );
  }

  Widget _buildLocationPicker() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: const Icon(Icons.location_on, color: AppTheme.primary, size: 20),
            ),
            title: Text('CLUB GPS LOCATION'.tr, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
            subtitle: Text(_lat != null ? 'LOCATION_CAPTURED'.tr : 'LOCATION_NOT_SET'.tr, style: TextStyle(color: _lat != null ? AppTheme.secondary : Colors.white24, fontSize: 10)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: _LocationActionButton(
                    label: 'PICK_FROM_MAP'.tr,
                    icon: Icons.map_rounded,
                    onTap: _pickFromMap,
                    color: AppTheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _LocationActionButton(
                    label: 'MY_LOCATION'.tr,
                    icon: Icons.gps_fixed_rounded,
                    onTap: _pickMyLocation,
                    color: AppTheme.secondary,
                    isLoading: _isLocating,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickMyLocation() async {
    setState(() => _isLocating = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw 'location_services_disabled'.tr;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) throw 'location_permission_denied'.tr;
      }
      
      const locationSettings = LocationSettings(accuracy: LocationAccuracy.high);
      final position = await Geolocator.getCurrentPosition(locationSettings: locationSettings);
      
      await _updateLocationData(position.latitude, position.longitude);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent));
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  Future<void> _updateLocationData(double lat, double lng) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(lat, lng);
      if (mounted) {
        setState(() {
          _lat = lat;
          _lng = lng;
          if (placemarks.isNotEmpty) {
            final p = placemarks.first;
            _addressController.text = '${p.street ?? ""}, ${p.subLocality ?? ""}, ${p.locality ?? ""}';
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('location_captured'.tr), backgroundColor: Colors.green));
      }
    } catch (_) {}
  }

  void _pickFromMap() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => PremiumLocationPicker(
          initialLocation: LatLng(_lat ?? 36.7538, _lng ?? 3.0588),
          initialAddress: _addressController.text,
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _lat = result['lat'];
        _lng = result['lng'];
        _addressController.text = result['address'];
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('location_updated'.tr), backgroundColor: Colors.green));
    }
  }

  Widget _buildTypeSelector() {
    final types = [
      {'id': 'club', 'label': 'CLUB_BRAND'.tr, 'icon': Icons.nightlife},
      {'id': 'restaurant', 'label': 'RESTAURANT_BRAND'.tr, 'icon': Icons.restaurant},
      {'id': 'cafe', 'label': 'CAFE_BRAND'.tr, 'icon': Icons.coffee},
      {'id': 'entertainment', 'label': 'ENTERTAINMENT_BRAND'.tr, 'icon': Icons.theater_comedy_rounded},
    ];

    return Wrap(
      spacing: 12,
      children: types.map((t) {
        final isSel = _businessType == t['id'];
        return ChoiceChip(
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(t['icon'] as IconData, size: 14, color: isSel ? Colors.black : Colors.white38),
              const SizedBox(width: 8),
              Text(t['label'] as String),
            ],
          ),
          selected: isSel,
          onSelected: (val) {
            if (val) setState(() => _businessType = t['id'] as String);
          },
          selectedColor: AppTheme.primary,
          backgroundColor: Colors.white.withValues(alpha: 0.03),
          labelStyle: TextStyle(color: isSel ? Colors.black : Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: isSel ? AppTheme.primary : Colors.white10)),
        );
      }).toList(),
    );
  }

  Widget _buildCountrySelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('CORE COUNTRY'.tr),
        SizedBox(
          height: 60,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: LocalizationService.supportedCountries.length,
            itemBuilder: (context, index) {
              final country = LocalizationService.supportedCountries[index];
              final sel = _countryCode == country.code;
              return GestureDetector(
                onTap: () => setState(() => _countryCode = country.code),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(right: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: sel ? AppTheme.primary.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: sel ? AppTheme.primary : Colors.white.withValues(alpha: 0.05)),
                  ),
                  child: Row(
                    children: [
                      Text(country.flag, style: const TextStyle(fontSize: 20)),
                      const SizedBox(width: 8),
                      Text(country.name.tr.toUpperCase(), style: TextStyle(color: sel ? Colors.white : Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLogoSection() {
    return Center(
      child: Column(
        children: [
          _buildSectionTitle('BRAND_LOGO'.tr),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _pickLogo,
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.primary, width: 2),
                    boxShadow: [BoxShadow(color: AppTheme.primary.withValues(alpha: 0.2), blurRadius: 20)],
                  ),
                  child: CircleAvatar(
                    radius: 60,
                    backgroundColor: AppTheme.surfaceContainer,
                    backgroundImage: _logoFile != null 
                        ? FileImage(_logoFile!) 
                        : (_currentLogoUrl != null ? NetworkImage(_currentLogoUrl!) : null) as ImageProvider?,
                    child: (_logoFile == null && _currentLogoUrl == null) 
                        ? const Icon(Icons.add_a_photo_rounded, color: AppTheme.primary, size: 40)
                        : null,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle),
                  child: const Icon(Icons.edit_rounded, color: Colors.black, size: 16),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text('OFFICIAL_LOGO_DESC'.tr, style: const TextStyle(color: Colors.white24, fontSize: 10)),
        ],
      ),
    );
  }
}

class _LocationActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  final bool isLoading;

  const _LocationActionButton({
    required this.label, 
    required this.icon, 
    required this.onTap, 
    required this.color,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: color))
            else
              Icon(icon, color: color, size: 16),
            const SizedBox(width: 8),
            Text(
              label.toUpperCase(),
              style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.5),
            ),
          ],
        ),
      ),
    );
  }
}

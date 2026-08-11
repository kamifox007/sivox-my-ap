import 'package:flutter/material.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/services/event_service.dart';
import 'package:my_app/services/translation_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geocoding/geocoding.dart';
import 'dart:io';
import 'dart:async';
import 'package:my_app/services/storage_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
// Removed unused import
import 'package:my_app/services/draft_service.dart';
import 'package:my_app/models/event.dart';
import 'package:supabase_flutter/supabase_flutter.dart';



class CreateEventScreen extends StatefulWidget {
  final Event? event;
  final String? clubId;
  final String? businessType;
  final bool isInitial;
  const CreateEventScreen({super.key, this.event, this.clubId, this.businessType, this.isInitial = false});

  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  String selectedCategory = 'club';
  String selectedContactType = 'PHONE';
  String selectedCountryCode = 'DZ';
  bool showContactInfo = false;
  bool hidePrice = false;
  bool hasEarlyBirdRewards = false;
  bool requireCallConfirmation = false;
  bool payAtDoor = false;
  bool _isFree = false;
  bool _isCapacityLimited = false; // NEW: Added missing declaration

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _endDateController = TextEditingController(); // NEW
  final TextEditingController _timeController = TextEditingController(); // NEW
  final TextEditingController _endTimeController = TextEditingController(); // NEW
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _rulesController = TextEditingController();
  final TextEditingController _latController = TextEditingController();
  final TextEditingController _lngController = TextEditingController();
  final TextEditingController _promoValueController = TextEditingController();
  final TextEditingController _promoLabelController = TextEditingController();
  final TextEditingController _promoLimitController = TextEditingController();
  final TextEditingController _promoDiscountController = TextEditingController(); // ADDED
  final TextEditingController _discountController = TextEditingController(); 
  final TextEditingController _perkController = TextEditingController();
  final TextEditingController _amenitiesController = TextEditingController();
  final TextEditingController _capacityController = TextEditingController(); // NEW
  
  String? _imageUrl;
  double? _lat;
  double? _lng;
  String? _organizerId;

  final _eventService = EventService();
  bool _isSubmitting = false;
  bool _notifyFollowers = true;

  XFile? _mainImage;
  final List<XFile> _galleryImages = [];
  final ImagePicker _picker = ImagePicker();


  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _fetchClubIdentity();
    _locationController.addListener(_onLocationChanged);
    if (widget.event != null) {
      _loadFromEvent(widget.event!);
    } else {
      if (widget.businessType != null) {
        selectedCategory = widget.businessType!;
      }
      // Check for Permanent Drafts (Instagram Style)
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkAndRestoreDraft());
    }
    _setupDraftListeners();
  }

  void _onLocationChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 1500), () async {
      final address = _locationController.text;
      if (address.length > 5) {
        try {
          List<Location> locations = await locationFromAddress(address);
          if (locations.isNotEmpty && mounted) {
            final loc = locations.first;
            setState(() {
              _lat = loc.latitude;
              _lng = loc.longitude;
              _latController.text = _lat.toString();
              _lngController.text = _lng.toString();
            });
          }
        } catch (_) {
          // Address not found or error, ignore to avoid annoying UI
        }
      }
    });
  }

  void _loadFromEvent(Event e) {
    _nameController.text = e.title;
    _locationController.text = e.venue ?? '';
    _priceController.text = e.price.toString();
    _descriptionController.text = e.description ?? '';
    _dateController.text = e.dateTime ?? '';
    _phoneController.text = e.contactNumber ?? '';
    _rulesController.text = e.rules ?? '';
    selectedCategory = e.category ?? 'club';
    selectedContactType = e.contactType ?? 'PHONE';
    selectedCountryCode = e.countryCode;
    hidePrice = e.hidePrice;
    requireCallConfirmation = e.requireCallConfirmation;
    _imageUrl = e.imageUrl;
    _lat = e.latitude;
    _lng = e.longitude;
    _latController.text = _lat?.toString() ?? '';
    _lngController.text = _lng?.toString() ?? '';
    _perkController.text = e.followerPerk ?? '';
    hasEarlyBirdRewards = e.hasEarlyBirdRewards;
    payAtDoor = e.payAtDoor;
    _isCapacityLimited = e.maxCapacity != null && e.maxCapacity! > 0;
    _capacityController.text = e.maxCapacity?.toString() ?? '';
    _endTimeController.text = e.endTime ?? '';
    _endDateController.text = e.endDate ?? '';
    _isFree = e.price == 0;
    showContactInfo = _phoneController.text.isNotEmpty;
  }

  void _setupDraftListeners() {
    _nameController.addListener(() => DraftService().saveDraft('event_name', _nameController.text));
    _locationController.addListener(() => DraftService().saveDraft('event_venue', _locationController.text));
    _descriptionController.addListener(() => DraftService().saveDraft('event_desc', _descriptionController.text));
    _priceController.addListener(() => DraftService().saveDraft('event_price', _priceController.text));
    _dateController.addListener(() => DraftService().saveDraft('event_date', _dateController.text));
    _phoneController.addListener(() => DraftService().saveDraft('event_phone', _phoneController.text));
    _rulesController.addListener(() => DraftService().saveDraft('event_rules', _rulesController.text));
    _perkController.addListener(() => DraftService().saveDraft('event_perk', _perkController.text));
    _endDateController.addListener(() => DraftService().saveDraft('event_end_date', _endDateController.text));
    _timeController.addListener(() => DraftService().saveDraft('event_time', _timeController.text));
    _endTimeController.addListener(() => DraftService().saveDraft('event_end_time', _endTimeController.text));
    _capacityController.addListener(() => DraftService().saveDraft('event_capacity', _capacityController.text));
  }

  void _checkAndRestoreDraft() {
    if (DraftService().hasDraftForPrefix('event_')) {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (context) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
            border: Border.all(color: AppTheme.primary.withValues(alpha: 0.1)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 32),
              const Icon(Icons.history_edu_rounded, color: AppTheme.primary, size: 48),
              const SizedBox(height: 24),
              Text('draft_found'.tr, style: AppTheme.headlineStyle.copyWith(fontSize: 22)),
              const SizedBox(height: 12),
              Text('restore_draft_query'.tr, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white38, fontSize: 13)),
              const SizedBox(height: 48),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () {
                        DraftService().clearDraftsByPrefix('event_');
                        Navigator.pop(context);
                      },
                      child: Text('discard_draft'.tr, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _nameController.text = DraftService().getDraft('event_name');
                          _locationController.text = DraftService().getDraft('event_venue');
                          _descriptionController.text = DraftService().getDraft('event_desc');
                          _priceController.text = DraftService().getDraft('event_price');
                          _dateController.text = DraftService().getDraft('event_date');
                          _endDateController.text = DraftService().getDraft('event_end_date');
                          _timeController.text = DraftService().getDraft('event_time');
                          _endTimeController.text = DraftService().getDraft('event_end_time');
                          _phoneController.text = DraftService().getDraft('event_phone');
                          _rulesController.text = DraftService().getDraft('event_rules');
                          _perkController.text = DraftService().getDraft('event_perk');
                          _capacityController.text = DraftService().getDraft('event_capacity');
                          _isFree = _priceController.text == '0';
                          showContactInfo = _phoneController.text.isNotEmpty;
                        });
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                      child: Text('restore'.tr, style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _locationController.removeListener(_onLocationChanged);
    _nameController.dispose();
    _locationController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _dateController.dispose();
    _phoneController.dispose();
    _rulesController.dispose();
    _latController.dispose();
    _lngController.dispose();
    _promoValueController.dispose();
    _promoLabelController.dispose();
    _promoLimitController.dispose();
    _promoDiscountController.dispose(); // ADDED
    _discountController.dispose();
    _perkController.dispose();
    _capacityController.dispose();
    super.dispose();
  }

  Future<void> _fetchClubIdentity() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;
      
      final profile = await Supabase.instance.client
          .from('organizer_profiles')
          .select('id, name, avatar_url, latitude, longitude, location_address, country_code, business_type, follower_perk, amenities, contact_phone')
          .eq('owner_id', user.id)
          .maybeSingle();
      
      if (profile != null && mounted) {
        setState(() {
          _organizerId = profile['id'];
          _phoneController.text = profile['contact_phone'] ?? '';
          showContactInfo = _phoneController.text.isNotEmpty;
          
          // AUTO-FILL LOCATION FOR NEW EVENTS (Perfection Fix: using location_address)
          if (widget.event == null && _lat == null && _lng == null) {
            _lat = profile['latitude'];
            _lng = profile['longitude'];
            _latController.text = _lat?.toString() ?? '';
            _lngController.text = _lng?.toString() ?? '';
            _locationController.text = profile['location_address'] ?? '';
            selectedCountryCode = profile['country_code'] ?? 'DZ';
            selectedCategory = profile['business_type'] ?? 'club';
            _perkController.text = profile['follower_perk'] ?? '';
            _amenitiesController.text = profile['amenities'] ?? '';
          }
        });
      }
    } catch (e) {
      debugPrint('Error fetching club identity: $e');
    }
  }

  Widget _buildLocationSyncBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          const Icon(Icons.sync_rounded, color: AppTheme.primary, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'LOCATION_SYNCED'.tr,
              style: const TextStyle(color: AppTheme.primary, fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }





  Future<void> _submit() async {
    if (_nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('PLEASE_ENTER_EVENT_NAME'.tr),
        backgroundColor: Colors.redAccent,
      ));
      return;
    }
    if (_imageUrl == null && _mainImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('PLEASE_SELECT_MAIN_IMAGE'.tr),
        backgroundColor: Colors.redAccent,
      ));
      return;
    }

    // Perfection Fix: Allow null/empty dates for a more flexible social experience
    final String displayDate = _dateController.text.isNotEmpty 
        ? '${_dateController.text} ${_timeController.text}'.trim()
        : (TranslationService.isRtl ? 'الليلة' : 'Tonight');

    setState(() => _isSubmitting = true);
    
    try {
      final storage = StorageService();
      String finalImg = _imageUrl ?? 'https://images.unsplash.com/photo-1514525253361-bee8718a7412';
      
      // 1. Upload Main Image
      if (_mainImage != null) {
        final url = await storage.uploadImage(File(_mainImage!.path), bucket: 'event-assets');
        if (url != null) finalImg = url;
      }

      // 2. Upload Gallery Images
      List<String> galleryUrls = [];
      for (var xf in _galleryImages) {
        final url = await storage.uploadImage(File(xf.path), bucket: 'event-assets');
        if (url != null) galleryUrls.add(url);
      }

      final success = widget.event == null 
        ? await _eventService.createEvent(
            organizerId: widget.clubId ?? _organizerId ?? Supabase.instance.client.auth.currentUser!.id,
            title: _nameController.text,
            category: selectedCategory,
            venue: _locationController.text,
            dateTime: displayDate,
            price: double.tryParse(_priceController.text) ?? 0.0,
            description: _descriptionController.text,
            imageUrl: finalImg,
            galleryImages: galleryUrls,
            contactNumber: showContactInfo ? _phoneController.text : null,
            contactType: showContactInfo ? selectedContactType : null,
            requireCallConfirmation: requireCallConfirmation,
            payAtDoor: payAtDoor,
            hidePrice: hidePrice,
            latitude: _lat,
            longitude: _lng,
            countryCode: selectedCountryCode,
            rules: _rulesController.text,
            promoDiscount: double.tryParse(_promoDiscountController.text) ?? 0.0,
            promoValue: _promoValueController.text,
            promoLabel: _promoLabelController.text,
            promoLimit: int.tryParse(_promoLimitController.text) ?? 0,
            followerDiscount: double.tryParse(_discountController.text) ?? 0.0,
            followerPerk: _perkController.text,
            hasEarlyBirdRewards: hasEarlyBirdRewards,
            maxCapacity: _isCapacityLimited ? int.tryParse(_capacityController.text) : null,
            shouldNotify: _notifyFollowers,
          ) != null
        : await _eventService.updateEvent(widget.event!.id, {
            'title': _nameController.text,
            'category': selectedCategory,
            'venue': _locationController.text,
            'date_time': _dateController.text,
            'price': double.tryParse(_priceController.text) ?? 0.0,
            'description': _descriptionController.text,
            'image_url': finalImg,
            'gallery_images': galleryUrls.isNotEmpty ? galleryUrls : null,
            'contact_number': showContactInfo ? _phoneController.text : null,
            'contact_type': showContactInfo ? selectedContactType : null,
            'require_call_confirmation': requireCallConfirmation,
            'hide_price': hidePrice,
            'latitude': _lat,
            'longitude': _lng,
            'country_code': selectedCountryCode,
            'rules': _rulesController.text,
            'promo_discount': double.tryParse(_promoDiscountController.text) ?? 0.0,
            'promo_value': _promoValueController.text.trim().isEmpty ? null : _promoValueController.text.trim(),
            'promo_label': _promoLabelController.text.trim().isEmpty ? null : _promoLabelController.text.trim(),
            'promo_limit': int.tryParse(_promoLimitController.text) ?? 0,
            'follower_discount': double.tryParse(_discountController.text) ?? 0.0,
            'follower_perk': _perkController.text.trim().isEmpty ? null : _perkController.text.trim(),
            'has_early_bird_rewards': hasEarlyBirdRewards,
            // 'amenities': _amenitiesController.text, // commented out to avoid postgres error
            'pay_at_door': payAtDoor,
            'end_date': _endDateController.text,
            'start_time': _timeController.text,
            'end_time': _endTimeController.text,
            'max_capacity': _isCapacityLimited ? int.tryParse(_capacityController.text) : null,
          });

      if (mounted) {
        setState(() => _isSubmitting = false);
        if (success) {
          DraftService().clearDraftsByPrefix('event_'); // Clear draft on success
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.event == null ? 'event_created_success'.tr : 'event_updated_success'.tr)));
          
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${'action_failed'.tr}: $e')));
      }
    }
  }

  Future<void> _pickImage(int index) async {
    final XFile? img = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
      maxWidth: 1080,
      maxHeight: 1080,
    );
    if (img != null) {
      setState(() {
        if (index == -1) {
          _mainImage = img;
        } else if (index == -2) {
          _galleryImages.add(img);
        } else {
          _galleryImages[index] = img;
        }
      });
    }
  }

  void _showSectionHelp(String section, {String? customDesc}) {
    String desc = customDesc ?? 'providing_details'.tr;
    if (section == 'media_studio'.tr) desc = 'HELP_MEDIA_DESC'.tr;
    if (section == 'FOLLOWER_PERKS'.tr) desc = 'HELP_PERKS_DESC'.tr;
    if (section == 'basic_info'.tr) desc = 'HELP_BASIC_DESC'.tr;
    if (section == 'logistics'.tr) desc = 'HELP_LOGISTICS_DESC'.tr;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(32),
        decoration: const BoxDecoration(color: Color(0xFF1A1A1A), borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
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
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.15), 
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: AppTheme.primary, size: 12),
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
        title: Text((widget.isInitial ? 'create_experience' : 'CREATE_EVENT').tr.toUpperCase(), style: AppTheme.labelStyle.copyWith(letterSpacing: 2)),
        leading: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
        actions: [
          if (widget.event == null)
            TextButton.icon(
              onPressed: _confirmClearDraft,
              icon: const Icon(Icons.delete_sweep_outlined, color: Colors.redAccent, size: 18),
              label: Text('clear'.tr.toUpperCase(), style: const TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionHeader('media_studio'.tr),
            _buildMainImagePicker(),
            const SizedBox(height: 16),
            _buildGalleryPicker(),
            
            const SizedBox(height: 32),
            // Removed static Follower Perks from here as they are inherited from Club Profile
            const SizedBox(height: 48),
            _buildLocationSyncBanner(),
            _buildSectionHeader('basic_info'.tr),
            _buildInputField('experience_name'.tr, 'experience_name_hint'.tr, _nameController, icon: Icons.auto_awesome_rounded),
            const SizedBox(height: 24),
            _buildInputField('description'.tr, 'description_hint'.tr, _descriptionController, maxLines: 4, maxLength: 250),
            
            const SizedBox(height: 32),
            _buildLogisticsSection(),
            const SizedBox(height: 32),
            _buildTimelineCard(),
            
            const SizedBox(height: 32),
            _buildCapacityCard(),

            const SizedBox(height: 32),
            _buildExpandableSection('POLICY_AND_RULES'.tr, Icons.gavel_rounded, [
              _buildInputField('house_rules'.tr, 'house_rules_hint'.tr, _rulesController, maxLines: 5),
            ]),

            const SizedBox(height: 32),
            _buildExpandableSection('universal_incentives'.tr, Icons.star_rounded, [
              Row(children: [
                Expanded(child: _buildInputField('fixed_discount'.tr + (TranslationService.isRtl ? ' (اختياري)' : ' (Optional)'), '500', _promoDiscountController, icon: Icons.money_off_rounded, keyboardType: TextInputType.number)),
                const SizedBox(width: 16),
                Expanded(flex: 2, child: _buildInputField('gift_description'.tr + (TranslationService.isRtl ? ' (اختياري)' : ' (Optional)'), 'free_drink'.tr, _promoValueController, icon: Icons.redeem_rounded)),
              ]),
              const SizedBox(height: 12),
              _buildPresetChips(['500', '1000', '2000'], (v) => _promoDiscountController.text = v),
              const SizedBox(height: 8),
              _buildPresetChips(['free_drink'.tr, 'vip_access'.tr, 'skip_line'.tr], (v) => _promoValueController.text = v),
            ]),
            
            const SizedBox(height: 32),
            // Removed Exclusive Rewards section as it's inherited from Profile

            const SizedBox(height: 48),
            _buildSectionHeader('settings'.tr),
            _buildSwitchTile('PRO-VETTING: CALL REQUIRED'.tr, 'require_confirm_desc'.tr, requireCallConfirmation, (v) => setState(() => requireCallConfirmation = v), helpKey: 'HELP_VETTING_POLICY_DESC', icon: Icons.phone_callback_rounded),
            const SizedBox(height: 8),
            _buildPaymentPolicySelector(),
            if (payAtDoor) ...[
              const SizedBox(height: 16),
              _buildInputField('${'price'.tr} (${_getCurrency()})', '2500', _priceController, icon: Icons.payments_outlined, keyboardType: TextInputType.number, helpKey: 'HELP_PRICING_DESC'),
            ],
            const SizedBox(height: 16),
            
            // SPECIAL ACTION: NOTIFY FOLLOWERS
            _buildNotifyFollowersBanner(),
            
            const SizedBox(height: 8),
            _buildSwitchTile('hide_price'.tr, 'hide_price_desc'.tr, hidePrice, (v) => setState(() => hidePrice = v), icon: Icons.money_off_rounded),
            const SizedBox(height: 8),

            const SizedBox(height: 64),
            _buildSubmitButton(),
            const SizedBox(height: 40),
            ],
          ),
        ),
      ],
    ),
    );
  }

  Widget _buildLogisticsSection() {
    return _buildExpandableSection('logistics_and_category'.tr, Icons.map_outlined, [
      const SizedBox(height: 8),
      Text('category'.tr.toUpperCase(), style: const TextStyle(color: Colors.white24, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 1)),
      const SizedBox(height: 12),
      _buildCategorySelector(),
      const SizedBox(height: 24),
      _buildInputField('venue_address'.tr, 'location_hint'.tr, _locationController, icon: Icons.location_on_rounded, helpKey: 'HELP_LOCATION_DESC'),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(child: _buildInputField('LAT', '0.0', _latController, keyboardType: TextInputType.number)),
          const SizedBox(width: 12),
          Expanded(child: _buildInputField('LNG', '0.0', _lngController, keyboardType: TextInputType.number)),
        ],
      ),
    ]);
  }

  Widget _buildCategorySelector() {
    final categories = ['club', 'lounge', 'bar', 'entertainment', 'restaurant'];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: categories.map((cat) {
        final isSel = selectedCategory == cat;
        return GestureDetector(
          onTap: () => setState(() => selectedCategory = cat),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isSel ? AppTheme.primary.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isSel ? AppTheme.primary : Colors.white.withValues(alpha: 0.05)),
            ),
            child: Text(
              cat.toUpperCase().tr,
              style: TextStyle(color: isSel ? AppTheme.primary : Colors.white38, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        children: [
          Text(title.toUpperCase(), style: AppTheme.labelStyle.copyWith(color: AppTheme.primary, fontSize: 11, letterSpacing: 3)),
          const SizedBox(width: 8),
          _buildInlineHelp(
            title, 
            'providing_details', 
            icon: title == 'media_studio'.tr ? Icons.photo_library_outlined : title == 'logistics'.tr ? Icons.map_outlined : Icons.info_outline_rounded
          ),
        ],
      ),
    );
  }

  Widget _buildMainImagePicker() {
    return GestureDetector(
      onTap: () => _pickImage(-1),
      child: Container(
        height: 220, width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 20, spreadRadius: -5),
          ],
          image: _mainImage != null ? DecorationImage(image: kIsWeb ? NetworkImage(_mainImage!.path) : FileImage(File(_mainImage!.path)) as ImageProvider, fit: BoxFit.cover) : null,
        ),
        child: _mainImage == null 
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
                  child: const Icon(Icons.add_a_photo_rounded, color: AppTheme.primary, size: 32),
                ),
                const SizedBox(height: 16),
                Text(selectedCategory.toUpperCase(), style: const TextStyle(color: AppTheme.primary, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2)),
                const SizedBox(height: 8),
                Text(
                  TranslationService.isRtl 
                    ? 'هذه الصورة ستظهر في القائمة الرئيسية' 
                    : 'This image will appear on the main feed',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            )
          : null,
      ),
    );
  }

  Widget _buildGalleryPicker() {
    return SizedBox(
      height: 90,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _galleryImages.length + 1,
        itemBuilder: (context, index) {
          if (index == _galleryImages.length) {
            return GestureDetector(
              onTap: () => _pickImage(-2),
              child: Container(
                width: 90, margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.01), 
                  borderRadius: BorderRadius.circular(20), 
                  border: Border.all(color: Colors.white.withValues(alpha: 0.05), style: BorderStyle.solid)
                ),
                child: const Icon(Icons.add_photo_alternate_outlined, color: Colors.white10),
              ),
            );
          }
          return Stack(
            children: [
              Container(
                width: 90, margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                  image: DecorationImage(image: kIsWeb ? NetworkImage(_galleryImages[index].path) : FileImage(File(_galleryImages[index].path)) as ImageProvider, fit: BoxFit.cover),
                ),
              ),
              Positioned(
                top: 5, right: 17,
                child: GestureDetector(
                  onTap: () => setState(() => _galleryImages.removeAt(index)),
                  child: Container(padding: const EdgeInsets.all(4), decoration: const BoxDecoration(color: Colors.black87, shape: BoxShape.circle), child: const Icon(Icons.close, color: Colors.white, size: 14)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildInputField(String label, String hint, TextEditingController c, {IconData? icon, int maxLines = 1, TextInputType? keyboardType, String? helpKey, int? maxLength}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label.toUpperCase(), style: const TextStyle(color: Colors.white24, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 2)),
            const SizedBox(width: 6),
            _buildInlineHelp(label, helpKey ?? (label == 'experience_name'.tr ? 'HELP_EXPERIENCE_SHORT' : 'explaining_role'), icon: label == 'experience_name'.tr ? Icons.edit_note_rounded : Icons.info_outline_rounded),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.02), 
            borderRadius: BorderRadius.circular(20), 
            border: Border.all(color: Colors.white.withValues(alpha: 0.05))
          ),
          child: TextField(
            controller: c, 
            maxLines: maxLines,
            maxLength: maxLength,
            keyboardType: keyboardType,
            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              hintText: hint, hintStyle: const TextStyle(color: Colors.white12, fontSize: 13),
              prefixIcon: icon != null ? Icon(icon, color: AppTheme.primary, size: 18) : null,
              border: InputBorder.none, contentPadding: const EdgeInsets.all(20),
            ),
          ),
        ),
      ],
    );
  }



  Widget _buildTimelineCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.event_repeat_rounded, color: AppTheme.primary.withValues(alpha: 0.5), size: 20),
              const SizedBox(width: 12),
              Text('EVENT_TIMELINE'.tr.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 2)),
              const SizedBox(width: 8),
              _buildInlineHelp('EVENT_TIMELINE'.tr, 'HELP_TIMELINE_DESC', icon: Icons.schedule_rounded),
            ],
          ),
          const SizedBox(height: 24),
          
          // STARTS ON
          Text('STARTS_ON'.tr.toUpperCase(), style: const TextStyle(color: Colors.white24, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 1)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildPickerField('date'.tr, _dateController, Icons.calendar_today_rounded, () => _selectDate(context, _dateController))),
              const SizedBox(width: 12),
              Expanded(child: _buildPickerField('time'.tr, _timeController, Icons.access_time_rounded, () => _selectTime(context, _timeController))),
            ],
          ),
          const SizedBox(height: 20),
          
          // ENDS ON
          Text('ENDS_ON'.tr.toUpperCase(), style: const TextStyle(color: Colors.white24, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 1)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildPickerField('date'.tr, _endDateController, Icons.calendar_today_rounded, () => _selectDate(context, _endDateController))),
              const SizedBox(width: 12),
              Expanded(child: _buildPickerField('time'.tr, _endTimeController, Icons.history_toggle_off_rounded, () => _selectTime(context, _endTimeController))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCapacityCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('ENABLE_CAPACITY_LIMIT'.tr, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(width: 6),
                      _buildInlineHelp('capacity'.tr, 'HELP_CAPACITY_SHORT', icon: Icons.groups_outlined),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _isCapacityLimited ? 'capacity'.tr : 'UNLIMITED_CAPACITY'.tr,
                    style: const TextStyle(color: Colors.white24, fontSize: 11),
                  ),
                ],
              ),
              Switch(
                value: _isCapacityLimited,
                onChanged: (v) => setState(() => _isCapacityLimited = v),
                activeThumbColor: AppTheme.primary,
                activeTrackColor: AppTheme.primary.withValues(alpha: 0.2),
              ),
            ],
          ),
          if (_isCapacityLimited) ...[
            const SizedBox(height: 20),
            _buildInputField('max_capacity'.tr, '150', _capacityController, icon: Icons.group_outlined, keyboardType: TextInputType.number),
          ],
        ],
      ),
    );
  }

  Widget _buildPaymentPolicySelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('PAYMENT_POLICY'.tr.toUpperCase(), style: const TextStyle(color: Colors.white24, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 2)),
        const SizedBox(height: 16),
        Row(
          children: [
            // 1. PAY AT DOOR
            Expanded(
              child: _policyCard(
                title: 'AT_DOOR'.tr,
                icon: Icons.payments_outlined,
                isActive: true,
                isSelected: payAtDoor,
                onTap: () {
                  setState(() {
                    _isFree = false;
                    payAtDoor = true;
                    if (_priceController.text == '0') _priceController.text = '';
                  });
                },
              ),
            ),
            const SizedBox(width: 8),
            // 2. FREE ENTRY
            Expanded(
              child: _policyCard(
                title: 'FREE'.tr,
                icon: Icons.redeem_rounded,
                isActive: true,
                isSelected: _isFree,
                onTap: () {
                  setState(() {
                    _isFree = true;
                    payAtDoor = false;
                    _priceController.text = '0';
                  });
                },
              ),
            ),
            const SizedBox(width: 8),
            // 3. PRE-PAID (FROZEN)
            Expanded(
              child: _policyCard(
                title: 'PREPAY_TEASER'.tr,
                icon: Icons.account_balance_wallet_outlined,
                isActive: false,
                isSelected: false,
                badge: 'SOON'.tr,
                onTap: () {
                   ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('HYPE_TITLE'.tr), backgroundColor: AppTheme.primary)
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _policyCard({
    required String title,
    required IconData icon,
    required bool isActive,
    required bool isSelected,
    required VoidCallback onTap,
    String? badge,
  }) {
    final Color color = isSelected ? AppTheme.primary : (isActive ? Colors.white54 : Colors.white10);
    
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 4),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary.withValues(alpha: 0.1) : (isActive ? Colors.white.withValues(alpha: 0.02) : Colors.transparent),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected ? AppTheme.primary : Colors.white.withValues(alpha: 0.05),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            if (isSelected)
              BoxShadow(color: AppTheme.primary.withValues(alpha: 0.1), blurRadius: 15, spreadRadius: -5),
          ],
        ),
        child: Opacity(
          opacity: isActive ? 1.0 : 0.5,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, color: isSelected ? AppTheme.primary : color, size: 24),
                  if (badge != null)
                    Positioned(
                      top: -12,
                      right: -12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: isSelected ? AppTheme.primary : Colors.white10,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Text(
                          badge.toUpperCase(),
                          style: TextStyle(
                            color: isSelected ? Colors.black : Colors.white24,
                            fontSize: 7,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                title.toUpperCase(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isSelected ? Colors.white : color,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSwitchTile(String title, String desc, bool val, Function(bool) onChanged, {String? helpKey, IconData? icon}) {
    return Container(
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.02), borderRadius: BorderRadius.circular(20)),
      child: SwitchListTile(
        secondary: icon != null ? Icon(icon, color: val ? AppTheme.primary : Colors.white38) : null,
        title: Row(
          children: [
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(width: 6),
            _buildInlineHelp(title, helpKey ?? (title.contains('VETTING') ? 'HELP_VETTING_SHORT' : 'explaining_role'), icon: title.contains('VETTING') ? Icons.verified_user_rounded : Icons.settings_rounded),
          ],
        ),
        subtitle: Text(desc, style: const TextStyle(color: Colors.white24, fontSize: 11)),
        value: val, onChanged: onChanged, activeThumbColor: AppTheme.primary,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      ),
    );
  }

  Widget _buildSubmitButton() {
    return GestureDetector(
      onTap: _isSubmitting ? null : _submit,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 64, width: double.infinity, alignment: Alignment.center,
        decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: AppTheme.primary.withValues(alpha: 0.3), blurRadius: 24, offset: const Offset(0, 8))]),
        child: _isSubmitting 
          ? const CircularProgressIndicator(color: Colors.black, strokeWidth: 3) 
          : Text('publish_event'.tr.toUpperCase(), style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, letterSpacing: 3, fontSize: 16)),
      ),
    );
  }

  Future<void> _selectDate(BuildContext context, TextEditingController controller) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppTheme.primary,
            onPrimary: Colors.black,
            surface: AppTheme.background,
            onSurface: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        controller.text = "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
      });
    }
  }

  Future<void> _selectTime(BuildContext context, TextEditingController controller) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppTheme.primary,
            onPrimary: Colors.black,
            surface: AppTheme.background,
            onSurface: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        controller.text = "${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}";
      });
    }
  }

  void _confirmClearDraft() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text('clear_draft'.tr, style: const TextStyle(color: Colors.white)),
        content: Text('clear_draft_confirm'.tr, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('cancel'.tr, style: const TextStyle(color: Colors.white24))),
          TextButton(
            onPressed: () {
              DraftService().clearDraftsByPrefix('event_');
              _clearControllers();
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('draft_cleared'.tr)));
            },
            child: Text('clear'.tr, style: const TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  void _clearControllers() {
    _nameController.clear();
    _descriptionController.clear();
    _locationController.clear();
    _priceController.clear();
    _dateController.clear();
    _endDateController.clear();
    _timeController.clear();
    _endTimeController.clear();
    setState(() {
      _mainImage = null;
      _galleryImages.clear();
    });
  }

  Widget _buildNotifyFollowersBanner() {
    return GestureDetector(
      onTap: () => setState(() => _notifyFollowers = !_notifyFollowers),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _notifyFollowers ? AppTheme.primary.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _notifyFollowers ? AppTheme.primary : Colors.white.withValues(alpha: 0.05)),
          boxShadow: [
            if (_notifyFollowers) BoxShadow(color: AppTheme.primary.withValues(alpha: 0.1), blurRadius: 20, spreadRadius: -5)
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: _notifyFollowers ? AppTheme.primary : Colors.white.withValues(alpha: 0.05), shape: BoxShape.circle),
              child: Icon(Icons.notifications_active_rounded, color: _notifyFollowers ? Colors.black : Colors.white24, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('SPECIAL_FOLLOWERS_INVITATION'.tr.toUpperCase(), style: TextStyle(color: _notifyFollowers ? AppTheme.primary : Colors.white, fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 1)),
                      const SizedBox(width: 6),
                      _buildInlineHelp('NOTIFY_FOLLOWERS'.tr, 'HELP_NOTIFY_SHORT', icon: Icons.campaign_outlined),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('notify_followers_desc'.tr, style: const TextStyle(color: Colors.white24, fontSize: 9)),
                ],
              ),
            ),
            Switch(
              value: _notifyFollowers, 
              onChanged: (v) => setState(() => _notifyFollowers = v),
              activeThumbColor: AppTheme.primary,
              activeTrackColor: AppTheme.primary.withValues(alpha: 0.2),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPickerField(String label, TextEditingController c, IconData icon, VoidCallback onTap) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: onTap,
          child: Container(
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withValues(alpha: 0.05))),
            child: Row(
              children: [
                Icon(icon, color: AppTheme.primary.withValues(alpha: 0.15), size: 20),
                const SizedBox(width: 12),
                Text(
                  c.text.isEmpty ? 'select'.tr : c.text,
                  style: TextStyle(color: c.text.isEmpty ? Colors.white12 : Colors.white, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPresetChips(List<String> options, Function(String) onSelect) {
    return SizedBox(
      height: 32,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: options.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ActionChip(
              label: Text(options[index], style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
              backgroundColor: Colors.white.withValues(alpha: 0.05),
              labelStyle: const TextStyle(color: AppTheme.primary),
              side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.2)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onPressed: () => onSelect(options[index]),
              padding: EdgeInsets.zero,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          );
        },
      ),
    );
  }
  Widget _buildExpandableSection(String title, IconData icon, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          iconColor: AppTheme.primary,
          collapsedIconColor: Colors.white38,
          title: Row(
            children: [
              Icon(icon, color: AppTheme.primary, size: 20),
              const SizedBox(width: 12),
              Text(title.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
            ],
          ),
          childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: children,
        ),
      ),
    );
  }

  String _getCurrency() {
    switch (selectedCountryCode) {
      case 'DZ': return 'DZD';
      case 'MA': return 'MAD';
      case 'TN': return 'TND';
      case 'EG': return 'EGP';
      case 'QA': return 'QAR';
      case 'AE': return 'AED';
      case 'SA': return 'SAR';
      case 'OM': return 'OMR';
      case 'KW': return 'KWD';
      case 'BH': return 'BHD';
      case 'LY': return 'LYD';
      case 'PS': return 'ILS/JOD';
      case 'SY': return 'SYP';
      case 'IQ': return 'IQD';
      case 'LB': return 'LBP';
      case 'JO': return 'JOD';
      default: return 'USD';
    }
  }
}


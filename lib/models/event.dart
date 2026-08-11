import 'package:my_app/services/localization_service.dart';

class Event {
  final String id;
  final String title;
  final String? imageUrl;
  final String? category;
  final String? venue;
  final String? dateTime;
  final double price;
  final String? description;
  final String? contactNumber; 
  final String? contactType; // CALL, WHATSAPP, VIBER, ALL
  final bool requireCallConfirmation;
  final bool hidePrice;
  final List<String> galleryImages; // optional 3 sub-images
  final int? maxCapacity; // max total persons allowed
  final String? organizerId;
  final String? organizerName;
  final String? organizerAvatar;
  final double? latitude;
  final double? longitude;
  final String countryCode; // Key for currency/prefix
  final String? rules; // NEW: House rules/entry guidelines
  final double promoDiscount;
  final String? promoValue;
  final String? promoLabel;
  final int promoLimit;
  final int promoClaimCount;
  final double followerDiscount; 
  final String? followerPerk; 
  final double globalDiscount; // NEW field
  final String? globalPerk; // NEW field
  final bool hasEarlyBirdRewards; 
  final int discountPercentage;
  final bool payAtDoor;
  final String? endTime; // FIXED: declared correctly
  final String? endDate; // NEW: Added missing field
  final bool isPinned;
  final bool isArchived;
  final bool isUrgent; // NEW: Manual Scarcity Booster
  final int totalBookedCount; // NEW: Auto-calculated Scarcity
  final int arrivedCount;
  final int bookingsCount;
  final int viewCount;
  final DateTime? createdAt;

  String? get currency => LocalizationService.getCountryByCode(countryCode).currencySymbol;

  Event({
    required this.id,
    required this.title,
    this.imageUrl,
    this.category,
    this.venue,
    this.dateTime,
    this.price = 0.0,
    this.description,
    this.contactNumber,
    this.contactType,
    this.requireCallConfirmation = false,
    this.hidePrice = false,
    this.galleryImages = const [],
    this.maxCapacity,
    this.organizerId,
    this.organizerName,
    this.organizerAvatar,
    this.latitude,
    this.longitude,
    this.countryCode = 'DZ',
    this.rules,
    this.promoDiscount = 0.0,
    this.promoValue,
    this.promoLabel,
    this.promoLimit = 0,
    this.promoClaimCount = 0,
    this.followerDiscount = 0.0,
    this.followerPerk,
    this.globalDiscount = 0.0,
    this.globalPerk,
    this.hasEarlyBirdRewards = false,
    this.discountPercentage = 0,
    this.payAtDoor = false,
    this.endTime,
    this.endDate,
    this.isPinned = false,
    this.isArchived = false,
    this.isUrgent = false,
    this.totalBookedCount = 0,
    this.arrivedCount = 0,
    this.bookingsCount = 0,
    this.viewCount = 0,
    this.createdAt,
  });

  factory Event.fromMap(Map<String, dynamic> map) {
    return Event(
      id: map['id']?.toString() ?? '',
      title: map['title'] ?? '',
      imageUrl: map['image_url'],
      category: map['category'],
      venue: map['venue'],
      dateTime: map['date_time'],
      price: (map['price'] ?? 0.0).toDouble(),
      description: map['description'],
      contactNumber: map['contact_number'],
      contactType: map['contact_type'],
      requireCallConfirmation: map['require_call_confirmation'] ?? false,
      hidePrice: map['hide_price'] ?? false,
      galleryImages: map['gallery_images'] != null 
          ? List<String>.from(map['gallery_images']) 
          : [],
      maxCapacity: map['max_capacity'] != null ? (map['max_capacity'] as num).toInt() : null,
      organizerId: map['organizer_id'],
      organizerName: map['organizer_profiles'] != null
          ? (map['organizer_profiles']['name'] ??
              map['organizer_profiles']['profiles']?['full_name'])
          : (map['profiles'] is Map ? map['profiles']['full_name'] : null),
      organizerAvatar: map['organizer_profiles'] != null
          ? map['organizer_profiles']['avatar_url']
          : (map['profiles'] is Map ? map['profiles']['avatar_url'] : null),
      latitude: map['latitude'] != null ? (map['latitude'] as num).toDouble() : null,
      longitude: map['longitude'] != null ? (map['longitude'] as num).toDouble() : null,
      countryCode: map['country_code'] ?? 'DZ',
      rules: map['rules'],
      promoDiscount: (map['promo_discount'] ?? 0.0).toDouble(),
      promoValue: map['promo_value'],
      promoLabel: map['promo_label'],
      promoLimit: map['promo_limit'] != null ? (map['promo_limit'] as num).toInt() : 0,
      promoClaimCount: map['promo_claim_count'] != null ? (map['promo_claim_count'] as num).toInt() : 0,
      followerDiscount: (map['follower_discount'] ?? 0.0).toDouble(),
      followerPerk: map['follower_perk'],
      globalDiscount: (map['global_discount'] ?? 0.0).toDouble(),
      globalPerk: map['global_perk'],
      hasEarlyBirdRewards: map['has_early_bird_rewards'] ?? false,
      discountPercentage: map['discount_percentage'] != null ? (map['discount_percentage'] as num).toInt() : 0,
      payAtDoor: map['pay_at_door'] ?? false,
      endTime: map['end_time'],
      endDate: map['end_date'],
      isPinned: map['is_pinned'] ?? false,
      isArchived: map['is_archived'] ?? false,
      isUrgent: map['is_urgent'] ?? false,
      totalBookedCount: (() {
        if (map['bookings'] != null && map['bookings'] is List) {
          int count = 0;
          for (var b in map['bookings']) {
            count += (b['num_guests'] as num?)?.toInt() ?? 0;
          }
          return count;
        }
        return 0;
      })(),
      arrivedCount: (() {
        if (map['bookings'] != null && map['bookings'] is List) {
          int count = 0;
          for (var b in map['bookings']) {
            if (b['is_scanned'] == true) {
              count += (b['num_guests'] as num?)?.toInt() ?? 0;
            }
          }
          return count;
        }
        return 0;
      })(),
      bookingsCount: (() {
        if (map['bookings'] != null && map['bookings'] is List) {
          int count = 0;
          for (var b in map['bookings']) {
            count += (b['num_guests'] as num?)?.toInt() ?? 0;
          }
          return count;
        }
        return 0;
      })(),
      viewCount: map['view_count'] != null ? (map['view_count'] as num).toInt() : 0,
      createdAt: map['created_at'] != null ? DateTime.parse(map['created_at']) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'image_url': imageUrl,
      'category': category,
      'venue': venue,
      'date_time': dateTime,
      'price': price,
      'description': description,
      'contact_number': contactNumber,
      'contact_type': contactType,
      'require_call_confirmation': requireCallConfirmation,
      'hide_price': hidePrice,
      'gallery_images': galleryImages,
      'max_capacity': maxCapacity,
      'organizer_id': organizerId,
      'latitude': latitude,
      'longitude': longitude,
      'country_code': countryCode,
      'rules': rules,
      'promo_discount': promoDiscount,
      'promo_value': promoValue,
      'promo_label': promoLabel,
      'promo_limit': promoLimit,
      'promo_claim_count': promoClaimCount,
      'follower_discount': followerDiscount,
      'follower_perk': followerPerk,
      'global_discount': globalDiscount,
      'global_perk': globalPerk,
      'has_early_bird_rewards': hasEarlyBirdRewards,
      'discount_percentage': discountPercentage,
      'pay_at_door': payAtDoor,
      'end_time': endTime,
      'end_date': endDate,
      'is_pinned': isPinned,
      'is_archived': isArchived,
      'is_urgent': isUrgent,
      'view_count': viewCount,
    };
  }
}

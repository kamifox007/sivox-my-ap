import 'package:google_maps_flutter/google_maps_flutter.dart';

class Club {
  final String id;
  final String ownerId;
  final String name;
  final String? bio;
  final String? contactPhone;
  final double? latitude;
  final double? longitude;
  final List<String> permanentGallery;
  final DateTime? createdAt;
  final String? logoUrl;
  final String businessType;

  Club({
    required this.id,
    required this.ownerId,
    required this.name,
    this.bio,
    this.contactPhone,
    this.latitude,
    this.longitude,
    this.permanentGallery = const [],
    this.createdAt,
    this.logoUrl,
    this.businessType = 'club',
  });

  factory Club.fromMap(Map<String, dynamic> map) {
    return Club(
      id: map['id']?.toString() ?? '',
      ownerId: map['owner_id']?.toString() ?? '',
      name: map['name'] ?? map['full_name'] ?? 'Elite Club',
      bio: map['bio'],
      contactPhone: map['contact_phone'],
      latitude: map['latitude']?.toDouble(),
      longitude: map['longitude']?.toDouble(),
      permanentGallery: List<String>.from(map['permanent_gallery'] ?? []),
      createdAt: map['created_at'] != null ? DateTime.parse(map['created_at']) : null,
      logoUrl: map['logo_url'],
      businessType: map['business_type']?.toString() ?? 'club',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'owner_id': ownerId,
      'name': name,
      'bio': bio,
      'contact_phone': contactPhone,
      'latitude': latitude,
      'longitude': longitude,
      'permanent_gallery': permanentGallery,
      'logo_url': logoUrl,
      'business_type': businessType,
    };
  }

  LatLng? get position => (latitude != null && longitude != null) 
    ? LatLng(latitude!, longitude!) 
    : null;
}

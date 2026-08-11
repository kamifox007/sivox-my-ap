class ExclusiveOffer {
  final String id;
  final String clubId;
  final String title;
  final String description;
  final String type; // 'discount', 'gift', 'vip'
  final int? maxClaims;
  final int claimCount;
  final DateTime? expiryDate;
  final bool isActive;
  final DateTime createdAt;

  ExclusiveOffer({
    required this.id,
    required this.clubId,
    required this.title,
    required this.description,
    required this.type,
    this.maxClaims,
    this.claimCount = 0,
    this.expiryDate,
    this.isActive = true,
    required this.createdAt,
  });

  factory ExclusiveOffer.fromMap(Map<String, dynamic> map) {
    return ExclusiveOffer(
      id: map['id']?.toString() ?? '',
      clubId: map['club_id']?.toString() ?? '',
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      type: map['type'] ?? 'discount',
      maxClaims: map['max_claims'] as int?,
      claimCount: map['claim_count'] ?? 0,
      expiryDate: map['expiry_date'] != null ? DateTime.parse(map['expiry_date']) : null,
      isActive: map['is_active'] ?? true,
      createdAt: DateTime.parse(map['created_at'] ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'club_id': clubId,
      'title': title,
      'description': description,
      'type': type,
      'max_claims': maxClaims,
      'claim_count': claimCount,
      'expiry_date': expiryDate?.toIso8601String(),
      'is_active': isActive,
    };
  }
}

import 'package:my_app/models/exclusive_offer.dart';

class Voucher {
  final String id;
  final String offerId;
  final String userId;
  final String claimCode;
  final String status;
  final DateTime createdAt;
  final ExclusiveOffer? offer;

  Voucher({
    required this.id,
    required this.offerId,
    required this.userId,
    required this.claimCode,
    required this.status,
    required this.createdAt,
    this.offer,
  });

  factory Voucher.fromMap(Map<String, dynamic> map) {
    return Voucher(
      id: map['id']?.toString() ?? '',
      offerId: map['offer_id']?.toString() ?? '',
      userId: map['user_id']?.toString() ?? '',
      claimCode: map['claim_code'] ?? '',
      status: map['status'] ?? 'active',
      createdAt: DateTime.parse(map['created_at'] ?? DateTime.now().toIso8601String()),
      offer: map['exclusive_offers'] != null 
          ? ExclusiveOffer.fromMap(map['exclusive_offers']) 
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'offer_id': offerId,
      'user_id': userId,
      'claim_code': claimCode,
      'status': status,
    };
  }
}

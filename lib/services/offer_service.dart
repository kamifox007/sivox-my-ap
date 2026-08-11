import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:my_app/models/exclusive_offer.dart';
import 'package:my_app/models/voucher.dart';

class OfferService {
  final supabase = Supabase.instance.client;

  /// Create a new exclusive offer for a club.
  Future<ExclusiveOffer?> createOffer({
    required String title,
    required String description,
    required String type,
    int? maxClaims,
    DateTime? expiryDate,
  }) async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return null;

      final response = await supabase.from('exclusive_offers').insert({
        'club_id': userId,
        'title': title,
        'description': description,
        'type': type,
        'max_claims': maxClaims,
        'expiry_date': expiryDate?.toIso8601String(),
        'is_active': true,
      }).select().single();

      final offer = ExclusiveOffer.fromMap(response);

      // Notify all followers about the new offer
      _notifyFollowersOfNewOffer(userId, offer);

      return offer;
    } catch (e) {
      return null;
    }
  }

  /// Fetch active offers for a specific club.
  Future<List<ExclusiveOffer>> getClubOffers(String clubId) async {
    try {
      final response = await supabase
          .from('exclusive_offers')
          .select()
          .eq('club_id', clubId)
          .eq('is_active', true)
          .order('created_at', ascending: false);

      return (response as List).map((o) => ExclusiveOffer.fromMap(o)).toList();
    } catch (e) {
      return [];
    }
  }

  /// Fetches all vouchers owned by the current user.
  Future<List<Voucher>> getUserVouchers() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return [];

      final response = await supabase
          .from('vouchers')
          .select('*, exclusive_offers(*)')
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      return (response as List).map((v) => Voucher.fromMap(v)).toList();
    } catch (e) {
      return [];
    }
  }

  /// Claim an offer for the current user (creates a Voucher).
  Future<Voucher?> claimOffer(String offerId) async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return null;

      // 1. Check if already claimed
      final existing = await supabase
          .from('vouchers')
          .select('*, exclusive_offers(*)')
          .eq('offer_id', offerId)
          .eq('user_id', userId)
          .maybeSingle();

      if (existing != null) return Voucher.fromMap(existing);

      // 2. Check if reached max claims
      final offerRes = await supabase
          .from('exclusive_offers')
          .select('max_claims, claim_count')
          .eq('id', offerId)
          .single();
      
      final int? max = offerRes['max_claims'];
      final int current = offerRes['claim_count'] ?? 0;

      if (max != null && current >= max) return null;

      // 3. Generate unique claim code (QR content)
      final random = Random().nextInt(90000) + 10000;
      final claimCode = 'VCH-$random-${DateTime.now().millisecondsSinceEpoch}';

      // 4. Record claim into vouchers table
      final response = await supabase.from('vouchers').insert({
        'offer_id': offerId,
        'user_id': userId,
        'claim_code': claimCode,
        'status': 'active',
      }).select('*, exclusive_offers(*)').single();

      // 5. Increment claim count on offer
      await supabase.from('exclusive_offers').update({
        'claim_count': current + 1
      }).eq('id', offerId);

      return Voucher.fromMap(response);
    } catch (e) {
      return null;
    }
  }

  Future<void> _notifyFollowersOfNewOffer(String clubId, ExclusiveOffer offer) async {
    try {
      // Fetch follower IDs
      final followersBatch = await supabase.from('followers').select('follower_id').eq('organizer_id', clubId);
      final List followers = (followersBatch as List).map((f) => f['follower_id'].toString()).toList();

      if (followers.isEmpty) return;

      // Batch insert notifications
      final notificationRows = followers.map((fId) => {
        'user_id': fId,
        'title': 'New Exclusive Offer! 🎁',
        'body': 'Check out what is new at your favorite club: ${offer.title}',
        'type': 'offer',
        'metadata': {'offer_id': offer.id, 'club_id': clubId},
        'is_read': false,
      }).toList();

      await supabase.from('notifications').insert(notificationRows);
    } catch (_) {}
  }
}

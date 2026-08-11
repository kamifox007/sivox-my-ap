import 'package:supabase_flutter/supabase_flutter.dart';

class ReviewService {
  final _supabase = Supabase.instance.client;

  Future<Map<String, dynamic>> getOrganizerRating(String organizerId) async {
    try {
      final res = await _supabase
          .from('organizer_reviews')
          .select('rating')
          .eq('organizer_id', organizerId);
      
      final list = res as List;
      if (list.isEmpty) return {'avg': 0.0, 'count': 0};

      double sum = 0;
      for (var item in list) {
        sum += (item['rating'] as int);
      }
      return {
        'avg': sum / list.length,
        'count': list.length,
      };
    } catch (e) {
      return {'avg': 0.0, 'count': 0};
    }
  }

  Future<int?> getUserReview(String organizerId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;
    
    try {
      final res = await _supabase
          .from('organizer_reviews')
          .select('rating')
          .eq('organizer_id', organizerId)
          .eq('user_id', user.id)
          .maybeSingle();
      
      return res?['rating'] as int?;
    } catch (e) {
      return null;
    }
  }

  Future<bool> submitReview(String organizerId, int rating, {String? comment}) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;

    try {
      await _supabase.from('organizer_reviews').upsert({
        'user_id': user.id,
        'organizer_id': organizerId,
        'rating': rating,
        'comment': comment,
        'created_at': DateTime.now().toIso8601String(),
      });
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Checks if there is a recently 'used' ticket for an event that has ended,
  /// and the user hasn't rated the club yet.
  Future<Map<String, dynamic>?> getPendingReviewEvent() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    try {
      // 1. Get used bookings
      final bookings = await _supabase
          .from('bookings')
          .select('event_id, events(organizer_id, title, organizer_profiles(name))')
          .eq('user_id', user.id)
          .eq('payment_status', 'used')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (bookings == null) return null;

      final event = bookings['events'];
      final organizerId = event['organizer_id'];
      final clubName = event['organizer_profiles']['name'];

      // 2. Check if already reviewed
      final existing = await _supabase
          .from('organizer_reviews')
          .select('id')
          .eq('user_id', user.id)
          .eq('organizer_id', organizerId)
          .maybeSingle();

      if (existing == null) {
        return {
          'organizer_id': organizerId,
          'club_name': clubName,
          'event_title': event['title'],
        };
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}

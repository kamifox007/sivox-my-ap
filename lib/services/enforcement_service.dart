import 'package:supabase_flutter/supabase_flutter.dart';

class EnforcementService {
  final supabase = Supabase.instance.client;

  /// Kicks a guest from an event by revoking their booking status.
  Future<bool> ejectGuest({
    required String bookingId,
    required String reason,
  }) async {
    try {
      await supabase.from('bookings').update({
        'payment_status': 'ejected',
        'cancellation_reason': reason,
      }).eq('id', bookingId);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Adds a guest to the permenant blacklist of a specific club.
  Future<bool> addToBlacklist({
    required String clubId,
    String? userId,
    String? phone,
    String? reason,
  }) async {
    try {
      await supabase.from('blacklist').upsert({
        'club_id': clubId,
        'user_id': userId,
        'phone_number': phone,
        'reason': reason ?? 'Security Policy',
        'created_at': DateTime.now().toIso8601String(),
      });
      return true;
    } catch (e) {
      // If table doesn't exist, we might fall back to a different mechanism
      // or just log it in staff_logs for now as a "Reported" action.
      return false;
    }
  }

  /// Checks if a guest is blacklisted in this club.
  Future<bool> isBlacklisted({
    required String clubId,
    String? userId,
    String? phone,
  }) async {
    try {
      if (userId == null && phone == null) return false;

      var query = supabase.from('blacklist').select().eq('club_id', clubId);
      
      if (userId != null) {
        query = query.eq('user_id', userId);
      } else if (phone != null) {
        query = query.eq('phone_number', phone);
      }

      final response = await query.maybeSingle();
      return response != null;
    } catch (e) {
      return false;
    }
  }

  /// Fetches the full blacklist for a specific club.
  Future<List<Map<String, dynamic>>> getBlacklist(String clubId) async {
    try {
      final response = await supabase
          .from('blacklist')
          .select('*, profiles:user_id(full_name, avatar_url)')
          .eq('club_id', clubId)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      return [];
    }
  }

  /// Removes a user from the permanent blacklist.
  Future<bool> removeFromBlacklist(String blacklistId) async {
    try {
      await supabase.from('blacklist').delete().eq('id', blacklistId);
      return true;
    } catch (e) {
      return false;
    }
  }
}

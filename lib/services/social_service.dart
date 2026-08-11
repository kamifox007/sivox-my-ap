import 'package:supabase_flutter/supabase_flutter.dart';

class SocialService {
  final supabase = Supabase.instance.client;

  /// Reports a club for a specific reason.
  Future<bool> reportClub({
    required String organizerId,
    required String reason,
    String? details,
  }) async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return false;

      await supabase.from('reports').insert({
        'user_id': userId,
        'organizer_id': organizerId,
        'reason': reason,
        'details': details,
      });
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Blocks a club for the current user.
  Future<bool> blockClub(String organizerId) async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return false;

      await supabase.from('blocks').insert({
        'user_id': userId,
        'organizer_id': organizerId,
      });
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Checks if a club is blocked by the current user.
  Future<bool> isBlocked(String organizerId) async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return false;

      final response = await supabase
          .from('blocks')
          .select()
          .eq('user_id', userId)
          .eq('organizer_id', organizerId)
          .maybeSingle();
      
      return response != null;
    } catch (e) {
      return false;
    }
  }

  /// Unblocks a club.
  Future<bool> unblockClub(String organizerId) async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return false;

      await supabase
          .from('blocks')
          .delete()
          .eq('user_id', userId)
          .eq('organizer_id', organizerId);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Fetches the list of blocked organizer IDs.
  Future<List<String>> getBlockedIds() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return [];

      final response = await supabase
          .from('blocks')
          .select('organizer_id')
          .eq('user_id', userId);
      
      return (response as List).map((r) => r['organizer_id'] as String).toList();
    } catch (e) {
      return [];
    }
  }
}

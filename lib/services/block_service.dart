import 'package:supabase_flutter/supabase_flutter.dart';

class BlockService {
  final supabase = Supabase.instance.client;

  /// Blocks an organizer for the current user.
  Future<bool> blockOrganizer(String organizerId) async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return false;

      // 1. Check if already blocked
      final existing = await supabase
          .from('blocks')
          .select()
          .eq('user_id', userId)
          .eq('blocked_organizer_id', organizerId)
          .maybeSingle();

      if (existing == null) {
        await supabase.from('blocks').insert({
          'user_id': userId,
          'blocked_organizer_id': organizerId,
        });
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Unblocks an organizer.
  Future<bool> unblockOrganizer(String organizerId) async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return false;

      await supabase
          .from('blocks')
          .delete()
          .eq('user_id', userId)
          .eq('blocked_organizer_id', organizerId);
      
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Fetches the list of blocked organizer IDs for the current user.
  Future<List<String>> getBlockedOrganizerIds() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return [];

      final response = await supabase
          .from('blocks')
          .select('blocked_organizer_id')
          .eq('user_id', userId);

      return (response as List)
          .map((b) => b['blocked_organizer_id'].toString())
          .toList();
    } catch (e) {
      return [];
    }
  }
}

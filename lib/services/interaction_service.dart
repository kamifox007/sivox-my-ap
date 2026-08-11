import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

class InteractionService {
  final supabase = Supabase.instance.client;

  Future<void> recordLike(String eventId) async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      // Check if already liked
      final existing = await supabase
          .from('likes')
          .select()
          .eq('user_id', userId)
          .eq('event_id', eventId)
          .maybeSingle();

      if (existing == null) {
        await supabase.from('likes').insert({
          'user_id': userId,
          'event_id': eventId,
        });
      }
    } catch (e) {
      debugPrint('Error recording like: $e');
    }
  }

  Future<void> recordShare(String eventId, {String? platform}) async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      await supabase.from('shares').insert({
        'user_id': userId,
        'event_id': eventId,
        'platform': platform,
      });
    } catch (e) {
      debugPrint('Error recording share: $e');
    }
  }

  Future<int> getEventLikesCount(String eventId) async {
    try {
      final res = await supabase
          .from('likes')
          .select('id')
          .eq('event_id', eventId);
      
      return (res as List).length;
    } catch (e) {
      return 0;
    }
  }

  Future<bool> isEventLiked(String eventId) async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return false;

      final existing = await supabase
          .from('likes')
          .select()
          .eq('user_id', userId)
          .eq('event_id', eventId)
          .maybeSingle();

      return existing != null;
    } catch (e) {
      return false;
    }
  }

  Future<void> toggleLike(String eventId) async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      final liked = await isEventLiked(eventId);
      if (liked) {
        await supabase
            .from('likes')
            .delete()
            .eq('user_id', userId)
            .eq('event_id', eventId);
      } else {
        await supabase.from('likes').insert({
          'user_id': userId,
          'event_id': eventId,
        });
      }
    } catch (e) {
      debugPrint('Error toggling like: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getLikes() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return [];

      final res = await supabase
          .from('likes')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      
      return List<Map<String, dynamic>>.from(res as List);
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getShares() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return [];

      final res = await supabase
          .from('shares')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      
      return List<Map<String, dynamic>>.from(res as List);
    } catch (e) {
      return [];
    }
  }
}

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:my_app/models/event.dart';

class FavoriteService {
  final _supabase = Supabase.instance.client;

  static const String tableFavorites = 'favorites';

  /// Adds a favorite (event or club).
  Future<bool> addFavorite({String? eventId, String? clubId}) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return false;

      await _supabase.from(tableFavorites).insert({
        'user_id': user.id,
        'event_id': eventId,
        'club_id': clubId,
      });
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Removes a favorite.
  Future<bool> removeFavorite({String? eventId, String? clubId}) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return false;

      final query = _supabase.from(tableFavorites).delete().eq('user_id', user.id);
      if (eventId != null) query.eq('event_id', eventId);
      if (clubId != null) query.eq('club_id', clubId);
      
      await query;
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Checks if an item is favorited.
  Future<bool> isFavorited({String? eventId, String? clubId}) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return false;

      final query = _supabase.from(tableFavorites).select('id').eq('user_id', user.id);
      if (eventId != null) query.eq('event_id', eventId);
      if (clubId != null) query.eq('club_id', clubId);
      
      final response = await query.maybeSingle();
      return response != null;
    } catch (e) {
      return false;
    }
  }

  /// Toggles a favorite (adds if not present, removes if present).
  Future<bool> toggleFavorite(dynamic eventOrId, {String? clubId}) async {
    try {
      final String eventId = eventOrId is Event ? eventOrId.id : eventOrId.toString();
      final isFav = await isFavorited(eventId: eventId, clubId: clubId);
      if (isFav) {
        return await removeFavorite(eventId: eventId, clubId: clubId);
      } else {
        return await addFavorite(eventId: eventId, clubId: clubId);
      }
    } catch (e) {
      return false;
    }
  }

  /// Fetches all favorite events for the current user.
  Future<List<Map<String, dynamic>>> getFavoriteEvents() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return [];

      final response = await _supabase
          .from(tableFavorites)
          .select('*, events(*)')
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      return [];
    }
  }

  /// Fetches all favorite event IDs for the current user.
  Future<List<String>> getFavoriteEventIds() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return [];

      final response = await _supabase
          .from(tableFavorites)
          .select('event_id')
          .eq('user_id', user.id);

      return List<String>.from((response as List).map((e) => e['event_id']?.toString() ?? ''));
    } catch (e) {
      return [];
    }
  }
}

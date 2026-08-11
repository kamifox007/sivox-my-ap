import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:my_app/services/audit_service.dart';

class FollowService {
  final supabase = Supabase.instance.client;
  final _audit = AuditService();

  /// Toggles following a club/organizer.
  Future<bool> toggleFollow(String organizerId) async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return false;

      final existing = await supabase
          .from('follows')
          .select()
          .eq('user_id', userId)
          .eq('organizer_id', organizerId)
          .maybeSingle();

      if (existing != null) {
        await unfollowOrganizer(organizerId);
        return false;
      } else {
        await followOrganizer(organizerId);
        return true;
      }
    } catch (e) {
      return false;
    }
  }

  /// Explicitly follows an organizer.
  Future<bool> followOrganizer(String organizerId) async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return false;

      await supabase.from('follows').upsert({
        'user_id': userId,
        'organizer_id': organizerId,
      });

      await _audit.logAction(
        actionType: 'NEW_FOLLOWER',
        description: 'Brand growth: A new visitor has followed your club profile.',
      );
      return true;
    } catch (e) {
      debugPrint('Error following organizer: $e');
      return false;
    }
  }

  /// Explicitly unfollows an organizer.
  Future<bool> unfollowOrganizer(String organizerId) async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return false;

      await supabase
          .from('follows')
          .delete()
          .eq('user_id', userId)
          .eq('organizer_id', organizerId);
      return true;
    } catch (e) {
      debugPrint('Error unfollowing organizer: $e');
      return false;
    }
  }

  /// Checks if a user is following a specific organizer.
  /// If [userId] is provided, checks that user. Otherwise checks the current user.
  Future<bool> isFollowing(String organizerId, {String? userId}) async {
    try {
      final uid = userId ?? supabase.auth.currentUser?.id;
      if (uid == null) return false;

      final response = await supabase
          .from('follows')
          .select()
          .eq('user_id', uid)
          .eq('organizer_id', organizerId)
          .maybeSingle();
      
      return response != null;
    } catch (e) {
      return false;
    }
  }

  Future<List<String>> getFollowedOrganizers() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return [];

      final response = await supabase
          .from('follows')
          .select('organizer_id')
          .eq('user_id', userId);

      return (response as List<dynamic>).map((f) => f['organizer_id'].toString()).toList();
    } catch (e) {
      return [];
    }
  }

  /// Organizer metrics: Count followers
  Future<int> getFollowerCount(String organizerId) async {
    try {
      final res = await supabase.from('follows').select('user_id').eq('organizer_id', organizerId);
      return (res as List<dynamic>).length;
    } catch (e) {
      return 0;
    }
  }

  /// Organizer metrics: Get all follower user IDs
  Future<List<String>> getFollowers(String organizerId) async {
    try {
      final res = await supabase.from('follows')
          .select('user_id')
          .eq('organizer_id', organizerId);
      return (res as List<dynamic>).map((r) => r['user_id'].toString()).toList();
    } catch (e) {
      return [];
    }
  }

  /// Organizer metrics: Get list of followers who have notifications enabled
  Future<List<String>> getFollowersOfOrganizer(String organizerId) async {
    try {
      final res = await supabase.from('follows')
          .select('user_id')
          .eq('organizer_id', organizerId)
          .eq('notifications_enabled', true);
      return (res as List<dynamic>).map((r) => r['user_id'].toString()).toList();
    } catch (e) {
      return [];
    }
  }

  /// Checks if notifications are enabled for a specific follow.

  Future<bool> areNotificationsEnabled(String organizerId) async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return false;

      final response = await supabase
          .from('follows')
          .select('notifications_enabled')
          .eq('user_id', userId)
          .eq('organizer_id', organizerId)
          .maybeSingle();
      
      return response?['notifications_enabled'] ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Toggles notifications for a specific follow.
  Future<bool> toggleNotifications(String organizerId) async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return false;

      final current = await areNotificationsEnabled(organizerId);
      final newValue = !current;

      await supabase
          .from('follows')
          .update({'notifications_enabled': newValue})
          .eq('user_id', userId)
          .eq('organizer_id', organizerId);
      
      return newValue;
    } catch (e) {
      return false;
    }
  }
}


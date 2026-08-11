import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:my_app/services/notification_service.dart';

class BroadcastService {
  final supabase = Supabase.instance.client;
  final _notifService = NotificationService();

  /// Fetches all user IDs who follow a specific organizer.
  Future<List<String>> getFollowerIds(String organizerId) async {
    try {
      final res = await supabase
          .from('followers')
          .select('user_id')
          .eq('organizer_id', organizerId);
      return (res as List).map((r) => r['user_id'].toString()).toList();
    } catch (e) {
      return [];
    }
  }

  /// Fetches all staff member IDs assigned to a specific organizer.
  Future<List<String>> getStaffIds(String organizerId) async {
    try {
      final res = await supabase
          .from('staff_assignments')
          .select('staff_id')
          .eq('organizer_id', organizerId)
          .eq('status', 'active');
      return (res as List).map((r) => r['staff_id'].toString()).toList();
    } catch (e) {
      return [];
    }
  }

  /// Sends a broadcast notification to a list of users.
  Future<void> sendBroadcast({
    required List<String> userIds,
    required String title,
    required String body,
    String? type,
  }) async {
    for (final id in userIds) {
      await _notifService.sendNotificationToUser(
        userId: id,
        title: title,
        body: body,
        type: type ?? 'broadcast',
      );
    }
  }
}

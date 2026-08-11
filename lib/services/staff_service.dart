import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:my_app/services/notification_service.dart';
import 'package:my_app/services/translation_service.dart';

class StaffService {
  final supabase = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> getActiveAssignments() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return [];

    try {
      final response = await supabase
          .from('staff_assignments')
          .select('*, events(title, venue, organizer_id, image_url), organizer_profiles(name, bio)')
          .eq('staff_id', userId)
          .or('status.eq.active,status.eq.pending')
          .order('created_at', ascending: false);


      return (response as List).map((res) {
        final event = res['events'];
        return {
          'id': res['id'],
          'event_id': res['event_id'],
          'club_name': event != null ? event['venue'] : 'Pending Club',
          'role': res['role'] ?? 'Scanner',
          'status': res['status'],
          'organizer_id': event != null ? event['organizer_id'] : res['organizer_id'],
          'event_title': event != null ? event['title'] : 'General Service',
          'image_url': event != null ? event['image_url'] : null,
          'permissions': res['permissions'] ?? {},
        };
      }).toList();
    } catch (e) {
      return [];
    }
  }

  Future<Map<String, dynamic>?> getActiveAssignment() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return null;

    try {
      // Fetch assignment from database
      final response = await supabase
          .from('staff_assignments')
          .select('*, events(title, venue, organizer_id)')
          .eq('staff_id', userId)
          .or('status.eq.active,status.eq.pending')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null) return null;

      final event = response['events'];
      final club = response['organizer_profiles'];
      return {
        'id': response['id'],
        'event_id': response['event_id'],
        'club_name': club != null ? club['name'] : (event != null ? event['venue'] : 'Pending Club'),
        'role': response['role'] ?? 'Scanner',
        'status': response['status'],
        'organizer_id': response['organizer_id'] ?? (event != null ? event['organizer_id'] : null),
        'event_title': event != null ? event['title'] : 'General Service',
        'permissions': response['permissions'] ?? {},
      };
    } catch (e) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> getAssignmentById(String id) async {
    try {
      final response = await supabase
          .from('staff_assignments')
          .select('*, events(title, venue, organizer_id)')
          .eq('id', id)
          .maybeSingle();

      if (response == null) return null;

      final event = response['events'];
      return {
        'id': response['id'],
        'club_name': event != null ? event['venue'] : 'Pending Club',
        'role': response['role'] ?? 'Scanner',
        'status': response['status'],
        'organizer_id': event != null ? event['organizer_id'] : response['organizer_id'],
        'event_title': event != null ? event['title'] : 'General Service',
      };
    } catch (e) {
      return null;
    }
  }

  Future<bool> acceptAssignment(String assignmentId) async {
    try {
      await supabase
          .from('staff_assignments')
          .update({'status': 'active'})
          .eq('id', assignmentId);
          
      // Notify Organizer
      final assignment = await getAssignmentById(assignmentId);
      if (assignment != null && assignment['organizer_id'] != null) {
        final staffName = supabase.auth.currentUser?.userMetadata?['full_name'] ?? 'Staff';
        await NotificationService().sendNotificationToUser(
          userId: assignment['organizer_id'],
          title: 'STAFF_ACCEPTED_TITLE'.tr,
          body: 'STAFF_ACCEPTED_BODY'.trArgs([staffName, assignment['role'].toString().tr]),
          type: 'staff_update',
        );
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> rejectAssignment(String assignmentId) async {
    try {
      await supabase
          .from('staff_assignments')
          .update({'status': 'rejected'})
          .eq('id', assignmentId);

      // Notify Organizer
      final assignment = await getAssignmentById(assignmentId);
      if (assignment != null && assignment['organizer_id'] != null) {
        final staffName = supabase.auth.currentUser?.userMetadata?['full_name'] ?? 'Staff';
        await NotificationService().sendNotificationToUser(
          userId: assignment['organizer_id'],
          title: 'STAFF_REJECTED_TITLE'.tr,
          body: 'STAFF_REJECTED_BODY'.trArgs([staffName]),
          type: 'staff_update',
        );
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> resignFromClub(String assignmentId) async {
    try {
      await supabase
          .from('staff_assignments')
          .delete()
          .eq('id', assignmentId);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> toggleAbsence(String assignmentId, bool isAbsent) async {
    try {
      await supabase
          .from('staff_assignments')
          .update({'status': isAbsent ? 'absent' : 'active'})
          .eq('id', assignmentId);
      return true;
    } catch (e) {
      return false;
    }
  }
}

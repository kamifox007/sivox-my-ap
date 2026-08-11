import 'package:supabase_flutter/supabase_flutter.dart';

class StaffShiftService {
  final supabase = Supabase.instance.client;

  /// Fetches the currently active shift for the logged-in staff member.
  Future<Map<String, dynamic>?> getCurrentShift() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return null;

      final res = await supabase
          .from('staff_shifts')
          .select()
          .eq('staff_id', userId)
          .isFilter('end_time', null)
          .order('start_time', ascending: false)
          .limit(1)
          .maybeSingle();
      
      return res;
    } catch (e) {
      return null;
    }
  }

  /// Starts a new shift for the staff member.
  Future<bool> clockIn(String assignmentId, {double? lat, double? lng}) async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return false;

      // Check for already active shift
      final active = await getCurrentShift();
      if (active != null) return false;

      await supabase.from('staff_shifts').insert({
        'staff_id': userId,
        'assignment_id': assignmentId,
        'start_time': DateTime.now().toIso8601String(),
        'start_lat': lat,
        'start_lng': lng,
      });
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Ends the currently active shift.
  Future<bool> clockOut({double? lat, double? lng}) async {
    try {
      final shift = await getCurrentShift();
      if (shift == null) return false;

      await supabase.from('staff_shifts').update({
        'end_time': DateTime.now().toIso8601String(),
        'end_lat': lat,
        'end_lng': lng,
      }).eq('id', shift['id']);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Fetches the total duration of the current shift in a readable format.
  String getFormatDuration(DateTime start) {
      final diff = DateTime.now().difference(start);
      final hours = diff.inHours.toString().padLeft(2, '0');
      final mins = (diff.inMinutes % 60).toString().padLeft(2, '0');
      return '$hours:$mins';
  }
}

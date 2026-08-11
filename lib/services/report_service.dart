import 'package:supabase_flutter/supabase_flutter.dart';

class ReportService {
  final _supabase = Supabase.instance.client;

  Future<void> submitReport({
    required String eventId,
    required String reason,
    String? details,
  }) async {
    final user = _supabase.auth.currentUser;
    
    // Insert report
    await _supabase.from('event_reports').insert({
      'event_id': eventId,
      'reporter_id': user?.id,
      'reason': reason,
      'details': details,
      'created_at': DateTime.now().toIso8601String(),
    });

    // Check count of reports for THE SAME REASON for THIS EVENT
    final response = await _supabase
        .from('event_reports')
        .select('id')
        .eq('event_id', eventId)
        .eq('reason', reason);
    
    final count = (response as List).length;

    // Auto-hide threshold = 20
    if (count >= 20) {
      await _supabase
          .from('events')
          .update({'is_hidden': true})
          .eq('id', eventId);
    }
  }
}

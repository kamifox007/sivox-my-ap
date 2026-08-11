import 'package:supabase_flutter/supabase_flutter.dart';

class SupportService {
  final _supabase = Supabase.instance.client;

  Future<void> sendSupportRequest({
    required String subject,
    required String message,
    String? category,
  }) async {
    final user = _supabase.auth.currentUser;
    await _supabase.from('support_requests').insert({
      'user_id': user?.id,
      'user_email': user?.email,
      'user_name': user?.userMetadata?['full_name'],
      'subject': subject,
      'message': message,
      'category': category ?? 'General',
      'status': 'pending',
      'created_at': DateTime.now().toIso8601String(),
    });
  }
}

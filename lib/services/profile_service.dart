import 'package:supabase_flutter/supabase_flutter.dart';

/// Creates a missing public profile for an authenticated user.
///
/// The database supplies the default role (attendee). User-editable Auth
/// metadata is used only for display fields and is never copied into role.
class ProfileService {
  final SupabaseClient _client;

  ProfileService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  Future<String> getTrustedRole(User user) async {
    try {
      await ensureProfile(user);
      final result = await _client.rpc('get_my_profile_role');
      final role = result?.toString().toLowerCase();
      const allowedRoles = {
        'attendee',
        'organizer',
        'staff',
        'admin',
        'manager',
        'owner',
      };
      return role != null && allowedRoles.contains(role) ? role : 'attendee';
    } catch (_) {
      return 'attendee';
    }
  }

  Future<void> ensureProfile(User user) async {
    final metadata = user.userMetadata ?? const <String, dynamic>{};
    final row = <String, dynamic>{'id': user.id};

    final fullName = metadata['full_name'];
    if (fullName is String && fullName.trim().isNotEmpty) {
      row['full_name'] = fullName.trim();
    }

    final avatarUrl = metadata['avatar_url'];
    if (avatarUrl is String && avatarUrl.trim().isNotEmpty) {
      row['avatar_url'] = avatarUrl.trim();
    }

    final countryCode = metadata['country_code'];
    if (countryCode is String && countryCode.trim().isNotEmpty) {
      row['country_code'] = countryCode.trim();
    }

    // Ignore conflicts so existing database roles and profile data stay untouched.
    await _client
        .from('profiles')
        .upsert(row, onConflict: 'id', ignoreDuplicates: true);
  }
}

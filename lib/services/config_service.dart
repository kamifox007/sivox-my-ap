import 'package:supabase_flutter/supabase_flutter.dart';

class ConfigService {
  final _supabase = Supabase.instance.client;

  Future<Map<String, dynamic>?> getAppConfig() async {
    try {
      final res = await _supabase
          .from('app_config')
          .select()
          .limit(1)
          .single();
      return res;
    } catch (e) {
      return null;
    }
  }

  Future<bool> checkMaintenance() async {
    final config = await getAppConfig();
    if (config == null) return false;
    return config['is_maintenance'] ?? false;
  }
}

import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  final client = Supabase.instance.client;
  final res = await client.from('test').select('*').count(CountOption.exact);
  // ignore: avoid_print
  print('Probe Result: ${res.data}');
}

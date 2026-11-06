import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:my_app/main.dart';

class MockLocalStorage extends LocalStorage implements GotrueAsyncStorage {
  const MockLocalStorage();

  @override
  Future<void> initialize() async {}

  @override
  Future<String?> accessToken() async => null;

  @override
  Future<bool> hasAccessToken() async => false;

  @override
  Future<void> persistSession(String persistSessionString) async {}

  @override
  Future<void> removePersistedSession() async {}

  @override
  Future<String?> getItem({required String key}) async => null;

  @override
  Future<void> setItem({required String key, required String value}) async {}

  @override
  Future<void> removeItem({required String key}) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Initialize Supabase with dummy credentials and mock storage for the test environment
    try {
      final mock = const MockLocalStorage();
      await Supabase.initialize(
        url: 'https://placeholder.supabase.co',
        anonKey: 'placeholder_anon_key',
        authOptions: FlutterAuthClientOptions(
          localStorage: mock,
          pkceAsyncStorage: mock,
        ),
      );
    } catch (_) {}
  });

  testWidgets('Sivox app renders its initialization fallback', (WidgetTester tester) async {
    // The initialized app starts SplashScreen, which deliberately owns a 2.5s
    // delayed route transition. Keep this smoke test deterministic by checking
    // the app's initialization fallback without creating an uncancellable timer.
    await tester.pumpWidget(const SivoxApp(initialized: false));

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('db_conn_failed'), findsOneWidget);
  });
}

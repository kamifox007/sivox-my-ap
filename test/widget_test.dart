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

  testWidgets('Smoke test for SIFO App Startup', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    // We pass initialized: true to simulate a successful connection
    await tester.pumpWidget(const SivoxApp(initialized: true));

    // Verify the root application renders without waiting for animations to settle.
    // The home feed intentionally contains repeating animations, so pumpAndSettle
    // would time out even when the application is working correctly.
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}

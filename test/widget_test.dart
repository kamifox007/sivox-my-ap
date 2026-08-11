import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:my_app/main.dart';

class MockLocalStorage extends LocalStorage {
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
}

void main() {
  setUpAll(() async {
    // Initialize Supabase with dummy credentials and mock storage for the test environment
    try {
      await Supabase.initialize(
        url: 'https://placeholder.supabase.co',
        anonKey: 'placeholder_anon_key',
        authOptions: const FlutterAuthClientOptions(
          localStorage: MockLocalStorage(),
        ),
      );
    } catch (_) {}
  });

  testWidgets('Smoke test for SIFO App Startup', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    // We pass initialized: true to simulate a successful connection
    await tester.pumpWidget(const SivoxApp(initialized: true));

    // Wait for the splash screen's initial frame
    await tester.pump();

    // Advance the timer by 3 seconds to let the splash screen transition delay expire
    await tester.pump(const Duration(milliseconds: 3000));

    // Wait for any route transitions to complete
    await tester.pumpAndSettle();

    // Verify that the app starts.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}

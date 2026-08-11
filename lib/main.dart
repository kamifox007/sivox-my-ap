import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/services/translation_service.dart';
import 'package:my_app/services/notification_service.dart';
import 'package:my_app/services/draft_service.dart';
import 'package:my_app/services/audit_service.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:my_app/screens/splash_screen.dart';
import 'package:my_app/screens/auth_screen.dart';
import 'package:my_app/screens/home_feed.dart';
import 'package:my_app/screens/organizer_main_wrapper.dart';
import 'package:my_app/screens/staff_acceptance_screen.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureLocalStorage extends LocalStorage {
  const SecureLocalStorage();

  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _sessionKey = 'sb-session';

  @override
  Future<void> initialize() async {}

  @override
  Future<String?> accessToken() async {
    return _secureStorage.read(key: _sessionKey);
  }

  @override
  Future<bool> hasAccessToken() async {
    final token = await _secureStorage.read(key: _sessionKey);
    return token != null;
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    await _secureStorage.write(key: _sessionKey, value: persistSessionString);
  }

  @override
  Future<void> removePersistedSession() async {
    await _secureStorage.delete(key: _sessionKey);
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint('Error loading .env file: $e');
  }

  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Firebase Initialization Error: $e');
  }

  // 📊 إعداد حارس الأخطاء العام والأعطال (Global Crash & Error Monitoring)
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('Flutter Error: ${details.exception}');
    
    // تسجيل الأخطاء البرمجية للواجهة في سجلات الأمان بقاعدة البيانات تلقائياً
    try {
      final audit = AuditService();
      audit.logAction(
        actionType: 'CLIENT_CRASH_FLUTTER',
        description: 'Flutter Framework Error: ${details.exceptionAsString()}',
        metadata: {
          'library': details.library ?? 'unknown',
          'stack': details.stack?.toString().substring(0, 1000) ?? '',
        },
      );
    } catch (_) {}
  };

  // التقاط كافة الأخطاء البرمجية غير المتزامنة (Asynchronous Unhandled Exceptions)
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    debugPrint('Async Unhandled Error: $error');
    
    try {
      final audit = AuditService();
      audit.logAction(
        actionType: 'CLIENT_CRASH_ASYNC',
        description: 'Async Error: $error',
        metadata: {
          'stack': stack.toString().substring(0, 1000),
        },
      );
    } catch (_) {}
    return true; // إعلام النظام بأن الخطأ تم معالجته وتسجيله بنجاح
  };

  try {
    await NotificationService.initExternalNotifications();
    await initializeDateFormatting('ar', null);
    await DraftService().init(); // Initialize permanent drafts
  } catch (e) {
    debugPrint('DateFormatting Error: $e');
  }

  // Use a simpler initial state
  bool initialized = false;
  try {
    await Supabase.initialize(
      url: dotenv.env['SUPABASE_URL'] ?? 'https://jufsecvkztpzugvyrhjo.supabase.co',
      anonKey: dotenv.env['SUPABASE_ANON_KEY'] ?? 'sb_publishable_Z37Cm5OShXJIv9ELlzVczQ_OGKV2i07',
      authOptions: FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
        localStorage: const SecureLocalStorage(),
      ),
    ).timeout(const Duration(seconds: 15));
    initialized = true;
  } catch (e) {
    debugPrint('Supabase Initialization Error: $e');
  }

  runApp(SivoxApp(initialized: initialized));
}

class SivoxApp extends StatelessWidget {
  final bool initialized;
  const SivoxApp({super.key, required this.initialized});

  @override
  Widget build(BuildContext context) {
    // Basic connectivity error screen if initialization failed
    if (!initialized) {
      return MaterialApp(
        title: 'Sivox',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: Scaffold(
          backgroundColor: AppTheme.background,
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.cloud_off_rounded,
                    color: AppTheme.primary,
                    size: 80,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'db_conn_failed'.tr,
                    style: AppTheme.headlineStyle.copyWith(fontSize: 20),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'check_internet'.tr,
                    textAlign: TextAlign.center,
                    style: AppTheme.bodyStyle.copyWith(color: Colors.white54),
                  ),
                  const SizedBox(height: 48),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => main(),
                      child: Text('retry'.tr.toUpperCase()),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return ValueListenableBuilder<Language>(
      valueListenable: TranslationService.currentLanguage,
      builder: (context, currentLang, _) {
        return MaterialApp(
          title: 'app_name'.tr,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.darkTheme,
          color: AppTheme.background,
          builder: (context, child) {
            return Directionality(
              textDirection: TranslationService.isRtl
                  ? TextDirection.rtl
                  : TextDirection.ltr,
              child: child ?? Container(color: AppTheme.background),
            );
          },
          initialRoute: '/',
          routes: {
            '/': (context) => const SplashScreen(),
            '/login': (context) => const AuthScreen(),
            '/home': (context) => const HomeFeedScreen(),
            '/organizer': (context) => const OrganizerMainWrapper(),
            '/staff': (context) => const OrganizerMainWrapper(),
          },
          onGenerateRoute: (settings) {
            // Handle staff invitations
            if (settings.name != null &&
                settings.name!.contains('staff-invite')) {
              final uri = Uri.parse(settings.name!);
              final assignmentId = uri.queryParameters['id'];
              if (assignmentId != null) {
                return MaterialPageRoute(
                  builder: (_) =>
                      StaffAcceptanceScreen(assignment: {'id': assignmentId}),
                );
              }
            }
            return null;
          },
        );
      },
    );
  }
}

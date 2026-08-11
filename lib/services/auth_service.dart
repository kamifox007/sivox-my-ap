import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final supabase = Supabase.instance.client;


  /// Get current user data.
  User? get currentUser => supabase.auth.currentUser;

  /// Stream of Auth changes.
  Stream<AuthState> get authStateChanges => supabase.auth.onAuthStateChange;

  /// Signs in using Google OAuth.
  Future<AuthResponse> signInWithGoogle() async {
    try {
      // Note: On Android, you must provide your web client ID from Google Cloud Console.
      const webClientId = '1019204925261-6a2f1o20f3bggg4li7dihnff6lg8daeb.apps.googleusercontent.com';
      
      final GoogleSignIn googleSignIn = GoogleSignIn(
        serverClientId: webClientId,
      );
      
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) throw 'Login cancelled by user';
      
      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      final accessToken = googleAuth.accessToken;

      if (idToken == null) throw 'No ID Token found.';

      return await supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );
    } catch (e) {
      rethrow;
    }
  }

  /// Normalizes Algerian phone numbers to the standard international format '+213XXXXXXXXX'
  static String normalizeAlgerianPhone(String phone) {
    // Remove all spaces, dashes, or parentheses
    String clean = phone.replaceAll(RegExp(r'[\s\-()]+'), '');
    
    // Convert 00213 to +213
    if (clean.startsWith('00213')) {
      clean = '+213${clean.substring(5)}';
    } else if (clean.startsWith('00')) {
      clean = '+${clean.substring(2)}';
    }
    
    if (clean.startsWith('+')) {
      if (clean.startsWith('+213')) {
        // Correct format, remove leading 0 after code if present (e.g. +21306... -> +2136...)
        if (clean.startsWith('+2130') && clean.length > 5) {
          clean = '+213${clean.substring(5)}';
        }
        return clean;
      }
      return clean; // Return as-is if international but not Algerian
    }
    
    // If it starts with 213 without '+'
    if (clean.startsWith('213') && clean.length >= 11) {
      return '+$clean';
    }
    
    // If it starts with '0' (e.g. 05, 06, 07)
    if (clean.startsWith('0') && clean.length == 10) {
      return '+213${clean.substring(1)}';
    }
    
    // If it is 9 digits and starts with 5, 6, 7 (e.g. 5xxxxxxx)
    if (clean.length == 9 && (clean.startsWith('5') || clean.startsWith('6') || clean.startsWith('7'))) {
      return '+213$clean';
    }
    
    return clean; // Fallback
  }

  /// Verifies phone number using Supabase native SMS.
  Future<void> verifyPhone({
    required String phone,
    required Function(String, int?) onCodeSent,
    required Function(String) onVerificationFailed,
  }) async {
    try {
      final normalizedPhone = normalizeAlgerianPhone(phone);
      await supabase.auth.signInWithOtp(
        phone: normalizedPhone,
        shouldCreateUser: true,
      );
      onCodeSent("OTP_SENT", null);
    } catch (e) {
      onVerificationFailed(e.toString());
    }
  }

  /// Verifies OTP and signs in to Supabase using native Phone Auth.
  Future<AuthResponse> verifyOtpAndSignInSupabase({
    required String smsCode,
    required String phone,
    String? fullName,
    String? password,
    String? countryCode,
    String? verificationId, // Kept for compatibility
  }) async {
    final normalizedPhone = normalizeAlgerianPhone(phone);
    final response = await supabase.auth.verifyOTP(
      phone: normalizedPhone,
      token: smsCode,
      type: OtpType.sms,
    );

    if (response.session != null && (fullName != null || password != null)) {
      // Update metadata and set credentials for new users
      final metaData = <String, dynamic>{
        'role': 'attendee',
        'phone': normalizedPhone,
        'country_code': countryCode ?? 'DZ',
      };
      metaData['full_name'] = fullName;   // null is fine; server ignores null entries
      final updates = UserAttributes(data: metaData);
      if (password != null && password.isNotEmpty) {
        updates.password = password;
        updates.email = '${normalizedPhone.replaceAll('+', '')}@temporary.app';
      }
      await supabase.auth.updateUser(updates);
    }
    
    return response;
  }

  /// Signs in with phone and password (using the temporary email mapping).
  Future<AuthResponse> signInWithPhoneAndPassword(String phone, String password) async {
    final normalizedPhone = normalizeAlgerianPhone(phone);
    final email = '${normalizedPhone.replaceAll('+', '')}@temporary.app';
    return await supabase.auth.signInWithPassword(email: email, password: password);
  }

  /// Initiates a phone number change by sending an OTP to the new phone.
  Future<void> changePhoneNumber(String newPhone) async {
    final normalizedPhone = normalizeAlgerianPhone(newPhone);
    await supabase.auth.updateUser(
      UserAttributes(phone: normalizedPhone),
    );
  }

  /// Verifies the OTP sent to the new phone number to complete the change.
  Future<bool> verifyPhoneChange(String newPhone, String token) async {
    try {
      final normalizedPhone = normalizeAlgerianPhone(newPhone);
      final response = await supabase.auth.verifyOTP(
        type: OtpType.phoneChange,
        token: token,
        phone: normalizedPhone,
      );
      return response.user != null;
    } catch (e) {
      return false;
    }
  }

  /// Signs in with email and password.
  Future<AuthResponse> signIn(String email, String password) async {
    return await supabase.auth.signInWithPassword(email: email, password: password);
  }

  /// Signs up with email, password, and metadata.
  Future<AuthResponse> signUp(String email, String password, String name, {String role = 'attendee', String? countryCode}) async {
    return await supabase.auth.signUp(
      email: email,
      password: password,
      data: {'full_name': name, 'role': 'attendee', 'country_code': countryCode ?? 'DZ'},
    );
  }

  /// Requests an OTP code to the provided email or phone.
  Future<bool> sendOtp(String contact, {bool isPhone = false, String? name, String? role}) async {
    try {
      if (isPhone) {
        final normalizedPhone = normalizeAlgerianPhone(contact);
        await supabase.auth.signInWithOtp(
          phone: normalizedPhone,
          data: {'full_name': name, 'role': 'attendee'}, // فرض attendee أمنياً
        );
      } else {
        await supabase.auth.signInWithOtp(
          email: contact,
          data: {'full_name': name, 'role': 'attendee'}, // فرض attendee أمنياً
        );
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Verifies the OTP code.
  Future<bool> verifyOtp(String contact, String token, {bool isPhone = false}) async {
    try {
      final normalizedContact = isPhone ? normalizeAlgerianPhone(contact) : contact;
      final response = await supabase.auth.verifyOTP(
        token: token,
        type: isPhone ? OtpType.sms : OtpType.magiclink,
        email: isPhone ? null : normalizedContact,
        phone: isPhone ? normalizedContact : null,
      );
      return response.session != null;
    } catch (e) {
      return false;
    }
  }

  /// Resends the confirmation email.
  Future<void> resendVerificationEmail(String email) async {
    await supabase.auth.resend(
      type: OtpType.signup,
      email: email,
    );
  }

  /// Sign out the current user.
  Future<void> signOut() async {
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn();
      if (await googleSignIn.isSignedIn()) {
        await googleSignIn.signOut();
      }
    } catch (_) {}
    await supabase.auth.signOut();
  }

  /// Delete the current user's account permanently (Google Play Compliant).
  Future<void> deleteAccount() async {
    try {
      await supabase.rpc('delete_user_account');
      await signOut();
    } catch (e) {
      rethrow;
    }
  }
}

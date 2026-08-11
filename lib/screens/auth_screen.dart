import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/services/translation_service.dart';
import 'package:my_app/services/auth_service.dart';
import 'package:my_app/screens/home_feed.dart';
import 'package:my_app/screens/organizer_dashboard.dart';
import 'package:my_app/screens/staff_hub_screen.dart';
import 'package:my_app/services/localization_service.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  bool _isLogin = true;
  bool _isLoading = false;
  bool _usePhone = false;
  bool _isCodeSent = false;
  bool _obscurePass = true;
  bool _obscureConfirmPass = true;
  bool _isForgotPassword = false;
  bool _isVerifiedForReset = false;
  bool _isEnteringPhoneAfterGoogle = false;
  String _verificationId = '';
  int _signupStep = 0; // 0: Name/Country, 1: Contact, 2: Security
  final String _selectedRole = 'attendee';
  CountryInfo _selectedCountry = LocalizationService.supportedCountries[0];
  // captcha disabled

  final _emailC = TextEditingController();
  final _passC = TextEditingController();
  final _nameC = TextEditingController();
  final _confirmPassC = TextEditingController();
  final _phoneC = TextEditingController();
  final _smsCodeC = TextEditingController();
  final _auth = AuthService();

  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeIn);
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _emailC.dispose();
    _passC.dispose();
    _nameC.dispose();
    super.dispose();
  }

  Future<void> _handleAuth() async {
    if (_isEnteringPhoneAfterGoogle) {
      if (!_isCodeSent) {
        if (_phoneC.text.isEmpty) {
          _showError('please_fill_all'.tr);
          return;
        }
        setState(() => _isLoading = true);
        try {
          String phone = _phoneC.text.trim();
          final prefix = _selectedCountry.phonePrefix;
          if (!phone.startsWith('+')) {
            if (phone.startsWith('0')) phone = phone.substring(1);
            phone = '$prefix$phone';
          }
          await _auth.verifyPhone(
            phone: phone,
            onCodeSent: (vId, token) {
              setState(() {
                _isCodeSent = true;
                _verificationId = vId;
                _isLoading = false;
              });
              _showSuccess('OTP_SENT_SUCCESS'.tr);
            },
            onVerificationFailed: (err) {
              _showError(err);
              setState(() => _isLoading = false);
            },
          );
        } catch (e) {
          _showError(e.toString());
          setState(() => _isLoading = false);
        }
      } else {
        if (_smsCodeC.text.isEmpty) {
          _showError('please_fill_all'.tr);
          return;
        }
        setState(() => _isLoading = true);
        try {
          String phone = _phoneC.text.trim();
          final prefix = _selectedCountry.phonePrefix;
          if (!phone.startsWith('+')) {
            if (phone.startsWith('0')) phone = phone.substring(1);
            phone = '$prefix$phone';
          }
          
          final res = await _auth.verifyOtpAndSignInSupabase(
            smsCode: _smsCodeC.text.trim(),
            phone: phone,
          );
          
          setState(() {
            _isEnteringPhoneAfterGoogle = false;
            _isLoading = false;
          });
          _redirectUser(res);
        } catch (e) {
          _showError(e.toString());
          setState(() => _isLoading = false);
        }
      }
      return;
    }

    if (_isForgotPassword) {
      if (_usePhone) {
        _handlePhoneAuth();
        return;
      }
      if (!_isVerifiedForReset) {
        if (!_isCodeSent) {
          if (_emailC.text.isEmpty) {
            _showError('please_fill_all'.tr);
            return;
          }
          setState(() => _isLoading = true);
          try {
            final success = await _auth.sendOtp(_emailC.text.trim(), isPhone: false);
            if (success) {
              setState(() {
                _isCodeSent = true;
                _isLoading = false;
              });
              _showSuccess('OTP_SENT_SUCCESS'.tr);
            } else {
              _showError('Failed to send OTP');
              setState(() => _isLoading = false);
            }
          } catch (e) {
            _showError(e.toString());
            setState(() => _isLoading = false);
          }
        } else {
          if (_smsCodeC.text.isEmpty) {
            _showError('please_fill_all'.tr);
            return;
          }
          setState(() => _isLoading = true);
          try {
            final success = await _auth.verifyOtp(_emailC.text.trim(), _smsCodeC.text.trim(), isPhone: false);
            if (success) {
              setState(() {
                _isVerifiedForReset = true;
                _isLoading = false;
              });
            } else {
              _showError('Invalid code');
              setState(() => _isLoading = false);
            }
          } catch (e) {
            _showError(e.toString());
            setState(() => _isLoading = false);
          }
        }
      } else {
        if (_passC.text.isEmpty || _confirmPassC.text.isEmpty) {
          _showError('please_fill_all'.tr);
          return;
        }
        if (_passC.text != _confirmPassC.text) {
          _showError('PASSWORDS_DO_NOT_MATCH'.tr);
          return;
        }
        setState(() => _isLoading = true);
        try {
          await Supabase.instance.client.auth.updateUser(UserAttributes(password: _passC.text.trim()));
          
          _showError('password_reset_success'.tr);
          setState(() {
            _isForgotPassword = false;
            _isVerifiedForReset = false;
            _isCodeSent = false;
            _isLogin = true;
          });
        } catch (e) {
          _showError(e.toString());
        } finally {
          if (mounted) setState(() => _isLoading = false);
        }
      }
      return;
    }

    if (!_isLogin && _usePhone) {
      _handlePhoneAuth();
      return;
    }

    if (_emailC.text.isEmpty ||
        _passC.text.isEmpty ||
        (!_isLogin && _nameC.text.isEmpty) ||
        (!_isLogin && _confirmPassC.text.isEmpty)) {
      _showError('please_fill_all'.tr);
      return;
    }

    if (!_isLogin && _passC.text != _confirmPassC.text) {
      _showError('PASSWORDS_DO_NOT_MATCH'.tr);
      return;
    }

    setState(() => _isLoading = true);
    try {
      if (_isLogin) {
        String identifier = _emailC.text.trim();
        bool isEmail = identifier.contains('@');
        
        if (isEmail) {
          final res = await _auth.signIn(identifier, _passC.text.trim());
          _redirectUser(res);
        } else {
          if (!identifier.startsWith('+')) {
            identifier = identifier.replaceFirst(RegExp(r'^0+'), '');
            identifier = '${_selectedCountry.phonePrefix}$identifier';
          }
          final res = await _auth.signInWithPhoneAndPassword(identifier, _passC.text.trim());
          _redirectUser(res);
        }
      } else {
        final res = await _auth.signUp(
          _emailC.text.trim(),
          _passC.text.trim(),
          _nameC.text.trim(),
          role: _selectedRole,
          countryCode: _selectedCountry.code,
        );
        if (res.session != null) {
          _redirectUser(res);
        } else {
          // Perfection Fix: Handle required email confirmation
          if (!mounted) return;
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF1A1A1A),
              title: Text('VERIFICATION_SENT'.tr, style: const TextStyle(color: Colors.white)),
              content: Text('CHECK_YOUR_EMAIL'.tr, style: const TextStyle(color: Colors.white70)),
              actions: [
                TextButton(
                  onPressed: () {
                    _auth.resendVerificationEmail(_emailC.text.trim());
                    Navigator.pop(ctx);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('RESENT'.tr)));
                    }
                  },
                  child: Text('RESENT'.tr, style: const TextStyle(color: AppTheme.primary)),
                ),
                TextButton(onPressed: () => Navigator.pop(ctx), child: Text('OK'.tr)),
              ],
            ),
          );
        }
      }
    } catch (e) {
      String msg = e.toString();
      if (msg.contains('user_already_exists') ||
          msg.contains('already registered')) {
        msg = 'user_already_exists'.tr;
      }
      _showError(msg);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handlePhoneAuth() async {
    if (_isForgotPassword) {
      if (!_isVerifiedForReset) {
        if (!_isCodeSent) {
          if (_phoneC.text.isEmpty) {
            _showError('please_fill_all'.tr);
            return;
          }
          setState(() => _isLoading = true);
          String phone = _phoneC.text.trim();
          final prefix = _selectedCountry.phonePrefix;
          if (!phone.startsWith('+')) {
            if (phone.startsWith('0')) phone = phone.substring(1);
            phone = '$prefix$phone';
          }
          try {
            final sent = await _auth.sendOtp(phone, isPhone: true);
            if (sent) {
              setState(() {
                _isCodeSent = true;
                _isLoading = false;
              });
              _showSuccess('OTP_SENT_SUCCESS'.tr);
            } else {
              _showError('OTP_SEND_FAILED'.tr);
              setState(() => _isLoading = false);
            }
          } catch (e) {
            _showError(e.toString());
            setState(() => _isLoading = false);
          }
        } else {
          if (_smsCodeC.text.isEmpty) {
            _showError('please_fill_all'.tr);
            return;
          }
          setState(() => _isLoading = true);
          try {
            final credential = fb_auth.PhoneAuthProvider.credential(
              verificationId: _verificationId,
              smsCode: _smsCodeC.text.trim(),
            );
            await fb_auth.FirebaseAuth.instance.signInWithCredential(credential);
            
            setState(() {
              _isVerifiedForReset = true;
              _isLoading = false;
            });
          } catch (e) {
            _showError(e.toString());
            setState(() => _isLoading = false);
          }
        }
      } else {
        if (_passC.text.isEmpty || _confirmPassC.text.isEmpty) {
          _showError('please_fill_all'.tr);
          return;
        }
        if (_passC.text != _confirmPassC.text) {
          _showError('PASSWORDS_DO_NOT_MATCH'.tr);
          return;
        }
        setState(() => _isLoading = true);
        try {
          _showError('password_reset_success'.tr);
          setState(() {
            _isForgotPassword = false;
            _isVerifiedForReset = false;
            _isCodeSent = false;
            _isLogin = true;
          });
        } catch (e) {
          _showError(e.toString());
        } finally {
          if (mounted) setState(() => _isLoading = false);
        }
      }
      return;
    }

    if (_isLogin) {
      if (_phoneC.text.isEmpty || _passC.text.isEmpty) {
        _showError('please_fill_all'.tr);
        return;
      }
      setState(() => _isLoading = true);
      String phone = _phoneC.text.trim();
      final prefix = _selectedCountry.phonePrefix;
      if (!phone.startsWith('+')) {
        if (phone.startsWith('0')) phone = phone.substring(1);
        phone = '$prefix$phone';
      }
      try {
        final res = await _auth.signInWithPhoneAndPassword(phone, _passC.text.trim());
        _redirectUser(res);
      } catch (e) {
        _showError(e.toString());
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
      return;
    }

    if (!_isCodeSent) {
      if (_phoneC.text.isEmpty || _passC.text.isEmpty || _confirmPassC.text.isEmpty) {
        _showError('please_fill_all'.tr);
        return;
      }
      if (_passC.text != _confirmPassC.text) {
        _showError('PASSWORDS_DO_NOT_MATCH'.tr);
        return;
      }
      setState(() => _isLoading = true);
      String phone = _phoneC.text.trim();
      final prefix = _selectedCountry.phonePrefix;
      if (!phone.startsWith('+')) {
        if (phone.startsWith('0')) phone = phone.substring(1);
        phone = '$prefix$phone';
      }
      try {
        await _auth.verifyPhone(
          phone: phone,
          onCodeSent: (vId, token) {
            setState(() {
              _isCodeSent = true;
              _verificationId = vId;
              _isLoading = false;
            });
            _showSuccess('OTP_SENT_SUCCESS'.tr);
          },
          onVerificationFailed: (err) {
            _showError(err);
            setState(() => _isLoading = false);
          },
        );
      } catch (e) {
        _showError(e.toString());
        setState(() => _isLoading = false);
      }
    } else {
      _handleVerifySmsCode();
    }
  }

  Future<void> _handleVerifySmsCode() async {
    if (_smsCodeC.text.isEmpty) {
      _showError('please_fill_all'.tr);
      return;
    }
    setState(() => _isLoading = true);
      String phone = _phoneC.text.trim();
      final prefix = _selectedCountry.phonePrefix;
      if (!phone.startsWith('+')) {
        if (phone.startsWith('0')) phone = phone.substring(1);
        phone = '$prefix$phone';
      }
      try {
        final res = await _auth.verifyOtpAndSignInSupabase(
          verificationId: _verificationId,
          smsCode: _smsCodeC.text.trim(),
          phone: phone,
        fullName: _nameC.text.trim(),
        password: _isLogin ? null : _passC.text.trim(),
        countryCode: _selectedCountry.code,
      );
      _redirectUser(res);
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isLoading = true);
    try {
      final res = await _auth.signInWithGoogle();
      _redirectUser(res);
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _redirectUser(AuthResponse res) {
    if (res.session == null || !mounted) return;

    final user = res.session!.user;
    final phone = user.userMetadata?['phone'] ?? user.phone ?? '';

    if (phone.isEmpty) {
      setState(() {
        _isEnteringPhoneAfterGoogle = true;
        _isLoading = false;
      });
      return;
    }

    final role = (user.userMetadata?['role']?.toString() ?? 'attendee').toLowerCase();

    Widget nextScreen;
    if (role == 'staff') {
      nextScreen = const StaffHubScreen();
    } else if (role == 'organizer' ||
        role == 'manager' ||
        role == 'owner' ||
        role == 'admin') {
      nextScreen = const OrganizerDashboardScreen();
    } else {
      nextScreen = const HomeFeedScreen();
    }

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => nextScreen),
      (r) => false,
    );
  }

  void _showError(String m) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent),
            const SizedBox(width: 8),
            Text('error'.tr, style: AppTheme.headlineStyle.copyWith(color: Colors.redAccent, fontSize: 18)),
          ],
        ),
        content: Text(m, style: AppTheme.bodyStyle),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('OK'.tr, style: const TextStyle(color: AppTheme.primary)),
          ),
        ],
      ),
    );
  }

  void _showSuccess(String m) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.greenAccent),
            const SizedBox(width: 8),
            Text('success'.tr, style: AppTheme.headlineStyle.copyWith(color: Colors.greenAccent, fontSize: 18)),
          ],
        ),
        content: Text(m, style: AppTheme.bodyStyle),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('OK'.tr, style: const TextStyle(color: AppTheme.primary)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [_buildAnimatedBackground(), _buildAuthContent()]),
    );
  }

  Widget _buildAnimatedBackground() {
    return Stack(
      children: [
        // Background Image
        Positioned.fill(
          child: Image.asset(
            'assets/images/app_intro_bg.png',
            fit: BoxFit.cover,
          ),
        ),
        // Gradient overlay instead of heavy blur to let the image shine
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.6),
                  Colors.black.withValues(alpha: 0.95),
                ],
                stops: const [0.0, 0.4, 1.0],
              ),
            ),
          ),
        ),
        Positioned(
          top: -100,
          right: -100,
          child: _auraCircle(AppTheme.primary.withValues(alpha: 0.25), 350),
        ),
        Positioned(
          bottom: -50,
          left: -50,
          child: _auraCircle(AppTheme.secondary.withValues(alpha: 0.2), 300),
        ),
      ],
    );
  }

  Widget _auraCircle(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [BoxShadow(color: color, blurRadius: 100, spreadRadius: 50)],
      ),
    );
  }

  Widget _buildAuthContent() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: FadeTransition(
          opacity: _fadeAnim,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(),
              _buildFloatingTicket(),
              const SizedBox(height: 16),
              _buildForm(),
              const SizedBox(height: 24),
              _toggleModeBtn(),
              const SizedBox(height: 40),
              _buildBottomActionRow(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.nightlife_rounded,
            size: 40,
            color: AppTheme.primary,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          _isLogin ? 'welcome_back'.tr : 'create_account'.tr,
          style: AppTheme.headlineStyle.copyWith(fontSize: 28),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          _isLogin ? 'login_subtitle'.tr : 'signup_subtitle'.tr,
          textAlign: TextAlign.center,
          style: AppTheme.bodyStyle.copyWith(
            color: Colors.white38,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  Widget _buildFloatingTicket() {
    return Container(
      margin: const EdgeInsets.only(top: 16, bottom: 8),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppTheme.primary.withValues(alpha: 0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withValues(alpha: 0.15),
            blurRadius: 25,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.star_rounded, color: AppTheme.primary, size: 28),
                  const SizedBox(width: 12),
                  Text(
                    'SIVOX EXCLUSIVE'.tr,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 3,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppTheme.primary, AppTheme.secondary],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'VIP',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _ticketDetail(Icons.diamond_rounded, 'MEMBER'.tr, 'PREMIUM'.tr),
              Container(width: 1, height: 40, color: Colors.white24),
              _ticketDetail(Icons.local_activity_rounded, 'ACCESS'.tr, 'ALL AREAS'.tr),
            ],
          ),
        ],
      ),
    );
  }

  Widget _ticketDetail(IconData icon, String label, String value) {
    return Column(
      children: [
        Icon(icon, color: Colors.white38, size: 16),
        const SizedBox(height: 8),
        Text(label.toUpperCase(), style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(value.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1)),
      ],
    );
  }

  Widget _buildForm() {
    return Container(
      decoration: AppTheme.glassDecoration(opacity: 0.15),
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          if (_isEnteringPhoneAfterGoogle) ...[
            Text(
              'LINK_PHONE_NUMBER'.tr,
              style: AppTheme.headlineStyle.copyWith(fontSize: 18),
            ),
            const SizedBox(height: 12),
            Text(
              'PHONE_REQUIRED_DESC'.tr,
              style: AppTheme.bodyStyle.copyWith(color: Colors.white38, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (!_isCodeSent) ...[
              _phoneInput(_phoneC),
            ] else
              _input('ENTER_SMS_CODE'.tr, Icons.sms_rounded, _smsCodeC),
          ] else if (_isForgotPassword) ...[
            if (!_isVerifiedForReset) ...[
              if (!_isCodeSent) ...[
                if (_usePhone)
                  _input('phone_number'.tr, Icons.phone_android_rounded, _phoneC)
                else
                  _input('email'.tr, Icons.alternate_email_rounded, _emailC),
              ] else
                _input('ENTER_SMS_CODE'.tr, Icons.sms_rounded, _smsCodeC),
            ] else ...[
              _input(
                'new_password'.tr,
                Icons.lock_outline_rounded,
                _passC,
                obscure: _obscurePass,
                suffix: IconButton(
                  icon: Icon(_obscurePass ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: Colors.white38),
                  onPressed: () => setState(() => _obscurePass = !_obscurePass),
                ),
              ),
              _input(
                'CONFIRM_PASSWORD'.tr,
                Icons.lock_outline_rounded,
                _confirmPassC,
                obscure: _obscureConfirmPass,
                suffix: IconButton(
                  icon: Icon(_obscureConfirmPass ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: Colors.white38),
                  onPressed: () => setState(() => _obscureConfirmPass = !_obscureConfirmPass),
                ),
              ),
            ],
          ] else ...[
            if (!_isLogin) ...[
              _buildSignupSteps(),
            ] else ...[
              _input('email_or_phone'.tr, Icons.account_circle_rounded, _emailC),
              _input(
                'password'.tr,
                Icons.lock_outline_rounded,
                _passC,
                obscure: _obscurePass,
                suffix: IconButton(
                  icon: Icon(_obscurePass ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: Colors.white38),
                  onPressed: () => setState(() => _obscurePass = !_obscurePass),
                ),
              ),
            ],
          ],
          if (_isLogin && !_isForgotPassword) ...[
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => setState(() {
                  _isForgotPassword = true;
                }),
                child: Text(
                  'forgot_password'.tr,
                  style: const TextStyle(color: AppTheme.secondary, fontSize: 12),
                ),
              ),
            ),
          ],
          // if (!_isLogin && !_isForgotPassword && !_isEnteringPhoneAfterGoogle) ...[
          //   TurnstileCaptcha(
          //     onVerified: (token) {
          //       _captchaToken = token;
          //     },
          //   ),
          // ],
          const SizedBox(height: 12),
          _submitBtn(),
          if (!_isEnteringPhoneAfterGoogle && (_isLogin || (!_isLogin && _signupStep == 0))) ...[
            const SizedBox(height: 24),
            _buildDivider(),
            const SizedBox(height: 24),
            _googleBtn(),
          ],
          const SizedBox(height: 12),
          if (!_isLogin) _togglePhoneModeBtn(),
        ],
      ),
    );
  }

  Widget _togglePhoneModeBtn() {
    return TextButton(
      onPressed: () => setState(() {
        _usePhone = !_usePhone;
        _isCodeSent = false;
        if (_usePhone) {
          _phoneC.clear();
        }
      }),
      child: Text(
        (_usePhone ? 'DIRECT_EMAIL_LOGIN'.tr : 'USE_PHONE'.tr).toUpperCase(),
        style: const TextStyle(color: AppTheme.secondary, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _countrySelector() {
    return GestureDetector(
      onTap: _showCountryPicker,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Text(_selectedCountry.flag, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _selectedCountry.name,
                style: AppTheme.bodyStyle,
              ),
            ),
            Text(
              _selectedCountry.phonePrefix,
              style: AppTheme.bodyStyle.copyWith(color: Colors.white38),
            ),
            const Icon(Icons.arrow_drop_down, color: Colors.white38),
          ],
        ),
      ),
    );
  }

  void _showCountryPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: BoxDecoration(
          color: AppTheme.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'SELECT_COUNTRY'.tr,
              style: AppTheme.headlineStyle.copyWith(fontSize: 20),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.separated(
                itemCount: LocalizationService.supportedCountries.length,
                separatorBuilder: (context, index) => const Divider(color: Colors.white10, height: 1),
                itemBuilder: (ctx, index) {
                  final country = LocalizationService.supportedCountries[index];
                  return ListTile(
                    leading: Text(country.flag, style: const TextStyle(fontSize: 24)),
                    title: Text(country.name, style: AppTheme.bodyStyle),
                    trailing: Text(
                      country.phonePrefix,
                      style: AppTheme.bodyStyle.copyWith(color: Colors.white38),
                    ),
                    onTap: () {
                      setState(() {
                        _selectedCountry = country;
                      });
                      Navigator.pop(ctx);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _phoneInput(TextEditingController c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: _showCountryPicker,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  border: Border(
                    right: BorderSide(
                      color: Colors.white.withValues(alpha: 0.05),
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_selectedCountry.flag, style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 8),
                    Text(
                      _selectedCountry.phonePrefix,
                      style: AppTheme.bodyStyle.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down, color: Colors.white38, size: 20),
                  ],
                ),
              ),
            ),
            Expanded(
              child: TextField(
                controller: c,
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: AppTheme.bodyStyle,
                textAlign: TextAlign.left, // Phone numbers always left-aligned
                decoration: InputDecoration(
                  hintText: 'phone_number'.tr,
                  hintStyle: AppTheme.bodyStyle.copyWith(color: Colors.white24),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 18,
                    horizontal: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _input(
    String hint,
    IconData icon,
    TextEditingController c, {
    bool obscure = false,
    Widget? suffix,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: TextField(
          controller: c,
          obscureText: obscure,
          style: AppTheme.bodyStyle,
          textAlign: TranslationService.isRtl
              ? TextAlign.right
              : TextAlign.left,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: AppTheme.bodyStyle.copyWith(color: Colors.white24),
            prefixIcon: Icon(
              icon,
              color: AppTheme.primary.withValues(alpha: 0.5),
              size: 20,
            ),
            suffixIcon: suffix,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              vertical: 18,
              horizontal: 16,
            ),
          ),
        ),
      ),
    );
  }

  Widget _submitBtn() {
    bool isLastStep = _isLogin || _isForgotPassword || _isEnteringPhoneAfterGoogle || _signupStep == 2 || (_usePhone && _isCodeSent);
    
    return Column(
      children: [
        if (!_isLogin && !_isForgotPassword && !_isEnteringPhoneAfterGoogle && _signupStep > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => setState(() {
                  // إذا كنا في Step 2 مع هاتف وتم إرسال OTP، نرجع لعرض حقول كلمة المرور
                  if (_signupStep == 2 && _usePhone && _isCodeSent) {
                    _isCodeSent = false;
                  } else {
                    _signupStep--;
                  }
                }),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: Text('back'.tr.toUpperCase(), style: const TextStyle(color: Colors.white54)),
              ),
            ),
          ),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isLoading ? null : () {
              if (!_isLogin && !_isForgotPassword && !_isEnteringPhoneAfterGoogle && _signupStep < 2) {
                // Validate steps before proceeding
                if (_signupStep == 0 && _nameC.text.isEmpty) {
                  _showError('please_fill_all'.tr);
                  return;
                }
                if (_signupStep == 1) {
                  if (_usePhone && _phoneC.text.isEmpty) {
                    _showError('please_fill_all'.tr);
                    return;
                  }
                  if (!_usePhone && _emailC.text.isEmpty) {
                    _showError('please_fill_all'.tr);
                    return;
                  }
                }
                setState(() => _signupStep++);
              } else if (!_isLogin && !_isForgotPassword && _signupStep == 2 && _usePhone && !_isCodeSent) {
                // Step 2 مع هاتف: تحقق من كلمة المرور ثم أرسل OTP
                if (_passC.text.isEmpty || _confirmPassC.text.isEmpty) {
                  _showError('please_fill_all'.tr);
                  return;
                }
                if (_passC.text != _confirmPassC.text) {
                  _showError('PASSWORDS_DO_NOT_MATCH'.tr);
                  return;
                }
                _handlePhoneAuth(); // سيرسل OTP ويضبط _isCodeSent = true
              } else {
                _handleAuth();
              }
            },
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      color: Colors.black,
                      strokeWidth: 2,
                    ),
                  )
                : Text((isLastStep ? (_isLogin ? 'login' : 'signup') : 'NEXT').tr.toUpperCase()),
          ),
        ),
      ],
    );
  }



  Widget _buildSignupSteps() {
    return Column(
      children: [
        _buildStepIndicator(),
        const SizedBox(height: 24),
        if (_signupStep == 0) ...[
          _input('full_name'.tr, Icons.person_outline_rounded, _nameC),
          const SizedBox(height: 8),
          _countrySelector(),
        ] else if (_signupStep == 1) ...[
          if (_usePhone) ...[
            if (!_isCodeSent)
              _phoneInput(_phoneC)
            else
              _input('ENTER_SMS_CODE'.tr, Icons.sms_rounded, _smsCodeC),
          ] else ...[
            _input('email'.tr, Icons.alternate_email_rounded, _emailC),
          ],
        ] else if (_signupStep == 2) ...[
          // إذا كان التسجيل برقم الهاتف والرمز أُرسل، نعرض حقل رمز التحقق
          if (_usePhone && _isCodeSent) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                'ENTER_SMS_CODE'.tr,
                style: AppTheme.bodyStyle.copyWith(color: Colors.white54, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
            _input('ENTER_SMS_CODE'.tr, Icons.sms_rounded, _smsCodeC),
          ] else ...[
            _input(
              'password'.tr,
              Icons.lock_outline_rounded,
              _passC,
              obscure: _obscurePass,
              suffix: IconButton(
                icon: Icon(_obscurePass ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: Colors.white38),
                onPressed: () => setState(() => _obscurePass = !_obscurePass),
              ),
            ),
            _input(
              'CONFIRM_PASSWORD'.tr,
              Icons.lock_outline_rounded,
              _confirmPassC,
              obscure: _obscureConfirmPass,
              suffix: IconButton(
                icon: Icon(_obscureConfirmPass ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: Colors.white38),
                onPressed: () => setState(() => _obscureConfirmPass = !_obscureConfirmPass),
              ),
            ),
          ],
        ],
      ],
    );
  }


  Widget _buildStepIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (index) {
        bool isActive = index <= _signupStep;
        return Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isActive ? AppTheme.primary : Colors.white.withValues(alpha: 0.05),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isActive ? AppTheme.primary : Colors.white10,
                  width: 2,
                ),
              ),
              child: Center(
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: isActive ? Colors.black : Colors.white38,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            if (index < 2)
              Container(
                width: 40,
                height: 2,
                color: index < _signupStep ? AppTheme.primary : Colors.white10,
              ),
          ],
        );
      }),
    );
  }

  Widget _buildDivider() {
    return Row(
      children: [
        const Expanded(child: Divider(color: Colors.white10)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            "OR".tr,
            style: AppTheme.labelStyle.copyWith(color: Colors.white12),
          ),
        ),
        const Expanded(child: Divider(color: Colors.white10)),
      ],
    );
  }

  Widget _googleBtn() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: OutlinedButton.icon(
        onPressed: _isLoading ? null : _handleGoogleSignIn,
        icon: const FaIcon(
          FontAwesomeIcons.google,
          size: 18,
          color: Colors.white,
        ),
        label: Text('continue_with_google'.tr),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          side: const BorderSide(color: Colors.white10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          foregroundColor: Colors.white,
          textStyle: AppTheme.bodyStyle.copyWith(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _toggleModeBtn() {
    return TextButton(
      onPressed: () => setState(() {
        _isLogin = !_isLogin;
        _signupStep = 0;
      }),
      child: RichText(
        text: TextSpan(
          text: _isLogin ? "dont_have_account".tr : "already_have_account".tr,
          style: AppTheme.bodyStyle.copyWith(
            color: Colors.white38,
            fontSize: 13,
          ),
          children: [
            TextSpan(
              text: "  ${(_isLogin ? 'signup' : 'login').tr}",
              style: AppTheme.bodyStyle.copyWith(
                color: AppTheme.primary,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomActionRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _smallBottomBtn(Icons.language_rounded, 'language'.tr, _showLanguagePicker),
        _smallBottomBtn(Icons.help_outline_rounded, 'assistance'.tr, _showHelpDialog),
        _smallBottomBtn(Icons.info_outline_rounded, 'about_app'.tr, _showAboutDialog),
      ],
    );
  }

  Widget _smallBottomBtn(IconData icon, String label, VoidCallback onTap) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, color: Colors.white38, size: 14),
      label: Text(
        label,
        style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold),
      ),
      style: TextButton.styleFrom(padding: EdgeInsets.zero),
    );
  }

  void _showLanguagePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: AppTheme.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            _langItem(ctx, 'العربية', Language.ar),
            const Divider(color: Colors.white10, height: 1),
            _langItem(ctx, 'English', Language.en),
            const Divider(color: Colors.white10, height: 1),
            _langItem(ctx, 'Français', Language.fr),
            const Divider(color: Colors.white10, height: 1),
            _langItem(ctx, 'Español', Language.es),
            const Divider(color: Colors.white10, height: 1),
            _langItem(ctx, 'Deutsch', Language.de),
            const Divider(color: Colors.white10, height: 1),
            _langItem(ctx, 'Türkçe', Language.tr),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  Widget _langItem(BuildContext ctx, String label, Language lang) {
    return ListTile(
      title: Center(
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      onTap: () {
        TranslationService.setLanguage(lang);
        Navigator.pop(ctx);
        if (mounted) {
          setState(() {});
        }
      },
    );
  }

  void _showCreateTicketDialog() {
    final contactC = TextEditingController();
    final messageC = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          decoration: BoxDecoration(
            color: AppTheme.background,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            border: Border.all(color: Colors.white10),
          ),
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 24),
              Text('SEND_MESSAGE'.tr, style: AppTheme.headlineStyle.copyWith(fontSize: 20)),
              const SizedBox(height: 24),
              _input('CONTACT_INFO_HINT'.tr, Icons.alternate_email_rounded, contactC),
              const SizedBox(height: 16),
              _input('MESSAGE_HINT'.tr, Icons.message_rounded, messageC),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    if (contactC.text.isEmpty || messageC.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('PLEASE_FILL_ALL_FIELDS'.tr)),
                      );
                      return;
                    }
                    
                    try {
                      await Supabase.instance.client.from('support_tickets').insert({
                        'contact': contactC.text.trim(),
                        'message': messageC.text.trim(),
                        'created_at': DateTime.now().toIso8601String(),
                      });
                      
                      if (!context.mounted) return;
                      
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('تم إرسال رسالتك بنجاح!'), backgroundColor: AppTheme.secondary),
                      );
                      Navigator.pop(context);
                      Navigator.pop(context);
                    } catch (e) {
                      if (!context.mounted) return;
                      
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('فشل الإرسال: $e'), backgroundColor: Colors.redAccent),
                      );
                    }
                  },
                  child: Text('إرسال'.toUpperCase()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }



  void _showHelpDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: AppTheme.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          border: Border.all(color: Colors.white10),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 24),
            Text('HOW_CAN_WE_HELP'.tr, style: AppTheme.headlineStyle.copyWith(fontSize: 20)),
            const SizedBox(height: 16),
            _helpTile('DIDNT_RECEIVE_CODE'.tr, 'DIDNT_RECEIVE_CODE_DESC'.tr),
            _helpTile('CANT_LOGIN'.tr, 'CANT_LOGIN_DESC'.tr),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _showCreateTicketDialog,
                icon: const Icon(Icons.support_agent_rounded),
                label: Text('CONTACT_SUPPORT'.tr),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.secondary,
                  foregroundColor: Colors.black,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _helpTile(String title, String desc) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTheme.bodyStyle.copyWith(fontWeight: FontWeight.bold, color: AppTheme.primary)),
          const SizedBox(height: 4),
          Text(desc, style: AppTheme.bodyStyle.copyWith(color: Colors.white38, fontSize: 12)),
        ],
      ),
    );
  }

  void _showAboutDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: AppTheme.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          border: Border.all(color: Colors.white10),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 24),
            const Icon(Icons.nightlife_rounded, size: 60, color: AppTheme.primary),
            const SizedBox(height: 16),
            Text('APP_NAME_LABEL'.tr, style: AppTheme.headlineStyle.copyWith(fontSize: 24)),
            const SizedBox(height: 8),
            Text('APP_VERSION'.tr, style: AppTheme.bodyStyle.copyWith(color: Colors.white24, fontSize: 12)),
            const SizedBox(height: 16),
            Text(
              'APP_DESC'.tr,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, height: 1.5),
            ),
            const SizedBox(height: 32),
            Text(
              'ALL_RIGHTS_RESERVED'.tr,
              style: const TextStyle(color: Colors.white24, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

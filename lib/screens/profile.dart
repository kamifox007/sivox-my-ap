import 'package:flutter/material.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:my_app/screens/edit_profile_screen.dart';
import 'package:my_app/services/performance_service.dart';
import 'package:my_app/screens/support_screen.dart';
import 'package:my_app/screens/auth_screen.dart';
import 'package:my_app/screens/account_selector.dart';
// ignore: unused_import
import 'package:my_app/services/translation_service.dart';
import 'package:my_app/screens/organizer_main_wrapper.dart';
import 'package:my_app/screens/favorites_screen.dart';
import 'package:my_app/services/booking_service.dart';
import 'package:my_app/screens/vault_screen.dart';
import 'package:my_app/services/auth_service.dart';
import 'package:my_app/screens/tickets_list_screen.dart';


class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _notifsEnabled = true;
  int _bookingCount = 0;
  int _followingCount = 0;
  bool _showAccountSettings = false;

  Future<void> _checkStats() async {
    final bookings = await BookingService().getUserBookings();
    final followed = await Supabase.instance.client
        .from('follows')
        .select()
        .eq('user_id', Supabase.instance.client.auth.currentUser!.id);

    if (mounted) {
      setState(() {
        _bookingCount = bookings.length;
        _followingCount = (followed as List).length;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _checkStats();
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final name = user?.userMetadata?['full_name'] ?? 'User';
    final email = user?.email ?? 'anonymous@Sivox.app';
    final phone = user?.userMetadata?['phone_number'] ?? '';
    final role = (user?.userMetadata?['role']?.toString() ?? 'attendee')
        .toLowerCase();

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          if (PerformanceService.useBlur)
            Positioned(
              top: -50,
              right: -50,
              child: _glow(AppTheme.primary.withValues(alpha: 0.08)),
            ),
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              _buildHeader(name, email, phone, user, role),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 20,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),
                      
                      // 1. QUICK ACTIONS GRID
                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 2,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        childAspectRatio: 1.2,
                        children: [
                            _buildGridCard(Icons.confirmation_num_outlined, 'passes'.tr, '($_bookingCount)', AppTheme.primary, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TicketsListScreen()))),
                            _buildGridCard(Icons.favorite_border_rounded, 'favorites'.tr, '', Colors.pinkAccent, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FavoritesScreen()))),
                            _buildGridCard(Icons.lock_clock_rounded, 'THE_VAULT'.tr, '', AppTheme.secondary, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VaultScreen()))),
                            _buildGridCard(Icons.help_outline, 'assistance'.tr, '', Colors.blueAccent, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SupportScreen()))),
                        ],
                      ),
                      const SizedBox(height: 32),

                      // 2. PRO HUB (Large Banner)
                      _buildProHubButton(),
                      const SizedBox(height: 32),

                      // 3. SETTINGS & ACCOUNT
                      Text('SETTINGS & ACCOUNT'.tr.toUpperCase(), style: AppTheme.labelStyle.copyWith(color: AppTheme.primary, letterSpacing: 2)),
                      const SizedBox(height: 16),
                      Container(
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.02), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white.withValues(alpha: 0.05))),
                        child: Column(
                            children: [
                                _buildSettingsTile(Icons.manage_accounts_rounded, 'ACCOUNT_SETTINGS'.tr, () => setState(() => _showAccountSettings = !_showAccountSettings)),
                                if (_showAccountSettings) ...[
                                    _buildSettingsTile(Icons.lock_outline_rounded, 'change_password'.tr, _showChangePasswordDialog, isSub: true),
                                    _buildSettingsTile(Icons.email_outlined, 'RECOVERY_EMAIL'.tr, _showAddEmailDialog, isSub: true),
                                    _buildSettingsTile(Icons.delete_forever_outlined, 'DELETE_ACCOUNT'.tr, _showDeleteAccountFlow, isSub: true, color: Colors.redAccent),
                                ],
                                const Divider(color: Colors.white10, height: 1),
                                _buildSwitchTile(Icons.notifications_none, 'push_notifications'.tr, _notifsEnabled, (v) => setState(() => _notifsEnabled = v)),
                                const Divider(color: Colors.white10, height: 1),
                                _buildSettingsTile(Icons.language_outlined, 'change_language'.tr, _showLanguagePicker),
                                const Divider(color: Colors.white10, height: 1),
                                _buildSettingsTile(Icons.policy_outlined, 'privacy_policy'.tr, () {
                                    showDialog(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        backgroundColor: const Color(0xFF1A1A1A),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.2))),
                                        title: Text('privacy_policy'.tr, style: const TextStyle(color: Colors.white)),
                                        content: const Text('This is the AfterDark privacy policy.\nYour data is securely stored and never shared with third parties without your explicit consent.', style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5)),
                                        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold)))],
                                      ),
                                    );
                                }),
                            ],
                        ),
                      ),
                      
                      const SizedBox(height: 40),
                      _buildLogoutBtn(),
                      const SizedBox(height: 12),
                      Center(child: Text('VERSION 1.0.6 - Sivox PRODUCTION', style: TextStyle(color: Colors.white.withValues(alpha: 0.05), fontSize: 10, letterSpacing: 2))),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGridCard(IconData icon, String title, String subtitle, Color color, VoidCallback onTap) {
      return GestureDetector(
          onTap: onTap,
          child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white.withValues(alpha: 0.05))),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                      Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle), child: Icon(icon, color: color, size: 24)),
                      const SizedBox(height: 12),
                      Text(title.toUpperCase(), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1)),
                      if (subtitle.isNotEmpty)
                          Padding(padding: const EdgeInsets.only(top: 4), child: Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 10))),
                  ]
              )
          )
      );
  }

  Widget _buildSettingsTile(IconData icon, String label, VoidCallback onTap, {bool isSub = false, Color? color}) {
      return ListTile(
          onTap: onTap,
          contentPadding: EdgeInsets.only(left: isSub ? 40 : 20, right: 20, top: 4, bottom: 4),
          leading: Icon(icon, color: color ?? Colors.white70, size: 20),
          title: Text(label, style: TextStyle(color: color ?? Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
          trailing: const Icon(Icons.chevron_right, color: Colors.white10, size: 16),
      );
  }

  Widget _buildHeader(
    String name,
    String email,
    String phone,
    User? user,
    String role,
  ) {
    return SliverAppBar(
      expandedHeight: 340,
      backgroundColor: Colors.transparent,
      pinned: true,
      centerTitle: false,
      leading: IconButton(
        icon: const Icon(
          Icons.arrow_back_ios_new,
          color: Colors.white,
          size: 20,
        ),
        onPressed: () => Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF0F0F0F), AppTheme.background],
                ),
              ),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 60),
                GestureDetector(
                  onTap: () =>
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const EditProfileScreen(),
                        ),
                      ).then((val) {
                        if (val == true) {
                          setState(() {});
                        }
                      }),
                  child: _buildAvatar(user),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      name.toUpperCase(),
                      style: AppTheme.headlineStyle.copyWith(
                        fontSize: 22,
                        letterSpacing: 2,
                      ),
                    ),
                    if (role != 'attendee')
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Icon(
                          Icons.verified_rounded,
                          color: AppTheme.primary,
                          size: 20,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  email,
                  style: const TextStyle(
                    color: Colors.white24,
                    fontSize: 13,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  phone.isNotEmpty
                      ? phone
                      : TranslationService.translate('set_phone_number'),
                  style: TextStyle(
                    color: phone.isNotEmpty ? AppTheme.primary : Colors.white10,
                    fontSize: 11,
                    fontWeight: phone.isNotEmpty
                        ? FontWeight.bold
                        : FontWeight.normal,
                    letterSpacing: 1,
                  ),
                ),
                if (user != null && user.emailConfirmedAt == null) ...[
                  const SizedBox(height: 12),
                  _buildVerificationBanner(user),
                ],
                const SizedBox(height: 16),
                const SizedBox(height: 16),
                _buildRatingAndStatsBar(3.0 + (_bookingCount * 0.1), role),
                const SizedBox(height: 16),

              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVerificationBanner(User? user) {
    if (user == null || user.emailConfirmedAt != null) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () async {
        try {
          // Show loading
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            ),
          );
          
          await AuthService().resendVerificationEmail(user.email!);
          
          if (!mounted) return;
          Navigator.pop(context); // Close loading
          
          _showVerifyEmailDialog(user.email!);
          
        } catch (e) {
          if (mounted) {
            Navigator.pop(context); // Close loading
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(e.toString()), backgroundColor: Colors.redAccent),
            );
          }
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.orangeAccent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 14),
            const SizedBox(width: 8),
            Text(
              'ACCOUNT_NOT_VERIFIED'.tr,
              style: const TextStyle(color: Colors.orangeAccent, fontSize: 10, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            Text(
              'VERIFY_NOW'.tr.toUpperCase(),
              style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900, decoration: TextDecoration.underline),
            ),
          ],
        ),
      ),
    );
  }

  void _showVerifyEmailDialog(String email) {
    final codeC = TextEditingController();
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
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
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'VERIFY_EMAIL'.tr,
              style: AppTheme.headlineStyle.copyWith(fontSize: 20),
            ),
            const SizedBox(height: 8),
            Text(
              '${'CODE_SENT_TO'.tr} $email',
              style: AppTheme.bodyStyle.copyWith(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 24),
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: TextField(
                controller: codeC,
                keyboardType: TextInputType.number,
                style: AppTheme.bodyStyle,
                decoration: InputDecoration(
                  hintText: 'ENTER_OTP_CODE'.tr,
                  hintStyle: AppTheme.bodyStyle.copyWith(color: Colors.white24),
                  prefixIcon: const Icon(Icons.password_rounded, color: Colors.white38, size: 20),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                ),
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  if (codeC.text.isEmpty) return;
                  try {
                    showDialog(
                      context: ctx,
                      barrierDismissible: false,
                      builder: (context) => const Center(
                        child: CircularProgressIndicator(color: AppTheme.primary),
                      ),
                    );
                    
                    await Supabase.instance.client.auth.verifyOTP(
                      email: email,
                      token: codeC.text.trim(),
                      type: OtpType.signup,
                    );
                    
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx); // close loader
                    Navigator.pop(ctx); // close bottom sheet
                    
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text('EMAIL_VERIFIED_SUCCESS'.tr), backgroundColor: AppTheme.secondary),
                    );
                    if (mounted) setState(() {});
                  } catch (e) {
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx); // close loader
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text(e.toString()), backgroundColor: Colors.redAccent),
                    );
                  }
                },
                child: Text('VERIFY'.tr.toUpperCase()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(User? user) {
    final avatarUrl = user?.userMetadata?['avatar_url'];
    final hasImg = avatarUrl != null && avatarUrl.toString().isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: AppTheme.primary.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: CircleAvatar(
        radius: 60,
        backgroundColor: Colors.white.withValues(alpha: 0.05),
        backgroundImage: hasImg ? NetworkImage(avatarUrl.toString()) : null,
        child: !hasImg
            ? const Icon(Icons.person, size: 40, color: Colors.white10)
            : null,
      ),
    );
  }

  Widget _buildRatingAndStatsBar(double rating, String role) {
    final bool isAttendee = role == 'attendee';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.stars_rounded, color: AppTheme.secondary, size: 16),
          const SizedBox(width: 8),
          Text(
            rating.toStringAsFixed(1),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14),
          ),
          const SizedBox(width: 16),
          Container(width: 1, height: 16, color: Colors.white10),
          const SizedBox(width: 16),
          Text(
            '$_followingCount',
            style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w900, fontSize: 14),
          ),
          const SizedBox(width: 6),
          Text(
            (isAttendee ? 'following' : 'followers').tr.toUpperCase(),
            style: const TextStyle(color: Colors.white38, fontWeight: FontWeight.w800, fontSize: 10, letterSpacing: 0.5),
          ),
        ],
      ),
    );
  }

  // NOTE: This joined staff logic is currently unused in the UI button triggers
  // but kept for future reference if needed.

  Widget _buildSwitchTile(
    IconData icon,
    String label,
    bool val,
    Function(bool) onChanged,
  ) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Icon(icon, color: Colors.white70, size: 20),
      title: Text(label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
      trailing: Switch(
        value: val,
        onChanged: onChanged,
        activeTrackColor: AppTheme.primary.withValues(alpha: 0.2),
        activeThumbColor: AppTheme.primary,
      ),
    );
  }

  Widget _buildLogoutBtn() {
    return TextButton(
      onPressed: () => Supabase.instance.client.auth.signOut().then((_) {
        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const AuthScreen()),
            (r) => false,
          );
        }
      }),
      child: Center(
        child: Text(
          TranslationService.translate('logout').toUpperCase(),
          style: const TextStyle(
            color: Colors.redAccent,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  void _showChangePasswordDialog() {
    final oldPassC = TextEditingController();
    final newPassC = TextEditingController();
    final confirmPassC = TextEditingController();
    bool obscureOld = true;
    bool obscureNew = true;
    bool obscureConfirm = true;

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
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'change_password'.tr,
                style: AppTheme.headlineStyle.copyWith(fontSize: 20),
              ),
              const SizedBox(height: 24),
              _dialogInput('old_password'.tr, oldPassC, obscureOld, () {
                setModalState(() => obscureOld = !obscureOld);
              }),
              const SizedBox(height: 16),
              _dialogInput('new_password'.tr, newPassC, obscureNew, () {
                setModalState(() => obscureNew = !obscureNew);
              }),
              const SizedBox(height: 16),
              _dialogInput('CONFIRM_PASSWORD'.tr, confirmPassC, obscureConfirm, () {
                setModalState(() => obscureConfirm = !obscureConfirm);
              }),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    if (oldPassC.text.isEmpty || newPassC.text.isEmpty || confirmPassC.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('please_fill_all'.tr)),
                      );
                      return;
                    }
                    if (newPassC.text != confirmPassC.text) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('PASSWORDS_DO_NOT_MATCH'.tr)),
                      );
                      return;
                    }

                    try {
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (context) => const Center(
                          child: CircularProgressIndicator(color: AppTheme.primary),
                        ),
                      );
                      
                      await Supabase.instance.client.auth.updateUser(
                        UserAttributes(password: newPassC.text.trim()),
                      );
                      
                      if (!context.mounted) return;
                      Navigator.pop(context); // close loader
                      
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('password_updated_success'.tr), backgroundColor: AppTheme.secondary),
                      );
                      Navigator.pop(context); // close bottom sheet
                    } catch (e) {
                      if (!context.mounted) return;
                      Navigator.pop(context); // close loader
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(e.toString()), backgroundColor: Colors.redAccent),
                      );
                    }
                  },
                  child: Text('SAVE'.tr.toUpperCase()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dialogInput(String hint, TextEditingController c, bool obscure, VoidCallback onToggle) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: TextField(
        controller: c,
        obscureText: obscure,
        style: AppTheme.bodyStyle,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: AppTheme.bodyStyle.copyWith(color: Colors.white24),
          prefixIcon: const Icon(Icons.lock_outline_rounded, color: Colors.white38, size: 20),
          suffixIcon: IconButton(
            icon: Icon(obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: Colors.white38),
            onPressed: onToggle,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
        ),
      ),
    );
  }

  void _showAddEmailDialog() {
    final emailC = TextEditingController();
    final confirmEmailC = TextEditingController();

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
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'ADD_RECOVERY_EMAIL'.tr,
                style: AppTheme.headlineStyle.copyWith(fontSize: 20),
              ),
              const SizedBox(height: 8),
              Text(
                'RECOVERY_EMAIL_DESC'.tr,
                style: AppTheme.bodyStyle.copyWith(color: Colors.white38, fontSize: 12),
              ),
              const SizedBox(height: 24),
              _emailInput('email'.tr, emailC),
              const SizedBox(height: 16),
              _emailInput('CONFIRM_EMAIL'.tr, confirmEmailC),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    if (emailC.text.isEmpty || confirmEmailC.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('please_fill_all'.tr)),
                      );
                      return;
                    }
                    if (emailC.text != confirmEmailC.text) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('EMAILS_DO_NOT_MATCH'.tr)),
                      );
                      return;
                    }
                    
                    try {
                      await Supabase.instance.client.auth.updateUser(
                        UserAttributes(email: emailC.text.trim()),
                      );
                      
                      if (!context.mounted) return;
                      
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('recovery_email_updated'.tr), backgroundColor: AppTheme.secondary),
                      );
                      Navigator.pop(context);
                    } catch (e) {
                      if (!context.mounted) return;
                      
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(e.toString()), backgroundColor: Colors.redAccent),
                      );
                    }
                  },
                  child: Text('SAVE'.tr.toUpperCase()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emailInput(String hint, TextEditingController c) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: TextField(
        controller: c,
        style: AppTheme.bodyStyle,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: AppTheme.bodyStyle.copyWith(color: Colors.white24),
          prefixIcon: const Icon(Icons.email_outlined, color: Colors.white38, size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
        ),
      ),
    );
  }

  void _showDeleteAccountFlow() {
    final passwordC = TextEditingController();
    bool obscurePassword = true;
    int currentStep = 0;

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
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              
              if (currentStep == 0) ...[
                Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 24),
                    const SizedBox(width: 12),
                    Text(
                      'DELETE_ACCOUNT'.tr,
                      style: AppTheme.headlineStyle.copyWith(fontSize: 20, color: Colors.redAccent),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'DELETE_ACCOUNT_WARNING'.tr,
                  style: AppTheme.bodyStyle.copyWith(color: Colors.white70),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () {
                      setModalState(() {
                        currentStep = 1;
                      });
                    },
                    child: Text(
                      'PROCEED'.tr.toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'CANCEL'.tr.toUpperCase(),
                      style: const TextStyle(color: Colors.white38, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ] else if (currentStep == 1) ...[
                Text(
                  'VERIFY_PASSWORD'.tr,
                  style: AppTheme.headlineStyle.copyWith(fontSize: 20),
                ),
                const SizedBox(height: 8),
                Text(
                  'ENTER_PASSWORD_TO_DELETE'.tr,
                  style: AppTheme.bodyStyle.copyWith(color: Colors.white38, fontSize: 12),
                ),
                const SizedBox(height: 24),
                _dialogInput('password'.tr, passwordC, obscurePassword, () {
                  setModalState(() => obscurePassword = !obscurePassword);
                }),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () async {
                      if (passwordC.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('please_fill_all'.tr)),
                        );
                        return;
                      }
                      
                      try {
                        showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (context) => const Center(
                            child: CircularProgressIndicator(),
                          ),
                        );

                        // Call the real secure account deletion service
                        await AuthService().deleteAccount();

                        if (!context.mounted) return;
                        Navigator.pop(context); // Pop loading dialog
                        Navigator.pop(context); // Pop bottom sheet

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('ACCOUNT_DELETED_SUCCESS'.tr),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                        
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(builder: (_) => const AuthScreen()),
                          (r) => false,
                        );
                      } catch (e) {
                        if (!context.mounted) return;
                        Navigator.pop(context); // Pop loading dialog
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('${'error_occurred'.tr}: $e'),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                      }
                    },
                    child: Text(
                      'CONFIRM_DELETE'.tr.toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () {
                      setModalState(() {
                        currentStep = 0;
                      });
                    },
                    child: Text(
                      'back'.tr.toUpperCase(),
                      style: const TextStyle(color: Colors.white38, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
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

  Widget _buildProHubButton() {
    return GestureDetector(
      onTap: () {
        final wrapper = OrganizerMainWrapper.of(context);
        if (wrapper != null) {
          wrapper.openSelector();
          Navigator.pop(context);
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AccountSelectorScreen()),
          );
        }
      },
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1A1A1A), Color(0xFF0F0F0F)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.1)),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primary.withValues(alpha: 0.05),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.rocket_launch_rounded,
                color: AppTheme.primary,
                size: 24,
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    TranslationService.translate('organize').toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    TranslationService.translate('management_console'),
                    style: const TextStyle(color: Colors.white24, fontSize: 10),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppTheme.primary,
              size: 28,
            ),
          ],
        ),
      ),
    );
  }




  Widget _glow(Color color) {
    if (!PerformanceService.useBlur) return const SizedBox.shrink();
    return Container(
      width: 300,
      height: 300,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          BoxShadow(
            color: color,
            blurRadius: 150,
            spreadRadius: 30,
          ),
        ],
      ),
    );
  }
}

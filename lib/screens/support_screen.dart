import 'package:flutter/material.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/services/support_service.dart';
import 'package:my_app/services/translation_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:ui';
import 'package:url_launcher/url_launcher.dart';

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  final _supportService = SupportService();
  final _subjectController = TextEditingController();
  final _messageController = TextEditingController();
  late String _selectedCategory;
  bool _isSending = false;

  final Map<String, String> _categoryKeys = {
    'Technical Issue': 'tech_issue',
    'Booking Problem': 'booking_prob',
    'Suggestion': 'suggestion',
    'Organizer Query': 'organizer_query',
    'Other': 'other'
  };

  @override
  void initState() {
    super.initState();
    _selectedCategory = _categoryKeys.keys.first;
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submitRequest() async {
    if (_subjectController.text.isEmpty || _messageController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('please_fill_all'.tr),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isSending = true);
    try {
      await _supportService.sendSupportRequest(
        subject: _subjectController.text,
        message: _messageController.text,
        category: _selectedCategory,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('request_sent_success'.tr),
            backgroundColor: AppTheme.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${'action_failed'.tr}: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _launchWhatsApp() async {
    final url = Uri.parse("https://wa.me/213555000000"); // Placeholder
    if (!await launchUrl(url)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Could not launch WhatsApp")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final isGuest = user == null;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          // PREMIUM BACKGROUND GRADIENTS
          Positioned(
            top: -150,
            right: -100,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.primary.withValues(alpha: 0.08),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
                child: Container(color: Colors.transparent),
              ),
            ),
          ),
          Positioned(
            bottom: -150,
            left: -100,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.secondary.withValues(alpha: 0.08),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
                child: Container(color: Colors.transparent),
              ),
            ),
          ),

          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              _buildAppBar(),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 32),
                      _buildHeader(),
                      const SizedBox(height: 48),
                      _buildContactOptions(),
                      const SizedBox(height: 48),
                      if (isGuest) ...[
                        _buildGuestPrompt(),
                        const SizedBox(height: 48),
                      ],
                      _buildSupportForm(),
                      const SizedBox(height: 48),
                      _buildFAQSection(),
                      const SizedBox(height: 120),
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

  Widget _buildAppBar() {
    return SliverAppBar(
      pinned: true,
      backgroundColor: AppTheme.background.withValues(alpha: 0.8),
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
        onPressed: () => Navigator.pop(context),
      ),
      flexibleSpace: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: FlexibleSpaceBar(
            centerTitle: true,
            title: Text(
              'assistance'.tr.toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: AppTheme.primary,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Sivox_ELITE_SUPPORT'.tr.toUpperCase(),
              style: const TextStyle(
                color: AppTheme.primary,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'HOW_CAN_WE_HELP'.tr,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 42,
            fontWeight: FontWeight.w900,
            height: 1.1,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'support_subtitle'.tr,
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 14,
            height: 1.6,
          ),
        ),
      ],
    );
  }

  Widget _buildContactOptions() {
    return Row(
      children: [
        Expanded(
          child: _actionCard(
            icon: Icons.chat_bubble_rounded,
            title: 'WhatsApp',
            subtitle: 'Direct Line',
            color: const Color(0xFF25D366),
            onTap: _launchWhatsApp,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _actionCard(
            icon: Icons.mail_rounded,
            title: 'Email',
            subtitle: 'Official Inquiry',
            color: AppTheme.secondary,
            onTap: () {},
          ),
        ),
      ],
    );
  }

  Widget _actionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: color.withValues(alpha: 0.1)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                color: color.withValues(alpha: 0.4),
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGuestPrompt() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.auto_awesome_rounded, color: AppTheme.primary, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'JOIN_Sivox_BENEFIT'.tr,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  'SIGN_UP_TO_TRACK'.tr,
                  style: const TextStyle(color: Colors.white24, fontSize: 10),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pushNamed(context, '/login'),
            child: Text(
              'SIGN_UP'.tr,
              style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSupportForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SEND_A_MESSAGE'.tr.toUpperCase(),
          style: const TextStyle(
            color: Colors.white24,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 24),
        
        // Category Selector
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: _categoryKeys.keys.map((cat) {
              final isSelected = _selectedCategory == cat;
              return GestureDetector(
                onTap: () => setState(() => _selectedCategory = cat),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.only(right: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected ? AppTheme.primary : Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected ? AppTheme.primary : Colors.white.withValues(alpha: 0.05),
                    ),
                  ),
                  child: Text(
                    _categoryKeys[cat]!.tr.toUpperCase(),
                    style: TextStyle(
                      color: isSelected ? Colors.black : Colors.white60,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        
        const SizedBox(height: 32),
        _buildTextField('subject'.tr, 'subject_hint'.tr, _subjectController, Icons.label_important_outline_rounded),
        const SizedBox(height: 24),
        _buildTextField('message'.tr, 'message_hint'.tr, _messageController, Icons.message_outlined, isLong: true),
        
        const SizedBox(height: 40),
        
        SizedBox(
          width: double.infinity,
          height: 64,
          child: ElevatedButton(
            onPressed: _isSending ? null : _submitRequest,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              elevation: 0,
            ),
            child: _isSending
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                : Text(
                    'send_request'.tr.toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildTextField(String label, String hint, TextEditingController controller, IconData icon, {bool isLong = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(color: Colors.white24, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: TextField(
            controller: controller,
            maxLines: isLong ? 6 : 1,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: Colors.white10),
              prefixIcon: Icon(icon, color: Colors.white24, size: 20),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(20),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFAQSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'COMMON_QUESTIONS'.tr.toUpperCase(),
          style: const TextStyle(
            color: Colors.white24,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 24),
        _faqTile('faq_booking_title'.tr, 'faq_booking_desc'.tr),
        _faqTile('faq_refund_title'.tr, 'faq_refund_desc'.tr),
        _faqTile('faq_staff_title'.tr, 'faq_staff_desc'.tr),
      ],
    );
  }

  Widget _faqTile(String q, String a) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: ExpansionTile(
        title: Text(q, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
        iconColor: AppTheme.primary,
        collapsedIconColor: Colors.white24,
        childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        children: [
          Text(
            a,
            style: const TextStyle(color: Colors.white60, fontSize: 12, height: 1.6),
          )
        ],
      ),
    );
  }
}

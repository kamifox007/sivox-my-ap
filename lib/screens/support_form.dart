import 'package:flutter/material.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/services/support_service.dart';
import 'package:my_app/services/translation_service.dart';

class SupportForm extends StatefulWidget {
  const SupportForm({super.key});

  @override
  State<SupportForm> createState() => _SupportFormState();
}

class _SupportFormState extends State<SupportForm> {
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
        SnackBar(content: Text('please_fill_all'.tr)),
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
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('request_sent_success'.tr)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${'action_failed'.tr}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('contact_dev'.tr, style: AppTheme.headlineStyle.copyWith(fontSize: 24)),
            const SizedBox(height: 8),
            Text('support_subtitle'.tr, style: AppTheme.bodyStyle.copyWith(color: AppTheme.onSurfaceVariant)),
            const SizedBox(height: 32),
            
            // Category Dropdown
            Text('category'.tr.toUpperCase(), style: AppTheme.labelStyle),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: AppTheme.surfaceContainer,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedCategory,
                  dropdownColor: AppTheme.surfaceContainer,
                  items: _categoryKeys.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value.tr))).toList(),
                  onChanged: (v) => setState(() => _selectedCategory = v ?? 'Other'),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Subject
            _buildField('subject'.tr.toUpperCase(), 'subject_hint'.tr, _subjectController),
            const SizedBox(height: 24),

            // Message
            _buildField('message'.tr.toUpperCase(), 'message_hint'.tr, _messageController, isLong: true),
            const SizedBox(height: 48),

            _isSending
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                : ElevatedButton(
                    onPressed: _submitRequest,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 56),
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Text('send_request'.tr.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildField(String label, String hint, TextEditingController controller, {bool isLong = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTheme.labelStyle),
        const SizedBox(height: 12),
        TextField(
          controller: controller,
          maxLines: isLong ? 4 : 1,
          style: AppTheme.bodyStyle,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white24),
            filled: true,
            fillColor: AppTheme.surfaceContainer,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          ),
        ),
      ],
    );
  }
}

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/services/event_service.dart';
import 'package:my_app/services/translation_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:my_app/services/storage_service.dart';

class EventCreationWidget extends StatefulWidget {
  final String clubId;
  final VoidCallback onCreated;

  const EventCreationWidget({
    super.key,
    required this.clubId,
    required this.onCreated,
  });

  @override
  State<EventCreationWidget> createState() => _EventCreationWidgetState();
}

class _EventCreationWidgetState extends State<EventCreationWidget> {
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _descController = TextEditingController();
  final _startDateController = TextEditingController();
  final _endDateController = TextEditingController();
  
  File? _image;
  bool _isSaving = false;
  final _picker = ImagePicker();
  String _paymentMode = 'at_door'; // at_door, free, pre_pre

  Future<void> _submit() async {
    if (_nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PLEASE_ENTER_EVENT_NAME'.tr), backgroundColor: Colors.redAccent));
      return;
    }
    if (_image == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PLEASE_SELECT_MAIN_IMAGE'.tr), backgroundColor: Colors.redAccent));
      return;
    }
    
    setState(() => _isSaving = true);
    try {
      final imageUrl = await StorageService().uploadImage(_image!, bucket: 'event-assets');
      if (imageUrl != null) {
        await EventService().createEvent(
          organizerId: widget.clubId,
          title: _nameController.text,
          category: 'club',
          venue: 'Your Club',
          dateTime: _endDateController.text.isEmpty
              ? _startDateController.text
              : '${_startDateController.text} - ${_endDateController.text}',
          price: _paymentMode == 'free' ? 0 : (double.tryParse(_priceController.text) ?? 2500),
          payAtDoor: _paymentMode == 'at_door',
          description: _descController.text,
          imageUrl: imageUrl,
        );
        widget.onCreated();
      }
    } catch (e) {
      debugPrint('Error creating event: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('PUBLISH NEW EXPERIENCE'.tr.toUpperCase(), style: AppTheme.labelStyle.copyWith(color: AppTheme.primary)),
          const SizedBox(height: 24),
          
          GestureDetector(
            onTap: () async {
              final xf = await _picker.pickImage(source: ImageSource.gallery);
              if (xf != null) setState(() => _image = File(xf.path));
            },
            child: Container(
              height: 180, width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.02),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                image: _image != null ? DecorationImage(image: FileImage(_image!), fit: BoxFit.cover) : null,
              ),
              child: _image == null ? const Icon(Icons.add_a_photo_rounded, color: Colors.white10, size: 40) : null,
            ),
          ),
          
          const SizedBox(height: 24),
          _buildPaymentModeSelector(),
          if (_paymentMode == 'at_door') ...[
            const SizedBox(height: 16),
            _field('PRICE'.tr, _priceController, keyboard: TextInputType.number),
          ],
          const SizedBox(height: 24),
          _field('TITLE'.tr, _nameController),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: _field('DATE'.tr, _startDateController, hint: 'Tonight 22:00')),
            const SizedBox(width: 12),
            Expanded(child: _field('End Time (Optional)', _endDateController, hint: 'Optional')),
          ]),
          const SizedBox(height: 16),
          _field('DESCRIPTION'.tr, _descController, maxLines: 3),
          
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            height: 60,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _submit,
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              child: _isSaving ? const CircularProgressIndicator(color: Colors.black) : Text('PUBLISH LIVE'.tr, style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentModeSelector() {
    final modes = [
      {'id': 'at_door', 'label': 'PAY_AT_VENUE'.tr, 'icon': Icons.door_front_door_rounded},
      {'id': 'free', 'label': 'FREE_ENTRY_MODE'.tr, 'icon': Icons.card_giftcard_rounded},
      {'id': 'pre', 'label': 'PRE_PAYMENT'.tr, 'icon': Icons.speed_rounded, 'locked': true},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('PAYMENT_MODE'.tr.toUpperCase(), style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
        const SizedBox(height: 12),
        Row(
          children: modes.map((m) {
            final isLocked = m['locked'] == true;
            final isSel = _paymentMode == m['id'];
            
            return Expanded(
              child: GestureDetector(
                onTap: isLocked ? null : () {
                  setState(() {
                    _paymentMode = m['id'] as String;
                    if (_paymentMode == 'free') {
                      _priceController.clear();
                    }
                  });
                },
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: isSel ? AppTheme.primary.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.02),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: isSel ? AppTheme.primary : (isLocked ? Colors.white.withValues(alpha: 0.01) : Colors.white.withValues(alpha: 0.05))),
                    boxShadow: isSel ? [BoxShadow(color: AppTheme.primary.withValues(alpha: 0.1), blurRadius: 10)] : null,
                  ),
                  child: Column(
                    children: [
                      Icon(m['icon'] as IconData, color: isSel ? AppTheme.primary : (isLocked ? Colors.white10 : Colors.white38), size: 18),
                      const SizedBox(height: 8),
                      Text(
                        m['label'] as String,
                        style: TextStyle(color: isSel ? AppTheme.primary : (isLocked ? Colors.white10 : Colors.white38), fontSize: 9, fontWeight: FontWeight.bold),
                      ),
                      if (isLocked)
                        Text(
                          'COMING_SOON'.tr.toUpperCase(),
                          style: const TextStyle(color: Colors.redAccent, fontSize: 6, fontWeight: FontWeight.w900),
                        ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _field(String label, TextEditingController c, {String? hint, int maxLines = 1, TextInputType? keyboard, bool enabled = true}) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: c, maxLines: maxLines, keyboardType: keyboard,
            enabled: enabled,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: hint, hintStyle: const TextStyle(color: Colors.white12),
              filled: true, fillColor: Colors.white.withValues(alpha: 0.03),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
        ],
      ),
    );
  }
}

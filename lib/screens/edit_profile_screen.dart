import 'dart:io';
import 'package:flutter/material.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/services/translation_service.dart';
import 'package:my_app/services/storage_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:my_app/services/auth_service.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _nameController = TextEditingController();
  final _storage = StorageService();
  final _picker = ImagePicker();
  
  bool _isNameLoading = false;
  File? _imageFile;
  String? _currentAvatarUrl;
  String _currentPhone = '';

  @override
  void initState() {
    super.initState();
    _loadCurrentData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _loadCurrentData() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      _nameController.text = user.userMetadata?['full_name'] ?? '';
      _currentPhone = user.userMetadata?['phone_number'] ?? user.phone ?? '';
      _currentAvatarUrl = user.userMetadata?['avatar_url'];
    }
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (image != null) {
      setState(() {
        _imageFile = File(image.path);
        _updateAvatar();
      });
    }
  }
  
  Future<void> _updateAvatar() async {
      try {
        String? newAvatarUrl = _currentAvatarUrl;
        if (_imageFile != null) {
          final uploadedUrl = await _storage.uploadImage(_imageFile!);
          if (uploadedUrl != null) newAvatarUrl = uploadedUrl;
        }
        await Supabase.instance.client.auth.updateUser(UserAttributes(data: {'avatar_url': newAvatarUrl}));
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Avatar updated'.tr), backgroundColor: AppTheme.secondary));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error updating avatar: $e'), backgroundColor: Colors.redAccent));
      }
  }

  Future<void> _updateName() async {
    if (_nameController.text.trim().isEmpty) return;
    
    setState(() => _isNameLoading = true);
    try {
      await Supabase.instance.client.auth.updateUser(UserAttributes(
        data: {'full_name': _nameController.text.trim()},
      ));

      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser != null) {
        await Supabase.instance.client.from('profiles').update({
          'full_name': _nameController.text.trim(),
        }).eq('id', currentUser.id);
      }
      
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Name updated successfully'.tr), backgroundColor: AppTheme.secondary));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent));
    } finally {
      if (mounted) setState(() => _isNameLoading = false);
    }
  }
  
  void _showPhoneChangeFlow() {
      final phoneC = TextEditingController();
      final codeC = TextEditingController();
      bool codeSent = false;
      bool isLoading = false;
      
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
            padding: EdgeInsets.only(left: 24, right: 24, top: 24, bottom: MediaQuery.of(context).viewInsets.bottom + 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 24),
                Text(!codeSent ? 'CHANGE_PHONE_NUMBER'.tr : 'VERIFY_PHONE'.tr, style: AppTheme.headlineStyle.copyWith(fontSize: 20)),
                const SizedBox(height: 8),
                Text(!codeSent ? 'ENTER_NEW_PHONE_DESC'.tr : '${'CODE_SENT_TO'.tr} ${phoneC.text}', style: AppTheme.bodyStyle.copyWith(color: Colors.white38, fontSize: 12)),
                const SizedBox(height: 24),
                
                if (!codeSent)
                  Container(
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.04), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withValues(alpha: 0.05))),
                    child: TextField(
                      controller: phoneC, keyboardType: TextInputType.phone, style: AppTheme.bodyStyle,
                      decoration: InputDecoration(hintText: 'e.g. 0555...', hintStyle: AppTheme.bodyStyle.copyWith(color: Colors.white24), prefixIcon: const Icon(Icons.phone_outlined, color: Colors.white38, size: 20), border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16)),
                    ),
                  )
                else
                  Container(
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.04), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withValues(alpha: 0.05))),
                    child: TextField(
                      controller: codeC, keyboardType: TextInputType.number, style: AppTheme.bodyStyle,
                      decoration: InputDecoration(hintText: 'ENTER_OTP_CODE'.tr, hintStyle: AppTheme.bodyStyle.copyWith(color: Colors.white24), prefixIcon: const Icon(Icons.password_rounded, color: Colors.white38, size: 20), border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16)),
                    ),
                  ),
                  
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isLoading ? null : () async {
                      if (!codeSent) {
                          if (phoneC.text.isEmpty) return;
                          setModalState(() => isLoading = true);
                          try {
                              await AuthService().changePhoneNumber(phoneC.text);
                              setModalState(() {
                                  isLoading = false;
                                  codeSent = true;
                              });
                          } catch (e) {
                              setModalState(() => isLoading = false);
                              if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: Colors.redAccent));
                          }
                      } else {
                          if (codeC.text.isEmpty) return;
                          setModalState(() => isLoading = true);
                          bool success = await AuthService().verifyPhoneChange(phoneC.text, codeC.text);
                          setModalState(() => isLoading = false);
                          
                          if (success) {
                              // We also update user metadata manually so we can fetch it easily later
                              await Supabase.instance.client.auth.updateUser(UserAttributes(data: {'phone_number': AuthService.normalizeAlgerianPhone(phoneC.text)}));
                              if (mounted) {
                                setState(() => _currentPhone = AuthService.normalizeAlgerianPhone(phoneC.text));
                                if (ctx.mounted) Navigator.pop(ctx);
                                if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('PHONE_VERIFIED_SUCCESS'.tr), backgroundColor: AppTheme.secondary));
                              }
                          } else {
                              if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('INVALID_CODE'.tr), backgroundColor: Colors.redAccent));
                          }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: isLoading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2)) : Text(!codeSent ? 'SEND_CODE'.tr.toUpperCase() : 'VERIFY'.tr.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('PERSONAL_INFO'.tr, style: AppTheme.headlineStyle.copyWith(fontSize: 16)),
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context, true)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        physics: const BouncingScrollPhysics(),
        children: [
            Center(child: _avatarStack()),
            const SizedBox(height: 48),
            
            // Name Section
            _buildSectionTitle('BASIC IDENTITY'.tr),
            const SizedBox(height: 12),
            Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white.withValues(alpha: 0.05))),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                        TextField(
                            controller: _nameController,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            decoration: InputDecoration(
                                labelText: 'FULL_NAME'.tr,
                                labelStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                                border: InputBorder.none,
                                prefixIcon: const Icon(Icons.person_outline, color: AppTheme.primary, size: 20),
                            ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                                onPressed: _isNameLoading ? null : _updateName,
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: _isNameLoading ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Text('SAVE_NAME'.tr),
                            ),
                        )
                    ],
                )
            ),
            
            const SizedBox(height: 32),
            
            // Phone Section
            _buildSectionTitle('CONTACT & SECURITY'.tr),
            const SizedBox(height: 12),
            Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white.withValues(alpha: 0.05))),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                        Row(
                            children: [
                                Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(color: AppTheme.secondary.withValues(alpha: 0.1), shape: BoxShape.circle),
                                    child: const Icon(Icons.phone_android_rounded, color: AppTheme.secondary, size: 20),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                            Text('PHONE_NUMBER'.tr, style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)),
                                            const SizedBox(height: 4),
                                            Text(_currentPhone.isEmpty ? 'NOT_SET'.tr : _currentPhone, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1)),
                                        ],
                                    ),
                                ),
                            ],
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                                onPressed: _showPhoneChangeFlow,
                                icon: const Icon(Icons.edit_rounded, size: 16, color: Colors.black),
                                label: Text('CHANGE_VERIFY_PHONE'.tr, style: const TextStyle(fontWeight: FontWeight.bold)),
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.secondary,
                                    foregroundColor: Colors.black,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    padding: const EdgeInsets.symmetric(vertical: 12)
                                ),
                            ),
                        ),
                    ],
                )
            ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Row(
      children: [
        Container(width: 12, height: 4, decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(title.toUpperCase(), style: AppTheme.labelStyle.copyWith(color: AppTheme.primary, letterSpacing: 2)),
      ],
    );
  }

  Widget _avatarStack() {
    ImageProvider? img;
    if (_imageFile != null) {
      img = FileImage(_imageFile!);
    } else if (_currentAvatarUrl != null) {
      img = NetworkImage(_currentAvatarUrl!);
    }

    return GestureDetector(
      onTap: _pickImage,
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3), width: 2)),
            child: CircleAvatar(radius: 50, backgroundColor: Colors.white.withValues(alpha: 0.05), backgroundImage: img, child: img == null ? const Icon(Icons.person, size: 40, color: Colors.white10) : null),
          ),
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle, border: Border.all(color: AppTheme.background, width: 3)), child: const Icon(Icons.camera_alt_rounded, color: Colors.black, size: 16)),
        ],
      ),
    );
  }
}

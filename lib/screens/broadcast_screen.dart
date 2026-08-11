import 'package:flutter/material.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/services/translation_service.dart';
import 'package:my_app/services/broadcast_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:my_app/services/draft_service.dart';
import 'dart:ui';

class BroadcastScreen extends StatefulWidget {
  final String? organizerId;
  const BroadcastScreen({super.key, this.organizerId});

  @override
  State<BroadcastScreen> createState() => _BroadcastScreenState();
}

class _BroadcastScreenState extends State<BroadcastScreen> {
  final _broadcastService = BroadcastService();
  final _messageController = TextEditingController();
  bool _isSending = false;
  String _target = 'followers'; // 'followers' or 'staff'

  @override
  void initState() {
    super.initState();
    _messageController.text = DraftService().getDraft('broadcast_msg');
    _messageController.addListener(() => DraftService().saveDraft('broadcast_msg', _messageController.text));
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _handleSend() async {
    final msg = _messageController.text.trim();
    if (msg.isEmpty) return;

    setState(() => _isSending = true);
    final organizerId = widget.organizerId ?? Supabase.instance.client.auth.currentUser?.id;
    if (organizerId == null) return;

    try {
      List<String> userIds;
      if (_target == 'followers') {
        userIds = await _broadcastService.getFollowerIds(organizerId);
      } else {
        userIds = await _broadcastService.getStaffIds(organizerId);
      }

      if (userIds.isNotEmpty) {
        await _broadcastService.sendBroadcast(
          userIds: userIds,
          title: 'Sivox Broadcast',
          body: msg,
          type: 'broadcast',
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('broadcast_sent'.tr), backgroundColor: AppTheme.primary));
        DraftService().clearDraft('broadcast_msg');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to send'), backgroundColor: Colors.redAccent));
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          Positioned(top: -100, right: -100, child: _aura(AppTheme.primary.withValues(alpha: 0.05))),
          CustomScrollView(
            slivers: [
              _buildAppBar(),
              _buildBody(),
            ],
          ),
          if (_isSending) _buildLoadingOverlay(),
        ],
      ),
    );
  }

  Widget _aura(Color c) => Container(width: 400, height: 400, decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: c, blurRadius: 150)]));

  Widget _buildAppBar() {
    return SliverAppBar(
      expandedHeight: 120,
      backgroundColor: Colors.transparent,
      pinned: true,
      title: Text('broadcast_title'.tr.toUpperCase(), style: AppTheme.headlineStyle.copyWith(fontSize: 18, letterSpacing: 2)),
      leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18), onPressed: () => Navigator.pop(context)),
    );
  }

  Widget _buildBody() {
    return SliverPadding(
      padding: const EdgeInsets.all(24),
      sliver: SliverList(
        delegate: SliverChildListDelegate([
          _buildEngineHeader(),
          const SizedBox(height: 32),
          Text('send_to'.tr.toUpperCase(), style: AppTheme.labelStyle.copyWith(color: AppTheme.primary, letterSpacing: 2)),
          const SizedBox(height: 16),
          _buildTargetSelector(),
          const SizedBox(height: 48),
          Text('message_label'.tr.toUpperCase(), style: AppTheme.labelStyle.copyWith(color: Colors.white24, letterSpacing: 2)),
          const SizedBox(height: 16),
          _buildMessageInput(),
          const SizedBox(height: 48),
          _buildSendButton(),
          const SizedBox(height: 60),
          _buildTemplateSection(),
        ]),
      ),
    );
  }

  Widget _buildEngineHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: const Icon(Icons.hub_rounded, color: AppTheme.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Text('REACH_YOUR_FANS'.tr.toUpperCase(), style: const TextStyle(color: AppTheme.primary, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2)),
          ],
        ),
        const SizedBox(height: 16),
        Text('marketing_engine_title'.tr, style: AppTheme.headlineStyle.copyWith(fontSize: 24)),
      ],
    );
  }

  Widget _buildTemplateSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('QUICK_TEMPLATES'.tr.toUpperCase(), style: const TextStyle(color: Colors.white24, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 2)),
        const SizedBox(height: 16),
        _templateCard('ðŸ”¥ Flash Party Alert', 'Join us tonight for a special session starting now!'),
        _templateCard('ðŸŽŸï¸ Last Tickets Left', 'Only 10% of capacity remains. Book your spot today!'),
        _templateCard('ðŸ¹ Follower Perk', 'Flash notification: Free drink for our followers tonight!'),
      ],
    );
  }

  Widget _templateCard(String title, String body) {
    return GestureDetector(
      onTap: () => setState(() => _messageController.text = body),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 4),
            Text(body, style: const TextStyle(color: Colors.white38, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _buildTargetSelector() {
    return Row(
      children: [
        _targetOption('followers', Icons.people_outline, 'followers'.tr),
        const SizedBox(width: 16),
        _targetOption('staff', Icons.badge_outlined, 'staff'.tr),
      ],
    );
  }

  Widget _targetOption(String val, IconData icon, String label) {
    bool sel = _target == val;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _target = val),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            color: sel ? AppTheme.primary : Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: sel ? AppTheme.primary : Colors.white10),
          ),
          child: Column(
            children: [
              Icon(icon, color: sel ? Colors.black : Colors.white38),
              const SizedBox(height: 8),
              Text(label, style: TextStyle(color: sel ? Colors.black : Colors.white38, fontWeight: FontWeight.bold, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white10)),
      child: TextField(
        controller: _messageController,
        maxLines: 8,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'message_label'.tr,
          hintStyle: const TextStyle(color: Colors.white12),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(24),
        ),
      ),
    );
  }

  Widget _buildSendButton() {
    return ElevatedButton.icon(
      onPressed: _isSending ? null : _handleSend,
      icon: const Icon(Icons.bolt_rounded, size: 18),
      label: Text('IGNITE_BROADCAST'.tr.toUpperCase()),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.black,
        minimumSize: const Size(double.infinity, 64),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 10,
        shadowColor: AppTheme.primary.withValues(alpha: 0.3),
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
      child: Container(
        color: Colors.black.withValues(alpha: 0.5),
        child: const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
      ),
    );
  }
}

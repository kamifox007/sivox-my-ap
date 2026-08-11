import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/services/translation_service.dart';
import 'package:my_app/services/audit_service.dart';
import 'package:my_app/services/notification_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:ui';
import 'package:my_app/screens/scan_entry.dart';

class VettingHubScreen extends StatefulWidget {
  final String? eventId;
  final String? clubId;
  const VettingHubScreen({super.key, this.eventId, this.clubId});

  @override
  State<VettingHubScreen> createState() => _VettingHubScreenState();
}

class _VettingHubScreenState extends State<VettingHubScreen> with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  late TabController _tabController;
  bool _isLoading = true;
  List<Map<String, dynamic>> _pendingCalls = [];
  List<Map<String, dynamic>> _pendingPayments = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchData();
    _setupRealtime();
  }

  void _setupRealtime() {
    supabase
        .channel('vetting_updates')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'bookings',
          callback: (payload) => _fetchData(isSilent: true),
        )
        .subscribe();
  }

  Future<void> _fetchData({bool isSilent = false}) async {
    if (!isSilent) setState(() => _isLoading = true);
    try {
      final query = supabase.from('bookings').select('*, events(title)');
      
      if (widget.eventId != null) {
        query.eq('event_id', widget.eventId!);
      } else if (widget.clubId != null) {
        // Find events for this club
        final eventsRes = await supabase.from('events').select('id').eq('organizer_id', widget.clubId!);
        final eventIds = (eventsRes as List).map((e) => e['id']).toList();
        query.inFilter('event_id', eventIds);
      }

      final res = await query.order('created_at', ascending: false);
      final bookings = (res as List).cast<Map<String, dynamic>>();

      setState(() {
        _pendingCalls = bookings.where((b) => b['payment_status'] == 'pending_confirmation').toList();
        _pendingPayments = bookings.where((b) => 
          (b['payment_status'] == 'pending' || b['payment_status'] == 'confirmed') && 
          b['payment_confirmed'] == false &&
          (b['scanned_at_security'] != null || b['is_walkin'] == true)
        ).toList();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Vetting error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        title: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('TACTICAL_VETTING'.tr.toUpperCase(), style: AppTheme.headlineStyle.copyWith(fontSize: 16, letterSpacing: 2)),
                Text('FIELD_VERIFICATION_HUB'.tr, style: const TextStyle(color: AppTheme.primary, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 1)),
              ],
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: () => _showHelp('TACTICAL_VETTING'.tr, 'HELPER_VETTING_DESC'.tr),
              child: Tooltip(
                message: 'MORE_INFO'.tr,
                child: const Icon(Icons.help_outline_rounded, color: Colors.white24, size: 10),
              ),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.primary,
          labelColor: AppTheme.primary,
          unselectedLabelColor: Colors.white24,
          tabs: [
            Tab(text: TranslationService.isRtl ? 'تأكيد التذاكر' : 'CONFIRM TICKETS'),
            Tab(text: 'PENDING_PAYMENTS'.tr.toUpperCase()),
          ],
        ),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
        : TabBarView(
            controller: _tabController,
            children: [
              _buildVettingList(_pendingCalls, isCall: true),
              _buildVettingList(_pendingPayments, isCall: false),
            ],
          ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ScanEntryScreen(organizerId: widget.clubId, eventId: widget.eventId))),
        backgroundColor: AppTheme.primary,
        child: const Icon(Icons.qr_code_scanner_rounded, color: Colors.black),
      ),
    );
  }

  Widget _buildVettingList(List<Map<String, dynamic>> items, {required bool isCall}) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(isCall ? Icons.phone_callback_rounded : Icons.payments_outlined, size: 64, color: Colors.white10),
            const SizedBox(height: 16),
            Text('CLEAR_QUEUE'.tr, style: const TextStyle(color: Colors.white24, fontSize: 14)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: items.length,
      itemBuilder: (context, index) => _vettingCard(items[index], isCall: isCall),
    );
  }

  Widget _vettingCard(Map<String, dynamic> booking, {required bool isCall}) {
    final String guestName = booking['user_name'] ?? 'Guest';
    final String phone = booking['guest_phone'] ?? '---';
    final String eventTitle = booking['events']?['title'] ?? 'Event';
    final String ticketType = booking['ticket_type'] ?? 'General';
    final int guests = booking['num_guests'] ?? 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: isCall ? Colors.blue.withValues(alpha: 0.1) : Colors.green.withValues(alpha: 0.1),
                      child: Icon(isCall ? Icons.phone_in_talk_rounded : Icons.receipt_long_rounded, 
                                  color: isCall ? Colors.blueAccent : Colors.greenAccent, size: 20),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(guestName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                          Text('$eventTitle • $ticketType x$guests', style: const TextStyle(color: Colors.white38, fontSize: 10)),
                        ],
                      ),
                    ),
                    if (isCall)
                      IconButton(
                        icon: const Icon(Icons.call, color: AppTheme.primary, size: 20),
                        onPressed: () => launchUrl(Uri.parse('tel:$phone')),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _actionButton(
                        isCall ? 'REJECT'.tr : 'DENY_PAYMENT'.tr,
                        isCall ? Colors.redAccent : Colors.orangeAccent,
                        () => _processBooking(booking, isCall ? 'cancelled' : 'failed', isCall),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _actionButton(
                        isCall ? 'CONFIRM_CALL'.tr : 'CONFIRM_PAYMENT'.tr,
                        isCall ? AppTheme.primary : Colors.greenAccent,
                        () => _processBooking(booking, isCall ? 'confirmed' : 'paid', isCall),
                        isPrimary: true,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showHelp(String title, String desc) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(32),
        decoration: const BoxDecoration(color: Color(0xFF1A1A1A), borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 24),
            const Icon(Icons.lightbulb_outline_rounded, color: AppTheme.primary, size: 32),
            const SizedBox(height: 16),
            Text(title.toUpperCase(), style: AppTheme.headlineStyle.copyWith(fontSize: 18)),
            const SizedBox(height: 12),
            Text(desc, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.5)),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _actionButton(String label, Color color, VoidCallback onTap, {bool isPrimary = false}) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: isPrimary ? color : color.withValues(alpha: 0.1),
        foregroundColor: isPrimary ? Colors.black : color,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
      child: Text(label.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1)),
    );
  }

  Future<void> _processBooking(Map<String, dynamic> booking, String newStatus, bool isCall) async {
    setState(() => _isLoading = true);
    try {
      final String bookingId = booking['id'];
      final String userId = booking['user_id'];
      final String eventId = booking['event_id'];
      
      if (isCall) {
        // Update payment_status for call verification
        await supabase.from('bookings').update({
          'payment_status': newStatus,
          'confirmed_by_manager': supabase.auth.currentUser?.id,
        }).eq('id', bookingId);

        // Notify visitor
        final bool isConfirmed = newStatus == 'confirmed';
        await NotificationService().sendNotificationToUser(
          userId: userId,
          title: isConfirmed ? 'TICKET_APPROVED'.tr : 'TICKET_REJECTED'.tr,
          body: isConfirmed 
            ? 'TICKET_CONFIRMED_BODY'.trArgs([booking['events']?['title'] ?? 'Event'])
            : 'TICKET_REJECTED_BODY'.trArgs([booking['events']?['title'] ?? 'Event']),
          type: 'booking_status',
          metadata: {'booking_id': bookingId},
        );

        await AuditService().logAction(
          actionType: isConfirmed ? 'BOOKING_CALL_CONFIRMED' : 'BOOKING_CALL_REJECTED',
          description: '${isConfirmed ? 'Confirmed' : 'Rejected'} call booking for ${booking['user_name']}.',
          relatedEventId: eventId,
        );
      } else {
        // Update payment_confirmed
        final bool isPaid = newStatus == 'paid';
        await supabase.from('bookings').update({
          'payment_confirmed': isPaid,
          'payment_status': isPaid ? 'used' : 'failed',
          'scanned_at_payment': DateTime.now().toIso8601String(),
          'scanned_at': DateTime.now().toIso8601String(),
          'confirmed_by_manager': supabase.auth.currentUser?.id,
        }).eq('id', bookingId);

        await AuditService().logAction(
          actionType: isPaid ? 'PAYMENT_CONFIRMED' : 'PAYMENT_DENIED',
          description: '${isPaid ? 'Confirmed' : 'Denied'} payment for ${booking['user_name']} at arrival.',
          relatedEventId: eventId,
        );
      }

      _fetchData(isSilent: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('action_failed'.tr)));
        setState(() => _isLoading = false);
      }
    }
  }
}

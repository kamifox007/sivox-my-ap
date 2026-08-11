import 'package:flutter/material.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/services/translation_service.dart';
import 'package:my_app/services/audit_service.dart';
import 'package:my_app/services/booking_service.dart';
import 'package:my_app/services/event_service.dart';
import 'package:my_app/models/booking.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BookingManagementScreen extends StatefulWidget {
  final String? clubId;
  final String? eventId;
  const BookingManagementScreen({super.key, this.clubId, this.eventId});

  @override
  State<BookingManagementScreen> createState() =>
      _BookingManagementScreenState();
}

class _BookingManagementScreenState extends State<BookingManagementScreen> {
  final _bookingService = BookingService();
  final _eventService = EventService();
  final _auditService = AuditService();
  final supabase = Supabase.instance.client;

  bool _isLoading = true;
  List<Booking> _bookings = [];
  String _selectedFilter = 'pending';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  final List<String> _cancelReasons = [
    'reason_mistake',
    'reason_duplicate',
    'reason_refused',
    'reason_other',
  ];

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    if (widget.eventId != null) {
      final res = await _bookingService.getBookingsForEvents([widget.eventId!]);
      setState(() {
        _bookings = res;
        _isLoading = false;
      });
    } else {
      final events = await _eventService.getOrganizerEvents(organizerId: widget.clubId);
      final eventIds = events.map((e) => e.id).toList();
      if (eventIds.isNotEmpty) {
        final res = await _bookingService.getBookingsForEvents(eventIds);
        setState(() {
          _bookings = res;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _updateStatus(String id, String status) async {
    if (status == 'cancelled') {
      _showCancelReasonDialog(id);
      return;
    }

    final ok = await _bookingService.updateBookingStatus(id, status);
    if (ok) {
      final booking = _bookings.firstWhere((b) => b.id == id);
      await _auditService.logAction(
        actionType: 'CONFIRM_BOOKING',
        description: 'Confirmed booking for ${booking.userName}',
        relatedEventId: booking.eventId,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('action_success'.tr),
            backgroundColor: AppTheme.primary,
          ),
        );
      }
      _loadData();
    }
  }

  void _showCancelReasonDialog(String id) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'select_cancel_reason'.tr,
              style: AppTheme.headlineStyle.copyWith(fontSize: 18),
            ),
            const SizedBox(height: 24),
            ..._cancelReasons.map(
              (reason) => ListTile(
                title: Text(
                  reason.tr,
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  final ok = await _bookingService.cancelBookingWithReason(
                    id,
                    reason: reason.tr,
                  );
                  if (ok) {
                    final booking = _bookings.firstWhere((b) => b.id == id);
                    await _auditService.logAction(
                      actionType: 'CANCEL_BOOKING',
                      description:
                          'Cancelled: ${booking.userName} - Reason: ${reason.tr}',
                      relatedEventId: booking.eventId,
                    );
                    _loadData();
                  }
                },
                trailing: const Icon(
                  Icons.chevron_right,
                  color: Colors.white24,
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  void _showHelp() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(32),
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 24),
            const Icon(Icons.auto_awesome_rounded, color: AppTheme.primary, size: 32),
            const SizedBox(height: 16),
            Text('manage_requests'.tr.toUpperCase(), style: AppTheme.headlineStyle.copyWith(fontSize: 18)),
            const SizedBox(height: 12),
            Text('HELPER_BOOKING_MGMT_DESC'.tr, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.5)),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _bookings
        .where((b) => b.paymentStatus == _selectedFilter)
        .toList();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          'manage_requests'.tr.toUpperCase(),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline_rounded, color: Colors.white24, size: 20),
            onPressed: () => _showHelp(),
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ['pending', 'pending_confirmation', 'confirmed', 'cancelled', 'used'].map((s) {
                bool sel = _selectedFilter == s;
                return GestureDetector(
                  onTap: () => setState(() => _selectedFilter = s),
                  child: Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: sel ? AppTheme.primary : Colors.white10,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      s.tr.toUpperCase(),
                      style: TextStyle(
                        color: sel ? Colors.black : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : filtered.isEmpty
          ? Center(
              child: Text(
                'no_requests'.tr,
                style: const TextStyle(color: Colors.white24),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(24),
              itemCount: filtered.length,
              itemBuilder: (context, i) => _buildBookingTile(filtered[i]),
            ),
    );
  }

  Widget _buildBookingTile(Booking b) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                b.userName.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${b.numGuests} ${'guests_label'.tr.toUpperCase()}',
                style: const TextStyle(
                  color: AppTheme.secondary,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: widget.eventId != null ? null : () {
               // Note: We'd need the full Event object here to navigate, 
               // or at least fetch it. For now, just styling it as a link if clickable.
            },
            child: Text(
              b.event?.title ?? 'event'.tr,
              style: TextStyle(
                color: widget.eventId != null ? Colors.white38 : AppTheme.primary.withValues(alpha: 0.7), 
                fontSize: 12,
                fontWeight: widget.eventId != null ? FontWeight.normal : FontWeight.bold
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (b.paymentStatus == 'pending' || b.paymentStatus == 'pending_confirmation')
            Column(
              children: [
                if (b.paymentStatus == 'pending_confirmation' && b.guestPhone != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        const Icon(Icons.phone_in_talk, color: AppTheme.primary, size: 14),
                        const SizedBox(width: 8),
                        Text(
                          b.guestPhone!,
                          style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _updateStatus(b.id, 'confirmed'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.greenAccent,
                          foregroundColor: Colors.black,
                        ),
                        child: Text('confirm'.tr.toUpperCase()),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _updateStatus(b.id, 'cancelled'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                        ),
                        child: Text('reject'.tr.toUpperCase()),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          
          if (b.paymentStatus == 'confirmed' && !b.paymentConfirmed)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final ok = await _bookingService.confirmManagerPayment(b.id);
                    if (ok) {
                      _loadData();
                    }
                  },
                  icon: const Icon(Icons.check_circle_outline, size: 16),
                  label: Text('CONFIRM_PAYMENT'.tr.toUpperCase()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.secondary.withValues(alpha: 0.15),
                    foregroundColor: AppTheme.secondary,
                    side: const BorderSide(color: AppTheme.secondary),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

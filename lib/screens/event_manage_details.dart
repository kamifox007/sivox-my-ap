import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/models/event.dart';
import 'package:my_app/models/booking.dart';
import 'package:my_app/screens/scan_entry.dart';
import 'package:my_app/screens/create_event.dart';
import 'package:my_app/screens/mission_matrix_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:printing/printing.dart';
import 'package:my_app/services/translation_service.dart';
import 'package:my_app/services/localization_service.dart';
import 'package:my_app/services/booking_service.dart';
import 'package:my_app/services/audit_service.dart';
import 'package:my_app/services/reporting_service.dart';
import 'package:my_app/services/notification_service.dart';
import 'package:my_app/screens/marketing_engine_screen.dart';
import 'package:my_app/screens/booking_management.dart';

class EventManageDetailsScreen extends StatefulWidget {
  final Event event;
  final bool showRequestsInitially;
  const EventManageDetailsScreen({super.key, required this.event, this.showRequestsInitially = false});

  @override
  State<EventManageDetailsScreen> createState() => _EventManageDetailsScreenState();
}

class _EventManageDetailsScreenState extends State<EventManageDetailsScreen> {
  final supabase = Supabase.instance.client;
  final _bookingService = BookingService();
  final _auditService = AuditService();
  final _reporting = ReportingService();
  final _notificationService = NotificationService();
  bool _hasAutoTriggered = false;

  Future<void> _exportReport() async {
    try {
      final clubName = Supabase.instance.client.auth.currentUser?.userMetadata?['full_name'] ?? 'Elite Club';
      final pdfBytes = await _reporting.generateEventReport(
        eventId: widget.event.id,
        userRole: 'organizer', // Organizer always gets full view
        eventTitle: widget.event.title,
        clubName: clubName,
      );
      await Printing.sharePdf(bytes: pdfBytes, filename: 'Sivox_Official_${widget.event.title}.pdf');
    } catch (_) {}
  }

  void _deleteEvent() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('حذف الفعالية', style: TextStyle(color: Colors.white)),
        content: const Text('هل أنت متأكد من حذف هذه الفعالية نهائياً؟ سيتم حذف جميع الحجوزات المرتبطة بها أيضاً.', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (!mounted) return;
      // SECOND CONFIRMATION
      final doubleConfirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.surfaceContainer,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('تأكيد أخير', style: TextStyle(color: Colors.redAccent)),
          content: const Text('هل أنت متأكد حقاً؟ لا يمكن التراجع عن هذا الإجراء وسيتم إخطار الحاجزين بالإلغاء.', style: TextStyle(color: Colors.white70)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('تراجع')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('نعم، احذف نهائياً', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

      if (doubleConfirmed == true) {
        try {
          // Delete bookings first to avoid foreign key constraints
          await supabase.from('bookings').delete().eq('event_id', widget.event.id);
          // Delete event
          await supabase.from('events').delete().eq('id', widget.event.id);
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('تم حذف الفعالية بنجاح')),
            );
            Navigator.pop(context); // Go back to profile
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('تعذر حذف الفعالية')),
            );
          }
        }
      }
    }
  }

  late Stream<List<Map<String, dynamic>>> _bookingsStream;

  @override
  void initState() {
    super.initState();
    _initStream();
  }

  void _initStream() {
    _bookingsStream = supabase.from('bookings').stream(primaryKey: ['id']).eq('event_id', widget.event.id).order('created_at', ascending: false);
  }

  Future<void> _refreshData() async {
    setState(() {
      _initStream();
    });
    await Future.delayed(const Duration(seconds: 1));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _bookingsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Scaffold(backgroundColor: AppTheme.background, body: Center(child: CircularProgressIndicator()));
        }

        final bookings = (snapshot.data ?? []).map((m) => Booking.fromMap(m)).toList();

        // AUTO-TRIGGER MODAL IF FLAG SET
        if (widget.showRequestsInitially && !_hasAutoTriggered) {
          _hasAutoTriggered = true;
          WidgetsBinding.instance.addPostFrameCallback((_) => _showRequestsModal(bookings));
        }

        final totalGuests = bookings.fold(0, (sum, item) => sum + (item.paymentStatus != 'cancelled' ? item.numGuests : 0));
        
        final capacity = widget.event.maxCapacity ?? 0;
        final progress = capacity > 0 ? totalGuests / capacity : 0.0;
        
        final role = supabase.auth.currentUser?.userMetadata?['role'] ?? 'attendee';
        final isAuthorized = role == 'owner' || role == 'manager' || role == 'admin' || role == 'organizer';

        // Revenue Calculations
        final eventPrice = widget.event.price;
        final revenueFinal = bookings.where((b) => b.paymentStatus == 'used' || b.paymentStatus == 'confirmed').fold(0.0, (s, b) => s + (b.numGuests * eventPrice));
        final revenuePending = bookings.where((b) => b.paymentStatus == 'pending').fold(0.0, (s, b) => s + (b.numGuests * eventPrice));

        return Scaffold(
          backgroundColor: AppTheme.background,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20), onPressed: () => Navigator.pop(context)),
            title: Text('TACTICAL_OPS_CENTER'.tr.toUpperCase(), style: AppTheme.headlineStyle.copyWith(fontSize: 16, letterSpacing: 2, color: AppTheme.primary)),
            centerTitle: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                onPressed: _deleteEvent,
                tooltip: 'delete_event'.tr,
              ),
              IconButton(
                icon: const Icon(Icons.edit_note_rounded, color: AppTheme.primary),
                onPressed: () => _editEvent(bookings),
                tooltip: 'edit_event'.tr,
              ),
              IconButton(
                icon: const Icon(Icons.picture_as_pdf_outlined, color: Colors.white70),
                onPressed: _exportReport,
                tooltip: 'export_pdf'.tr,
              ),
              IconButton(icon: const Icon(Icons.refresh, color: Colors.white38), onPressed: _refreshData),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: _refreshData,
            color: AppTheme.primary,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeroHeader(totalGuests, capacity, progress),
                  const SizedBox(height: 24),
                  
                  if (isAuthorized) _buildRevenueSection(revenueFinal, revenuePending),

                  const SizedBox(height: 32),
                  _buildActionButtons(isAuthorized, bookings),
                  const SizedBox(height: 48),
                  _buildSectionHeader('activity_feed'.tr.toUpperCase()),
                  _buildActivityList(bookings),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRevenueSection(double finalRev, double pendingRev) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Expanded(child: _revStat('total_revenue'.tr, finalRev, AppTheme.primary)),
          Container(width: 1, height: 40, color: Colors.white10),
          Expanded(child: _revStat('pending_payment'.tr, pendingRev, Colors.amber)),
        ],
      ),
    );
  }

  Widget _revStat(String label, double val, Color color) {
    return Column(
      children: [
        Text(label.toUpperCase(), style: AppTheme.labelStyle.copyWith(fontSize: 8)),
        const SizedBox(height: 4),
        Text(LocalizationService.formatPrice(val, widget.event.countryCode), 
             style: AppTheme.headlineStyle.copyWith(color: color, fontSize: 20)),
      ],
    );
  }

  Widget _buildHeroHeader(int total, int capacity, double progress) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainer,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('total_entered'.tr.toUpperCase(), style: AppTheme.labelStyle.copyWith(color: AppTheme.secondary, fontSize: 10)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$total', style: AppTheme.headlineStyle.copyWith(fontSize: 56)),
              Text('/ ${capacity == 0 ? '∞' : capacity}', style: AppTheme.headlineStyle.copyWith(fontSize: 24, color: Colors.white38)),
            ],
          ),
          const SizedBox(height: 24),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: Colors.white10,
              color: progress > 0.9 ? Colors.redAccent : AppTheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(bool isAuthorized, List<Booking> bookings) {
    return Column(
      children: [
        // Large Scan Tickets Button
        GestureDetector(
          onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (context) => ScanEntryScreen(
              organizerId: supabase.auth.currentUser?.id,
              eventId: widget.event.id,
            )));
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.1),
              border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.qr_code_scanner, color: AppTheme.primary, size: 32),
                const SizedBox(width: 16),
                Text(
                  'scan_tickets'.tr.toUpperCase(),
                  style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 2),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          childAspectRatio: 1.3,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          children: [
            _buildActionTile(Icons.person_add_alt_1, 'add_visitor'.tr, AppTheme.secondary, () => _showAddVisitorModal()),
            _buildActionTile(Icons.analytics_outlined, 'live_stats'.tr, AppTheme.primary, () => _showQuickStatsModal(bookings)),
            _buildActionTile(
              Icons.assignment_ind_rounded, 
              'attendance_requests'.tr, 
              bookings.any((b) => b.paymentStatus == 'pending_confirmation' || b.paymentStatus == 'pending') ? Colors.orangeAccent : Colors.amber, 
              () => Navigator.push(context, MaterialPageRoute(builder: (_) => BookingManagementScreen(eventId: widget.event.id))),
              hasBadge: bookings.any((b) => b.paymentStatus == 'pending_confirmation' || b.paymentStatus == 'pending'),
            ),
            if (isAuthorized)
              _buildActionTile(Icons.rocket_launch_rounded, 'MARKETING_CENTER'.tr, AppTheme.secondary, () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => MarketingEngineScreen(initialEventId: widget.event.id)));
              }),
            if (isAuthorized)
              _buildActionTile(Icons.picture_as_pdf_outlined, 'export_pdf'.tr, Colors.orangeAccent, _exportReport),
            if (isAuthorized)
              _buildActionTile(Icons.bolt_rounded, 'EXCLUSIVE_FOLLOWER_DEAL'.tr, Colors.amber, () => _promptDiscountPush()),
            if (isAuthorized)
              _buildActionTile(Icons.campaign_rounded, 'NEW_ANNOUNCEMENT'.tr, AppTheme.primary, () => _promptAnnouncementPush()),
            if (isAuthorized)
              _buildActionTile(Icons.inventory_2_rounded, 'FINALIZE_MISSION'.tr, Colors.redAccent, () => _confirmFinalizeMission(bookings)),
            if (isAuthorized)
              _buildActionTile(Icons.edit_note_rounded, 'edit_event'.tr, AppTheme.primary, () => _editEvent(bookings)),
            if (isAuthorized)
              _buildActionTile(Icons.delete_forever_rounded, 'delete_event'.tr, Colors.redAccent, () => _deleteEvent()),
          ],
        ),
      ],
    );
  }

  Widget _buildActionTile(IconData icon, String label, Color color, VoidCallback onTap, {bool hasBadge = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.05),
              border: Border.all(color: color.withValues(alpha: 0.2)),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 28),
                const SizedBox(height: 12),
                Text(
                  label.toUpperCase(), 
                  style: AppTheme.labelStyle.copyWith(color: color, fontSize: 10, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          if (hasBadge)
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: Colors.redAccent,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.background, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showRequestsModal(List<Booking> initialBookings) {
    final List<String> loadingIds = [];
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StreamBuilder<List<Map<String, dynamic>>>(
        stream: supabase.from('bookings').stream(primaryKey: ['id']).eq('event_id', widget.event.id).order('created_at', ascending: false),
        builder: (context, snapshot) {
          final currentBookings = (snapshot.data ?? []).map((m) => Booking.fromMap(m)).toList();
          final pending = currentBookings.where((b) => b.paymentStatus == 'pending' || b.paymentStatus == 'pending_confirmation').toList();

          return StatefulBuilder(
            builder: (context, setModalState) {
              return Container(
                height: MediaQuery.of(context).size.height * 0.85,
                padding: const EdgeInsets.all(32),
                decoration: const BoxDecoration(
                  color: Color(0xFF121212),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
                  border: Border(top: BorderSide(color: Colors.white10)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(2)))),
                    const SizedBox(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('attendance_requests'.tr.toUpperCase(), style: AppTheme.labelStyle.copyWith(color: Colors.amber, letterSpacing: 2)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), 
                          decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)), 
                          child: Text('${pending.length} ${'pending'.tr}', style: const TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold))
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    if (pending.isEmpty)
                       Expanded(child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.assignment_turned_in_rounded, color: Colors.white10, size: 64), const SizedBox(height: 16), Text('no_pending_requests'.tr, style: const TextStyle(color: Colors.white24))]))),
                    if (pending.isNotEmpty)
                        Expanded(
                        child: ListView.builder(
                          itemCount: pending.length,
                          itemBuilder: (context, idx) {
                            final b = pending[idx];
                            final isCallReq = b.paymentStatus == 'pending_confirmation';
                            final isLoading = loadingIds.contains(b.id);
                            
                            return Container(
                              margin: const EdgeInsets.only(bottom: 20),
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.02), 
                                borderRadius: BorderRadius.circular(32), 
                                border: Border.all(color: isCallReq ? Colors.amber.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.05)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 48, height: 48,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: AppTheme.primary.withValues(alpha: 0.1),
                                          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
                                        ),
                                        child: Center(child: Text(b.userName[0].toUpperCase(), style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w900, fontSize: 18))),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start, 
                                          children: [
                                            Text(b.userName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 0.5)),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                Icon(Icons.people_alt_rounded, color: Colors.white38, size: 10),
                                                const SizedBox(width: 4),
                                                Text('${b.numGuests} ${'guests'.tr} • ${b.createdAt?.substring(0, 10) ?? 'N/A'}', style: const TextStyle(color: Colors.white24, fontSize: 10)),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (b.guestPhone != null)
                                        _IconButton(
                                          icon: Icons.call_rounded, 
                                          color: Colors.amber, 
                                          onTap: () => launchUrl(Uri.parse('tel:${b.guestPhone}')),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 24),
                                  
                                  if (isCallReq) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                      decoration: BoxDecoration(
                                        color: Colors.amber.withValues(alpha: 0.05),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(color: Colors.amber.withValues(alpha: 0.1)),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.info_outline_rounded, color: Colors.amber, size: 14),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              'CALL_VERIFICATION_REQUIRED'.tr,
                                              style: const TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                  ],
    
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _TacticalButton(
                                          onTap: () => _processRequest(b.id, 'cancelled', b.userId, setModalState, loadingIds),
                                          label: 'REJECT'.tr,
                                          color: Colors.redAccent,
                                          isOutlined: true,
                                          isLoading: isLoading,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        flex: 2,
                                        child: _TacticalButton(
                                          onTap: () => _processRequest(b.id, 'confirmed', b.userId, setModalState, loadingIds),
                                          label: (isCallReq ? 'VERIFY_&_ACCEPT' : 'ACCEPT_REQUEST').tr,
                                          color: AppTheme.primary,
                                          isOutlined: false,
                                          isLoading: isLoading,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              );
            }
          );
        }
      ),
    );
  }

  Future<void> _processRequest(String bookingId, String status, String visitorId, StateSetter setModalState, List<String> loadingIds) async {
    if (loadingIds.contains(bookingId)) return;
    
    setModalState(() => loadingIds.add(bookingId));
    try {
      final success = await _bookingService.updateBookingStatus(
        bookingId, 
        status, 
        staffId: 'organizer', 
        eventId: widget.event.id
      );
      
      if (!success && mounted) {
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(
           content: Text('update_failed'.tr),
           backgroundColor: Colors.redAccent,
         ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('error_occurred'.tr),
          backgroundColor: Colors.redAccent,
        ));
      }
    } finally {
      if (mounted) {
        setModalState(() => loadingIds.remove(bookingId));
      }
    }
  }

  void _promptAnnouncementPush() {
    String message = '';
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Text('NEW_ANNOUNCEMENT'.tr, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('announcement_desc'.tr, style: const TextStyle(color: Colors.white38, fontSize: 11)),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(16)),
              child: TextField(
                onChanged: (v) => message = v,
                maxLines: 4,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'announcement_hint'.tr,
                  hintStyle: const TextStyle(color: Colors.white10),
                  border: InputBorder.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('cancel'.tr, style: const TextStyle(color: Colors.white38))),
          MaterialButton(
            onPressed: () async {
              if (message.isEmpty) return;
              final ns = _notificationService;
              await ns.notifyFollowers(
                organizerId: supabase.auth.currentUser!.id,
                title: 'OFFICIAL_ANNOUNCEMENT'.trArgs([widget.event.title]),
                body: message,
                type: 'announcement',
                metadata: {'event_id': widget.event.id, 'event_title': widget.event.title},
              );
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('broadcast_sent'.tr),
                  backgroundColor: AppTheme.primary,
                  behavior: SnackBarBehavior.floating,
                ));
              }
            },
            color: AppTheme.primary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Text('SEND_NOW'.tr.toUpperCase(), style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _notifyAttendeesOfUpdate(List<Booking> bookings) async {
    final attendeeIds = bookings
        .where((b) => b.paymentStatus == 'confirmed' || b.paymentStatus == 'used')
        .map((b) => b.userId)
        .toSet()
        .toList();

    for (final userId in attendeeIds) {
      await _notificationService.sendNotificationToUser(
        userId: userId,
        title: 'تحديث في الفعالية',
        body: 'تم تحديث تفاصيل الفعالية: ${widget.event.title}. يرجى مراجعة تذكرتك.',
        type: 'event_update',
        metadata: {'event_id': widget.event.id},
      );
    }
  }

  Future<void> _editEvent(List<Booking> bookings) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CreateEventScreen(event: widget.event)),
    );
    if (result == true) {
      await _notifyAttendeesOfUpdate(bookings);
      setState(() {});
    }
  }

  void _showAddVisitorModal() {
    String phone = '';
    int numGuests = 1;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: AppTheme.surfaceContainer,
            title: Text('generate_entry_ticket'.tr, style: const TextStyle(color: Colors.white)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  onChanged: (v) => phone = v,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(hintText: 'phone_number'.tr, hintStyle: const TextStyle(color: Colors.white24)),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('guests_label'.tr, style: const TextStyle(color: Colors.white70)),
                    Row(
                      children: [
                        IconButton(icon: const Icon(Icons.remove, color: Colors.white), onPressed: () => setState(() => numGuests > 1 ? numGuests-- : null)),
                        Text('$numGuests', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        IconButton(icon: const Icon(Icons.add, color: Colors.white), onPressed: () => setState(() => numGuests++)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: Text('cancel'.tr)),
              TextButton(
                onPressed: () async {
                  await _bookingService.createBooking(
                    eventId: widget.event.id, 
                    guestPhone: phone, 
                    numGuests: numGuests, 
                    paymentStatus: 'pending_confirmation',
                    ticketType: 'Generated',
                  );
                  await _auditService.logAction(actionType: 'MANUAL_BOOKING', description: 'manual_entry_issued'.tr, relatedEventId: widget.event.id);
                  if (context.mounted) Navigator.pop(context);
                }, 
                child: Text('issue_ticket'.tr),
              ),
            ],
          );
        }
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(padding: const EdgeInsets.only(bottom: 20), child: Text(title, style: AppTheme.labelStyle.copyWith(letterSpacing: 2, fontSize: 11)));
  }

  Widget _buildActivityList(List<Booking> bookings) {
    if (bookings.isEmpty) return Center(child: Text('no_requests'.tr, style: const TextStyle(color: Colors.white24)));
    final recent = bookings.take(20).toList();

    return Column(
      children: recent.map((b) {
        final isCancelled = b.paymentStatus == 'cancelled';
        final isConfirmed = b.paymentStatus == 'confirmed' || b.paymentStatus == 'used';
        
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.surfaceContainer,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: isCancelled ? Colors.red.withValues(alpha: 0.1) : Colors.white10),
          ),
          child: Row(
            children: [
              Icon(isCancelled ? Icons.cancel_outlined : (isConfirmed ? Icons.check_circle : Icons.hourglass_empty), 
                   color: isCancelled ? Colors.redAccent : (isConfirmed ? AppTheme.primary : Colors.amber), size: 20),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(b.userName, style: AppTheme.bodyStyle.copyWith(fontWeight: FontWeight.bold)),
                    Text('${b.numGuests} ${'guests_label'.tr} • ${b.paymentStatus.tr.toUpperCase()}', style: AppTheme.bodyStyle.copyWith(color: AppTheme.onSurfaceVariant, fontSize: 11)),
                  ],
                ),
              ),
              if (b.guestPhone != null && b.guestPhone!.isNotEmpty) 
                IconButton(icon: const Icon(Icons.call, size: 16, color: AppTheme.secondary), onPressed: () => launchUrl(Uri.parse('tel:${b.guestPhone}'))),
            ],
          ),
        );
      }).toList(),
    );
  }

  void _showQuickStatsModal(List<Booking> bookings) {
    final totalBooked = bookings.fold(0, (sum, item) => sum + (item.paymentStatus != 'cancelled' ? item.numGuests : 0));
    final arrived = bookings.where((b) => b.paymentStatus == 'used').fold(0, (sum, b) => sum + b.numGuests);
    final generatedCount = bookings.where((b) => b.ticketType == 'Generated').fold(0, (sum, b) => sum + b.numGuests);
    final capacity = widget.event.maxCapacity ?? 0;
    final revFinal = bookings.where((b) => b.paymentStatus == 'used' || b.paymentStatus == 'confirmed').fold(0.0, (s, b) => s + (b.numGuests * widget.event.price));
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppTheme.surfaceContainer.withValues(alpha: 0.98),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05), width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 32),
            Text('live_stats'.tr.toUpperCase(), style: AppTheme.labelStyle.copyWith(color: AppTheme.primary, letterSpacing: 4, fontSize: 10)),
            const SizedBox(height: 32),
            
            Row(
              children: [
                Expanded(child: _miniMetric('bookings'.tr, '$totalBooked', Icons.confirmation_number_outlined, AppTheme.secondary)),
                const SizedBox(width: 16),
                Expanded(child: _miniMetric('arrived'.tr, '$arrived', Icons.login_rounded, AppTheme.primary)),
              ],
            ),
            const SizedBox(height: 16),
            _miniMetric('GENERATED_PASSES'.tr, '$generatedCount', Icons.local_activity_rounded, Colors.blueAccent, wide: true),
            const SizedBox(height: 16),
            _miniMetric('total_revenue'.tr, LocalizationService.formatPrice(revFinal, widget.event.countryCode), Icons.payments_outlined, Colors.greenAccent, wide: true),
            
            const SizedBox(height: 32),
            if (capacity > 0) ...[
               Row(
                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
                 children: [
                   Text('capacity_usage'.tr.toUpperCase(), style: const TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1)),
                   Text('${((arrived / capacity) * 100).toInt()}%', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900)),
                 ],
               ),
               const SizedBox(height: 12),
               ClipRRect(
                 borderRadius: BorderRadius.circular(10),
                 child: LinearProgressIndicator(
                   value: (arrived / capacity).clamp(0.0, 1.0),
                   minHeight: 6,
                   backgroundColor: Colors.white.withValues(alpha: 0.05),
                   color: AppTheme.primary,
                 ),
               ),
            ],
            
            const SizedBox(height: 48),
            GestureDetector(
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => MissionMatrixScreen(
                  organizerId: supabase.auth.currentUser?.id,
                  eventId: widget.event.id,
                )));
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 18),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.1), border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)), borderRadius: BorderRadius.circular(20)),
                child: Text('view_all_reports'.tr.toUpperCase(), style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 2)),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _promptDiscountPush() {
    String discount = '20%';
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: AppTheme.surfaceContainer,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            title: Row(
              children: [
                const Icon(Icons.bolt_rounded, color: Colors.amber, size: 20),
                const SizedBox(width: 12),
                Text('EXCLUSIVE_FOLLOWER_DEAL'.tr, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('proactive_desc'.tr, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                const SizedBox(height: 24),
                
                // Pulse Presets
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: ['10%', '20%', '50%'].map((p) => GestureDetector(
                    onTap: () => setState(() => discount = p),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: discount == p ? AppTheme.primary : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: discount == p ? AppTheme.primary : Colors.white10),
                      ),
                      child: Text(p, style: TextStyle(color: discount == p ? Colors.black : Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  )).toList(),
                ),
                
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(16)),
                  child: TextField(
                    onChanged: (v) => discount = v,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'CUSTOM_VALUE'.tr,
                      hintStyle: const TextStyle(color: Colors.white10),
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: Text('cancel'.tr, style: const TextStyle(color: Colors.white38))),
              MaterialButton(
                onPressed: () async {
                  if (discount.isEmpty) return;
                  final ns = _notificationService;
                  await ns.notifyDiscountFlash(
                    organizerId: supabase.auth.currentUser!.id,
                    eventTitle: widget.event.title,
                    discountAmount: discount,
                  );
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('broadcast_sent'.tr),
                      backgroundColor: AppTheme.primary,
                      behavior: SnackBarBehavior.floating,
                    ));
                  }
                },
                color: AppTheme.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Text('BROADCAST_NOW'.tr.toUpperCase(), style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        }
      ),
    );
  }

  void _confirmFinalizeMission(List<Booking> bookings) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceContainer,
        title: Text('FINALIZE_MISSION'.tr, style: const TextStyle(color: Colors.redAccent)),
        content: Text('FINALIZE_CONFIRM_DESC'.tr, style: const TextStyle(color: Colors.white70, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('cancel'.tr, style: const TextStyle(color: Colors.white38))),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _performFinalize(bookings);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            child: Text('FINALIZE_NOW'.tr.toUpperCase()),
          ),
        ],
      ),
    );
  }

  Future<void> _performFinalize(List<Booking> bookings) async {
    final totalBooked = bookings.fold(0, (sum, item) => sum + (item.paymentStatus != 'cancelled' ? item.numGuests : 0));
    final arrived = bookings.where((b) => b.paymentStatus == 'used').fold(0, (sum, b) => sum + b.numGuests);
    
    final securityStats = await _auditService.getSecurityStats(widget.event.id);
    
    final success = await _auditService.finalizeAndArchiveMission(
      clubId: widget.event.organizerId ?? '',
      title: widget.event.title,
      census: {
        'total': totalBooked,
        'scanned': arrived,
      },
      security: securityStats,
    );

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('MISSION_ARCHIVED_SUCCESS'.tr),
        backgroundColor: Colors.greenAccent,
      ));
    }
  }

  Widget _miniMetric(String label, String val, IconData icon, Color color, {bool wide = false}) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(28), border: Border.all(color: color.withValues(alpha: 0.1))),
      child: Column(
        crossAxisAlignment: wide ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 16),
          Text(val, style: AppTheme.headlineStyle.copyWith(fontSize: 24, color: Colors.white)),
          Text(label.toUpperCase(), style: TextStyle(color: color.withValues(alpha: 0.6), fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
        ],
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _IconButton({required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }
}

class _TacticalButton extends StatefulWidget {
  final VoidCallback onTap;
  final String label;
  final Color color;
  final bool isOutlined;
  final bool isLoading;

  const _TacticalButton({required this.onTap, required this.label, required this.color, required this.isOutlined, this.isLoading = false});

  @override
  State<_TacticalButton> createState() => _TacticalButtonState();
}

class _TacticalButtonState extends State<_TacticalButton> {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.isLoading ? null : (_) => setState(() => _scale = 0.98),
      onTapUp: widget.isLoading ? null : (_) {
        setState(() => _scale = 1.0);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _scale = 1.0),
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 100),
        child: Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.isOutlined ? Colors.transparent : widget.color.withValues(alpha: widget.isLoading ? 0.5 : 1.0),
            borderRadius: BorderRadius.circular(16),
            border: widget.isOutlined ? Border.all(color: widget.color.withValues(alpha: 0.3)) : null,
          ),
          child: widget.isLoading 
            ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: widget.isOutlined ? widget.color : Colors.black))
            : Text(
                widget.label.toUpperCase(),
                style: TextStyle(
                  color: widget.isOutlined ? widget.color : Colors.black,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  letterSpacing: 1,
                ),
              ),
        ),
      ),
    );
  }
}


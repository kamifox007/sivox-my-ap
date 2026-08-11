import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/booking.dart';
import '../models/event.dart';
import '../services/booking_service.dart';
import '../services/event_service.dart';
import '../services/localization_service.dart';
import '../services/translation_service.dart';
import '../theme/app_theme.dart';
import 'package:qr_flutter/qr_flutter.dart';
// import 'package:flutter_windowmanager/flutter_windowmanager.dart';

class TicketScreen extends StatefulWidget {
  final Booking? booking;
  final Event? event;
  const TicketScreen({super.key, this.booking, this.event});

  @override
  State<TicketScreen> createState() => _TicketScreenState();
}

class _TicketScreenState extends State<TicketScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  final _bookingService = BookingService();
  final _eventService = EventService();
  
  List<Booking> _bookings = [];
  List<Event> _events = [];
  bool _isLoading = true;
  
  final Map<String, int> _editCounts = {};
  final Set<String> _updatingIds = {};
  final List<String> _hiddenTickets = [];
  bool isTransferring = false;
  final _transferController = TextEditingController();
  late AnimationController _pulseController;
  RealtimeChannel? _realtimeSubscription;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _pulseController = AnimationController(
      vsync: this, 
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
    
    // Initialize with passed data if available
    if (widget.booking != null) {
      _bookings = [widget.booking!];
    }
    if (widget.event != null) {
      _events = [widget.event!];
    }
    
    _refresh();
    _setupRealtimeSync();
    _secureScreen();
  }

  Future<void> _secureScreen() async {
    // await FlutterWindowManager.addFlags(FlutterWindowManager.FLAG_SECURE);
  }

  void _setupRealtimeSync() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    _realtimeSubscription = Supabase.instance.client
        .channel('public:bookings_sync:${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'bookings',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: user.id,
          ),
          callback: (payload) {
            if (mounted) {
              // Smooth refresh when booking status is updated (e.g., scanned/used)
              _refresh();
            }
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _realtimeSubscription?.unsubscribe();
    // FlutterWindowManager.clearFlags(FlutterWindowManager.FLAG_SECURE);
    _tabController.dispose();
    _transferController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _isLoading = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final futures = await Future.wait([
        _bookingService.getUserBookings(),
        _eventService.getAllEvents(),
      ]);

      if (mounted) {
        setState(() {
          _bookings = futures[0] as List<Booking>;
          _events = futures[1] as List<Event>;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _bookings.where((b) => b.paymentStatus != 'cancelled' && b.paymentStatus != 'refunded' && b.paymentStatus != 'used' && !_hiddenTickets.contains(b.id)).toList();
    final history = _bookings.where((b) => b.paymentStatus == 'cancelled' || b.paymentStatus == 'refunded' || b.paymentStatus == 'used' || _hiddenTickets.contains(b.id)).toList();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: Text('MY_TICKETS'.tr.toUpperCase(), style: AppTheme.headlineStyle.copyWith(fontSize: 20, letterSpacing: 2)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(20),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primary.withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              labelColor: Colors.black,
              unselectedLabelColor: Colors.white38,
              labelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1),
              indicatorSize: TabBarIndicatorSize.tab,
              tabs: [
                 Tab(text: 'ACTIVE'.tr.toUpperCase()),
                 Tab(text: 'HISTORY'.tr.toUpperCase()),
              ],
            ),
          ),
        ),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
        : TabBarView(
            controller: _tabController,
            children: [
              _buildList(active, false),
              _buildList(history, true),
            ],
          ),
    );
  }

  Widget _buildList(List<Booking> list, bool isHist) {
    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(isHist ? Icons.history : Icons.local_activity_outlined, size: 64, color: Colors.white10),
            const SizedBox(height: 16),
            Text(isHist ? 'no_history'.tr : 'no_tickets'.tr, style: const TextStyle(color: Colors.white38)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      color: AppTheme.primary,
      child: ListView.builder(
        padding: const EdgeInsets.all(24),
        itemCount: list.length,
        itemBuilder: (context, i) => _buildPassCard(list[i], _events),
      ),
    );
  }

  Widget _buildPassCard(Booking b, List<Event> allEvents) {
    final e = allEvents.any((ev) => ev.id == b.eventId) 
        ? allEvents.firstWhere((ev) => ev.id == b.eventId) 
        : null;
    final isUsed = b.paymentStatus == 'used';
    final isHist = b.paymentStatus == 'cancelled' || b.paymentStatus == 'refunded' || isUsed;
    final curCount = _editCounts[b.id] ?? b.numGuests;
    final changed = curCount != b.numGuests;
    final updating = _updatingIds.contains(b.id);

    return Hero(
      tag: 'ticket_${b.id}',
      child: Container(
        margin: const EdgeInsets.only(bottom: 24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primary.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
          child: Material(
            color: const Color(0xFF1A1A1A),
            clipBehavior: Clip.antiAlias,
            shape: const TicketShapeBorder(),
            child: Stack(
                children: [
                  // Glassy surface
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white.withValues(alpha: 0.05),
                            Colors.white.withValues(alpha: 0.01),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // WAITING FOR VETTING OVERLAY (Call or Payment)
                  if (b.paymentStatus == 'pending_confirmation' || ((b.scannedAtSecurity != null || b.isWalkin) && !b.paymentConfirmed))
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(32),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(32),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center, 
                              children: [
                                const Icon(Icons.verified_user_rounded, color: AppTheme.secondary, size: 48),
                                const SizedBox(height: 24),
                                Text(
                                  (b.paymentStatus == 'pending_confirmation') 
                                    ? 'WAITING_FOR_CONFIRMATION'.tr 
                                    : 'WAITING_FOR_PAYMENT'.tr,
                                  style: AppTheme.headlineStyle.copyWith(
                                    fontSize: 16, 
                                    color: AppTheme.secondary,
                                    letterSpacing: 2,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 40),
                                  child: Text(
                                    (b.paymentStatus == 'pending_confirmation')
                                      ? 'call_to_confirm_desc'.tr
                                      : 'payment_at_door_desc'.tr,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                   // NEW: Holographic Background Layer
                   Positioned.fill(
                    child: AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        return CustomPaint(
                          painter: _HolographicPainter(
                            animationValue: _pulseController.value,
                            color: isUsed ? Colors.transparent : AppTheme.primary,
                          ),
                        );
                      },
                    ),
                  ),
                  Column(
                    children: [
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Icon(
                                isUsed ? Icons.check_circle_outline : Icons.confirmation_number_outlined,
                                color: AppTheme.primary,
                                size: 30,
                              ),
                            ),
                            const SizedBox(width: 20),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    b.ticketType.toUpperCase(),
                                    style: TextStyle(
                                      color: AppTheme.primary,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 18,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${b.numGuests} ${'guests'.tr}',
                                    style: const TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: (isUsed ? Colors.white10 : AppTheme.primary.withValues(alpha: 0.1)),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
                              ),
                              child: Text(
                                b.paymentStatus.toUpperCase(),
                                style: TextStyle(
                                  color: isUsed ? Colors.white38 : AppTheme.primary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 32),
                        
                        if (!isHist) ...[
                          _guestStepper(b, curCount),
                          const SizedBox(height: 16),
                          _buildDetailRow('event'.tr, e?.title ?? '---', Icons.auto_awesome),
                          const SizedBox(height: 16),
                          _buildDetailRow('entry_id'.tr, b.qrCode.toUpperCase(), Icons.layers_outlined),
                          
                          if (e != null && !e.hidePrice) ...[
                            const SizedBox(height: 24),
                            const Divider(color: Colors.white10),
                            const SizedBox(height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('original_price'.tr, style: const TextStyle(color: Colors.white24, fontSize: 12)),
                                Text(
                                  LocalizationService.formatPrice(e.price, e.countryCode),
                                  style: const TextStyle(color: Colors.white70, decoration: TextDecoration.lineThrough, fontSize: 13),
                                ),
                              ],
                            ),
                            if (b.discountAmount > 0) ...[
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('discount'.tr, style: const TextStyle(color: AppTheme.secondary, fontSize: 12)),
                                  Text(
                                    '- ${LocalizationService.formatPrice(b.discountAmount, e.countryCode)}',
                                    style: const TextStyle(color: AppTheme.secondary, fontSize: 13, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('final_price'.tr, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                                Text(
                                  LocalizationService.formatPrice(
                                    b.totalPricePaid > 0 ? b.totalPricePaid : (e.price * b.numGuests) - b.discountAmount, 
                                    e.countryCode
                                  ),
                                  style: TextStyle(color: isUsed ? Colors.white38 : AppTheme.primary, fontSize: 18, fontWeight: FontWeight.w900),
                                ),
                              ],
                            ),
                          ],
                          if (changed) ...[
                            const SizedBox(height: 16),
                            _confirmModBtn(b, updating),
                          ],
                          const SizedBox(height: 24),
                          Center(
                            child: _PremiumFeedbackWrapper(
                              onTap: () => _showTicketOptions(context, b, e),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                decoration: BoxDecoration(
                                  color: AppTheme.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.qr_code_2_rounded, color: AppTheme.primary, size: 18),
                                    const SizedBox(width: 8),
                                    Text('SHOW_OPTIONS'.tr, style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Center(child: TextButton(onPressed: () => _cancel(b), child: Text('cancel_res'.tr.toUpperCase(), style: const TextStyle(color: Colors.white24, fontSize: 10, letterSpacing: 1)))),
                        ],

                        // Actions for Used/History tickets (Moved outside)
                        if (isUsed) ...[
                          const SizedBox(height: 24),
                          const Divider(color: Colors.white10),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildUsedActionButton(
                                Icons.archive_outlined, 
                                'ARCHIVE'.tr, 
                                Colors.white38,
                                () => _archiveTicket(b.id)
                              ),
                              const SizedBox(width: 24),
                              _buildUsedActionButton(
                                Icons.delete_outline, 
                                'REMOVE'.tr, 
                                Colors.redAccent.withValues(alpha: 0.5),
                                () => _cancel(b)
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Center(
                            child: _PremiumFeedbackWrapper(
                              onTap: () => _showTicketOptions(context, b, e),
                              child: Text('VIEW_QR'.tr, style: const TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUsedActionButton(IconData icon, String label, Color color, VoidCallback onTap) {
    return _PremiumFeedbackWrapper(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.primary.withValues(alpha: 0.5), size: 16),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label.toUpperCase(), style: const TextStyle(color: Colors.white24, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 1)),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _guestStepper(Booking b, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Text('guests_label'.tr, style: const TextStyle(color: Colors.white24, fontSize: 9, fontWeight: FontWeight.bold)),
          const Spacer(),
          IconButton(icon: const Icon(Icons.remove, size: 16, color: Colors.white), onPressed: () => setState(() => _editCounts[b.id] = (count > 1 ? count - 1 : 1))),
          SizedBox(width: 40, child: Center(child: Text('$count', style: AppTheme.headlineStyle.copyWith(fontSize: 20, color: AppTheme.primary)))),
          IconButton(icon: const Icon(Icons.add, size: 16, color: Colors.white), onPressed: () => setState(() => _editCounts[b.id] = (count < 10 ? count + 1 : 10))),
        ],
      ),
    );
  }

  Widget _confirmModBtn(Booking b, bool loading) {
    return ElevatedButton(
      onPressed: loading ? null : () => _submitMod(b),
      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.black, minimumSize: const Size(double.infinity, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
      child: loading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black)) : Text('change_count'.tr.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
    );
  }

  Widget _qr(String data, bool used) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: used ? Colors.white24 : Colors.white, borderRadius: BorderRadius.circular(24)),
      child: QrImageView(
        data: data, 
        version: QrVersions.auto, 
        size: 140, 
        eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: used ? Colors.white54 : Colors.black), 
        dataModuleStyle: QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: used ? Colors.white54 : Colors.black)
      ),
    );
  }

  Future<void> _archiveTicket(String id) async {
    setState(() => _hiddenTickets.add(id));
  }

  Future<void> _cancel(Booking b) async {
    // Implement cancellation
  }

  Future<void> _submitMod(Booking b) async {
    // Implement modification
  }

  void _handleRedeem() async {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('redeem_success'.tr)));
  }

  void _showTicketOptions(BuildContext context, Booking b, Event? e) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.1)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 24),
            Text('REDEMPTION'.tr, style: AppTheme.labelStyle.copyWith(color: AppTheme.primary, letterSpacing: 2)),
            const SizedBox(height: 32),
            _qr(b.qrCode, b.paymentStatus == 'used'),
            const SizedBox(height: 12),
            Text(b.qrCode.toUpperCase(), style: const TextStyle(color: Colors.white24, fontSize: 10, letterSpacing: 4, fontWeight: FontWeight.bold)),
            const SizedBox(height: 40),
            Row(
              children: [
                Expanded(
                  child: _buildOption(Icons.local_activity, 'CLAIM'.tr, () {
                    Navigator.pop(ctx);
                    _handleRedeem();
                  }, isPrimary: true),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildOption(Icons.send_rounded, 'TRANSFER'.tr, () {
                    Navigator.pop(ctx);
                    _showTransferSheet(b);
                  }),
                ),
              ],
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  void _showTransferSheet(Booking b) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 32,
              top: 32,
              left: 32,
              right: 32,
            ),
            decoration: const BoxDecoration(
              color: Color(0xFF141414),
              borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
              border: Border(top: BorderSide(color: Colors.white10)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 32),
                Text('TRANSFER_TICKET'.tr.toUpperCase(), style: AppTheme.labelStyle.copyWith(color: AppTheme.primary, letterSpacing: 2)),
                const SizedBox(height: 40),
                
                TextField(
                  controller: _transferController,
                  onChanged: (v) => setModalState(() {}),
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    labelText: 'FRIEND_PHONE'.tr,
                    labelStyle: const TextStyle(color: Colors.white38),
                    prefixIcon: const Icon(Icons.phone, color: AppTheme.primary),
                    hintText: '05...'.tr,
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Colors.white10)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppTheme.primary)),
                  ),
                ),
                const SizedBox(height: 24),
                Text('TRANSFER_WARNING'.tr, style: const TextStyle(color: Colors.white24, fontSize: 10), textAlign: TextAlign.center),
                const SizedBox(height: 48),

                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: ElevatedButton(
                    onPressed: _transferController.text.isEmpty || isTransferring ? null : () => _handleTransfer(b.id),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    child: isTransferring 
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                      : Text('CONFIRM_TRANSFER'.tr.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _handleTransfer(String bookingId) async {
    if (isTransferring) return;
    setState(() => isTransferring = true);
    
    final success = await _bookingService.transferTicket(bookingId, _transferController.text);
    
    if (mounted) {
      setState(() => isTransferring = false);
      if (success) {
        Navigator.pop(context);
        _transferController.clear();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('transfer_success'.tr),
          backgroundColor: Colors.green,
        ));
        _refresh();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('transfer_failed'.tr),
          backgroundColor: Colors.redAccent,
        ));
      }
    }
  }

  Widget _buildOption(IconData icon, String label, VoidCallback onTap, {bool isPrimary = false}) {
    return _PremiumFeedbackWrapper(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isPrimary ? AppTheme.primary.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isPrimary ? AppTheme.primary.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.1),
          ),
          boxShadow: isPrimary ? [
            BoxShadow(
              color: AppTheme.primary.withValues(alpha: 0.05),
              blurRadius: 15,
              spreadRadius: 2,
            )
          ] : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: isPrimary ? AppTheme.primary : Colors.white70, size: 32),
            const SizedBox(height: 12),
            Text(
              label, 
              textAlign: TextAlign.center, 
              style: TextStyle(
                color: isPrimary ? Colors.white : Colors.white70, 
                fontSize: 10, 
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PremiumFeedbackWrapper extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const _PremiumFeedbackWrapper({required this.child, required this.onTap});

  @override
  State<_PremiumFeedbackWrapper> createState() => _PremiumFeedbackWrapperState();
}

class _PremiumFeedbackWrapperState extends State<_PremiumFeedbackWrapper> {
  double _scale = 1.0;

  void _onTapDown(TapDownDetails details) {
    HapticFeedback.lightImpact();
    setState(() => _scale = 0.92);
  }

  void _onTapUp(TapUpDetails details) {
    setState(() => _scale = 1.0);
    widget.onTap();
  }

  void _onTapCancel() {
    setState(() => _scale = 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

class _HolographicPainter extends CustomPainter {
  final double animationValue;
  final Color color;

  _HolographicPainter({required this.animationValue, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (color == Colors.transparent) return;

    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment(-1.0 + (animationValue * 3), -1.0),
        end: Alignment(0.0 + (animationValue * 3), 1.0),
        colors: [
          color.withValues(alpha: 0.0),
          color.withValues(alpha: 0.1),
          color.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Offset.zero & size);

    canvas.drawRect(Offset.zero & size, paint);

    // Subtle Grid Pattern
    final gridPaint = Paint()
      ..color = color.withValues(alpha: 0.02)
      ..strokeWidth = 0.5;

    for (double i = 0; i < size.width; i += 25) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), gridPaint);
    }
    for (double i = 0; i < size.height; i += 25) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), gridPaint);
    }
  }

  @override
  bool shouldRepaint(_HolographicPainter oldDelegate) =>
      oldDelegate.animationValue != animationValue;
}

class TicketShapeBorder extends ShapeBorder {
  const TicketShapeBorder();

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => getOuterPath(rect, textDirection: textDirection);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final path = Path();
    const double radius = 32;
    const double cutoutRadius = 16;
    final double cutoutY = rect.height * 0.72;

    path.moveTo(rect.left + radius, rect.top);
    path.lineTo(rect.right - radius, rect.top);
    path.quadraticBezierTo(rect.right, rect.top, rect.right, rect.top + radius);
    
    // Right cutout
    path.lineTo(rect.right, cutoutY - cutoutRadius);
    path.arcToPoint(Offset(rect.right, cutoutY + cutoutRadius), radius: const Radius.circular(cutoutRadius), clockwise: false);
    path.lineTo(rect.right, rect.bottom - radius);
    
    path.quadraticBezierTo(rect.right, rect.bottom, rect.right - radius, rect.bottom);
    path.lineTo(rect.left + radius, rect.bottom);
    path.quadraticBezierTo(rect.left, rect.bottom, rect.left, rect.bottom - radius);
    
    // Left cutout
    path.lineTo(rect.left, cutoutY + cutoutRadius);
    path.arcToPoint(Offset(rect.left, cutoutY - cutoutRadius), radius: const Radius.circular(cutoutRadius), clockwise: false);
    path.lineTo(rect.left, rect.top + radius);
    path.quadraticBezierTo(rect.left, rect.top, rect.left + radius, rect.top);
    
    path.close();
    return path;
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawPath(getOuterPath(rect, textDirection: textDirection), paint);
  }

  @override
  ShapeBorder scale(double t) => const TicketShapeBorder();
}

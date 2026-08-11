import 'package:flutter/material.dart';

import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/models/booking.dart';
import 'package:my_app/services/booking_service.dart';
import 'package:my_app/services/audit_service.dart';
// ignore: unused_import
import 'package:my_app/services/translation_service.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:my_app/services/notification_service.dart';
import 'package:my_app/services/enforcement_service.dart';
import 'package:my_app/screens/organizer_main_wrapper.dart';

class ScanEntryScreen extends StatefulWidget {
  final String? organizerId;
  final String? eventId;
  const ScanEntryScreen({super.key, this.organizerId, this.eventId});

  @override
  State<ScanEntryScreen> createState() => _ScanEntryScreenState();
}

enum ScannerMode { security, payment }

class _ScanEntryScreenState extends State<ScanEntryScreen> with WidgetsBindingObserver {
  final supabase = Supabase.instance.client;
  final _bookingService = BookingService();
  final _auditService = AuditService();
  final _enforcementService = EnforcementService();
  final _phoneC = TextEditingController();
  final MobileScannerController _cameraController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    detectionTimeoutMs: 1500,
  );

  bool _isProcessing = false;
  bool _isActionProcessing = false; // For buttons in sheets
  bool _torchOn = false;
  int _scannedToday = 0;
  int _totalCapacity = 0;
  String? _lastEventName;
  String? _lastEventId;
  String? _eventStartTime;
  String _staffName = 'Manager';

  // Permissions State
  String _staffRole = 'role_security';
  Map<String, bool> _staffPerms = {
    'can_scan': true,
    'can_cancel': false,
    'can_generate': false,
  };
  Booking? _foundBooking;
  ScannerMode _currentMode = ScannerMode.security;

  final Set<int> _sentCapMilestones = {}; // Track 90, 100 to avoid duplicates

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPermissions();
    _loadStats();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController.dispose();
    _phoneC.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _cameraController.start();
    } else if (state == AppLifecycleState.paused) {
      _cameraController.stop();
    }
  }

  Future<void> _loadPermissions() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      return;
    }

    final role = (user.userMetadata?['role']?.toString() ?? 'attendee').toLowerCase();
    if (role == 'staff') {
      final response = await supabase
          .from('staff_assignments')
          .select('role, permissions')
          .eq('staff_id', user.id)
          .maybeSingle();

      if (response != null && response['permissions'] != null) {
        setState(() {
          _staffRole = response['role'] ?? 'role_security';
          _staffPerms = Map<String, bool>.from(response['permissions']);
          _staffName = user.userMetadata?['full_name'] ?? 'Staff';
        });
      }
    } else {
      // Organizers have all perms
      setState(() {
        _staffName = user.userMetadata?['full_name'] ?? 'Organizer';
        _staffRole = 'role_manager';
        _staffPerms = {
          'can_scan': true,
          'can_cancel': true,
          'can_generate': true,
          'can_view_stats': true,
          'can_manage_guests': true,
          'can_view_logs': true,
          'can_block_guest': true,
          'can_eject_guest': true,
          'can_mark_late': true,
        };
      });
    }
  }

  Future<void> _loadStats() async {
    try {
      final effectiveUserId = widget.organizerId ?? supabase.auth.currentUser?.id;
      if (effectiveUserId == null) return;

      String eventId;
      int cap = 0;
      String title = '';
      String? timeStr;

      if (widget.eventId != null) {
        eventId = widget.eventId!;
        final eventRes = await supabase.from('events').select('title, max_capacity, date_time').eq('id', eventId).single();
        cap = eventRes['max_capacity'] as int? ?? 0;
        title = eventRes['title'] as String? ?? '';
        timeStr = eventRes['date_time'];
      } else {
        final events = await supabase
            .from('events')
            .select('id, title, max_capacity, date_time')
            .eq('organizer_id', effectiveUserId)
            .order('created_at', ascending: false)
            .limit(1);

        if (events.isEmpty) {
          return;
        }

        eventId = events[0]['id'];
        cap = events[0]['max_capacity'] as int? ?? 0;
        title = events[0]['title'] as String? ?? '';
        timeStr = events[0]['date_time'];
      }

      final usedResponse = await supabase
          .from('bookings')
          .select('num_guests')
          .eq('event_id', eventId)
          .inFilter('payment_status', ['used', 'late_accepted']);

      int usedPersons = 0;
      for (var b in usedResponse as List) {
        usedPersons += (b['num_guests'] as int? ?? 1);
      }

      if (mounted) {
        setState(() {
          _scannedToday = usedPersons;
          _totalCapacity = cap;
          _lastEventName = title;
          _lastEventId = eventId;
          
          _eventStartTime = null;
          if (timeStr != null) {
            final match = RegExp(r'(\d{1,2}:\d{2})').firstMatch(timeStr);
            _eventStartTime = match?.group(1);
          }
        });
      }
    } catch (e) {
      debugPrint('Error: $e');
    }
  }

  Future<void> _handleManualSearch() async {
    if (_phoneC.text.isEmpty) {
      return;
    }
    setState(() => _isProcessing = true);
    try {
      final response = await supabase.from('bookings').select('*, events(*)').eq('guest_phone', _phoneC.text.trim()).eq('event_id', _lastEventId ?? '').maybeSingle();
      if (response == null) {
        _showResultSheet(icon: Icons.search_off, iconColor: Colors.orange, title: 'no_booking_found'.tr, subtitle: 'check_phone_again'.tr, isSuccess: false);
      } else {
        final booking = Booking.fromMap(response);
        _processBookingResult(booking);
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _handleDetect(BarcodeCapture capture) async {
    if (_isProcessing) {
      return;
    }
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) {
      return;
    }
    final rawValue = barcodes.first.rawValue;
    if (rawValue == null) {
      return;
    }

    setState(() => _isProcessing = true);
    await _cameraController.stop();

    try {
      // More flexible search: Try to find booking by QR code within this organizer's events
      var query = supabase.from('bookings').select('*, events(*)').eq('qr_code', rawValue);
      
      // If we have a specific event, filter by it, otherwise just by organizer
      if (_lastEventId != null) {
        query = query.eq('event_id', _lastEventId!);
      } else if (widget.organizerId != null) {
        query = query.eq('events.organizer_id', widget.organizerId!);
      }

      final response = await query.maybeSingle();
      if (response == null) {
        _showResultSheet(icon: Icons.qr_code_2, iconColor: Colors.orange, title: 'qr_unknown'.tr, subtitle: 'qr_unknown_desc'.tr, isSuccess: false);
      } else {
        final booking = Booking.fromMap(response);
        await _processBookingResult(booking);
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _processBookingResult(Booking booking) async {
    // 1. BLACKLIST CHECK
    final isBlocked = await _enforcementService.isBlacklisted(
      clubId: widget.organizerId ?? '', 
      phone: booking.guestPhone, 
      userId: booking.userId
    );
    
    if (isBlocked) {
      _showResultSheet(
        icon: Icons.person_off_rounded, 
        iconColor: Colors.red, 
        title: 'access_denied'.tr, 
        subtitle: '${booking.userName}\n${'USER_BLACKLISTED'.tr}', 
        isSuccess: false, 
        booking: booking
      );
      return;
    }

    // 2. STATUS CHECK
    if (booking.paymentStatus == 'used') {
      final scanTime = booking.scannedAtSecurity != null 
          ? DateFormat('HH:mm').format(DateTime.parse(booking.scannedAtSecurity!)) 
          : 'N/A';
      _showResultSheet(
        icon: Icons.block, 
        iconColor: Colors.red, 
        title: 'used_ticket'.tr, 
        subtitle: '${booking.userName}\n${'ALREADY_SCANNED_AT'.tr}: $scanTime', 
        isSuccess: false, 
        booking: booking
      );
      return;
    } else if (booking.paymentStatus == 'ejected') {
      _showResultSheet(
        icon: Icons.gavel_rounded, 
        iconColor: Colors.purple, 
        title: 'ejected_status'.tr, 
        subtitle: '${booking.userName}\n${booking.cancellationReason ?? 'No reason provided'}', 
        isSuccess: false, 
        booking: booking
      );
      return;
    }

    // 3. TIME CHECK (Lateness)
    final delayMinutes = _calculateLateness(booking.event?.dateTime);
    final isLate = delayMinutes > 15; // 15 mins grace period

    // 4. MODE LOGIC (Automatic Update)
    if (_currentMode == ScannerMode.security) {
      bool success = true;
      Booking displayBooking = booking;
      if (!booking.securityCleared) {
        success = await _bookingService.verifySecurityClearance(booking.id);
        if (success) {
          displayBooking = booking.copyWith(securityCleared: true);
          await _auditService.logAction(
            actionType: 'SECURITY_ENTRY',
            description: 'SEC_ENTRY (Auto) | Guest: ${booking.userName} | Guests: ${booking.numGuests}',
            relatedEventId: booking.eventId,
            metadata: {'guest_id': booking.userId, 'num_guests': booking.numGuests}
          );
        }
      }
      _showResultSheet(
        icon: success ? Icons.verified_user : Icons.error_outline,
        iconColor: success ? Colors.greenAccent : Colors.redAccent,
        title: success ? 'SECURITY_CLEARED'.tr : 'ERROR'.tr,
        subtitle: '${booking.userName}\n${booking.numGuests} ${'guests_count'.tr}',
        isSuccess: false, // false hides the manual confirmation button
        booking: displayBooking,
      );
    } else {
      // Payment/Manager Mode
      if (isLate) {
        // Require manual confirmation if late
        _showResultSheet(
          icon: Icons.timer_outlined,
          iconColor: Colors.orange,
          title: 'late_entry'.tr,
          subtitle: '${booking.userName}\n${booking.numGuests} ${'guests_count'.tr}\n(+$delayMinutes min)',
          isSuccess: true, // true shows manual confirmation buttons
          booking: booking,
        );
      } else {
        // Auto confirm if not late
        bool success = await _bookingService.confirmManagerPayment(booking.id);
        if (success) {
          await _auditService.logAction(
            actionType: 'MANAGER_CHECKIN',
            description: 'MGR_CHECKIN (Auto) | Guest: ${booking.userName} | Guests: ${booking.numGuests}',
            relatedEventId: booking.eventId,
            metadata: {'guest_id': booking.userId, 'num_guests': booking.numGuests}
          );
          if (mounted) {
            setState(() {
              _scannedToday += booking.numGuests;
              try { _checkCapacityMilestones(); } catch(e) { /* ignore – synchronous helper */ }
            });
          }
        }
        _showResultSheet(
          icon: success ? Icons.check_circle_outline : Icons.error_outline,
          iconColor: success ? Colors.greenAccent : Colors.redAccent,
          title: success ? 'ENTRY_CONFIRMED'.tr : 'ERROR'.tr,
          subtitle: '${booking.userName}\n${booking.numGuests} ${'guests_count'.tr}',
          isSuccess: false,
          booking: booking,
        );
      }
    }
  }

  int _calculateLateness(String? dateTimeStr) {
    if (dateTimeStr == null) return 0;
    try {
      // Very simple parser for formats like "22:00" or "Tonight â€¢ 22:00"
      final timeMatch = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(dateTimeStr);
      if (timeMatch == null) return 0;

      final hour = int.parse(timeMatch.group(1)!);
      final minute = int.parse(timeMatch.group(2)!);

      final now = DateTime.now();
      final eventTime = DateTime(now.year, now.month, now.day, hour, minute);

      // If event time is say 10 PM and it's 2 AM next day, we might need logic.
      // But for now, pure difference on same day:
      final diff = now.difference(eventTime).inMinutes;
      return diff > 0 ? diff : 0;
    } catch (e) {
      return 0;
    }
  }

  void _showError(String m) {
    _showResultSheet(icon: Icons.error, iconColor: Colors.red, title: 'error'.tr, subtitle: m, isSuccess: false);
  }

  void _showResultSheet({required IconData icon, required Color iconColor, required String title, required String subtitle, required bool isSuccess, Booking? booking}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceContainer,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 80, color: iconColor),
            const SizedBox(height: 16),
            Text(title, style: AppTheme.headlineStyle.copyWith(fontSize: 22), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(subtitle, style: AppTheme.bodyStyle.copyWith(color: AppTheme.onSurfaceVariant), textAlign: TextAlign.center),
            
            // FOLLOWER MEMBER BADGE FOR SECURITY
            if (booking != null && (booking.discountAmount > 0 || booking.appliedPerk != null)) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [AppTheme.secondary, AppTheme.tertiary]),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: AppTheme.secondary.withValues(alpha: 0.4), blurRadius: 20)],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.verified_rounded, color: Colors.black, size: 20),
                    const SizedBox(width: 12),
                    Text('follower_member'.tr.toUpperCase(), style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 2)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              FutureBuilder<bool>(
                future: _bookingService.isVisitorFollower(booking.userId, widget.organizerId ?? ''),
                builder: (ctx, snap) {
                  final isFollower = snap.data ?? false;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: isFollower ? Colors.green.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: isFollower ? Colors.greenAccent : Colors.white12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(isFollower ? Icons.security_rounded : Icons.person_outline, color: isFollower ? Colors.greenAccent : Colors.white38, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          isFollower ? 'VERIFIED_FOLLOWER_DESC'.tr : 'STANDARD_GUEST'.tr,
                          style: TextStyle(color: isFollower ? Colors.greenAccent : Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
                        ),
                      ],
                    ),
                  );
                }
              ),
            ],

            // SECURITY CLEARANCE WARNING FOR MANAGER
            if (_currentMode == ScannerMode.payment && booking != null && !booking.securityCleared) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.15), 
                  borderRadius: BorderRadius.circular(20), 
                  border: Border.all(color: Colors.redAccent, width: 2),
                  boxShadow: [BoxShadow(color: Colors.redAccent.withValues(alpha: 0.2), blurRadius: 20)],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.gavel_rounded, color: Colors.redAccent, size: 28),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('SECURITY_PENDING_WARNING'.tr.toUpperCase(), style: const TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1)),
                          const SizedBox(height: 4),
                          Text('ASK_GUEST_TO_GO_TO_SECURITY'.tr, style: const TextStyle(color: Colors.redAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            
            const SizedBox(height: 32),
            if (isSuccess && booking != null)
              Column(
                children: [
                  ElevatedButton(
                    onPressed: _isActionProcessing ? null : () async {
                      setState(() => _isActionProcessing = true);
                      try {
                        bool success = false;
                        if (_currentMode == ScannerMode.security) {
                          success = await _bookingService.verifySecurityClearance(booking.id);
                          if (success) {
                            await _auditService.logAction(
                              actionType: 'SECURITY_ENTRY',
                              description: 'SEC_ENTRY | Guest: ${booking.userName} | Guests: ${booking.numGuests}',
                              relatedEventId: booking.eventId,
                              metadata: {'guest_id': booking.userId, 'num_guests': booking.numGuests}
                            );
                          }
                        } else {
                          success = await _bookingService.confirmManagerPayment(booking.id);
                          if (success) {
                            await _auditService.logAction(
                              actionType: 'MANAGER_CHECKIN',
                              description: 'MGR_CHECKIN | Guest: ${booking.userName} | Guests: ${booking.numGuests}',
                              relatedEventId: booking.eventId,
                              metadata: {'guest_id': booking.userId, 'num_guests': booking.numGuests}
                            );
                          }
                        }
                        
                        if (success && mounted) {
                          if (ctx.mounted) Navigator.pop(ctx);
                          _cameraController.start();
                          if (_currentMode == ScannerMode.payment) {
                            setState(() {
                              _scannedToday += booking.numGuests;
                              _checkCapacityMilestones();
                            });
                          }
                        } else if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('operation_failed'.tr), backgroundColor: Colors.redAccent),
                          );
                        }
                      } finally {
                        if (mounted) setState(() => _isActionProcessing = false);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 64), 
                      backgroundColor: _currentMode == ScannerMode.security ? AppTheme.primary : AppTheme.secondary, 
                      foregroundColor: Colors.black, 
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))
                    ),
                    child: _isActionProcessing 
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2)) 
                      : Text(
                        (_currentMode == ScannerMode.security ? 'ALLOW_ENTRY'.tr : 'CONFIRM_PAYMENT_ENTRY'.tr).toUpperCase(), 
                        style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2)
                      ),
                  ),
                  if (_staffPerms['can_mark_late'] == true && _currentMode == ScannerMode.payment) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _isActionProcessing ? null : () async {
                              setState(() => _isActionProcessing = true);
                              try {
                                final success = await _bookingService.markAsLate(booking.id);
                                if (success && mounted) {
                                  await _auditService.logAction(
                                    actionType: 'LATE_ACCEPTED', 
                                    description: 'LATE_ACC | Guest: ${booking.userName}', 
                                    relatedEventId: booking.eventId
                                  );
                                  setState(() => _scannedToday += booking.numGuests);
                                  if (ctx.mounted) Navigator.pop(ctx);
                                  _cameraController.start();
                                } else if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('operation_failed'.tr), backgroundColor: Colors.redAccent),
                                  );
                                }
                              } finally {
                                if (mounted) setState(() => _isActionProcessing = false);
                              }
                            },
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(double.infinity, 56), 
                              side: const BorderSide(color: Colors.amber, width: 2), 
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              backgroundColor: Colors.amber.withValues(alpha: 0.05),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (_isActionProcessing) 
                                  const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(color: Colors.amber, strokeWidth: 2))
                                else
                                  const Icon(Icons.timer_outlined, size: 14, color: Colors.amber),
                                const SizedBox(width: 8),
                                Text('late_accepted'.tr.toUpperCase(), style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.w900, fontSize: 10)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _isActionProcessing ? null : () async {
                              setState(() => _isActionProcessing = true);
                              try {
                                final success = await _bookingService.cancelBooking(booking.id, reason: 'reason_late'.tr);
                                if (success && mounted) {
                                  if (ctx.mounted) Navigator.pop(ctx);
                                  _cameraController.start();
                                } else if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('operation_failed'.tr), backgroundColor: Colors.redAccent),
                                  );
                                }
                              } finally {
                                if (mounted) setState(() => _isActionProcessing = false);
                              }
                            },
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(double.infinity, 56), 
                              side: const BorderSide(color: Colors.redAccent), 
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              backgroundColor: Colors.redAccent.withValues(alpha: 0.05),
                            ),
                            child: Text('late_refused'.tr.toUpperCase(), style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 10)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              )
            else
              ElevatedButton(
                onPressed: () { Navigator.pop(ctx); _cameraController.start(); },
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 56), backgroundColor: Colors.white10, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                child: Text('scan_next'.tr.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            if (booking != null && (_staffRole == 'role_manager' || _staffPerms['can_manage_guests'] == true)) ...[
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () => _showGrantPerkDialog(booking),
                icon: const Icon(Icons.stars_rounded, color: Colors.black, size: 18),
                label: Text('grant_perk'.tr.toUpperCase(), style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, letterSpacing: 1)),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 54), 
                  backgroundColor: AppTheme.secondary, 
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 2,
                  shadowColor: AppTheme.secondary.withValues(alpha: 0.3),
                ),
              ),
            ],
            const SizedBox(height: 16),
            if (booking != null && (_staffPerms['can_block_guest'] == true || _staffPerms['can_eject_guest'] == true)) ...[
              const SizedBox(height: 24),
              Row(
                children: [
                  if (_staffPerms['can_eject_guest'] == true)
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _handleEject(booking, ctx),
                        icon: const Icon(Icons.gavel_rounded, size: 18),
                        label: Text('eject_guest'.tr.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange.withValues(alpha: 0.1),
                          foregroundColor: Colors.orange,
                          minimumSize: const Size(0, 56),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.orange.withValues(alpha: 0.3))),
                        ),
                      ),
                    ),
                  if (_staffPerms['can_eject_guest'] == true && _staffPerms['can_block_guest'] == true)
                    const SizedBox(width: 12),
                  if (_staffPerms['can_block_guest'] == true)
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _handleBlock(booking, ctx),
                        icon: const Icon(Icons.person_off_rounded, size: 18),
                        label: Text('block_visitor'.tr.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent.withValues(alpha: 0.1),
                          foregroundColor: Colors.redAccent,
                          minimumSize: const Size(0, 56),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.3))),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    ).whenComplete(() { if (!_isProcessing) _cameraController.start(); });
  }

  Future<void> _handleEject(Booking booking, BuildContext ctx) async {
    setState(() => _isActionProcessing = true);
    try {
      final ok = await _enforcementService.ejectGuest(bookingId: booking.id, reason: 'reason_security'.tr);
      if (ok && mounted) {
        await _auditService.logAction(actionType: 'SECURITY_EJECT', description: 'User ${booking.userName} ejected from event.', relatedEventId: booking.eventId);
        if (ctx.mounted) Navigator.pop(ctx);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('operation_failed'.tr), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isActionProcessing = false);
    }
  }

  Future<void> _handleBlock(Booking booking, BuildContext ctx) async {
    setState(() => _isActionProcessing = true);
    try {
      final ok = await _enforcementService.addToBlacklist(clubId: widget.organizerId ?? '', phone: booking.guestPhone, userId: booking.userId, reason: 'reason_security'.tr);
      if (ok && mounted) {
        await _auditService.logAction(actionType: 'SECURITY_BLOCK', description: 'User ${booking.userName} added to permanent blacklist.', relatedEventId: booking.eventId);
        if (ctx.mounted) Navigator.pop(ctx);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('operation_failed'.tr), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isActionProcessing = false);
    }
  }




  void _showGrantPerkDialog(Booking booking) {
    final perkC = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceContainer,
        title: Text('GRANT SPECIAL PERK'.tr, style: const TextStyle(color: AppTheme.secondary)),
        content: TextField(
          controller: perkC,
          decoration: InputDecoration(hintText: 'Enter perk description...', hintStyle: const TextStyle(color: Colors.white24)),
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('cancel'.tr, style: const TextStyle(color: Colors.white24))),
          ElevatedButton(
            onPressed: () async {
              final ok = await _bookingService.grantManualPerk(booking.id, perkC.text.trim(), managerId: supabase.auth.currentUser?.id);
              if (ok && mounted) {
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) Navigator.pop(context); // Close result sheet
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('perk_granted_success'.tr)));
              } else if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('operation_failed'.tr), backgroundColor: Colors.redAccent),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.secondary, foregroundColor: Colors.black),
            child: Text('confirm'.tr),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmFoundEntry() async {
    if (_foundBooking == null) return;
    
    setState(() => _isActionProcessing = true);
    try {
      bool ok = false;
      if (_currentMode == ScannerMode.security) {
        ok = await _bookingService.verifySecurityClearance(_foundBooking!.id);
      } else {
        ok = await _bookingService.confirmManagerPayment(_foundBooking!.id);
      }

      if (ok) {
          final isManual = _foundBooking!.ticketType == 'Manual';
          final passId = (_foundBooking!.id.hashCode.abs() % 10000).toString().padLeft(4, '0');
          
          await _auditService.logAction(
            actionType: _currentMode == ScannerMode.security ? 'SECURITY_PHONE_CLEAR' : 'MANAGER_PHONE_PAY',
            description: isManual 
                ? 'Manual Pass | ID: $passId | Mode: $_currentMode'
                : 'Phone Entry | ID: $passId | Mode: $_currentMode',
            relatedEventId: _lastEventId,
          );
          
          if (!mounted) return;
          setState(() {
            if (_currentMode == ScannerMode.payment) {
              _scannedToday += _foundBooking!.numGuests;
            }
            _foundBooking = null;
            _phoneC.clear();
          });
          _showResultSheet(icon: Icons.check_circle, iconColor: Colors.greenAccent, title: 'SUCCESS'.tr, subtitle: 'ACTION_COMPLETED'.tr, isSuccess: false);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('operation_failed'.tr), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isActionProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background.withValues(alpha: 0.9),
        elevation: 0,
        title: Text(_currentMode == ScannerMode.security ? 'SECURITY_MODE'.tr : 'MANAGER_MODE'.tr, 
                    style: const TextStyle(letterSpacing: 1, fontWeight: FontWeight.w900, fontSize: 13, color: Colors.white70)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Row(
              children: [
                _modeTab(ScannerMode.security, Icons.shield_outlined, 'SECURITY'.tr),
                const SizedBox(width: 12),
                _modeTab(ScannerMode.payment, Icons.payments_outlined, 'MANAGER'.tr),
              ],
            ),
          ),
        ),
        actions: [
        IconButton(
          icon: Icon(_torchOn ? Icons.flashlight_on : Icons.flashlight_off, color: _torchOn ? AppTheme.secondary : Colors.white24),
          onPressed: () { _cameraController.toggleTorch(); setState(() => _torchOn = !_torchOn); },
        ),
        if (_foundBooking != null)
           IconButton(icon: const Icon(Icons.close, color: Colors.white24), onPressed: () => setState(() => _foundBooking = null)),
        if ((_staffRole == 'role_manager' || supabase.auth.currentUser?.id == widget.organizerId) && _staffPerms['can_generate'] == true && _foundBooking == null)
          IconButton(
            icon: const Icon(Icons.person_add_alt_1, color: AppTheme.primary),
            onPressed: _showManualEntryDialog,
          ),
      ],
      ),
      body: _foundBooking != null ? _buildFoundBookingView() : _buildBody(),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.white.withValues(alpha: 0.05),
        elevation: 0,
        onPressed: () => OrganizerMainWrapper.of(context)?.setIndex(1),
        child: const Icon(Icons.exit_to_app_rounded, color: Colors.white, size: 28),
      ),
    );
  }

  Widget _modeTab(ScannerMode mode, IconData icon, String label) {
    bool sel = _currentMode == mode;
    final isSecurity = _staffRole == 'role_security';
    final isManager = _staffRole == 'role_manager' || supabase.auth.currentUser?.id == widget.organizerId;
    
    // TACTICAL LOCKING: Enforcement of roles
    bool isLocked = (mode == ScannerMode.security && !isSecurity && !isManager) || 
                    (mode == ScannerMode.payment && !isManager);

    return Expanded(
      child: GestureDetector(
        onTap: isLocked ? null : () => setState(() => _currentMode = mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          height: 44,
          decoration: BoxDecoration(
            color: sel ? (mode == ScannerMode.security ? AppTheme.primary : AppTheme.secondary).withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: sel ? (mode == ScannerMode.security ? AppTheme.primary : AppTheme.secondary) : Colors.transparent),
          ),
          child: Opacity(
            opacity: isLocked ? 0.3 : 1.0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: sel ? (mode == ScannerMode.security ? AppTheme.primary : AppTheme.secondary) : Colors.white24, size: 16),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(color: sel ? (mode == ScannerMode.security ? AppTheme.primary : AppTheme.secondary) : Colors.white24, fontWeight: FontWeight.w900, fontSize: 10)),
              if (isLocked) ...[
                const SizedBox(width: 4),
                const Icon(Icons.lock_outline, size: 10, color: Colors.white24),
              ],
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildStaffHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Icon(
            _staffRole == 'role_manager' ? Icons.admin_panel_settings : Icons.shield_rounded,
            color: _staffRole == 'role_manager' ? AppTheme.secondary : AppTheme.primary,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _staffName.toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
                ),
                Text(
                  _staffRole.tr.toUpperCase(),
                  style: TextStyle(color: _staffRole == 'role_manager' ? AppTheme.secondary : AppTheme.primary, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
            child: Text('VERIFIED'.tr, style: const TextStyle(color: Colors.greenAccent, fontSize: 8, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final occupancy = _totalCapacity > 0 ? (_scannedToday / _totalCapacity) : 0.0;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStaffHeader(),
          const SizedBox(height: 24),
          // LIVE OCCUPANCY GLANCE
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surfaceContainer,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('LIVE OCCUPANCY'.tr, style: const TextStyle(color: Colors.white24, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 2)),
                    Text('${(occupancy * 100).toInt()}%', style: TextStyle(color: occupancy > 0.9 ? Colors.redAccent : AppTheme.primary, fontSize: 10, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: occupancy,
                    minHeight: 6,
                    backgroundColor: Colors.white.withValues(alpha: 0.05),
                    color: occupancy > 0.9 ? Colors.redAccent : (occupancy > 0.7 ? Colors.orange : AppTheme.primary),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _miniStat('IN'.tr, '$_scannedToday', AppTheme.primary),
                    _miniStat('CAP'.tr, '$_totalCapacity', Colors.white24),
                    _miniStat('LEFT'.tr, '${_totalCapacity - _scannedToday}', AppTheme.secondary),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Text(_lastEventName ?? 'loading'.tr, style: AppTheme.headlineStyle.copyWith(fontSize: 24)),
          const SizedBox(height: 24),
          _buildScannerFrame(),
          const SizedBox(height: 24),
          _buildManualInput(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 16)),
        Text(label, style: const TextStyle(color: Colors.white10, fontSize: 8, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildFoundBookingView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: const Color(0xFF141414),
            borderRadius: BorderRadius.circular(40),
            border: Border.all(color: AppTheme.primary.withValues(alpha: 0.1)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_foundBooking!.ticketType == 'Manual' ? 'SERIAL_ID_LAST_4'.tr : 'PASS_ID'.tr, style: TextStyle(color: AppTheme.primary.withValues(alpha: 0.5), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 4)),
              Text(
                _foundBooking!.ticketType == 'Manual' 
                  ? _foundBooking!.qrCode.substring(_foundBooking!.qrCode.length - 4) 
                  : (_foundBooking!.id.hashCode.abs() % 10000).toString().padLeft(4, '0'), 
                style: AppTheme.headlineStyle.copyWith(
                  fontSize: 64, 
                  color: AppTheme.primary, 
                  letterSpacing: 12
                )
              ),
              if (_foundBooking!.ticketType == 'Manual')
                Text('${'FULL_SN'.tr}: ${_foundBooking!.qrCode}', style: const TextStyle(color: Colors.white24, fontSize: 10, letterSpacing: 1)),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
                child: QrImageView(data: _foundBooking!.qrCode, version: QrVersions.auto, size: 120, eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black), dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.black)),
              ),
              const SizedBox(height: 12),
              Text(_foundBooking!.guestPhone?.toUpperCase() ?? 'NO_PHONE'.tr, style: const TextStyle(color: Colors.white38, fontSize: 14, letterSpacing: 2, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              const Divider(color: Colors.white10),
              const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_lastEventName ?? '...', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                            if (_lastEventId != null)
                              StreamBuilder(
                                stream: Stream.periodic(const Duration(seconds: 1)),
                                builder: (context, snapshot) {
                                  return Text(
                                    DateTime.now().toIso8601String().substring(11, 16),
                                    style: TextStyle(color: AppTheme.primary.withValues(alpha: 0.8), fontSize: 12, fontWeight: FontWeight.bold),
                                  );
                                }
                              ),
                          ],
                        ),
                        if (_lastEventId != null)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(16)),
                            child: Column(
                              children: [
                                Text('start_time'.tr.toUpperCase(), style: const TextStyle(color: Colors.white38, fontSize: 8, letterSpacing: 1)),
                                Text(_eventStartTime ?? '--:--', style: const TextStyle(color: AppTheme.secondary, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                      ],
                    ),
              const SizedBox(height: 48),
              Text(_foundBooking!.userName.toUpperCase(), style: AppTheme.headlineStyle.copyWith(fontSize: 22)),
              const SizedBox(height: 8),
              if (_foundBooking!.appliedPerk != null && _foundBooking!.appliedPerk!.isNotEmpty)
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFE65C00), Color(0xFFF9D423)], // Glowing gold/orange
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFE65C00).withValues(alpha: 0.5),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.card_giftcard_rounded, color: Colors.black, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('🎁 قَدِّمْ لَهُ هَدِيَّةً 🎁', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1)),
                            const SizedBox(height: 4),
                            Text(_foundBooking!.appliedPerk!.toUpperCase(), style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              Text('${_foundBooking!.numGuests} ${'guests_label'.tr.toUpperCase()}', style: const TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 48),
              ElevatedButton(
                onPressed: _confirmFoundEntry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.black,
                  minimumSize: const Size(double.infinity, 64),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: _isActionProcessing
                  ? const CircularProgressIndicator(color: Colors.black)
                  : Text('confirm_entry'.tr.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
              ),
              const SizedBox(height: 16),
              TextButton(onPressed: () => setState(() => _foundBooking = null), child: Text('back_to_scan'.tr.toUpperCase(), style: const TextStyle(color: Colors.white24, fontSize: 10))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScannerFrame() {
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(32), border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2), width: 2)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: Stack(
            children: [
              MobileScanner(controller: _cameraController, onDetect: _handleDetect),
              if (_isProcessing) Container(color: Colors.black87, child: const Center(child: CircularProgressIndicator(color: AppTheme.primary))),
              _buildScannerOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScannerOverlay() {
    return Center(
      child: SizedBox(
        width: 220,
        height: 220,
        child: Stack(
          children: [
            // Corners
            Positioned(top: 0, left: 0, child: _hudCorner(topLeft: true)),
            Positioned(top: 0, right: 0, child: _hudCorner(topRight: true)),
            Positioned(bottom: 0, left: 0, child: _hudCorner(bottomLeft: true)),
            Positioned(bottom: 0, right: 0, child: _hudCorner(bottomRight: true)),
            
            // Target Lines (Crosshairs)
            Center(
              child: Container(
                width: 1,
                height: 30,
                color: AppTheme.primary.withValues(alpha: 0.3),
              ),
            ),
            Center(
              child: Container(
                width: 30,
                height: 1,
                color: AppTheme.primary.withValues(alpha: 0.3),
              ),
            ),
            
            // Subtle Inner Box
            Center(
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  border: Border.all(color: AppTheme.primary.withValues(alpha: 0.1), width: 1),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            
            // Scanning Line Effect
            Center(
              child: Container(
                width: 180,
                height: 2,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primary.withValues(alpha: 0),
                      AppTheme.primary,
                      AppTheme.primary.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hudCorner({bool topLeft = false, bool topRight = false, bool bottomLeft = false, bool bottomRight = false}) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        border: Border(
          top: (topLeft || topRight) ? const BorderSide(color: AppTheme.primary, width: 3) : BorderSide.none,
          bottom: (bottomLeft || bottomRight) ? const BorderSide(color: AppTheme.primary, width: 3) : BorderSide.none,
          left: (topLeft || bottomLeft) ? const BorderSide(color: AppTheme.primary, width: 3) : BorderSide.none,
          right: (topRight || bottomRight) ? const BorderSide(color: AppTheme.primary, width: 3) : BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildManualInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: AppTheme.surfaceContainer, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Expanded(child: TextField(controller: _phoneC, style: const TextStyle(color: Colors.white), keyboardType: TextInputType.phone, decoration: InputDecoration(hintText: 'phone_number'.tr, hintStyle: const TextStyle(color: Colors.white24), border: InputBorder.none))),
          IconButton(onPressed: _handleManualSearch, icon: const Icon(Icons.search, color: AppTheme.primary)),
        ],
      ),
    );
  }



  void _showManualEntryDialog() {
    int guests = 1;

    bool isConfirming = false;
    
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) => AlertDialog(
          backgroundColor: AppTheme.surfaceContainer,
          title: Text(isConfirming ? 'confirm_action'.tr : 'manual_ticket_btn'.tr, style: AppTheme.headlineStyle.copyWith(fontSize: 18, color: isConfirming ? AppTheme.secondary : Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(isConfirming ? 'confirm_manual_issuance'.tr : 'instant_ticket_desc'.tr, style: TextStyle(color: isConfirming ? Colors.white : Colors.white54, fontSize: 13, fontWeight: isConfirming ? FontWeight.bold : FontWeight.normal)),
              const SizedBox(height: 24),
              if (!isConfirming)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('guests_count'.tr, style: const TextStyle(color: Colors.white70)),
                    Row(
                      children: [
                        IconButton(icon: const Icon(Icons.remove, color: Colors.white24), onPressed: guests > 1 ? () => setLocalState(() => guests--) : null),
                        Text('$guests', style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 18)),
                        IconButton(icon: const Icon(Icons.add, color: AppTheme.primary), onPressed: () => setLocalState(() => guests++)),
                      ],
                    ),
                  ],
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                  decoration: BoxDecoration(color: AppTheme.secondary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.secondary.withValues(alpha: 0.3))),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.people_alt, color: AppTheme.secondary, size: 20),
                      const SizedBox(width: 12),
                      Text('$guests ${'guests_label'.tr}', style: const TextStyle(color: AppTheme.secondary, fontWeight: FontWeight.bold, fontSize: 18)),
                    ],
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('cancel'.tr, style: const TextStyle(color: Colors.white24))),
            ElevatedButton(
              onPressed: _isActionProcessing ? null : () async {
                if (!isConfirming) {
                  setLocalState(() => isConfirming = true);
                  return;
                }

                if (_lastEventId == null) return;
                
                setState(() => _isActionProcessing = true);
                try {
                  final booking = await _bookingService.createManualBooking(
                    eventId: _lastEventId!,
                    guestName: '',
                    guestPhone: '',
                    numGuests: guests,
                  );
                  
                  if (booking != null && mounted) {
                    final ok = await _bookingService.markAsUsed(booking.id);
                    if (ok) {
                      final passId = (booking.id.hashCode.abs() % 10000).toString().padLeft(4, '0');
                      await _auditService.logAction(
                        actionType: 'MANUAL_TICKET',
                        description: 'INSTANT TICKET | SN: ${booking.qrCode} | PASS: $passId | Guests: ${booking.numGuests}',
                        relatedEventId: _lastEventId,
                      );
                      
                      if (mounted) {
                        setState(() {
                          _scannedToday += booking.numGuests;
                        });
                      }
                    }

                    if (mounted) {
                      if (ctx.mounted) Navigator.pop(ctx);
                      _showResultSheet(
                        icon: Icons.check_circle, 
                        iconColor: Colors.greenAccent, 
                        title: 'ticket_issued'.tr, 
                        subtitle: 'manual_entry_success_desc'.trArgs([booking.qrCode.substring(booking.qrCode.length - 4)]), 
                        isSuccess: true
                      );
                    }
                  } else if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('operation_failed'.tr), backgroundColor: Colors.redAccent),
                    );
                  }
                } finally {
                  if (mounted) setState(() => _isActionProcessing = false);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: isConfirming ? AppTheme.secondary : AppTheme.primary, 
                foregroundColor: Colors.black,
                minimumSize: const Size(120, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
              ),
              child: _isActionProcessing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                : Text(isConfirming ? 'confirm_are_you_sure'.tr : 'confirm'.tr, style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _checkCapacityMilestones() async {
    if (_totalCapacity <= 0 || _lastEventId == null) return;
    
    final percentage = (_scannedToday / _totalCapacity) * 100;
    
    if (percentage >= 100 && !_sentCapMilestones.contains(100)) {
      _sendCapacityAlert('Event Full!'.tr, 'Capacity has reached 100% ($_scannedToday/$_totalCapacity)'.tr, 100);
    } else if (percentage >= 90 && !_sentCapMilestones.contains(90)) {
      _sendCapacityAlert('Warning: Capacity 90%'.tr, 'Crowd alert: $_scannedToday/$_totalCapacity entered.'.tr, 90);
    }
  }

  void _sendCapacityAlert(String title, String body, int milestone) async {
    final organizerId = widget.organizerId ?? supabase.auth.currentUser?.id;
    if (organizerId == null) return;

    await NotificationService().sendNotificationToUser(
      userId: organizerId,
      title: title,
      body: body,
      type: 'alert',
      metadata: {'event_id': _lastEventId, 'milestone': milestone},
    );
    _sentCapMilestones.add(milestone);
  }
}

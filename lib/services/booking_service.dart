import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:my_app/services/audit_service.dart';
import 'package:my_app/services/notification_service.dart';
import 'package:my_app/services/event_service.dart';
import 'package:my_app/services/follow_service.dart';
import 'package:my_app/services/translation_service.dart';
import 'package:my_app/models/booking.dart';

class BookingService {
  final supabase = Supabase.instance.client;
  final _audit = AuditService();
  final _notifications = NotificationService();
  final _followService = FollowService();

  /// Check if the current user already has a booking for this event.
  Future<Booking?> getBookingForEvent(String eventId) async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return null;

      final response = await supabase
          .from('bookings')
          .select('*, events(*)')
          .eq('event_id', eventId)
          .eq('user_id', userId)
          .neq('payment_status', 'cancelled')
          .maybeSingle();

      if (response == null) return null;
      return Booking.fromMap(response);
    } catch (e) {
      return null;
    }
  }

  /// Returns total persons attending (sum of num_guests) for a given event.
  Future<int> getTotalPersonsForEvent(String eventId) async {
    try {
      final response = await supabase
          .from('bookings')
          .select('num_guests')
          .eq('event_id', eventId)
          .not('payment_status', 'eq', 'cancelled');

      final list = response as List;
      int total = 0;
      for (var row in list) {
        total += (row['num_guests'] as int? ?? 1);
      }
      return total;
    } catch (e) {
      return 0;
    }
  }

  /// Returns count of scanned (used) persons for an event.
  Future<int> getScannedCountForEvent(String eventId) async {
    try {
      final response = await supabase
          .from('bookings')
          .select('num_guests')
          .eq('event_id', eventId)
          .inFilter('payment_status', ['used', 'late_accepted']);

      final list = response as List;
      int total = 0;
      for (var row in list) {
        total += (row['num_guests'] as int? ?? 1);
      }
      return total;
    } catch (e) {
      return 0;
    }
  }

  String _generateTacticalSerial(String prefix) {
    final now = DateTime.now();
    final random = Random.secure();
    // 8-character random hex
    final randomHex = List.generate(8, (_) => random.nextInt(16).toRadixString(16)).join().toUpperCase();
    final rawUserId = supabase.auth.currentUser?.id ?? '0000';
    final userId = rawUserId.length >= 4 ? rawUserId.substring(0, 4) : rawUserId.padRight(4, '0');
    final timestamp = now.millisecondsSinceEpoch.toString().substring(8);
    return '$prefix-$userId-$timestamp-$randomHex';
  }

  /// Organizer/Staff: Create a manual ticket for an on-site guest.
  Future<Booking?> createManualBooking({
    required String eventId,
    String? guestName,
    String? guestPhone,
    int numGuests = 1,
  }) async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return null;

      String finalName = guestName?.trim() ?? '';
      String finalPhone = guestPhone?.trim() ?? 'Walk-in';

      if (finalName.isEmpty && finalPhone != 'Walk-in') {
        final suffix = finalPhone.length >= 4
            ? finalPhone.substring(finalPhone.length - 4)
            : finalPhone;
        finalName = 'Guest-$suffix';
      } else if (finalName.isEmpty) {
        finalName = 'WALKIN_GUEST'.tr;
      }

      final serial = _generateTacticalSerial('GEN');

      final response = await supabase
          .from('bookings')
          .insert({
            'event_id': eventId,
            'user_id': user.id,
            'user_name': finalName,
            'ticket_type': 'Manual',
            'num_guests': numGuests,
            'payment_status': 'confirmed',
            'qr_code': serial,
            'pass_id': serial,
            'guest_phone': finalPhone,
            'created_by': user.id,
            'is_walkin': true,
            'walkin_serial': serial,
            'security_cleared': true,
            'scanned_at_security': DateTime.now().toIso8601String(),
          })
          .select('*, events(*)')
          .single();

      final result = Booking.fromMap(response);

      await _audit.logAction(
        actionType: 'GEN_TICKET_ISSUED',
        description: 'Direct Issuance: $serial created for ${result.userName}',
        relatedEventId: eventId,
      );

      await _scheduleEventReminders(result);
      return result;
    } catch (e) {
      return null;
    }
  }

  Future<Booking?> createBooking({
    required String eventId,
    int numGuests = 1,
    String ticketType = 'General',
    String paymentStatus = 'pending',
    String? guestPhone,
    int? maxCapacity,
    double? totalPricePaid,
  }) async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return null;

      final EventService evs = EventService();
      final event = await evs.getEventById(eventId);
      if (event == null) return null;

      double appliedDiscount = 0.0;
      String? appliedPerk;
      final bool hasUniversalPromo = (event.promoDiscount > 0 || event.promoValue != null);
      if (hasUniversalPromo && (event.promoLimit == 0 || event.promoClaimCount < event.promoLimit)) {
        appliedDiscount = event.promoDiscount;
        appliedPerk = event.promoValue;

        if (event.promoLimit > 0) {
          await supabase.from('events').update({'promo_claim_count': event.promoClaimCount + 1}).eq('id', eventId);
        }
      }

      if (appliedDiscount == 0 && appliedPerk == null && event.organizerId != null) {
        final isFollower = await _followService.isFollowing(event.organizerId!);
        if (isFollower) {
          if (event.followerDiscount > 0) {
            appliedDiscount = (event.price * event.followerDiscount / 100);
          }
          if (event.followerPerk != null) appliedPerk = event.followerPerk;
        }
      }

      // Loyalty Logic: Check if user attended 3 events
      final usedBookingsRes = await supabase
          .from('bookings')
          .select('id')
          .eq('user_id', userId)
          .eq('payment_status', 'used')
          .count(CountOption.exact);
      final usedCount = usedBookingsRes.count;

      bool wonReward = false;
      String? rewardText;
      
      // Tiered Loyalty Progression: 1st, 3rd, 7th, 12th bookings
      final milestones = {
        1: 'مشروب ترحيبي مجاني 🍹',
        3: 'وجبة خفيفة مجانية 🍔',
        7: 'دخول مجاني لفعالية قادمة 🎟️',
        12: 'ترقية مجانية للـ VIP 🌟',
      };
      
      final currentAttempt = usedCount + 1;
      if (milestones.containsKey(currentAttempt)) {
        wonReward = true;
        rewardText = milestones[currentAttempt];
        appliedPerk = (appliedPerk != null) ? '$appliedPerk + $rewardText' : rewardText;
      }

      final existing = await getBookingForEvent(eventId);
      if (existing != null) return existing;

      int totalPersons = await getTotalPersonsForEvent(eventId);
      if (maxCapacity != null && maxCapacity > 0) {
        if (totalPersons + numGuests > maxCapacity) return null;
      }

      if (event.hasEarlyBirdRewards && appliedPerk == null) {
        final limit = maxCapacity != null ? (maxCapacity * 0.2).round().clamp(10, 100) : 25;
        if (totalPersons < limit) {
          appliedPerk = 'early_bird_advantage'.tr;
          if (appliedDiscount == 0 && event.price > 0) {
            appliedDiscount = (event.price * 0.1);
          }
        }
      }

      final serial = _generateTacticalSerial('RES');
      final userName = supabase.auth.currentUser?.userMetadata?['full_name'] ?? 'Attendee';

      String finalStatus = paymentStatus;
      if (event.requireCallConfirmation) {
        finalStatus = 'pending_confirmation';
      } else if (event.price > 0 && !event.payAtDoor) {
        // 🔒 أمنياً: أي فعالية مدفوعة عبر الإنترنت يجب أن تبدأ بحالة 'pending' للتحقق من الدفع عبر الـ Webhook
        finalStatus = 'pending';
      } else if (event.payAtDoor || event.price == 0) {
        finalStatus = 'confirmed';
      }

      final double totalOriginal = (event.price * numGuests);
      final double finalPrice = totalPricePaid ?? (totalOriginal - appliedDiscount).clamp(0, 999999).toDouble();

      final response = await supabase
          .from('bookings')
          .insert({
            'event_id': eventId,
            'user_id': userId,
            'user_name': userName,
            'num_guests': numGuests,
            'ticket_type': ticketType,
            'payment_status': finalStatus,
            'qr_code': serial,
            'pass_id': serial,
            'guest_phone': guestPhone,
            'applied_perk': appliedPerk,
            'discount_amount': appliedDiscount,
            'total_price_paid': finalPrice,
          })
          .select('*, events(*)')
          .single();

      final result = Booking.fromMap(response);

      if (wonReward) {
        await _notifications.sendNotificationToUser(
          userId: userId,
          title: '🎉 مبروك! مكافأة المستوى 🎉',
          body: 'لقد وصلت للحجز رقم $currentAttempt! حصلت على $rewardText في تذكرتك الحالية!',
          type: 'loyalty_reward',
        );
      }

      await _audit.logAction(
        actionType: 'BOOKING_CREATED',
        description: 'New digital booking by ${result.userName} (${result.numGuests} guests)',
        relatedEventId: eventId,
      );

      if (result.paymentStatus == 'confirmed') {
        await _scheduleEventReminders(result);
      }

      if (result.event?.organizerId != null) {
        final bool isPendingConf = result.paymentStatus == 'pending_confirmation';
        await _notifications.sendNotificationToUser( 
          userId: result.event!.organizerId!,
          title: isPendingConf ? 'BOOKING_ACTION_REQUIRED'.tr : 'New Booking!'.tr,
          body: isPendingConf 
              ? 'BOOKING_PENDING_CALL_BODY'.trArgs([result.userName])
              : '${result.userName} just booked for ${result.event?.title}'.tr,
          type: 'booking',
          metadata: {'booking_id': result.id, 'event_id': eventId},
        );

        // Motivational Milestone
        if (maxCapacity != null && maxCapacity > 0) {
          final double ratio = (totalPersons + numGuests) / maxCapacity;
          final double oldRatio = totalPersons / maxCapacity;
          if ((ratio >= 0.5 && oldRatio < 0.5) || (ratio >= 0.9 && oldRatio < 0.9) || (ratio >= 1.0 && oldRatio < 1.0)) {
            await _notifications.sendNotificationToUser(
              userId: result.event!.organizerId!,
              title: 'EVENT_MILESTONE'.tr,
              body: 'MILESTONE_BODY'.trArgs([(ratio * 100).toInt().toString(), result.event!.title]),
              type: 'milestone',
            );
          }
        }
      }

      return result;
    } catch (e) {
      return null;
    }
  }

  Future<bool> updateBooking(String bookingId, int newCount) async {
    try {
      if (newCount < 1 || newCount > 10) return false;
      await supabase.from('bookings').update({'num_guests': newCount}).eq('id', bookingId);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> transferTicket(String bookingId, String targetPhone) async {
    try {
      final fromUser = supabase.auth.currentUser;
      if (fromUser == null) return false;

      final targetUser = await supabase
          .from('profiles')
          .select('id, full_name')
          .eq('phone', targetPhone.trim())
          .maybeSingle();

      if (targetUser == null || targetUser['id'] == fromUser.id) return false;
      final String toId = targetUser['id'];
      
      final response = await supabase
          .from('bookings')
          .update({'user_id': toId, 'user_name': targetUser['full_name']})
          .eq('id', bookingId)
          .select('events(title)')
          .single();
      
      final String eventTitle = response['events']?['title'] ?? 'Event';

      await _notifications.sendNotificationToUser(
        userId: toId,
        title: 'TICKET_RECEIVED_TITLE'.tr,
        body: 'TICKET_RECEIVED_BODY'.trArgs([eventTitle]),
        type: 'booking',
      );

      await _audit.logAction(
        actionType: 'TICKET_TRANSFERRED',
        description: 'Ticket $bookingId moved from ${fromUser.id} to $toId',
      );

      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> updateBookingStatus(String bookingId, String status, {String? staffId, String? eventId, String? reason}) async {
    try {
      final Map<String, dynamic> updateData = {
        'payment_status': status,
      };
      if (reason != null) updateData['cancellation_reason'] = reason;

      final response = await supabase
          .from('bookings')
          .update(updateData)
          .eq('id', bookingId)
          .select('user_id, user_name, events(title)')
          .single();

      final String guestId = response['user_id'];
      final String guestName = response['user_name'] ?? 'Attendee';
      final String eventTitle = response['events']?['title'] ?? 'Event';

      await _notifyBookingGuest(guestId, status, eventTitle);

      await _audit.logAction(
        actionType: 'STATUS_UPDATE',
        description: '$status confirmation for $guestName'.toUpperCase(),
        relatedEventId: eventId,
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> approveRequest(String bookingId, {String? staffId, String? eventId}) async {
    final success = await updateBookingStatus(bookingId, 'confirmed', staffId: staffId, eventId: eventId);
    if (success) {
      final b = await supabase.from('bookings').select('*, events(*)').eq('id', bookingId).single();
      await _scheduleEventReminders(Booking.fromMap(b));
    }
    return success;
  }

  Future<void> _scheduleEventReminders(Booking result) async {
    // dateTime is checked for robustness
    final eventTimeStr = result.event?.dateTime;
    if (eventTimeStr == null) return;

    try {
      final eventDate = DateTime.parse(eventTimeStr);
      final now = DateTime.now();

      final reminderDate12 = eventDate.subtract(const Duration(hours: 12));
      if (reminderDate12.isAfter(now)) {
        await NotificationService.scheduleReminder(
          id: result.id.hashCode,
          title: 'REMINDER_12H_TITLE'.trArgs([result.event!.title]),
          body: 'REMINDER_12H_BODY'.tr,
          scheduledDate: reminderDate12,
        );
      }

      final reminderDate3 = eventDate.subtract(const Duration(hours: 3));
      if (reminderDate3.isAfter(now)) {
        await NotificationService.scheduleReminder(
          id: result.id.hashCode + 1,
          title: 'REMINDER_3H_TITLE'.trArgs([result.event!.title]),
          body: 'REMINDER_3H_BODY'.tr,
          scheduledDate: reminderDate3,
        );
      }
    } catch (_) {}
  }

  Future<bool> declineRequest(String bookingId, {String? staffId, String? eventId, String? reason}) async {
    return updateBookingStatus(bookingId, 'cancelled', staffId: staffId, eventId: eventId, reason: reason);
  }

  Future<void> _notifyBookingGuest(String userId, String status, String eventTitle) async {
    String title = '';
    String body = '';

    try {
      String guestName = ' زائر ';
      if (status == 'used' || status == 'late_accepted') {
        final userData = await supabase.from('profiles').select('full_name').eq('id', userId).maybeSingle();
        if (userData != null) guestName = userData['full_name'];
      }

      switch (status) {
        case 'confirmed':
          title = 'TICKET_APPROVED'.tr;
          body = 'secured_spot_desc'.trArgs([eventTitle]);
          break;
        case 'pending_confirmation':
          title = 'BOOKING_PENDING_CALL'.tr;
          body = 'call_required_desc'.trArgs([eventTitle]);
          break;
        case 'cancelled':
          title = 'TICKET_REJECTED'.tr;
          body = 'declined_notice_body'.trArgs([eventTitle]);
          break;
        case 'used':
        case 'late_accepted':
          title = 'welcome_visitor_title'.trArgs([guestName]);
          body = 'welcome_visitor_body'.trArgs([eventTitle]);
          break;
      }

      if (title.isNotEmpty) {
        await _notifications.sendNotificationToUser(
          userId: userId,
          title: title,
          body: body,
          type: 'booking',
        );
      }
    } catch (_) {}
  }

  Future<void> _notifyOrganizerOfArrival(String organizerId, String guestName, String eventTitle, bool isFollower) async {
    try {
      final String prefix = isFollower ? '💎 VIP FOLLOWED' : '👤 VISITOR';
      
      // Notify Organizer
      await _notifications.sendNotificationToUser(
        userId: organizerId,
        title: '$prefix ARRIVED'.tr,
        body: '$guestName ${'has_arrived_at'.tr} $eventTitle',
        type: 'presence',
        metadata: {'guest_name': guestName, 'is_vip': isFollower},
      );

      // Notify Staff (Managers and Security)
      final staffRes = await supabase
          .from('staff_assignments')
          .select('staff_id')
          .eq('organizer_id', organizerId)
          .eq('status', 'active')
          .neq('staff_id', organizerId);
      
      final staffList = staffRes as List;
      for (var staff in staffList) {
        final String staffId = staff['staff_id'];
        await _notifications.sendNotificationToUser(
          userId: staffId,
          title: '$prefix ARRIVED'.tr,
          body: '$guestName ${'has_arrived_at'.tr} $eventTitle',
          type: 'presence',
          metadata: {'guest_name': guestName, 'is_vip': isFollower},
        );
      }
    } catch (_) {}
  }

  Future<bool> markAsUsed(String bookingId, {String? tableNumber}) async {
    try {
      final response = await supabase
          .from('bookings')
          .update({
            'payment_status': 'used',
            'scanned_at': DateTime.now().toIso8601String(),
            'table_number': tableNumber,
          })
          .eq('id', bookingId)
          .select('user_id, events(title, organizer_id)')
          .single();

      final String guestId = response['user_id'];
      final String eventTitle = response['events']?['title'] ?? 'Event';
      final String? organizerId = response['events']?['organizer_id'];

      await _notifyBookingGuest(guestId, 'used', eventTitle);

      if (organizerId != null) {
        final isFollower = await _followService.isFollowing(organizerId, userId: guestId);
        final userData = await supabase.from('profiles').select('full_name').eq('id', guestId).maybeSingle();
        final guestName = userData?['full_name'] ?? 'Visitor';
        await _notifyOrganizerOfArrival(organizerId, guestName, eventTitle, isFollower);
      }

      await _audit.logAction(
        actionType: 'TICKET_SCANNED',
        description: 'Guest checked in successfully',
        relatedEventId: response['events']?['id'],
      );

      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> markAsLate(String bookingId) async {
    try {
      final response = await supabase
          .from('bookings')
          .update({
            'payment_status': 'late_accepted',
            'scanned_at': DateTime.now().toIso8601String(),
          })
          .eq('id', bookingId)
          .select('user_id, events(title, organizer_id)')
          .single();

      final String guestId = response['user_id'];
      final String eventTitle = response['events']?['title'] ?? 'Event';
      final String? organizerId = response['events']?['organizer_id'];

      await _notifyBookingGuest(guestId, 'late_accepted', eventTitle);

      if (organizerId != null) {
        final isFollower = await _followService.isFollowing(organizerId, userId: guestId);
        final userData = await supabase.from('profiles').select('full_name').eq('id', guestId).maybeSingle();
        final guestName = userData?['full_name'] ?? 'Visitor';
        await _notifyOrganizerOfArrival(organizerId, guestName, eventTitle, isFollower);
      }

      await _audit.logAction(
        actionType: 'LATE_ENTRY_ACCEPTED',
        description: 'Late guest allowed by staff',
        relatedEventId: response['events']?['id'],
      );

      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> verifySecurityClearance(String bookingId) async {
    try {
      final response = await supabase
          .from('bookings')
          .update({
            'security_cleared': true,
            'scanned_at_security': DateTime.now().toIso8601String(),
          })
          .eq('id', bookingId)
          .select('*, events(title, organizer_id)')
          .single();

      final String eventTitle = response['events']?['title'] ?? 'Event';
      final String? orgId = response['events']?['organizer_id'];

      await _audit.logAction(
        actionType: 'SECURITY_CLEARED',
        description: 'First-stage validation: Security passed for booking $bookingId',
        relatedEventId: response['event_id'],
      );

      // Notify Organizer and Staff
      if (orgId != null) {
        // Notify Organizer
        await _notifications.sendNotificationToUser(
          userId: orgId,
          title: 'SECURITY_CHECK_PASSED'.tr,
          body: 'SECURITY_CHECK_BODY'.trArgs([response['user_name'] ?? 'Guest', eventTitle]),
          type: 'security',
        );

        // Notify Managers and Security Staff
        final staffRes = await supabase
            .from('staff_assignments')
            .select('staff_id')
            .eq('organizer_id', orgId)
            .eq('status', 'active')
            .neq('staff_id', orgId);
        
        final staffList = staffRes as List;
        for (var staff in staffList) {
          final String staffId = staff['staff_id'];
          await _notifications.sendNotificationToUser(
            userId: staffId,
            title: 'SECURITY_CHECK_PASSED'.tr,
            body: 'SECURITY_CHECK_BODY'.trArgs([response['user_name'] ?? 'Guest', eventTitle]),
            type: 'security',
          );
        }
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> confirmManagerPayment(String bookingId) async {
    try {
      final managerId = supabase.auth.currentUser?.id;
      final response = await supabase
          .from('bookings')
          .update({
            'payment_confirmed': true,
            'payment_status': 'used',
            'scanned_at_payment': DateTime.now().toIso8601String(),
            'scanned_at': DateTime.now().toIso8601String(),
            'confirmed_by_manager': managerId,
          })
          .eq('id', bookingId)
          .select('user_id, events(title, organizer_id)')
          .single();

      final String guestId = response['user_id'];
      final String eventTitle = response['events']?['title'] ?? 'Event';
      final String? organizerId = response['events']?['organizer_id'];

      await _notifyBookingGuest(guestId, 'used', eventTitle);

      if (organizerId != null) {
        final isFollower = await _followService.isFollowing(organizerId, userId: guestId);
        final userData = await supabase.from('profiles').select('full_name').eq('id', guestId).maybeSingle();
        final guestName = userData?['full_name'] ?? 'Visitor';
        await _notifyOrganizerOfArrival(organizerId, guestName, eventTitle, isFollower);
      }

      await _audit.logAction(
        actionType: 'FINAL_ENTRY_CONFIRMED',
        description: 'Payment verified and entry granted for booking $bookingId by Manager $managerId',
        relatedEventId: response['events']?['id'] ?? response['event_id'],
      );

      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> approveBooking(String bookingId) async {
    try {
      final response = await supabase
          .from('bookings')
          .update({'payment_status': 'confirmed'})
          .eq('id', bookingId)
          .select('user_id, events(title)')
          .single();

      final String guestId = response['user_id'];
      final String eventTitle = response['events']?['title'] ?? 'Event';

      await _notifications.sendNotificationToUser(
        userId: guestId,
        title: 'TICKET APPROVED'.tr,
        body: 'The organizer has approved your request for $eventTitle!'.tr,
        type: 'booking',
      );

      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> cancelBooking(String bookingId, {String? reason, String? eventId}) async {
    try {
      final response = await supabase
          .from('bookings')
          .update({
            'payment_status': 'cancelled',
            'cancellation_reason': reason ?? 'User requested',
          })
          .eq('id', bookingId)
          .select('user_id, events(title)')
          .single();

      final String guestId = response['user_id'];
      final String eventTitle = response['events']?['title'] ?? 'Event';

      await _notifications.sendNotificationToUser(
        userId: guestId,
        title: 'TICKET CANCELLED'.tr,
        body: 'Your ticket for $eventTitle has been cancelled.'.tr,
        type: 'booking',
      );

      await _audit.logAction(
        actionType: 'BOOKING_CANCELLED',
        description: 'Booking $bookingId cancelled. Reason: ${reason ?? "User requested"}',
        relatedEventId: eventId,
      );

      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> cancelBookingWithReason(String bookingId, {required String reason}) async {
    return cancelBooking(bookingId, reason: reason);
  }

  Future<List<Booking>> getUserBookings() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return [];

      final response = await supabase
          .from('bookings')
          .select('*, events(*)')
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      return (response as List).map((b) => Booking.fromMap(b)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<Booking?> getLatestBooking() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return null;

      final response = await supabase
          .from('bookings')
          .select('*, events(*)')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null) return null;
      return Booking.fromMap(response);
    } catch (e) {
      return null;
    }
  }

  Future<List<Booking>> getEventBookings(String eventId) async {
    try {
      final response = await supabase
          .from('bookings')
          .select('*, events(*)')
          .eq('event_id', eventId)
          .order('created_at', ascending: false);
      return (response as List).map((b) => Booking.fromMap(b)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<bool> isVisitorFollower(String visitorId, String organizerId) async {
    return _followService.isFollowing(organizerId, userId: visitorId);
  }

  Future<bool> grantManualPerk(String bookingId, String perk, {String? managerId}) async {
    try {
      await supabase.from('bookings').update({
        'applied_perk': perk,
        'perk_granted_by': managerId,
      }).eq('id', bookingId);

      await _audit.logAction(
        actionType: 'PERK_GRANTED',
        description: 'Special perk ($perk) granted to guest by manager',
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<Map<String, dynamic>> getEventAnalytics(String eventId) async {
    try {
      final response = await supabase
          .from('bookings')
          .select('num_guests, payment_status, created_at, scanned_at')
          .eq('event_id', eventId);
      final List bookings = response as List;
      
      final Map<int, int> hourly = {};
      final Map<String, int> statusDist = {};
      
      for (var b in bookings) {
        final status = b['payment_status'] ?? 'pending';
        statusDist[status] = (statusDist[status] ?? 0) + 1;
        
        // Use scanned_at for entry trend if available, otherwise created_at
        final timeStr = b['scanned_at'] ?? b['created_at'];
        if (timeStr != null) {
          try {
            final time = DateTime.parse(timeStr);
            final hour = time.hour;
            if (status == 'used' || status == 'late_accepted') {
              hourly[hour] = (hourly[hour] ?? 0) + (b['num_guests'] as int? ?? 1);
            }
          } catch (_) {}
        }
      }
      
      return {
        'hourly_entries': hourly,
        'status_distribution': statusDist,
      };
    } catch (e) {
      return {'hourly_entries': {}, 'status_distribution': {}};
    }
  }

  Future<List<Booking>> getBookingsForEvents(List<String> eventIds) async {
    try {
      if (eventIds.isEmpty) return [];
      final response = await supabase
          .from('bookings')
          .select('*, events(*)')
          .inFilter('event_id', eventIds)
          .order('created_at', ascending: false);
      return (response as List).map((b) => Booking.fromMap(b)).toList();
    } catch (e) {
      return [];
    }
  }
}

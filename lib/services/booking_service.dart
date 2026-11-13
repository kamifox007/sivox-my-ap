import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:my_app/services/audit_service.dart';
import 'package:my_app/services/auth_service.dart';
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
            'payment_status': 'pending',
            'qr_code': serial,
            'pass_id': serial,
            'guest_phone': finalPhone,
            'created_by': user.id,
            'is_walkin': true,
            'walkin_serial': serial,
            'security_cleared': false,
          })
          .select('*, events(*)')
          .single();

      final result = Booking.fromMap(response);

      await _audit.logAction(
        actionType: 'GEN_TICKET_ISSUED',
        description: 'Direct Issuance: $serial created for ${result.userName}',
        relatedEventId: eventId,
      );

      // Manual reservations remain pending; reminders are scheduled after approval.
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

      // Every reservation remains pending until the organizer or an authorized
      // delegate approves it. The call preference changes guest instructions,
      // not the approval state.
      final String finalStatus =
          event.requireCallConfirmation ? 'pending_confirmation' : 'pending';

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
        await _notifications.sendBookingStageNotification(
          bookingId: result.id,
          title: isPendingConf ? 'BOOKING_ACTION_REQUIRED'.tr : 'New Booking!'.tr,
          body: isPendingConf
              ? 'BOOKING_PENDING_CALL_BODY'.trArgs([result.userName])
              : '${result.userName} just booked for ${result.event?.title}'.tr,
          type: 'booking',
          metadata: {'event_id': eventId},
          notifyGuest: false,
          notifyOrganizer: true,
          notifyStaff: false,
        );

        // Motivational Milestone
        if (maxCapacity != null && maxCapacity > 0) {
          final double ratio = (totalPersons + numGuests) / maxCapacity;
          final double oldRatio = totalPersons / maxCapacity;
          if ((ratio >= 0.5 && oldRatio < 0.5) || (ratio >= 0.9 && oldRatio < 0.9) || (ratio >= 1.0 && oldRatio < 1.0)) {
            await _notifications.sendBookingStageNotification(
              bookingId: result.id,
              title: 'EVENT_MILESTONE'.tr,
              body: 'MILESTONE_BODY'.trArgs([(ratio * 100).toInt().toString(), result.event!.title]),
              type: 'milestone',
              notifyGuest: false,
              notifyOrganizer: true,
              notifyStaff: false,
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
      if (fromUser == null || targetPhone.trim().isEmpty) return false;
      final normalizedTargetPhone =
          AuthService.normalizeAlgerianPhone(targetPhone);
      if (normalizedTargetPhone.isEmpty) return false;

      // Read only this caller's booking title to preserve the localized message.
      final bookingInfo = await supabase
          .from('bookings')
          .select('events(title)')
          .eq('id', bookingId)
          .eq('user_id', fromUser.id)
          .maybeSingle();
      if (bookingInfo == null) return false;
      final eventTitle = bookingInfo['events']?['title']?.toString() ?? 'Event';

      // Phone matching, booking ownership validation, transfer and recipient
      // notification are performed atomically in the database. The target
      // user's UUID is never returned to the client.
      final dynamic result = await supabase.rpc(
        'transfer_booking_ticket_by_phone',
        params: {
          'p_booking_id': bookingId,
          'p_phone': normalizedTargetPhone,
          'p_title': 'TICKET_RECEIVED_TITLE'.tr,
          'p_body': 'TICKET_RECEIVED_BODY'.trArgs([eventTitle]),
        },
      );

      if (result is! List || result.isEmpty) return false;
      final transferred = Map<String, dynamic>.from(result.first as Map);
      final String? eventId = transferred['event_id']?.toString();

      await _audit.logAction(
        actionType: 'TICKET_TRANSFERRED',
        description: 'Ticket ' + bookingId + ' transferred by its owner ' + fromUser.id,
        relatedEventId: eventId,
        metadata: {'booking_id': bookingId},
      );
      return true;
    } catch (e) {
      return false;
    }
  }
  Future<bool> updateBookingStatus(
    String bookingId,
    String status, {
    String? staffId,
    String? eventId,
    String? reason,
  }) async {
    // Critical booking transitions must use the permission-checked database
    // functions; never perform these status changes with a direct client UPDATE.
    if (status == 'confirmed') return approveBooking(bookingId);
    if (status == 'used') return confirmManagerPayment(bookingId);
    if (status == 'late_accepted') return markAsLate(bookingId);

    try {
      final Map<String, dynamic> updateData = {'payment_status': status};
      if (reason != null) updateData['cancellation_reason'] = reason;

      final response = await supabase
          .from('bookings')
          .update(updateData)
          .eq('id', bookingId)
          .select('user_id, user_name, event_id, events(title)')
          .single();

      final String guestId = response['user_id'].toString();
      final String guestName = response['user_name'] ?? 'Attendee';
      final String eventTitle = response['events']?['title'] ?? 'Event';

      await _notifyBookingGuest(bookingId, guestId, status, eventTitle);
      await _audit.logAction(
        actionType: 'STATUS_UPDATE',
        description: '$status confirmation for $guestName'.toUpperCase(),
        relatedEventId: (eventId ?? response['event_id'])?.toString(),
        metadata: {'booking_id': bookingId, 'staff_id': staffId},
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> approveRequest(
    String bookingId, {
    String? staffId,
    String? eventId,
  }) async {
    return approveBooking(bookingId);
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

  Future<void> _notifyBookingGuest(
    String bookingId,
    String userId,
    String status,
    String eventTitle,
  ) async {
    String title = '';
    String body = '';
    String notificationType = 'booking';

    try {
      String guestName = ' زائر ';
      if (status == 'used' || status == 'late_accepted') {
        final userData = await supabase
            .from('profiles')
            .select('full_name')
            .eq('id', userId)
            .maybeSingle();
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
          notificationType = 'booking_cancel';
          break;
        case 'used':
        case 'late_accepted':
          title = 'welcome_visitor_title'.trArgs([guestName]);
          body = 'welcome_visitor_body'.trArgs([eventTitle]);
          notificationType =
              status == 'late_accepted' ? 'late' : 'presence';
          break;
        case 'ejected':
          title = 'TICKET_REJECTED'.tr;
          body = 'Your ticket for $eventTitle has been revoked.'.tr;
          notificationType = 'ejected';
          break;
      }

      if (title.isNotEmpty) {
        await _notifications.sendBookingStageNotification(
          bookingId: bookingId,
          title: title,
          body: body,
          type: notificationType,
          metadata: {'status': status},
          notifyGuest: true,
          notifyOrganizer: false,
          notifyStaff: false,
        );
      }
    } catch (_) {}
  }

  Future<void> _notifyOrganizerOfArrival(
    String bookingId,
    String guestName,
    String eventTitle,
    bool isFollower,
  ) async {
    final String prefix = isFollower ? '💎 VIP FOLLOWED' : '👤 VISITOR';
    await _notifications.sendBookingStageNotification(
      bookingId: bookingId,
      title: '$prefix ARRIVED'.tr,
      body: '$guestName ${'has_arrived_at'.tr} $eventTitle',
      type: 'presence',
      metadata: {'guest_name': guestName, 'is_vip': isFollower},
      notifyGuest: false,
      notifyOrganizer: true,
      notifyStaff: true,
    );
  }

  Future<bool> markAsUsed(String bookingId, {String? tableNumber}) async {
    final success = await confirmManagerPayment(bookingId);
    if (!success || tableNumber == null) return success;

    try {
      await supabase
          .from('bookings')
          .update({'table_number': tableNumber})
          .eq('id', bookingId)
          .eq('payment_status', 'used');
    } catch (_) {
      // Entry has already been confirmed; a table assignment is optional metadata.
    }
    return true;
  }

  Future<Map<String, dynamic>?> _callBookingStageRpc(
    String functionName,
    String bookingId,
  ) async {
    final dynamic result = await supabase.rpc(
      functionName,
      params: {'p_booking_id': bookingId},
    );

    if (result is List && result.isNotEmpty) {
      return Map<String, dynamic>.from(result.first as Map);
    }
    if (result is Map) {
      return Map<String, dynamic>.from(result);
    }
    return null;
  }

  Future<bool> markAsLate(String bookingId, {String? assignmentId}) async {
    try {
      final response = await _callBookingStageRpc(
        'accept_booking_late_entry',
        bookingId,
      );
      if (response == null) return false;

      final String? guestId = response['user_id']?.toString();
      if (guestId == null || guestId.isEmpty) return false;
      final String eventTitle = response['event_title']?.toString() ?? 'Event';
      final String? organizerId = response['organizer_id']?.toString();

      await _notifyBookingGuest(bookingId, guestId, 'late_accepted', eventTitle);

      if (organizerId != null) {
        final isFollower = await _followService.isFollowing(
          organizerId,
          userId: guestId,
        );
        final userData = await supabase
            .from('profiles')
            .select('full_name')
            .eq('id', guestId)
            .maybeSingle();
        final guestName = userData?['full_name'] ?? 'Visitor';
        await _notifyOrganizerOfArrival(
          bookingId,
          guestName,
          eventTitle,
          isFollower,
        );
      }

      await _audit.logAction(
        actionType: 'LATE_ENTRY_ACCEPTED',
        description: 'Late guest allowed by staff',
        relatedEventId: response['event_id']?.toString(),
        metadata: {'booking_id': bookingId, 'payment_confirmed': true, 'assignment_id': assignmentId},
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> verifySecurityClearance(String bookingId, {String? assignmentId}) async {
    try {
      final response = await _callBookingStageRpc(
        'verify_booking_security_clearance',
        bookingId,
      );
      if (response == null) return false;

      final String? guestId = response['user_id']?.toString();
      if (guestId == null || guestId.isEmpty) return false;
      final String eventTitle = response['event_title']?.toString() ?? 'Event';
      final String? eventId = response['event_id']?.toString();
      final String guestName = response['user_name']?.toString() ?? 'Guest';

      await _audit.logAction(
        actionType: 'SECURITY_CLEARED',
        description: 'First-stage validation: Security passed for booking $bookingId',
        relatedEventId: eventId,
        metadata: {'booking_id': bookingId, 'guest_id': guestId, 'assignment_id': assignmentId},
      );

      await _notifications.sendBookingStageNotification(
        bookingId: bookingId,
        title: 'SECURITY_CHECK_PASSED'.tr,
        body: 'Your ticket passed the security check for $eventTitle. Please proceed to the payment point.',
        type: 'security',
        metadata: {'guest_id': guestId},
        notifyGuest: true,
        notifyOrganizer: false,
        notifyStaff: false,
      );

      await _notifications.sendBookingStageNotification(
        bookingId: bookingId,
        title: 'SECURITY_CHECK_PASSED'.tr,
        body: 'SECURITY_CHECK_BODY'.trArgs([guestName, eventTitle]),
        type: 'security',
        metadata: {'guest_id': guestId},
        notifyGuest: false,
        notifyOrganizer: true,
        notifyStaff: true,
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> confirmManagerPayment(String bookingId, {String? assignmentId}) async {
    try {
      final managerId = supabase.auth.currentUser?.id;
      final response = await _callBookingStageRpc(
        'confirm_booking_manager_payment',
        bookingId,
      );
      if (response == null) return false;

      final String? guestId = response['user_id']?.toString();
      if (guestId == null || guestId.isEmpty) return false;
      final String eventTitle = response['event_title']?.toString() ?? 'Event';
      final String? organizerId = response['organizer_id']?.toString();

      await _notifyBookingGuest(bookingId, guestId, 'used', eventTitle);

      if (organizerId != null) {
        final isFollower = await _followService.isFollowing(
          organizerId,
          userId: guestId,
        );
        final userData = await supabase
            .from('profiles')
            .select('full_name')
            .eq('id', guestId)
            .maybeSingle();
        final guestName = userData?['full_name'] ?? 'Visitor';
        await _notifyOrganizerOfArrival(
          bookingId,
          guestName,
          eventTitle,
          isFollower,
        );
      }

      await _audit.logAction(
        actionType: 'FINAL_ENTRY_CONFIRMED',
        description: 'Payment verified and entry granted for booking $bookingId by Manager $managerId',
        relatedEventId: response['event_id']?.toString(),
        metadata: {'booking_id': bookingId, 'payment_confirmed': true},
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> approveBooking(String bookingId, {String? assignmentId}) async {
    try {
      final response = await _callBookingStageRpc(
        'approve_event_booking',
        bookingId,
      );
      if (response == null) return false;

      final String? guestId = response['user_id']?.toString();
      if (guestId == null || guestId.isEmpty) return false;
      final String eventTitle = response['event_title']?.toString() ?? 'Event';
      final String? eventId = response['event_id']?.toString();

      await _notifications.sendBookingStageNotification(
        bookingId: bookingId,
        title: 'TICKET APPROVED'.tr,
        body: 'The organizer has approved your request for $eventTitle!'.tr,
        type: 'booking',
        metadata: {'event_id': eventId},
        notifyGuest: true,
        notifyOrganizer: false,
        notifyStaff: false,
      );

      await _audit.logAction(
        actionType: 'BOOKING_APPROVED',
        description: 'Booking $bookingId approved for $eventTitle',
        relatedEventId: eventId,
        metadata: {'booking_id': bookingId, 'guest_id': guestId, 'assignment_id': assignmentId},
      );

      final bookingData = await supabase
          .from('bookings')
          .select('*, events(*)')
          .eq('id', bookingId)
          .maybeSingle();
      if (bookingData != null) {
        await _scheduleEventReminders(Booking.fromMap(bookingData));
      }
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
          .select('user_id, event_id, events(title)')
          .single();

      final String guestId = response['user_id'];
      final String eventTitle = response['events']?['title'] ?? 'Event';

      await _notifications.sendBookingStageNotification(
        bookingId: bookingId,
        title: 'TICKET CANCELLED'.tr,
        body: 'Your ticket for $eventTitle has been cancelled.'.tr,
        type: 'booking_cancel',
        metadata: {'reason': reason ?? 'User requested', 'guest_id': guestId},
        notifyGuest: true,
        notifyOrganizer: true,
        notifyStaff: true,
      );

      await _audit.logAction(
        actionType: 'BOOKING_CANCELLED',
        description: 'Booking $bookingId cancelled. Reason: ${reason ?? "User requested"}',
        relatedEventId: (eventId ?? response['event_id'])?.toString(),
        metadata: {'booking_id': bookingId},
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

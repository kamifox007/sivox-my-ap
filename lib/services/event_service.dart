import 'package:my_app/services/translation_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:my_app/models/event.dart';
import 'package:my_app/services/notification_service.dart';
import 'package:my_app/services/audit_service.dart';

class EventService {
  final supabase = Supabase.instance.client;
  final _notif = NotificationService();
  final _audit = AuditService();

  /// Creates a new event in the Supabase 'events' table.
  /// Automatically associates the event with the current organizer (user).
  Future<Event?> createEvent({
    required String organizerId, // Explicit Club ID
    required String title,
    required String category,
    required String venue,
    required String dateTime,
    required double price,
    required String description,
    required String imageUrl,
    List<String> galleryImages = const [],
    String? contactNumber,
    String? contactType,
    bool requireCallConfirmation = false,
    bool hidePrice = false,
    double? latitude,
    double? longitude,
    String countryCode = 'DZ',
    String? rules,
    double promoDiscount = 0.0,
    String? promoValue,
    String? promoLabel,
    int promoLimit = 0,
    double followerDiscount = 0.0,
    String? followerPerk,
    bool hasEarlyBirdRewards = false,
    double globalDiscount = 0.0,
    String? globalPerk,
    int discountPercentage = 0,
    bool payAtDoor = false,
    String? endTime,
    int? maxCapacity,
    bool shouldNotify = true,
  }) async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return null;

      final response = await supabase.from('events').insert({
        'title': title,
        'category': category,
        'venue': venue,
        'date_time': dateTime,
        'price': price,
        'description': description,
        'image_url': imageUrl,
        'gallery_images': galleryImages,
        'organizer_id': organizerId,
        'contact_number': contactNumber,
        'contact_type': contactType,
        'require_call_confirmation': requireCallConfirmation,
        'hide_price': hidePrice,
        'latitude': latitude,
        'longitude': longitude,
        'country_code': countryCode,
        'rules': rules,
        'promo_discount': promoDiscount,
        'promo_value': promoValue,
        'promo_label': promoLabel,
        'promo_limit': promoLimit,
        'follower_discount': followerDiscount,
        'follower_perk': followerPerk,
        'has_early_bird_rewards': hasEarlyBirdRewards,
        'global_discount': globalDiscount,
        'global_perk': globalPerk,
        'discount_percentage': discountPercentage,
        'pay_at_door': payAtDoor,
        'end_time': endTime,
        'max_capacity': maxCapacity,
      }).select('*, bookings(num_guests, is_scanned)').single();

      final result = Event.fromMap(response);
      
      await _audit.logAction(
        actionType: 'EVENT_CREATED',
        description: 'New event published: ${result.title} at ${result.venue}',
        relatedEventId: result.id,
      );
      
      if (shouldNotify) {
        _notif.notifyFollowers(
          organizerId: organizerId,
          title: 'new_event_title'.trArgs([title]),
          body: 'new_event_body'.trArgs([venue]),
          type: 'event',
          metadata: {'event_id': result.id},
        );
      }

      return result;
    } catch (e) {
      return null;
    }
  }

  /// Fetches all events created by the currently logged-in organizer.
  Future<List<Event>> getOrganizerEvents({String? organizerId}) async {
    try {
      final userId = organizerId ?? supabase.auth.currentUser?.id;
      if (userId == null) return [];

      final response = await supabase
          .from('events')
          .select('*, bookings(num_guests, is_scanned), organizer_profiles(name, avatar_url, profiles(full_name))')
          .eq('organizer_id', userId)
          .order('created_at', ascending: false);

      return (response as List).map((e) => Event.fromMap(e)).toList();
    } catch (e) {
// print cleaned
      return [];
    }
  }

  /// Fetches public events for the home feed with pagination support.
  Future<List<Event>> getPaginatedEvents({int from = 0, int to = 9, String? countryCode}) async {
    try {
      var query = supabase
          .from('events')
          .select('*, bookings(num_guests, is_scanned), organizer_profiles(name, avatar_url, profiles(full_name))');

      if (countryCode != null) {
        query = query.eq('country_code', countryCode);
      }

      final response = await query
          .order('created_at', ascending: false)
          .range(from, to);

      return (response as List).map((e) => Event.fromMap(e)).toList();
    } catch (e) {
      return [];
    }
  }

  /// Fetches all public events for the home feed (legacy/fallback).
  Future<List<Event>> getAllEvents() async {
    try {
      final response = await supabase
          .from('events')
          .select('*, bookings(num_guests, is_scanned), organizer_profiles(name, avatar_url, profiles(full_name))')
          .order('created_at', ascending: false);

      return (response as List).map((e) => Event.fromMap(e)).toList();
    } catch (e) {
// print cleaned
      return [];
    }
  }
  /// Fetches a single event by its unique ID.
  Future<Event?> getEventById(String id) async {
    try {
      final response = await supabase
          .from('events')
          .select('*, bookings(num_guests, is_scanned), organizer_profiles(name, profiles(full_name))')
          .eq('id', id)
          .maybeSingle();

      if (response == null) return null;
      return Event.fromMap(response);
    } catch (e) {
      return null;
    }
  }

  /// Deletes an event from the database.
  Future<bool> deleteEvent(String id) async {
    try {
      // Fetch event info first
      final event = await supabase.from('events').select('title, organizer_id').eq('id', id).maybeSingle();
      final title = event?['title'] ?? 'Event';

      // Fetch all confirmed/pending bookings
      final bookings = await supabase.from('bookings').select('user_id').eq('event_id', id);
      final List<dynamic> usersToNotify = bookings as List;

      await _audit.logAction(
        actionType: 'EVENT_DELETED',
        description: 'Event "$title" was deleted. Notifying attendees.',
        relatedEventId: id,
      );

      // Notify each attendee
      for (final b in usersToNotify) {
        final uId = b['user_id'];
        if (uId != null) {
          await _notif.sendNotificationToUser(
            userId: uId,
            title: 'EVENT_CANCELLED_TITLE'.tr,
            body: 'EVENT_CANCELLED_BODY'.trArgs([title]),
            type: 'event_cancellation',
          );
        }
      }

      await supabase.from('events').delete().eq('id', id);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Updates an existing event's data.
  Future<bool> updateEvent(String id, Map<String, dynamic> updates) async {
    try {
      await supabase.from('events').update(updates).eq('id', id);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Increments the view count for an event (Analytical Insight).
  Future<void> incrementViewCount(String eventId) async {
    try {
      // In a real high-traffic app, you'd use a RPC or increment logic
      await supabase.rpc('increment_event_views', params: {'row_id': eventId});
    } catch (e) {
      // Fallback if RPC isn't ready: manual update (less efficient)
      try {
        final res = await supabase.from('events').select('view_count').eq('id', eventId).maybeSingle();
        if (res != null) {
          final count = (res['view_count'] ?? 0) + 1;
          await supabase.from('events').update({'view_count': count}).eq('id', eventId);
        }
      } catch (_) {}
    }
  }
}


import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:flutter/foundation.dart';
import 'package:my_app/services/translation_service.dart';

class AppNotification {
  final String id;
  final String title;
  final String body;
  final DateTime createdAt;
  final String? type;
  final Map<String, dynamic>? metadata;
  bool isRead;

  AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    this.type,
    this.metadata,
    this.isRead = false,
  });

  factory AppNotification.fromMap(Map<String, dynamic> map) {
    return AppNotification(
      id: map['id']?.toString() ?? '',
      title: map['title'] ?? '',
      body: map['body'] ?? '',
      createdAt: DateTime.parse(map['created_at'] ?? DateTime.now().toIso8601String()),
      isRead: map['is_read'] ?? false,
      type: map['type'],
      metadata: map['metadata'] is Map ? Map<String, dynamic>.from(map['metadata']) : null,
    );
  }
}

class NotificationService {
  final supabase = Supabase.instance.client;
  static final ValueNotifier<int> unreadCount = ValueNotifier(0);
  
  // Singleton pattern for globally accessible real-time listener
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  RealtimeChannel? _subscription;
  static final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  static Future<void> initExternalNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings initializationSettingsIOS = DarwinInitializationSettings();
    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );
    await _localNotifications.initialize(
      settings: initializationSettings,
    );

    // Initialize Timezones
    tz.initializeTimeZones();
    final String localTimeZone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(localTimeZone));
  }

  static Future<void> scheduleReminder({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    String? payload,
  }) async {
    final now = DateTime.now();
    if (scheduledDate.isBefore(now)) return; // Don't schedule in past

    const AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'Sivox_reminders', 'Sivox Reminders',
      channelDescription: 'Event countdown reminders',
      importance: Importance.max,
      priority: Priority.high,
    );
    const NotificationDetails platformChannelSpecifics = NotificationDetails(android: androidPlatformChannelSpecifics);

    await _localNotifications.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: tz.TZDateTime.from(scheduledDate, tz.local),
      notificationDetails: platformChannelSpecifics,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: payload,
    );
  }

  static Future<void> showExternalAlert(String title, String body) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'Sivox_alerts', 'Sivox Alerts',
      channelDescription: 'New event and club alerts',
      importance: Importance.max,
      priority: Priority.high,
    );
    const NotificationDetails platformChannelSpecifics = NotificationDetails(android: androidPlatformChannelSpecifics);
    await _localNotifications.show(id: 0, title: title, body: body, notificationDetails: platformChannelSpecifics);
  }

  /// Fetches notifications for the current user.
  Future<List<AppNotification>> getNotifications() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return [];

      final response = await supabase
          .from('notifications')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      final notifications = (response as List).map((n) => AppNotification.fromMap(n)).toList();
      unreadCount.value = notifications.where((n) => !n.isRead).length;
      
      return notifications;
    } catch (e) {
      return [];
    }
  }

  /// Marks a notification as read.
  Future<void> markAsRead(String notificationId) async {
    try {
      await supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('id', notificationId);
          
      if (unreadCount.value > 0) unreadCount.value--;
    } catch (e) {
      debugPrint('Error marking notification as read: $e');
    }
  }

  /// Specialized method for Discount/Flash Offer push
  Future<void> notifyDiscountFlash({
    required String organizerId,
    required String eventTitle,
    required String discountAmount,
  }) async {
    try {
      await notifyFollowers(
        organizerId: organizerId,
        title: 'discount_push_title'.trArgs([eventTitle]),
        body: 'discount_push_body'.trArgs([discountAmount]),
        type: 'event',
        metadata: {'event_title': eventTitle, 'discount': discountAmount},
      );
    } catch (e) {
      debugPrint('Error notifying discount flash: $e');
    }
  }

  /// Sends a tactical mission call to a specific user using secure RPC.
  Future<void> sendStaffMission({
    required String staffId,
    required String organizerId,
    required String clubName,
    required String missionText,
    String? eventId,
  }) async {
    try {
      await supabase.rpc('send_staff_notification', params: {
        'p_staff_id': staffId,
        'p_organizer_id': organizerId,
        'p_title': 'MISSION_CALL'.tr,
        'p_body': '[$clubName]: $missionText',
        'p_type': 'staff_mission',
        'p_metadata': {
          'club_name': clubName,
          'mission': missionText,
          'event_id': eventId,
          'is_high_priority': true,
        },
      });
    } catch (e) {
      debugPrint('Error sending staff mission: $e');
    }
  }

  /// Sends a notification to a specific staff member using secure RPC.
  Future<void> sendStaffNotification({
    required String staffId,
    required String organizerId,
    required String title,
    required String body,
    required String type,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      await supabase.rpc('send_staff_notification', params: {
        'p_staff_id': staffId,
        'p_organizer_id': organizerId,
        'p_title': title,
        'p_body': body,
        'p_type': type,
        'p_metadata': metadata ?? {},
      });
    } catch (e) {
      debugPrint('Error sending staff notification: $e');
    }
  }

  /// Sends a notification to a specific user (fallback, works only if auth.uid() == userId).
  Future<void> sendNotificationToUser({
    required String userId,
    required String title,
    required String body,
    String? type,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      await supabase.from('notifications').insert({
        'user_id': userId,
        'title': title,
        'body': body,
        'type': type,
        'metadata': metadata,
        'is_read': false,
      });
    } catch (e) {
      debugPrint('Error sending notification to user: $e');
    }
  }

  /// Notifies all followers of an organizer about an update using secure RPC.
  Future<void> notifyFollowers({
    required String organizerId,
    required String title,
    required String body,
    String? type,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      await supabase.rpc('send_organizer_notification', params: {
        'p_organizer_id': organizerId,
        'p_title': title,
        'p_body': body,
        'p_type': type ?? 'announcement',
        'p_metadata': metadata ?? {},
      });
    } catch (e) {
      debugPrint('Error notifying followers: $e');
    }
  }

  /// Sends a local notification (mocking a push).
  Future<void> sendMockNotification(String title, String body) async {
    await showExternalAlert(title, body);
  }

  // Mock and test methods removed for production

  /// Listens for real-time notifications for the current user.
  void startRealtimeListener() {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    // stop existing
    stopRealtimeListener();

    _subscription = supabase
        .channel('public:notifications:user_id=eq.$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            final newNotif = AppNotification.fromMap(payload.newRecord);
            unreadCount.value++;
            showExternalAlert(newNotif.title, newNotif.body);
          },
        )
        .subscribe();
  }

  void stopRealtimeListener() {
    _subscription?.unsubscribe();
    _subscription = null;
  }

  Stream<List<AppNotification>> getNotificationsStream() {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return Stream.value([]);
    
    return supabase
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .map((data) {
          final list = data.map((n) => AppNotification.fromMap(n)).toList();
          unreadCount.value = list.where((n) => !n.isRead).length;
          return list;
        });
  }

  Future<void> markAllAsRead() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    
    await supabase.from('notifications').update({'is_read': true}).eq('user_id', userId);
    unreadCount.value = 0;
  }
}


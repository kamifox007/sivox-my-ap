import 'package:supabase_flutter/supabase_flutter.dart';

class AuditService {
  final supabase = Supabase.instance.client;

  static const String tableOrganizer = 'organizer_ledger';
  static const String tableWorker = 'worker_logs';
  static const String tableVisitor = 'visitor_logs';
  static const String tableArchive = 'mission_archives';

  /// Records an action into the appropriate tactical stream based on the actor's role.
  Future<void> logAction({
    required String actionType,
    required String description,
    String? relatedEventId,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;
      
      final userName = user.userMetadata?['full_name'] ?? 'TERMINAL_OPERATOR';
      final role = (user.userMetadata?['role']?.toString() ?? 'visitor').toLowerCase();

      // ROUTING LOGIC: Determine which "Private Database" to use
      String targetTable = tableWorker; // Default
      if (role == 'organizer' || role == 'admin' || role == 'owner') {
        targetTable = tableOrganizer;
      } else if (role == 'visitor' || role == 'attendee') {
        targetTable = tableVisitor;
      }

      await supabase.from(targetTable).insert({
        'user_id': user.id,
        'user_name': userName,
        'role': role,
        'action_type': actionType,
        'description': description,
        'related_event_id': relatedEventId,
        'metadata': metadata ?? {},
      });
      
      // Mirroring to legacy staff_logs for backward compatibility during phased migration
      await supabase.from('staff_logs').insert({
        'user_id': user.id,
        'user_name': userName,
        'role': role,
        'action_type': actionType,
        'description': description,
        'related_event_id': relatedEventId,
        'metadata': metadata ?? {},
      });

    } catch (e) {
      // Slient failure for logs to prevent UI blocking
    }
  }

  /// Fetches logs from a specific tactical stream
  Future<List<Map<String, dynamic>>> getLogs({
    String? eventId, 
    String? organizerId, 
    String? staffIdFilter,
    String sourceTable = 'staff_logs', // Use mirrored logs for consistent dashboard view
  }) async {
    try {
      var query = supabase.from(sourceTable).select();
      
      if (eventId != null) {
        query = query.eq('related_event_id', eventId);
      } else if (organizerId != null) {
        final events = await supabase.from('events').select('id').eq('organizer_id', organizerId);
        final ids = (events as List).map((e) => e['id'].toString()).toList();
        if (ids.isNotEmpty) {
          query = query.inFilter('related_event_id', ids);
        } else {
          return [];
        }
      }

      if (staffIdFilter != null) {
        query = query.eq('user_id', staffIdFilter);
      }

      final response = await query.order('created_at', ascending: false).limit(100);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      return [];
    }
  }

  /// Specialized: Get Visitor Interaction History
  Future<List<Map<String, dynamic>>> getVisitorHistory() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return [];
      
      final response = await supabase
          .from(tableVisitor)
          .select('*, events(title, image_url)')
          .eq('user_id', user.id)
          .order('created_at', ascending: false);
          
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      return [];
    }
  }

  /// Ø­Ø°Ù  Ø³Ø¬Ù„ Ù…Ø¹ÙŠÙ† (ÙŠØ³ØªØ®Ø¯Ù… Ù„Ù„ØªÙ†Ø¸ÙŠÙ  Ø§Ù„Ø´Ø®ØµÙŠ)
  Future<bool> deleteLog(String logId) async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return false;

      // Ø§Ù„ØªØ£ÙƒØ¯ Ù…Ù† Ø£Ù† Ø§Ù„Ù…Ø³ØªØ®Ø¯Ù… ÙŠØ­Ø°Ù  Ø³Ø¬Ù„Ù‡ Ø§Ù„Ø®Ø§Øµ Ù Ù‚Ø· Ø¹Ø¨Ø± ÙƒÙˆØ¯ Ø§Ù„Ù€ RLS Ø£Ùˆ Ø§Ù„ØªØ­Ù‚Ù‚ Ù‡Ù†Ø§
      await supabase.from('staff_logs').delete().eq('id', logId).eq('user_id', user.id);
      return true;
    } catch (e) {
// print cleaned
      return false;
    }
  }

  /// ÙŠÙ…ÙƒÙ† Ù„Ù„Ù…Ø§Ù„Ùƒ Ø­Ø°Ù  Ø§Ù„Ø³Ø¬Ù„Ø§Øª Ù…ØªÙ‰ Ø£Ø±Ø§Ø¯ (ÙŠÙ Ø¶Ù„ ØªØ±ÙƒÙ‡Ø§ Ù„Ù„Ù†Ø²Ø§Ù‡Ø©)
  Future<bool> clearLogs(String eventId) async {
    try {
      await supabase.from('staff_logs').delete().eq('related_event_id', eventId); 
      return true;
    } catch (e) {
// print cleaned
      return false;
    }
  }

  /// Bulk clearing of all tactical logs for an organizer
  Future<bool> clearAllOrganizerLogs(String organizerId) async {
    try {
      // 1. Get all events for this organizer
      final events = await supabase.from('events').select('id').eq('organizer_id', organizerId);
      final ids = (events as List).map((e) => e['id'].toString()).toList();
      
      if (ids.isEmpty) return true;

      // 2. Delete from all tactical tables
      await Future.wait([
        supabase.from('staff_logs').delete().inFilter('related_event_id', ids),
        supabase.from(tableOrganizer).delete().inFilter('related_event_id', ids),
        supabase.from(tableWorker).delete().inFilter('related_event_id', ids),
      ]);
      
      return true;
    } catch (e) {
      return false;
    }
  }

  /// PRO ANALYTICS: Get security counts
  Future<Map<String, int>> getSecurityStats(String eventId) async {
    try {
      final response = await supabase
          .from('staff_logs')
          .select('action_type')
          .eq('related_event_id', eventId);
      
      final List list = response as List;
      int ejections = 0;
      int blocks = 0;
      int refusals = 0;

      for (var log in list) {
        final action = log['action_type'];
        if (action == 'SECURITY_EJECT' || action == 'GUEST_EJECTED') ejections++;
        if (action == 'SECURITY_BLOCK' || action == 'GUEST_BLOCKED') blocks++;
        if (action == 'LATE_REFUSED' || action == 'ENTRY_REFUSED') refusals++;
      }

      return {
        'ejections': ejections,
        'blocks': blocks,
        'refusals': refusals,
      };
    } catch (e) {
      return {'ejections': 0, 'blocks': 0, 'refusals': 0};
    }
  }
  
  /// MASTER CENSUS: Get aggregated attendance across all active events
  Future<Map<String, int>> getGlobalCensus(String organizerId) async {
    try {
      // 1. Get all events for this specific organizer/club
      final eventsRes = await supabase.from('events').select('id').eq('organizer_id', organizerId);
      final List eventIds = (eventsRes as List).map((e) => e['id'].toString()).toList();
      
      if (eventIds.isEmpty) return {'total': 0, 'scanned': 0, 'remaining': 0};

      // 2. Get all non-cancelled bookings for these events
      final bookingsRes = await supabase
          .from('bookings')
          .select('num_guests, payment_status')
          .inFilter('event_id', eventIds)
          .not('payment_status', 'eq', 'cancelled');

      final List bookings = bookingsRes as List;
      int total = 0;
      int scanned = 0;

      for (var b in bookings) {
        final count = (b['num_guests'] as int? ?? 1);
        total += count;
        if (b['payment_status'] == 'used' || b['payment_status'] == 'late_accepted') {
          scanned += count;
        }
      }

      return {
        'total': total,
        'scanned': scanned,
        'remaining': (total - scanned).clamp(0, 999999),
      };
    } catch (e) {
      return {'total': 0, 'scanned': 0, 'remaining': 0};
    }
  }

  /// REAL-TIME: Subscribe to live mission updates for a specific club/organizer
  RealtimeChannel subscribeToMissions(String clubId, Function(Map<String, dynamic>) onUpdate) {
    final channel = supabase.channel('staff_updates_$clubId');
    
    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'staff_logs',
      callback: (payload) {
        final data = payload.newRecord;
        // Basic check: is this related to an event?
        if (data['related_event_id'] != null) {
          onUpdate(data);
        }
      },
    ).subscribe();

    return channel;
  }

  /// SEAL ARCHIVE: Snapshots mission context
  Future<bool> finalizeAndArchiveMission({
    required String clubId,
    required String title,
    required Map<String, int> census,
    required Map<String, int> security, 
  }) async {
    try {
      // Fetch logs for this organizer to save in the archive
      final logs = await getLogs(organizerId: clubId, sourceTable: tableOrganizer);

      await supabase.from(tableArchive).insert({
        'club_id': clubId,
        'title': title,
        'metrics': {
          'total': census['total'],
          'scanned': census['scanned'],
          'security': security,
          'detailed_logs': logs, // Save full logs inside the JSON map to save space and maintain speed
        },
        'finalized_at': DateTime.now().toIso8601String(),
      });
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Fetches sealed mission archives for a club
  Future<List<Map<String, dynamic>>> getMissionArchives(String clubId) async {
    try {
      final response = await supabase
          .from(tableArchive)
          .select()
          .eq('club_id', clubId)
          .order('finalized_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      return [];
    }
  }

  /// Deletes a specific mission archive
  Future<bool> deleteMissionArchive(String id) async {
    try {
      await supabase.from(tableArchive).delete().eq('id', id);
      return true;
    } catch (e) {
      return false;
    }
  }
}


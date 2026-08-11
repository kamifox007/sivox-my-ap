import 'package:flutter/material.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/models/event.dart';
import 'package:my_app/services/audit_service.dart';
import 'package:my_app/services/event_service.dart';
import 'package:my_app/services/translation_service.dart';
import 'package:my_app/services/stats_report_service.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';

class StaffLogsScreen extends StatefulWidget {
  final String? organizerId;
  final String? eventId;
  const StaffLogsScreen({super.key, this.organizerId, this.eventId});

  @override
  State<StaffLogsScreen> createState() => _StaffLogsScreenState();
}

class _StaffLogsScreenState extends State<StaffLogsScreen> {
  final _eventService = EventService();
  List<Event> _events = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    setState(() => _isLoading = true);

    if (widget.eventId != null) {
      final event = await _eventService.getEventById(widget.eventId!);
      if (mounted) {
        setState(() {
          _events = event != null ? [event] : [];
          _isLoading = false;
        });
      }
      return;
    }

    final events = await _eventService.getOrganizerEvents(
      organizerId: widget.organizerId,
    );
    if (mounted) {
      setState(() {
        _events = events;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background.withValues(alpha: 0.8),
        iconTheme: const IconThemeData(color: AppTheme.primary),
        title: Text(
          widget.eventId == null ? 'OPERATIONAL_LEDGER'.tr : 'EVENT_LOGS'.tr,
          style: AppTheme.headlineStyle.copyWith(fontSize: 18),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            )
          : _events.isEmpty
          ? Center(
              child: Text(
                'no_events_found'.tr,
                style: const TextStyle(color: Colors.white54),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _events.length,
              itemBuilder: (context, index) {
                final event = _events[index];
                return _buildEventCard(event);
              },
            ),
    );
  }

  Widget _buildEventCard(Event event) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 12,
        ),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            image: DecorationImage(
              image: NetworkImage(event.imageUrl ?? ''),
              fit: BoxFit.cover,
            ),
          ),
        ),
        title: Text(
          event.title.toUpperCase(),
          style: AppTheme.headlineStyle.copyWith(fontSize: 16),
        ),
        subtitle: Text('tap_to_view_scanned'.tr),
        trailing: const Icon(
          Icons.arrow_forward_ios,
          color: AppTheme.primary,
          size: 16,
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => EventLogDetailScreen(event: event),
            ),
          );
        },
      ),
    );
  }
}

class EventLogDetailScreen extends StatefulWidget {
  final Event event;
  const EventLogDetailScreen({super.key, required this.event});

  @override
  State<EventLogDetailScreen> createState() => _EventLogDetailScreenState();
}

class _EventLogDetailScreenState extends State<EventLogDetailScreen>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>> _logs = [];
  bool _isLoading = true;
  String? _currentUserId;
  bool _canViewTeamLogs = false;
  late TabController _tabController;
  final _auditService = AuditService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _currentUserId = _auditService.supabase.auth.currentUser?.id;
    _checkPermissionsAndLoad();
  }

  Future<void> _checkPermissionsAndLoad() async {
    setState(() => _isLoading = true);
    try {
      if (_currentUserId != null) {
        // Fetch current assignment to check permissions
        final res = await _auditService.supabase
            .from('staff_assignments')
            .select('permissions')
            .eq('staff_id', _currentUserId!)
            .eq('event_id', widget.event.id)
            .maybeSingle();
        
        if (res != null) {
          final perms = res['permissions'] as Map<String, dynamic>?;
          _canViewTeamLogs = perms?['can_view_team_logs'] == true;
        }
      }
    } catch (e) {
      debugPrint('Permission Check Error: $e');
    }
    await _loadLogs();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadLogs() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    
    // IF NOT MANAGER -> FILTER BY OWN ID
    final logs = await _auditService.getLogs(
      eventId: widget.event.id,
      staffIdFilter: _canViewTeamLogs ? null : _currentUserId,
      sourceTable: AuditService.tableWorker,
    );
    
    if (mounted) {
      setState(() {
        _logs = logs;
        _isLoading = false;
      });
    }
  }

  void _showHelp(String category) {
    String title = category;
    String desc = 'staff_personal_docs'.tr;
    
    if (category == 'SHARE_TOOL') {
      title = 'SHARE_TOOL'.tr;
      desc = 'HELP_SHARE_STAFF_DESC'.tr;
    } else if (category == 'DOWNLOAD_TOOL') {
      title = 'DOWNLOAD_TOOL'.tr;
      desc = 'HELP_DOWNLOAD_STAFF_DESC'.tr;
    }

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
            const Icon(Icons.help_outline_rounded, color: AppTheme.primary, size: 32),
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

  List<Map<String, dynamic>> _filterLogs(bool isManual) {
    if (isManual) {
      return _logs
          .where(
            (l) =>
                l['action_type'] == 'MANUAL_TICKET' ||
                l['action_type'] == 'PHONE_ENTRY' ||
                l['action_type'] == 'GEN_TICKET_ISSUED',
          )
          .toList();
    } else {
      return _logs
          .where(
            (l) =>
                l['action_type'] != 'MANUAL_TICKET' &&
                l['action_type'] != 'PHONE_ENTRY',
          )
          .toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background.withValues(alpha: 0.8),
        iconTheme: const IconThemeData(color: AppTheme.primary),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.event.title,
              style: AppTheme.headlineStyle.copyWith(fontSize: 16),
            ),
            Text(
              _canViewTeamLogs ? 'TEAM_OPERATIONAL_LOGS'.tr : 'MY_OPERATIONAL_LOGS'.tr,
              style: AppTheme.labelStyle.copyWith(
                fontSize: 10,
                color: AppTheme.secondary,
              ),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          dividerColor: Colors.transparent,
          indicator: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3))),
          labelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 1),
          unselectedLabelColor: Colors.white24,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          tabs: [
            Tab(text: 'SCAN_AUDIT'.tr.toUpperCase()),
            Tab(text: 'MANUAL_ENTRIES'.tr.toUpperCase()),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'SHARE'.tr,
            icon: const Icon(Icons.share_rounded, color: Colors.white24, size: 18),
            onPressed: _shareMyLogs,
          ),
          IconButton(
            icon: const Icon(Icons.help_outline_rounded, color: Colors.white10, size: 14),
            onPressed: () => _showHelp('SHARE_TOOL'),
          ),
          IconButton(
            tooltip: 'DOWNLOAD_TOOL'.tr,
            icon: const Icon(Icons.picture_as_pdf_rounded, color: AppTheme.primary, size: 18),
            onPressed: _downloadMyLogs,
          ),
          IconButton(
            icon: const Icon(Icons.help_outline_rounded, color: Colors.white10, size: 14),
            onPressed: () => _showHelp('DOWNLOAD_TOOL'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                RefreshIndicator(
                  onRefresh: _loadLogs,
                  color: AppTheme.primary,
                  backgroundColor: AppTheme.surfaceContainer,
                  child: _buildLogList(
                    _filterLogs(false),
                    'no_scans_found'.tr,
                  ),
                ),
                RefreshIndicator(
                  onRefresh: _loadLogs,
                  color: AppTheme.primary,
                  backgroundColor: AppTheme.surfaceContainer,
                  child: _buildLogList(
                    _filterLogs(true),
                    'no_manual_found'.tr,
                  ),
                ),
              ],
            ),
    );
  }

  void _shareMyLogs() {
    final summary = """
[Sivox PERSONAL LOG]
Agent: ${_auditService.supabase.auth.currentUser?.userMetadata?['full_name']}
Event: ${widget.event.title}
Operations Recorded: ${_logs.length}
Generated: ${DateTime.now().toIso8601String()}
""";
    SharePlus.instance.share(
      ShareParams(
        text: summary,
      ),
    );
  }

  Future<void> _downloadMyLogs() async {
    await StatsReportService().generateLogReport(
      logs: _logs,
      title: 'Personal Logs: ${_auditService.supabase.auth.currentUser?.userMetadata?['full_name']}',
      subtitle: 'Event: ${widget.event.title}',
    );
  }

  Widget _buildLogList(List<Map<String, dynamic>> logs, String emptyMsg) {
    if (logs.isEmpty) {
      return Center(
        child: Text(emptyMsg, style: const TextStyle(color: Colors.white54)),
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: logs.length,
      separatorBuilder: (context, index) =>
          const Divider(color: Colors.white10),
      itemBuilder: (context, index) {
        final log = logs[index];
        final date = DateTime.tryParse(log['created_at'] ?? '');

        String timeStr = '';
        if (date != null) {
          timeStr = DateFormat('HH:mm').format(date);
        }

        final isMyLog = log['user_id'] == _currentUserId;
        final isManual =
            log['action_type'] == 'MANUAL_BOOKING' ||
            log['action_type'] == 'ON_SITE_GENERATION';

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          leading: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: log['description']?.toString().contains('SUCCESS') == true
                  ? Colors.green.withValues(alpha: 0.1)
                  : log['description']?.toString().contains('LATE_REF') == true
                      ? Colors.red.withValues(alpha: 0.1)
                      : log['description']?.toString().contains('LATE_ACC') == true
                          ? Colors.orange.withValues(alpha: 0.1)
                          : isManual
                              ? AppTheme.secondary.withValues(alpha: 0.1)
                              : AppTheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(
              log['description']?.toString().contains('LATE_REF') == true 
                  ? Icons.gavel_rounded
                  : isManual ? Icons.app_registration : Icons.qr_code_scanner,
              color: log['description']?.toString().contains('SUCCESS') == true
                  ? Colors.greenAccent
                  : log['description']?.toString().contains('LATE_REF') == true
                      ? Colors.redAccent
                      : log['description']?.toString().contains('LATE_ACC') == true
                          ? Colors.orangeAccent
                          : isManual ? AppTheme.secondary : AppTheme.primary,
              size: 20,
            ),
          ),
          title: _buildParsedDescription(
            log['description'] ?? 'UNNAMED_OPERATION',
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.shield_outlined, color: Colors.white24, size: 10),
                  const SizedBox(width: 6),
                  Text(
                    log['user_name']?.toUpperCase() ?? 'UNKNOWN_AGENT',
                    style: TextStyle(
                      color: isManual ? AppTheme.secondary : AppTheme.primary,
                      fontWeight: FontWeight.w900, fontSize: 9, letterSpacing: 1
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Icon(Icons.history_toggle_off_rounded, color: Colors.white24, size: 10),
                  const SizedBox(width: 6),
                  Text(
                    timeStr,
                    style: const TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),
          trailing: isMyLog
              ? IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Colors.white24,
                    size: 16,
                  ),
                  onPressed: () => _handleDelete(log['id'].toString()),
                )
              : null,
        );
      },
    );
  }

  Widget _buildParsedDescription(String description) {
    if (description.contains('|')) {
      final parts = description.split('|').map((e) => e.trim()).toList();
      String mainText = parts[0];
      List<Widget> badges = [];

      for (int i = 1; i < parts.length; i++) {
        final pair = parts[i].split(':');
        if (pair.length == 2) {
          final t = pair[0].trim();
          final v = pair[1].trim();
          badges.add(
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    t,
                    style: const TextStyle(color: Colors.white54, fontSize: 9),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    v,
                    style: const TextStyle(
                      color: AppTheme.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          );
        } else {
          mainText += ' - ${parts[i]}';
        }
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            mainText,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (badges.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: badges),
          ],
        ],
      );
    }

    return Text(
      description,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 13,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Future<void> _handleDelete(String logId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceContainer,
        title: Text('DELETE_LOG'.tr, style: const TextStyle(color: Colors.white)),
        content: Text(
          'DELETE_LOG_CONFIRM'.tr,
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('CANCEL'.tr),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('DELETE'.tr, style: const TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _auditService.deleteLog(logId);
      _loadLogs();
    }
  }
}

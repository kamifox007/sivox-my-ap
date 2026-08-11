import 'package:flutter/material.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/services/audit_service.dart';
import 'package:my_app/services/translation_service.dart';
import 'package:my_app/services/stats_report_service.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';

class MasterOperationalLedgerScreen extends StatefulWidget {
  final String organizerId;
  const MasterOperationalLedgerScreen({super.key, required this.organizerId});

  @override
  State<MasterOperationalLedgerScreen> createState() => _MasterOperationalLedgerScreenState();
}

class _MasterOperationalLedgerScreenState extends State<MasterOperationalLedgerScreen> {
  final _auditService = AuditService();
  List<Map<String, dynamic>> _logs = [];
  List<Map<String, dynamic>> _archives = [];
  Map<String, int> _census = {'total': 0, 'scanned': 0, 'remaining': 0};
  Map<String, int> _security = {'refusals': 0, 'incidents': 0};
  bool _isLoading = true;
  DateTime? _filterDate;

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _auditService.getLogs(
        organizerId: widget.organizerId,
        sourceTable: AuditService.tableOrganizer,
      ),
      _auditService.getGlobalCensus(widget.organizerId),
      _auditService.getMissionArchives(widget.organizerId),
    ]);
    
    if (mounted) {
      setState(() {
        _logs = results[0] as List<Map<String, dynamic>>;
        _census = results[1] as Map<String, int>;
        _archives = results[2] as List<Map<String, dynamic>>;
        
        // Aggregate security stats from logs
        int refusals = 0;
        int incidents = 0;
        for (var l in _logs) {
          final type = l['action_type'].toString();
          if (type.contains('REFUSED')) refusals++;
          if (type.contains('EJECT') || type.contains('BLOCK')) incidents++;
        }
        _security = {'refusals': refusals, 'incidents': incidents};
        
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> _getFilteredLogs(String type) {
    var filtered = _logs;

    // 1. Filter by Date
    if (_filterDate != null) {
      filtered = filtered.where((l) {
        final d = DateTime.tryParse(l['created_at'] ?? '');
        return d != null && 
               d.year == _filterDate!.year && 
               d.month == _filterDate!.month && 
               d.day == _filterDate!.day;
      }).toList();
    }

    // 2. Filter by Category
    if (type == 'ALL') return filtered;
    if (type == 'SECURITY') {
      return filtered.where((l) => 
        l['action_type'].toString().contains('SECURITY') || 
        l['action_type'].toString().contains('REFUSED') ||
        l['action_type'].toString().contains('SCAN') ||
        l['action_type'].toString().contains('EJECT') ||
        l['action_type'].toString().contains('BLOCK') ||
        l['action_type'].toString().contains('ENTRY_CONFIRMED') ||
        l['action_type'].toString().contains('CHECKIN') ||
        l['action_type'].toString().contains('LATE_ACCEPTED')
      ).toList();
    }
    if (type == 'MANAGEMENT') {
      return filtered.where((l) => 
        l['action_type'].toString().contains('EVENT') || 
        l['action_type'].toString().contains('STATUS_UPDATE') ||
        l['action_type'].toString().contains('MANUAL_PERK') ||
        l['action_type'].toString().contains('INVITE') ||
        l['action_type'].toString().contains('GEN_TICKET')
      ).toList();
    }
    if (type == 'GROWTH') {
      return filtered.where((l) => 
        l['action_type'].toString().contains('FOLLOW') ||
        l['action_type'].toString().contains('MARKETING')
      ).toList();
    }
    return filtered;
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _filterDate ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.primary,
              onPrimary: Colors.black,
              surface: Color(0xFF1A1A1A),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _filterDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: _buildNavHeader(),
        body: Stack(
          children: [
            _buildBackground(),
            if (_isLoading)
               const Center(child: CircularProgressIndicator(color: AppTheme.primary))
            else
               Column(
                 children: [
                   _buildCensusMatrix(),
                   Expanded(
                     child: TabBarView(
                       children: [
                         _buildLogListView('ALL'),
                         _buildLogListView('SECURITY'),
                         _buildLogListView('MANAGEMENT'),
                         _buildLogListView('GROWTH'),
                         _buildArchivesListView(),
                       ],
                     ),
                   ),
                 ],
               ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildNavHeader() {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
        onPressed: () => Navigator.pop(context),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('OPERATIONAL_LEDGER'.tr.toUpperCase(), style: AppTheme.headlineStyle.copyWith(fontSize: 12, letterSpacing: 2)),
          Text(widget.organizerId.toUpperCase(), style: const TextStyle(color: AppTheme.secondary, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 1)),
        ],
      ),
      actions: [
        if (_filterDate != null)
           IconButton(icon: const Icon(Icons.close, color: Colors.redAccent, size: 18), onPressed: () => setState(() => _filterDate = null)),
        IconButton(
          tooltip: 'FILTER_BY_DATE'.tr,
          icon: Icon(Icons.calendar_month_rounded, color: _filterDate != null ? AppTheme.primary : Colors.white24, size: 18),
          onPressed: _pickDate,
        ),
        IconButton(
          tooltip: 'SHARE_TOOL'.tr,
          icon: const Icon(Icons.share_rounded, color: Colors.white24, size: 18),
          onPressed: _shareTacticalLog,
        ),
        IconButton(
          tooltip: 'DOWNLOAD_TOOL'.tr,
          icon: const Icon(Icons.picture_as_pdf_rounded, color: AppTheme.primary, size: 18),
          onPressed: _downloadTacticalLog,
        ),
        IconButton(
          tooltip: 'CLEAR_HISTORY'.tr,
          icon: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent, size: 18),
          onPressed: _clearHistory,
        ),
        IconButton(
          tooltip: 'SEAL_ARCHIVE'.tr,
          icon: const Icon(Icons.archive_rounded, color: AppTheme.secondary, size: 18),
          onPressed: _sealMissionArchive,
        ),
        const SizedBox(width: 8),
      ],
      bottom: TabBar(
        isScrollable: true,
        dividerColor: Colors.transparent,
        indicatorColor: AppTheme.primary,
        indicatorPadding: const EdgeInsets.symmetric(horizontal: 16),
        labelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 1),
        unselectedLabelColor: Colors.white24,
        tabs: [
          const Tab(text: 'الخط الزمني'),
          const Tab(text: 'الأمن'),
          const Tab(text: 'الإدارة'),
          const Tab(text: 'النمو'),
          const Tab(text: 'الأرشيفات'),
        ],
      ),
    );
  }

  void _showHelp(String category) {
    String title = category;
    String desc = 'operational_insight'.tr;
    
    if (category == 'SHARE_TOOL') {
      title = 'SHARE_TOOL'.tr;
      desc = 'HELP_SHARE_DESC'.tr;
    } else if (category == 'DOWNLOAD_TOOL') {
      title = 'DOWNLOAD_TOOL'.tr;
      desc = 'HELP_DOWNLOAD_DESC'.tr;
    } else if (category == 'DELETE_TOOL') {
      title = 'DELETE_TOOL'.tr;
      desc = 'HELP_DELETE_DESC'.tr;
    } else if (category == 'CENSUS_MATRIX') {
      title = 'operational_census'.tr;
      desc = 'HELP_CENSUS_DESC'.tr;
    } else if (category == 'ARCHIVE_TOOL') {
      title = 'SEAL_ARCHIVE'.tr;
      desc = 'HELP_ARCHIVE_DESC'.tr;
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

  Future<void> _sealMissionArchive() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('SEAL_ARCHIVE'.tr, style: const TextStyle(color: Colors.white)),
        content: Text('SEAL_ARCHIVE_WARNING'.tr, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('CANCEL'.tr)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('PROCEED'.tr, style: const TextStyle(color: AppTheme.secondary)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      final success = await _auditService.finalizeAndArchiveMission(
        clubId: widget.organizerId,
        title: 'Mission Snapshot ${DateTime.now().toString().substring(0, 10)}',
        census: _census,
        security: _security,
      );

      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(success ? 'mission_sealed_success'.tr : 'action_failed'.tr)),
        );
      }
    }
  }

  Widget _buildCensusMatrix() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('OPERATIONAL_CENSUS'.tr.toUpperCase(), style: const TextStyle(color: Colors.white24, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 2)),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _showHelp('CENSUS_MATRIX'),
                child: const Icon(Icons.help_outline_rounded, color: Colors.white10, size: 12),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _censusCard('TOTAL_PERSONS'.tr, _census['total'].toString(), AppTheme.primary),
              const SizedBox(width: 12),
              _censusCard('CHECKED_IN'.tr, _census['scanned'].toString(), Colors.greenAccent),
              const SizedBox(width: 12),
              _censusCard('REMAINING_PERSONS'.tr, _census['remaining'].toString(), Colors.orangeAccent),
            ],
          ),
        ],
      ),
    );
  }

  Widget _censusCard(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(), style: const TextStyle(color: Colors.white24, fontSize: 7, fontWeight: FontWeight.w900, letterSpacing: 1)),
            const SizedBox(height: 8),
            Text(value, style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -1)),
          ],
        ),
      ),
    );
  }

  Widget _buildLogListView(String type) {
    final filtered = _getFilteredLogs(type);
    if (filtered.isEmpty) return _buildEmptyState();

    // Group logs by date (YYYY-MM-DD)
    final Map<String, List<Map<String, dynamic>>> groupedByDay = {};
    for (final log in filtered) {
      final date = DateTime.tryParse(log['created_at'] ?? '');
      final dayKey = date != null ? DateFormat('yyyy-MM-dd').format(date) : 'unknown';
      groupedByDay.putIfAbsent(dayKey, () => []).add(log);
    }

    // Sort days descending (newest first)
    final sortedDays = groupedByDay.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    return RefreshIndicator(
      onRefresh: _loadAllData,
      color: AppTheme.primary,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
        itemCount: sortedDays.length,
        itemBuilder: (context, dayIndex) {
          final day = sortedDays[dayIndex];
          final dayLogs = groupedByDay[day]!;
          final date = DateTime.tryParse(day);
          final isToday = date != null && DateFormat('yyyy-MM-dd').format(DateTime.now()) == day;
          final dayLabel = date != null
              ? (isToday ? 'اليوم • ${DateFormat('EEEE d MMMM', 'ar').format(date)}' : DateFormat('EEEE d MMMM yyyy', 'ar').format(date))
              : day;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── DATE HEADER ──────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 24, 4, 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: isToday ? AppTheme.primary.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isToday ? AppTheme.primary.withValues(alpha: 0.4) : Colors.white10,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isToday ? Icons.radio_button_checked_rounded : Icons.calendar_today_outlined,
                            color: isToday ? AppTheme.primary : Colors.white38,
                            size: 11,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            dayLabel,
                            style: TextStyle(
                              color: isToday ? AppTheme.primary : Colors.white54,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.05))),
                    const SizedBox(width: 8),
                    Text(
                      '${dayLogs.length}',
                      style: const TextStyle(color: Colors.white24, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              // ── LOGS FOR THIS DAY ─────────────────────────────────────────
              ...dayLogs.map((log) => _LogTile(log: log)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Text('NO_MISSION_RECORDS'.tr, style: const TextStyle(color: Colors.white24, fontSize: 12)),
    );
  }

  Widget _buildArchivesListView() {
    if (_archives.isEmpty) {
      return const Center(
        child: Text('لا توجد سجلات مؤرشفة بعد.', style: TextStyle(color: Colors.white24, fontSize: 12)),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAllData,
      color: AppTheme.primary,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        itemCount: _archives.length,
        itemBuilder: (context, index) {
          final archive = _archives[index];
          final metrics = archive['metrics'] as Map<String, dynamic>? ?? {};
          final date = DateTime.tryParse(archive['finalized_at'] ?? '');
          final dateStr = date != null ? DateFormat('yyyy-MM-dd HH:mm').format(date) : '';

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.secondary.withValues(alpha: 0.1)),
            ),
            child: ExpansionTile(
              backgroundColor: Colors.transparent,
              collapsedBackgroundColor: Colors.transparent,
              title: Text(
                archive['title'] ?? 'أرشيف الفعالية', 
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)
              ),
              subtitle: Text(dateStr, style: const TextStyle(color: Colors.white24, fontSize: 10)),
              trailing: const Icon(Icons.keyboard_arrow_down, color: AppTheme.secondary),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Divider(color: Colors.white10, height: 1),
                      const SizedBox(height: 16),
                      _archiveStatRow('العدد الكلي للتذاكر', metrics['total'].toString()),
                      _archiveStatRow('الذين دخلوا بالفعل', metrics['scanned'].toString()),
                      const SizedBox(height: 12),
                      const Text('التقرير الأمني', style: TextStyle(color: AppTheme.primary, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                      const SizedBox(height: 8),
                      _archiveStatRow('تذاكر مرفوضة', (metrics['security']?['refusals'] ?? 0).toString()),
                      _archiveStatRow('أشخاص تم حظرهم', (metrics['security']?['blocks'] ?? 0).toString()),
                      _archiveStatRow('أشخاص تم طردهم', (metrics['security']?['ejections'] ?? 0).toString()),
                      const Divider(color: Colors.white10, height: 32),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                            onPressed: () => _deleteArchive(archive['id']?.toString() ?? ''),
                            tooltip: 'حذف الأرشيف',
                          ),
                          IconButton(
                            icon: const Icon(Icons.share_rounded, color: Colors.white24, size: 20),
                            onPressed: () => _shareArchive(archive),
                            tooltip: 'مشاركة',
                          ),
                          IconButton(
                            icon: const Icon(Icons.picture_as_pdf_rounded, color: AppTheme.primary, size: 20),
                            onPressed: () => _downloadArchive(archive),
                            tooltip: 'تحميل PDF',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _deleteArchive(String id) async {
    if (id.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('حذف الأرشيف', style: TextStyle(color: Colors.white)),
        content: const Text('هل أنت متأكد من حذف هذا الأرشيف نهائياً؟', style: TextStyle(color: Colors.white70)),
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
      setState(() => _isLoading = true);
      final success = await _auditService.deleteMissionArchive(id);
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(success ? 'تم حذف الأرشيف بنجاح' : 'فشلت العملية')),
        );
        _loadAllData();
      }
    }
  }

  void _shareArchive(Map<String, dynamic> archive) {
    final metrics = archive['metrics'] as Map<String, dynamic>? ?? {};
    final summary = """
[أرشيف الفعالية: ${archive['title']}]
العدد الكلي للتذاكر: ${metrics['total']}
الذين دخلوا: ${metrics['scanned']}
تذاكر مرفوضة: ${metrics['security']?['refusals'] ?? 0}
أشخاص تم حظرهم: ${metrics['security']?['blocks'] ?? 0}
أشخاص تم طردهم: ${metrics['security']?['ejections'] ?? 0}
""";
    SharePlus.instance.share(ShareParams(text: summary));
  }

  Future<void> _downloadArchive(Map<String, dynamic> archive) async {
    final metrics = archive['metrics'] as Map<String, dynamic>? ?? {};
    final logs = metrics['detailed_logs'] as List<dynamic>? ?? [];
    
    await StatsReportService().generateLogReport(
      logs: logs.map((l) => Map<String, dynamic>.from(l)).toList(),
      title: archive['title'] ?? 'أرشيف الفعالية',
      subtitle: 'العدد الكلي: ${metrics['total']} | الدخول: ${metrics['scanned']}',
    );
  }

  Widget _archiveStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
        ],
      ),
    );
  }

  void _shareTacticalLog() {
    final summary = """
[Sivox OPERATIONAL LOG]
Club ID: ${widget.organizerId}
Total Bookings: ${_census['total']}
Actual Arrived: ${_census['scanned']}
Log Count: ${_logs.length}
Generated: ${DateTime.now().toIso8601String()}
""";
    SharePlus.instance.share(
      ShareParams(
        text: summary,
      ),
    );
  }

  Future<void> _downloadTacticalLog() async {
    await StatsReportService().generateLogReport(
      logs: _logs,
      title: 'Mission Matrix: ${widget.organizerId}',
      subtitle: 'Operational Census: ${_census['total']} Total | ${_census['scanned']} Arrived',
    );
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('CLEAR_LOGS'.tr, style: const TextStyle(color: Colors.white)),
        content: Text('CLEAR_LOGS_WARNING'.tr, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('CANCEL'.tr)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('CLEAR'.tr, style: const TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      final success = await _auditService.clearAllOrganizerLogs(widget.organizerId);
      
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(success ? 'history_cleared'.tr : 'action_failed'.tr))
        );
        _loadAllData();
      }
    }
  }

  Widget _buildBackground() {
    return Positioned.fill(
      child: Stack(
        children: [
          Positioned(top: -50, right: -50, child: Container(width: 250, height: 250, decoration: BoxDecoration(shape: BoxShape.circle, color: AppTheme.primary.withValues(alpha: 0.03), boxShadow: [BoxShadow(color: AppTheme.primary.withValues(alpha: 0.05), blurRadius: 100)]))),
        ],
      ),
    );
  }
}

class _LogTile extends StatelessWidget {
  final Map<String, dynamic> log;
  const _LogTile({required this.log});

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(log['created_at'] ?? '');
    final timeStr = date != null ? DateFormat('HH:mm').format(date) : '--:--';
    
    final type = log['action_type']?.toString() ?? 'GENERAL';
    final role = log['role']?.toString() ?? 'SYSTEM';
    
    final isEntry = type.contains('ACCEPTED') || type.contains('CLEAR') || type.contains('ENTRY') || type.contains('CHECKIN');
    final isWarning = type.contains('REFUSED') || type.contains('BLOCK') || type.contains('EJECT');
    
    final Color accent = isWarning ? Colors.redAccent : (isEntry ? AppTheme.primary : AppTheme.secondary);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: accent.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
               Container(
                 padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                 decoration: BoxDecoration(
                   color: accent.withValues(alpha: 0.1), 
                   borderRadius: BorderRadius.circular(8),
                   border: Border.all(color: accent.withValues(alpha: 0.2)),
                 ),
                 child: Text(
                   type.replaceAll('_', ' ').toUpperCase(), 
                   style: TextStyle(color: accent, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1.5),
                 ),
               ),
               const Spacer(),
               Text(timeStr, style: const TextStyle(color: Colors.white24, fontSize: 10, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 16),
          Text(log['description'] ?? 'No tactical description provided.', style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4, fontWeight: FontWeight.w500)),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), shape: BoxShape.circle),
                child: Icon(_getAgentIcon(role, type), color: Colors.white38, size: 12),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'MISSION AGENT: ${log['user_name'] ?? 'TERMINAL'}'.toUpperCase(), 
                  style: const TextStyle(color: Colors.white24, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 1),
                ),
              ),
              if (log['metadata']?['discount_applied'] == true) ...[
                const SizedBox(width: 8),
                const Icon(Icons.confirmation_num_outlined, color: Colors.amberAccent, size: 14),
              ],
            ],
          ),
        ],
      ),
    );
  }

  IconData _getAgentIcon(String role, String type) {
    if (type.contains('SCAN') || type.contains('REFUSED') || type.contains('SECURITY')) return Icons.shield_rounded;
    if (type.contains('FOLLOW')) return Icons.trending_up_rounded;
    if (role == 'manager' || role == 'organizer') return Icons.stars_rounded;
    return Icons.settings_rounded;
  }
}

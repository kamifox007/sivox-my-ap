import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/services/translation_service.dart';
import 'package:my_app/services/event_service.dart';
import 'package:my_app/services/booking_service.dart';
import 'package:my_app/services/audit_service.dart';
import 'package:my_app/services/stats_report_service.dart';
import 'package:my_app/models/event.dart';
import 'package:my_app/screens/master_operational_ledger.dart';
import 'package:my_app/screens/organizer_main_wrapper.dart';
import 'package:my_app/screens/blacklist_management_screen.dart';
import 'package:my_app/screens/vetting_hub_screen.dart';

class MissionMatrixScreen extends StatefulWidget {
  final String? organizerId;
  final String? eventId;
  final String? clubName;
  const MissionMatrixScreen({super.key, this.organizerId, this.eventId, this.clubName});

  @override
  State<MissionMatrixScreen> createState() => _MissionMatrixScreenState();
}

class _MissionMatrixScreenState extends State<MissionMatrixScreen> {
  final _eventService = EventService();
  final _bookingService = BookingService();
  final _auditService = AuditService();
  final supabase = Supabase.instance.client;

  List<Event> _events = [];
  Event? _selectedEvent;
  bool _isLoading = true;

  // Stats Data
  int _totalBookings = 0;
  int _arrivedCount = 0;
  int _capacity = 0;
  double _globalRevenue = 0;
  Map<int, int> _hourlyEntries = {};
  Map<String, int> _statusDist = {};
  Map<String, int> _securityStats = {
    'ejections': 0,
    'blocks': 0,
    'refusals': 0,
  };
  int _followerCount = 0;
  List<Map<String, dynamic>> _recentLogs = [];

  @override
  void initState() {
    super.initState();
    _loadEvents();
    _subscribeToLiveUpdates();
  }

  RealtimeChannel? _missionSubscription;
  void _subscribeToLiveUpdates() {
    if (widget.organizerId != null) {
      _missionSubscription = _auditService.subscribeToMissions(widget.organizerId!, (data) {
        if (mounted) {
          // Trigger a silent reload of stats
          _loadStats(isSilent: true);
          
          // Show a tactical alert snackbar
          final type = data['action_type'] ?? 'ACTION';
          final desc = data['description'] ?? '';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.bolt, color: AppTheme.secondary, size: 16),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'LIVE: $type - $desc'.toUpperCase(),
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1),
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.black,
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(16),
              duration: const Duration(seconds: 2),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: AppTheme.secondary.withValues(alpha: 0.3))),
            ),
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _missionSubscription?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadEvents() async {
    setState(() => _isLoading = true);

    if (widget.eventId != null) {
      final event = await _eventService.getEventById(widget.eventId!);
      if (mounted) {
        setState(() {
          _selectedEvent = event;
          _events = event != null ? [event] : [];
          if (_selectedEvent != null) {
            _loadStats();
          } else {
            _isLoading = false;
          }
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
        // Default to Global Overview if not specified
        _selectedEvent = null;
        _loadStats();
      });
    }
  }

  Future<void> _loadStats({bool isSilent = false}) async {
    if (!isSilent) setState(() => _isLoading = true);
    _recentLogs = []; // Clear old logs before loading new ones
    _recentLogs = []; // Clear old logs before loading new ones

    if (_selectedEvent == null) {
      // GLOBAL OVERVIEW
      int totalB = 0;
      int arrivedC = 0;
      int totalCap = 0;
      double totalRev = 0;
      Map<int, int> combinedHourly = {};
      Map<String, int> combinedStatus = {};
      Map<String, int> combinedSecurity = {
        'ejections': 0,
        'blocks': 0,
        'refusals': 0,
      };

      // OPTIMIZED: Parallel Data Fetching
      final List<Future> queries = _events.map((event) async {
        final results = await Future.wait([
          _bookingService.getTotalPersonsForEvent(event.id),
          _bookingService.getScannedCountForEvent(event.id),
          _bookingService.getEventAnalytics(event.id),
          _auditService.getSecurityStats(event.id),
          _auditService.getLogs(eventId: event.id),
        ]);

        final total = results[0] as int;
        final arrived = results[1] as int;
        final analytics = results[2] as Map<String, dynamic>;
        final security = results[3] as Map<String, int>;
        final logs = results[4] as List<Map<String, dynamic>>;

        totalB += total;
        arrivedC += arrived;
        totalCap += (event.maxCapacity ?? 0);
        totalRev += (arrived * event.price).toDouble();
        _recentLogs.addAll(logs);

        // Merge Hourly
        (analytics['hourly_entries'] as Map<dynamic, dynamic>?)?.forEach((
          h,
          c,
        ) {
          final hour = h is int ? h : int.parse(h.toString());
          combinedHourly[hour] =
              (combinedHourly[hour] ?? 0) + (c as num).toInt();
        });

        // Merge Status
        (analytics['status_distribution'] as Map<dynamic, dynamic>?)?.forEach((
          s,
          c,
        ) {
          combinedStatus[s.toString()] =
              (combinedStatus[s.toString()] ?? 0) + (c as num).toInt();
        });

        // Merge Security
        security.forEach((k, v) {
          combinedSecurity[k] = (combinedSecurity[k] ?? 0) + v;
        });
      }).toList();

      await Future.wait(queries);
      // Sort combined logs
      _recentLogs.sort((a, b) {
        final dateA = a['created_at']?.toString() ?? '';
        final dateB = b['created_at']?.toString() ?? '';
        return dateB.compareTo(dateA);
      });

      if (mounted) {
        int followerCount = 0;
        if (widget.organizerId != null) {
          final followRes = await supabase
              .from('follows')
              .select('id')
              .eq('following_id', widget.organizerId!);
          followerCount = (followRes as List).length;
        }
        setState(() {
          _totalBookings = totalB;
          _arrivedCount = arrivedC;
          _capacity = totalCap;
          _globalRevenue = totalRev;
          _hourlyEntries = combinedHourly;
          _statusDist = combinedStatus;
          _securityStats = combinedSecurity;
          _followerCount = followerCount;
          _isLoading = false;
        });
      }
    } else {
      // SINGLE EVENT STATS
      final total = await _bookingService.getTotalPersonsForEvent(
        _selectedEvent!.id,
      );
      final arrived = await _bookingService.getScannedCountForEvent(
        _selectedEvent!.id,
      );
      final analytics = await _bookingService.getEventAnalytics(
        _selectedEvent!.id,
      );
      final security = await _auditService.getSecurityStats(_selectedEvent!.id);
      final logs = await _auditService.getLogs(eventId: _selectedEvent!.id);

      if (mounted) {
        int followerCount = 0;
        if (widget.organizerId != null) {
          final followRes = await supabase
              .from('follows')
              .select('id')
              .eq('following_id', widget.organizerId!);
          followerCount = (followRes as List).length;
        }
        setState(() {
          _totalBookings = total;
          _arrivedCount = arrived;
          _capacity = _selectedEvent!.maxCapacity ?? 0;
          _hourlyEntries = {};
          (analytics['hourly_entries'] as Map<dynamic, dynamic>?)?.forEach((h, c) {
            final hour = h is int ? h : int.tryParse(h.toString()) ?? 0;
            _hourlyEntries[hour] = (c as num).toInt();
          });
          _statusDist = {};
          (analytics['status_distribution'] as Map<dynamic, dynamic>?)?.forEach((s, c) {
            _statusDist[s.toString()] = (c as num).toInt();
          });
          _securityStats = security;
          _recentLogs = logs;
          _followerCount = followerCount;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          Positioned(
            top: -100,
            right: -100,
            child: _aura(AppTheme.primary.withValues(alpha: 0.08)),
          ),
          Positioned(
            bottom: -100,
            left: -100,
            child: _aura(AppTheme.secondary.withValues(alpha: 0.05)),
          ),

          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              _buildAppBar(),
              if (_events.isEmpty && !_isLoading)
                _buildEmptyState()
              else ...[
                _buildSelector(),
                if (_isLoading)
                  const SliverFillRemaining(
                    child: Center(
                      child: CircularProgressIndicator(color: AppTheme.primary),
                    ),
                  )
                else
                  _buildStatsContent(),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _aura(Color c) => Container(
    width: 400,
    height: 400,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      boxShadow: [BoxShadow(color: c, blurRadius: 200)],
    ),
  );

  Widget _buildAppBar() {
    return SliverAppBar(
      expandedHeight: 80,
      backgroundColor: Colors.transparent,
      pinned: true,
      centerTitle: true,
      elevation: 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'البث الحي للعمليات',
            style: AppTheme.headlineStyle.copyWith(
              fontSize: 14,
              letterSpacing: 2,
            ),
          ),
          if (widget.clubName != null)
            Text(
              widget.clubName!.toUpperCase(),
              style: const TextStyle(
                color: AppTheme.primary,
                fontSize: 8,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
        ],
      ),
      leading: IconButton(
        icon: const Icon(
          Icons.arrow_back_ios_new,
          color: Colors.white,
          size: 18,
        ),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        IconButton(
          tooltip: 'REFRESH'.tr,
          icon: const Icon(Icons.refresh_rounded, color: AppTheme.primary, size: 20),
          onPressed: () => _loadStats(),
        ),
        IconButton(
          tooltip: 'DOWNLOAD_REPORT'.tr,
          icon: const Icon(Icons.picture_as_pdf_rounded, color: AppTheme.primary, size: 20),
          onPressed: () async {
            await StatsReportService().generateAndPrintReport(
              event: _selectedEvent,
              stats: _statusDist,
              security: _securityStats,
              totalBooked: _totalBookings,
              arrived: _arrivedCount,
              globalRevenue: _selectedEvent == null ? _globalRevenue : null,
            );
          },
        ),
        IconButton(
          tooltip: 'TACTICAL_VETTING'.tr,
          icon: const Icon(Icons.verified_user_rounded, color: AppTheme.secondary, size: 20),
          onPressed: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => VettingHubScreen(
              eventId: _selectedEvent?.id,
              clubId: widget.organizerId,
            )));
          },
        ),
        IconButton(
          tooltip: 'BLACKLIST'.tr,
          icon: const Icon(Icons.security, color: Colors.white24, size: 20),
          onPressed: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => BlacklistManagementScreen(clubId: widget.organizerId ?? supabase.auth.currentUser!.id)));
          },
        ),
        IconButton(
          tooltip: 'OPERATIONAL_LEDGER'.tr,
          icon: const Icon(Icons.history_edu_rounded, color: Colors.white24, size: 20),
          onPressed: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => MasterOperationalLedgerScreen(organizerId: widget.organizerId ?? supabase.auth.currentUser!.id)));
          },
        ),
        IconButton(
          icon: const Icon(Icons.switch_account_rounded, color: Colors.white24, size: 20),
          onPressed: () {
            final wrapper = OrganizerMainWrapper.of(context);
            if (wrapper != null) wrapper.openSelector();
          },
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildEmptyState() {
    return SliverFillRemaining(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.bar_chart_outlined,
              size: 80,
              color: Colors.white10,
            ),
            const SizedBox(height: 24),
            Text(
              'no_events_found'.tr,
              style: const TextStyle(color: Colors.white38, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelector() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<Event?>(
                  value: _selectedEvent,
                  dropdownColor: const Color(0xFF1A1A1A),
                  icon: const Icon(
                    Icons.keyboard_arrow_down,
                    color: AppTheme.primary,
                  ),
                  isExpanded: true,
                  items: [
                    DropdownMenuItem<Event?>(
                      value: null,
                      child: Text(
                        'global_overview'.tr.toUpperCase(),
                        style: const TextStyle(
                          color: AppTheme.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                    ..._events.map(
                      (e) => DropdownMenuItem<Event?>(
                        value: e,
                        child: Text(
                          e.title.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ),
                  ],
                  onChanged: (e) {
                    setState(() {
                      _selectedEvent = e;
                      _loadStats();
                    });
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatsContent() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            _buildMainMetricsRow(),
            const SizedBox(height: 24),
            _buildEventsRecapSection(),
            const SizedBox(height: 24),
            _buildCapacityTracker(),
            const SizedBox(height: 24),
            _buildAudienceSection(),
            const SizedBox(height: 32),
            _buildChartSection(
              title: 'entry_trend'.tr,
              subtitle: 'hourly_entries_title'.tr,
              child: _buildHourlyTrendChart(),
            ),
            const SizedBox(height: 32),
            _buildFullLedgerNavigation(),
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: _buildChartSection(
                    title: 'status_distribution'.tr,
                    subtitle: 'checkin_modes'.tr,
                    child: _buildStatusPieChart(),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(flex: 2, child: _buildSecurityRecapSection()),
              ],
            ),
            const SizedBox(height: 24),
            _buildStaffPerformanceSection(),
            const SizedBox(height: 48),
            _buildActivitySection(),
          ],
        ),
      ),
    );
  }

  Widget _buildStaffPerformanceSection() {
    // Aggregate logs by user_name
    final Map<String, int> performance = {};
    for (var log in _recentLogs) {
      final name = log['user_name'] ?? 'staff'.tr;
      performance[name] = (performance[name] ?? 0) + 1;
    }

    final sortedStaff = performance.keys.toList()
      ..sort((a, b) => performance[b]!.compareTo(performance[a]!));
    final topStaff = sortedStaff.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'STAFF_EFFICIENCY'.tr.toUpperCase(),
              style: const TextStyle(
                color: AppTheme.primary,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _showHelp('STAFF_EFFICIENCY'.tr),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), shape: BoxShape.circle),
                child: const Icon(Icons.help_outline_rounded, color: Colors.white24, size: 10),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            children: topStaff.isEmpty
                ? [
                    Center(
                      child: Text(
                        'NO_DATA'.tr,
                        style: const TextStyle(color: Colors.white10),
                      ),
                    ),
                  ]
                : topStaff.map((name) {
                    final count = performance[name]!;
                    final progress = count / (performance[topStaff.first] ?? 1);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                '$count actions'.tr,
                                style: const TextStyle(
                                  color: AppTheme.primary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: progress,
                            backgroundColor: Colors.white10,
                            color: AppTheme.primary,
                            minHeight: 2,
                          ),
                        ],
                      ),
                    );
                  }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildMainMetricsRow() {
    final securityTotal = (_securityStats['ejections'] ?? 0) + 
                         (_securityStats['blocks'] ?? 0) + 
                         (_securityStats['refusals'] ?? 0);
    return Row(
      children: [
        Expanded(
          child: _metricCard(
            'TOTAL_BOOKINGS'.tr,
            '$_totalBookings',
            Icons.confirmation_num_outlined,
            AppTheme.secondary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _metricCard(
            'FIELD_CENSUS'.tr,
            '$_arrivedCount',
            Icons.login_rounded,
            AppTheme.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _metricCard(
            'SECURITY_INCIDENTS'.tr,
            '$securityTotal',
            Icons.gavel_rounded,
            Colors.redAccent,
          ),
        ),
      ],
    );
  }

  Widget _metricCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 16),
          Text(
            value,
            style: AppTheme.headlineStyle.copyWith(
              fontSize: 22,
              color: Colors.white,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    color: color.withValues(alpha: 0.6),
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => _showHelp(label),
                child: Tooltip(
                  message: 'MORE_INFO'.tr,
                  child: Icon(Icons.help_outline_rounded, color: color.withValues(alpha: 0.3), size: 10),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChartSection({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainer,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _showHelp(title),
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), shape: BoxShape.circle),
                  child: const Icon(Icons.help_outline_rounded, color: Colors.white24, size: 10),
                ),
              ),
            ],
          ),
          Text(
            subtitle,
            style: const TextStyle(color: Colors.white38, fontSize: 10),
          ),
          const SizedBox(height: 32),
          SizedBox(height: 200, child: child),
        ],
      ),
    );
  }

  Widget _buildHourlyTrendChart() {
    if (_hourlyEntries.isEmpty) {
      return const Center(
        child: Text(
          'Waiting for entries...',
          style: TextStyle(color: Colors.white12),
        ),
      );
    }

    // Sort hours
    final sortedHours = _hourlyEntries.keys.toList()..sort();
    final spots = sortedHours
        .map((h) => FlSpot(h.toDouble(), _hourlyEntries[h]!.toDouble()))
        .toList();

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (val, _) => Text(
                '${val.toInt()}:00',
                style: const TextStyle(color: Colors.white24, fontSize: 8),
              ),
              interval: 1,
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: AppTheme.primary,
            barWidth: 4,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  AppTheme.primary.withValues(alpha: 0.3),
                  AppTheme.primary.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPieChart() {
    if (_statusDist.isEmpty) return const SizedBox.shrink();

    final used = _statusDist['used']?.toDouble() ?? 0;
    final late = _statusDist['late_accepted']?.toDouble() ?? 0;
    final confirmed = _statusDist['confirmed']?.toDouble() ?? 0;

    return PieChart(
      PieChartData(
        sectionsSpace: 4,
        centerSpaceRadius: 40,
        sections: [
          PieChartSectionData(
            value: used,
            color: AppTheme.primary,
            title: '',
            radius: 15,
          ),
          PieChartSectionData(
            value: late,
            color: Colors.orangeAccent,
            title: '',
            radius: 15,
          ),
          PieChartSectionData(
            value: confirmed,
            color: Colors.white10,
            title: '',
            radius: 10,
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityRecapSection() {
    return Column(
      children: [
        _miniSecurityCard(
          'rejected'.tr,
          _securityStats['refusals'].toString(),
          Colors.redAccent,
        ),
        const SizedBox(height: 8),
        _miniSecurityCard(
          'ejected'.tr,
          _securityStats['ejections'].toString(),
          Colors.orangeAccent,
        ),
        const SizedBox(height: 8),
        _miniSecurityCard(
          'blocked'.tr,
          _securityStats['blocks'].toString(),
          Colors.deepPurpleAccent,
        ),
      ],
    );
  }

  Widget _miniSecurityCard(String label, String value, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: color.withValues(alpha: 0.4),
              fontSize: 7,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCapacityTracker() {
    if (_capacity <= 0) return const SizedBox.shrink();
    final capRate = (_arrivedCount / _capacity).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.primary.withValues(alpha: 0.1), Colors.transparent],
        ),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    'capacity_usage'.tr.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _showHelp('capacity_usage'.tr),
                    child: Tooltip(
                      message: 'MORE_INFO'.tr,
                      child: const Icon(Icons.help_outline_rounded, color: Colors.white24, size: 10),
                    ),
                  ),
                ],
              ),
              Text(
                '${(capRate * 100).toInt()}%',
                style: const TextStyle(
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Stack(
            children: [
              Container(
                height: 12,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              FractionallySizedBox(
                widthFactor: capRate,
                child: Container(
                  height: 12,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppTheme.primary, AppTheme.secondary],
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${'arrived'.tr}: $_arrivedCount / $_capacity',
            style: const TextStyle(
              color: Colors.white24,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivitySection() {
    final eventId = _selectedEvent?.id;

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: supabase
          .from('staff_logs')
          .stream(primaryKey: ['id'])
          .eq('related_event_id', eventId ?? '')
          .limit(5)
          .order('created_at', ascending: false),
      builder: (context, snapshot) {
        final logs = eventId == null ? _recentLogs : (snapshot.data ?? []);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'recent_security_activity'.tr.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
                IconButton(
                  onPressed: () => _showHelp('recent_security_activity'.tr),
                  icon: const Icon(
                    Icons.help_outline_rounded,
                    color: Colors.white24,
                    size: 10,
                  ),
                ),
                const Spacer(),
                const Icon(
                  Icons.history_toggle_off_rounded,
                  color: Colors.white24,
                  size: 16,
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (logs.isEmpty)
              Padding(
                padding: const EdgeInsets.all(48),
                child: Center(
                  child: Column(
                    children: [
                      const Icon(
                        Icons.shield_outlined,
                        color: Colors.white10,
                        size: 32,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No recent actions'.tr,
                        style: const TextStyle(
                          color: Colors.white10,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: logs.length.clamp(0, 5),
                itemBuilder: (context, index) => _logTile(logs[index]),
              ),
          ],
        );
      },
    );
  }

  Widget _logTile(Map<String, dynamic> log) {
    final type = log['action_type'] ?? '';
    final color = type.contains('EJECT')
        ? Colors.orangeAccent
        : (type.contains('REF') ? Colors.redAccent : Colors.white24);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.security_rounded, size: 16, color: color),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  log['description'] ?? '',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.person_outline,
                      size: 10,
                      color: Colors.white24,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      log['user_name'] ?? 'Staff',
                      style: const TextStyle(
                        color: Colors.white24,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Text(
            log['created_at'] != null
                ? DateTime.tryParse(
                        log['created_at'],
                      )?.toLocal().toString().substring(11, 16) ??
                      ''
                : '',
            style: const TextStyle(
              color: Colors.white12,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAudienceSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'AUDIENCE_INTELLIGENCE'.tr.toUpperCase(),
          style: const TextStyle(
            color: AppTheme.secondary,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppTheme.secondary.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: AppTheme.secondary.withValues(alpha: 0.1)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$_followerCount',
                      style: AppTheme.headlineStyle.copyWith(
                        fontSize: 32,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'total_fans'.tr.toUpperCase(),
                      style: TextStyle(
                        color: AppTheme.secondary.withValues(alpha: 0.6),
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: _showFollowersSheet,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.secondary,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
                child: Text(
                  'manage_fans'.tr,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showFollowersSheet() {
    if (widget.organizerId == null) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.85,
        decoration: const BoxDecoration(
          color: Color(0xFF111111),
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back_ios_new,
                      color: Colors.white,
                      size: 20,
                    ),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'fan_base'.tr.toUpperCase(),
                    style: AppTheme.headlineStyle.copyWith(
                      fontSize: 16,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white10, height: 40),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: supabase
                    .from('follows')
                    .select('follower_id, profiles!follower_id(full_name, avatar_url)')
                    .eq('following_id', widget.organizerId!),
                builder: (ctx, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final fans = snap.data ?? [];
                  if (fans.isEmpty) {
                    return Center(
                      child: Text(
                        'no_followers_yet'.tr,
                        style: const TextStyle(color: Colors.white24),
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    itemCount: fans.length,
                    itemBuilder: (ctx, i) {
                      final profile = fans[i]['profiles'] ?? {};
                      final name = profile['full_name'] ?? 'Fan';
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.02),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.03)),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            radius: 20,
                            backgroundImage:
                                profile['avatar_url'] != null
                                    ? NetworkImage(profile['avatar_url'])
                                    : null,
                            backgroundColor: Colors.white.withValues(alpha: 0.05),
                            child:
                                profile['avatar_url'] == null
                                    ? Text(
                                      name[0].toUpperCase(),
                                      style: const TextStyle(
                                        color: AppTheme.secondary,
                                        fontSize: 12,
                                      ),
                                    )
                                    : null,
                          ),
                          title: Text(
                            name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            'FAN'.tr,
                            style: const TextStyle(
                              color: Colors.white24,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFullLedgerNavigation() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.1)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => MasterOperationalLedgerScreen(
                  organizerId: widget.organizerId ?? supabase.auth.currentUser!.id,
                ),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.history_edu_rounded, color: AppTheme.primary, size: 24),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'VIEW_FULL_LOGS'.tr.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          letterSpacing: 1,
                        ),
                      ),
                      Text(
                        'detailed_tactical_ledger'.tr,
                        style: const TextStyle(color: Colors.white24, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded, color: AppTheme.primary, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEventsRecapSection() {
    if (_selectedEvent != null) return const SizedBox.shrink(); // Only show in Global mode
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'EVENT_ARCHIVE'.tr.toUpperCase(),
          style: const TextStyle(
            color: Colors.white24,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 16),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _events.length.clamp(0, 5),
          itemBuilder: (context, index) {
            final e = _events[index];
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.02),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                        Text(e.dateTime ?? '', style: const TextStyle(color: Colors.white24, fontSize: 9)),
                      ],
                    ),
                  ),
                  _miniStat(e.arrivedCount.toString(), AppTheme.primary),
                  const SizedBox(width: 8),
                  _miniStat(e.bookingsCount.toString(), AppTheme.secondary),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _miniStat(String val, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(val, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900)),
    );
  }

  void _showHelp(String title) {
    String desc = 'ميزة قيد التطوير أو لا يوجد شرح لها حالياً.';
    if (title == 'SECURITY_INCIDENTS'.tr) desc = 'تعرض عدد الحالات الأمنية مثل الطرد أو المنع عند الباب.';
    if (title == 'FIELD_CENSUS'.tr) desc = 'تعرض عدد الأشخاص الذين دخلوا الحفل بالفعل حتى الآن.';
    if (title == 'TOTAL_BOOKINGS'.tr) desc = 'تعرض العدد الكلي للتذاكر المحجوزة لهذا الحفل.';
    if (title == 'capacity_usage'.tr) desc = 'توضح نسبة امتلاء القاعة مقارنة بالطاقة الاستيعابية القصوى.';
    if (title == 'THE_VAULT'.tr) desc = 'تعرض المبالغ المالية التي تم جمعها كاش عند الباب.';
    if (title == 'recent_security_activity'.tr) desc = 'تعرض آخر العمليات التي قام بها طاقم الأمن.';
    if (title == 'entry_trend'.tr) desc = 'مخطط بياني يوضح أوقات الذروة لدخول الزوار حسب الساعات.';
    if (title == 'status_distribution'.tr) desc = 'يوضح توزيع التذاكر حسب حالتها (مستخدمة، متأخرة، مؤكدة).';
    if (title == 'STAFF_EFFICIENCY'.tr) desc = 'يوضح نشاط كل فرد من طاقم العمل وكم عملية قام بها.';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(32),
        decoration: const BoxDecoration(color: Color(0xFF1A1A1A), borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 24),
            Icon(Icons.lightbulb_outline_rounded, color: AppTheme.primary, size: 32),
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
}

import 'package:flutter/material.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/services/audit_service.dart';
import 'package:my_app/services/translation_service.dart';
import 'package:intl/intl.dart';
import 'dart:ui';

class MissionLogsScreen extends StatefulWidget {
  final String clubId;
  const MissionLogsScreen({super.key, required this.clubId});

  @override
  State<MissionLogsScreen> createState() => _MissionLogsScreenState();
}

class _MissionLogsScreenState extends State<MissionLogsScreen> {
  final _auditService = AuditService();
  bool _isLoading = true;
  List<Map<String, dynamic>> _logs = [];

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() => _isLoading = true);
    final logs = await _auditService.getLogs(); // In a real app, we'd filter by clubId in the query
    // Filtering for the current club (simulation logic)
    setState(() {
      _logs = logs; 
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: CustomScrollView(
        slivers: [
          _buildAppBar(),
          if (_isLoading)
            const SliverFillRemaining(child: Center(child: CircularProgressIndicator(color: AppTheme.primary)))
          else if (_logs.isEmpty)
            _buildEmptyState()
          else
            SliverPadding(
              padding: const EdgeInsets.all(24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => _buildLogCard(_logs[i]),
                  childCount: _logs.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      pinned: true,
      backgroundColor: AppTheme.background.withValues(alpha: 0.8),
      expandedHeight: 120,
      centerTitle: true,
      flexibleSpace: FlexibleSpaceBar(
        title: Text('STAFF_MISSION_LOGS'.tr.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 4)),
        background: ClipRRect(child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10), child: Container(color: Colors.transparent))),
      ),
    );
  }

  Widget _buildLogCard(Map<String, dynamic> log) {
    final DateTime? createdAt = log['created_at'] != null ? DateTime.parse(log['created_at']) : null;
    final String timeStr = createdAt != null ? DateFormat('HH:mm').format(createdAt) : '--:--';
    final String dateStr = createdAt != null ? DateFormat('dd MMM').format(createdAt) : '';
    final String action = log['action_type'] ?? 'OPERATION';
    final String colorHex = _getColorForAction(action);
    final Color actionColor = Color(int.parse(colorHex.replaceAll('#', '0xFF')));

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Text(timeStr, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
              const SizedBox(height: 4),
              Text(dateStr, style: const TextStyle(color: Colors.white24, fontSize: 10, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(width: 20),
          Container(
            width: 2, height: 80,
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [actionColor, AppTheme.background]),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: actionColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: actionColor.withValues(alpha: 0.3))),
                      child: Text(action.replaceAll('_', ' '), style: TextStyle(color: actionColor, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1)),
                    ),
                    const Spacer(),
                    const Icon(Icons.verified_user_outlined, color: Colors.white10, size: 14),
                  ],
                ),
                const SizedBox(height: 12),
                Text(log['user_name'] ?? 'Staff', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 4),
                Text(log['description'] ?? '', style: const TextStyle(color: Colors.white24, fontSize: 11, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getColorForAction(String action) {
    if (action.contains('SECURITY')) return '#00DDFF';
    if (action.contains('PAYMENT')) return '#FFD700';
    if (action.contains('EJECT')) return '#FF3366';
    if (action.contains('BOOKING')) return '#00FFAA';
    return '#FFFFFF';
  }

  Widget _buildEmptyState() {
    return SliverFillRemaining(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.history_edu_rounded, color: Colors.white10, size: 64),
            const SizedBox(height: 24),
            Text('NO_LOGS_YET'.tr, style: const TextStyle(color: Colors.white24, fontSize: 12, letterSpacing: 2)),
          ],
        ),
      ),
    );
  }
}

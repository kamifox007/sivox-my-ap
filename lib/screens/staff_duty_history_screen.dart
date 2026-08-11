import 'package:flutter/material.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/services/audit_service.dart';
import 'package:my_app/services/translation_service.dart';
import 'package:intl/intl.dart';

class StaffDutyHistoryScreen extends StatefulWidget {
  const StaffDutyHistoryScreen({super.key});

  @override
  State<StaffDutyHistoryScreen> createState() => _StaffDutyHistoryScreenState();
}

class _StaffDutyHistoryScreenState extends State<StaffDutyHistoryScreen> {
  final _auditService = AuditService();
  bool _isLoading = true;
  List<Map<String, dynamic>> _logs = [];

  @override
  void initState() {
    super.initState();
    _fetchGlobalHistory();
  }

  Future<void> _fetchGlobalHistory() async {
    setState(() => _isLoading = true);
    final user = _auditService.supabase.auth.currentUser;
    if (user != null) {
      final data = await _auditService.getLogs(
        staffIdFilter: user.id,
        sourceTable: AuditService.tableWorker,
      );
      if (mounted) {
        setState(() {
          _logs = data;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('PERSONNEL_DUTY_LOG'.tr.toUpperCase(), style: AppTheme.headlineStyle.copyWith(fontSize: 16, letterSpacing: 2)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.secondary))
          : _logs.isEmpty
              ? _buildEmptyState()
              : _buildList(),
    );
  }

  Widget _buildList() {
    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: _logs.length,
      itemBuilder: (ctx, i) => _buildLogCard(_logs[i]),
    );
  }

  Widget _buildLogCard(Map<String, dynamic> log) {
    final date = DateTime.tryParse(log['created_at'] ?? '');
    final dateStr = date != null ? DateFormat('MMM dd, HH:mm').format(date) : '';
    final action = log['action_type'] ?? 'OPERATION';
    final desc = log['description'] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppTheme.secondary.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: const Icon(Icons.shield_rounded, color: AppTheme.secondary, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(action.toString().replaceAll('_', ' '), style: const TextStyle(color: AppTheme.secondary, fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 1)),
                    Text(dateStr, style: const TextStyle(color: Colors.white24, fontSize: 9)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(desc, style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_toggle_off_rounded, color: Colors.white.withValues(alpha: 0.02), size: 100),
          const SizedBox(height: 24),
          Text('NO_VISIT_HISTORY'.tr, style: const TextStyle(color: Colors.white10, letterSpacing: 1.5, fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

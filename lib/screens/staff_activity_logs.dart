import 'package:flutter/material.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/services/audit_service.dart';
import 'package:my_app/services/translation_service.dart';
import 'package:intl/intl.dart';

class StaffActivityLogsScreen extends StatefulWidget {
  final String? eventId;
  const StaffActivityLogsScreen({super.key, this.eventId});

  @override
  State<StaffActivityLogsScreen> createState() => _StaffActivityLogsScreenState();
}

class _StaffActivityLogsScreenState extends State<StaffActivityLogsScreen> {
  final _auditService = AuditService();
  bool _isLoading = true;
  List<Map<String, dynamic>> _logs = [];

  @override
  void initState() {
    super.initState();
    _fetchLogs();
  }

  Future<void> _fetchLogs() async {
    setState(() => _isLoading = true);
    final logs = await _auditService.getLogs(eventId: widget.eventId);
    setState(() {
      _logs = logs;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        title: Text('staff_activity_logs'.tr, style: AppTheme.headlineStyle.copyWith(fontSize: 18)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: AppTheme.primary), onPressed: _fetchLogs),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : _logs.isEmpty
              ? _buildEmptyState()
              : _buildLogsList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.history_toggle_off, size: 60, color: Colors.white10),
          const SizedBox(height: 16),
          Text('No activity recorded yet.'.tr, style: const TextStyle(color: Colors.white24)),
        ],
      ),
    );
  }

  Widget _buildLogsList() {
    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: _logs.length,
      itemBuilder: (context, index) {
        final log = _logs[index];
        final type = log['action_type'] ?? 'INFO';
        final isEmergency = type == 'CANCEL_BOOKING';
        
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: isEmergency ? Colors.redAccent.withValues(alpha: 0.1) : Colors.white10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getTypeColor(type).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(type.toString().replaceAll('_', ' '), style: TextStyle(color: _getTypeColor(type), fontSize: 9, fontWeight: FontWeight.bold)),
                  ),
                  Text(_formatDate(log['created_at']), style: const TextStyle(color: Colors.white24, fontSize: 10)),
                ],
              ),
              const SizedBox(height: 16),
              _buildParsedDescription(log['description'] ?? ''),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.person, size: 12, color: AppTheme.primary),
                  const SizedBox(width: 4),
                  Text(log['user_name'] ?? 'Staff Member', style: const TextStyle(color: AppTheme.primary, fontSize: 11)),
                  const Spacer(),
                  Text(log['role'] ?? '', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Color _getTypeColor(String type) {
    if (type == 'ENTRY_SCAN') return Colors.greenAccent;
    if (type == 'CANCEL_BOOKING') return Colors.redAccent;
    if (type == 'MANUAL_TICKET') return AppTheme.secondary;
    return AppTheme.primary;
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    final dt = DateTime.parse(dateStr).toLocal();
    return DateFormat('HH:mm - dd/MM').format(dt);
  }

  Widget _buildParsedDescription(String description) {
    if (description.contains('|')) {
      final parts = description.split('|').map((e) => e.trim()).toList();
      String mainText = parts[0];
      List<Widget> badges = [];
      
      for (int i=1; i < parts.length; i++) {
        final pair = parts[i].split(':');
        if (pair.length == 2) {
          final t = pair[0].trim();
          final v = pair[1].trim();
          badges.add(Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(t, style: const TextStyle(color: Colors.white54, fontSize: 9)),
                const SizedBox(width: 4),
                Text(v, style: const TextStyle(color: AppTheme.primary, fontSize: 11, fontWeight: FontWeight.bold)),
              ],
            )
          ));
        } else {
           mainText += ' - ${parts[i]}';
        }
      }
      
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(mainText, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
          if (badges.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: badges),
          ]
        ],
      );
    }
    
    return Text(description, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500));
  }
}

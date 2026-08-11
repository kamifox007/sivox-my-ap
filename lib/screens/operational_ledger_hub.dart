import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/services/event_service.dart';
import 'package:my_app/services/audit_service.dart';
import 'package:my_app/services/translation_service.dart';
import 'package:my_app/models/event.dart';
import 'package:my_app/screens/event_ledger_detail.dart';

class OperationalLedgerHub extends StatefulWidget {
  final String clubId;
  const OperationalLedgerHub({super.key, required this.clubId});

  @override
  State<OperationalLedgerHub> createState() => _OperationalLedgerHubState();
}

class _OperationalLedgerHubState extends State<OperationalLedgerHub> {
  final supabase = Supabase.instance.client;
  final _eventService = EventService();
  final _auditService = AuditService();
  bool _isLoading = true;
  List<Map<String, dynamic>> _eventStats = [];

  @override
  void initState() {
    super.initState();
    _loadArchives();
  }

  Future<void> _loadArchives() async {
    setState(() => _isLoading = true);
    try {
      final events = await _eventService.getOrganizerEvents(
        organizerId: widget.clubId,
      );
      final List<Map<String, dynamic>> stats = [];

      for (var event in events) {
        final logs = await _auditService.getLogs(eventId: event.id);
        final auditStats = await _auditService.getSecurityStats(event.id);
        final generatedCount = await supabase
            .from('bookings')
            .select('id')
            .eq('event_id', event.id)
            .eq('is_walkin', true)
            .count(CountOption.exact);

        stats.add({
          'event': event,
          'entered': logs
              .where((l) => 
                l['action_type'].toString().contains('SCAN') || 
                l['action_type'].toString().contains('ENTRY') || 
                l['action_type'].toString().contains('CLEARED')
              )
              .length,
          'refused': auditStats['refusals'] ?? 0,
          'ejections': auditStats['ejections'] ?? 0,
          'generated': generatedCount.count,
        });
      }

      setState(() {
        _eventStats = stats;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            Text(
              'OPERATIONAL_ARCHIVES'.tr.toUpperCase(),
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 14,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _showLedgerHelp,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), shape: BoxShape.circle),
                child: const Icon(Icons.help_outline_rounded, color: Colors.white24, size: 10),
              ),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            )
          : _eventStats.isEmpty
          ? _buildEmptyState()
          : ListView.builder(
              padding: const EdgeInsets.all(24),
              itemCount: _eventStats.length,
              itemBuilder: (context, index) =>
                  _buildEventArchiveCard(_eventStats[index]),
            ),
    );
  }

  Widget _buildEventArchiveCard(Map<String, dynamic> data) {
    final Event event = data['event'];
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => EventLedgerDetailScreen(event: event),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Column(
            children: [
              Container(
                height: 100,
                width: double.infinity,
                decoration: BoxDecoration(
                  image: event.imageUrl != null
                      ? DecorationImage(
                          image: NetworkImage(event.imageUrl!),
                          fit: BoxFit.cover,
                        )
                      : null,
                  color: Colors.white.withValues(alpha: 0.05),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.8),
                      ],
                    ),
                  ),
                  padding: const EdgeInsets.all(16),
                  alignment: Alignment.bottomLeft,
                  child: Text(
                    event.title.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _statPill(
                      '${data['entered']}',
                      'ENTERED'.tr,
                      AppTheme.primary,
                    ),
                    _statPill(
                      '${data['generated']}',
                      'GENERATED_PASSES'.tr,
                      AppTheme.secondary,
                    ),
                    _statPill(
                      '${data['refused']}',
                      'REFUSED'.tr,
                      Colors.orangeAccent,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statPill(String value, String label, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: Colors.white24,
            fontSize: 8,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 64,
            color: Colors.white.withValues(alpha: 0.05),
          ),
          const SizedBox(height: 24),
          Text(
            'NO_ARCHIVES_FOUND'.tr,
            style: const TextStyle(
              color: Colors.white24,
              fontSize: 12,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }

  void _showLedgerHelp() {
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
            const Icon(Icons.inventory_2_outlined, color: AppTheme.primary, size: 32),
            const SizedBox(height: 16),
            Text('OPERATIONAL_ARCHIVES'.tr.toUpperCase(), style: AppTheme.headlineStyle.copyWith(fontSize: 18)),
            const SizedBox(height: 12),
            Text('HELPER_ARCHIVES_DESC'.tr, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.5)),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

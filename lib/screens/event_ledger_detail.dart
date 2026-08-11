import 'package:flutter/material.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/services/audit_service.dart';
import 'package:my_app/services/translation_service.dart';
import 'package:my_app/models/event.dart';
import 'package:intl/intl.dart';
import 'package:my_app/models/booking.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EventLedgerDetailScreen extends StatefulWidget {
  final Event event;
  const EventLedgerDetailScreen({super.key, required this.event});

  @override
  State<EventLedgerDetailScreen> createState() => _EventLedgerDetailScreenState();
}

class _EventLedgerDetailScreenState extends State<EventLedgerDetailScreen> {
  final _auditService = AuditService();
  bool _isLoading = true;
  List<Map<String, dynamic>> _logs = [];
  List<Booking> _generatedBookings = []; // NEW
  Map<String, int> _tacticalStats = {'ejections': 0, 'blocks': 0, 'refusals': 0};
  int _currentTab = 0; // 0: Timeline, 1: Generated

  @override
  void initState() {
    super.initState();
    _loadTacticalData();
  }

  Future<void> _loadTacticalData() async {
    setState(() => _isLoading = true);
    try {
      final logs = await _auditService.getLogs(eventId: widget.event.id);
      final stats = await _auditService.getSecurityStats(widget.event.id);
      
      final supabase = Supabase.instance.client;
      final bookingsRes = await supabase
          .from('bookings')
          .select()
          .eq('event_id', widget.event.id)
          .eq('is_walkin', true);
      
      setState(() {
        _logs = logs;
        _tacticalStats = stats;
        _generatedBookings = (bookingsRes as List).map((b) => Booking.fromMap(b)).toList();
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
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          _buildSliverAppBar(),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   _buildTacticalGrid(),
                   const SizedBox(height: 32),
                   _buildTabSelector(),
                   const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          if (_isLoading)
            const SliverFillRemaining(child: Center(child: CircularProgressIndicator(color: AppTheme.primary)))
          else if (_currentTab == 0) ...[
            if (_logs.isEmpty) SliverFillRemaining(child: _buildEmptyTimeline())
            else SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              sliver: SliverList(delegate: SliverChildBuilderDelegate((context, index) => _LogTacticalTile(log: _logs[index]), childCount: _logs.length)),
            ),
          ] else ...[
            if (_generatedBookings.isEmpty) SliverFillRemaining(child: _buildEmptyTimeline())
            else SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              sliver: SliverList(delegate: SliverChildBuilderDelegate((context, index) => _GeneratedPassTile(booking: _generatedBookings[index]), childCount: _generatedBookings.length)),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  Widget _buildTabSelector() {
    return Container(
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          _tabButton('TIMELINE'.tr, 0),
          _tabButton('GENERATED'.tr, 1),
        ],
      ),
    );
  }

  Widget _tabButton(String label, int index) {
    final isSelected = _currentTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _currentTab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(child: Text(label, style: TextStyle(color: isSelected ? Colors.black : Colors.white54, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1))),
        ),
      ),
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 200,
      pinned: true,
      backgroundColor: AppTheme.background,
      flexibleSpace: FlexibleSpaceBar(
        title: Text(widget.event.title.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1)),
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (widget.event.imageUrl != null)
              Image.network(widget.event.imageUrl!, fit: BoxFit.cover),
            Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, AppTheme.background]))),
          ],
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.help_outline_rounded, color: Colors.white24, size: 20),
          onPressed: () => _showHelp(),
        ),
        IconButton(
          icon: const Icon(Icons.delete_sweep_outlined, color: Colors.redAccent),
          onPressed: _confirmClearLedger,
        ),
      ],
    );
  }

  Widget _buildTacticalGrid() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _tacticalStat('TOTAL'.tr, '${_logs.length}', AppTheme.primary),
          _tacticalStat('REFUSED'.tr, '${_tacticalStats['refusals']}', Colors.orangeAccent),
          _tacticalStat('EJECTED'.tr, '${_tacticalStats['ejections']}', Colors.redAccent),
        ],
      ),
    );
  }

  Widget _tacticalStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -1)),
        const SizedBox(height: 4),
        Text(label.toUpperCase(), style: const TextStyle(color: Colors.white24, fontSize: 7, fontWeight: FontWeight.bold, letterSpacing: 1)),
      ],
    );
  }

  Widget _buildEmptyTimeline() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history_outlined, size: 48, color: Colors.white.withValues(alpha: 0.05)),
          const SizedBox(height: 16),
          const Text('NO TACTICAL LOGS RECORDED', style: TextStyle(color: Colors.white10, fontSize: 10, letterSpacing: 2)),
        ],
      ),
    );
  }

  void _confirmClearLedger() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141414),
        title: Text('CLEAR_LOGS'.tr),
        content: Text('Are you sure you want to permanently delete all records for this event? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('cancel'.tr, style: const TextStyle(color: Colors.white24))),
          TextButton(
            onPressed: () async {
              final success = await _auditService.clearLogs(widget.event.id);
              if (!mounted) return;
              if (success && ctx.mounted) {
                Navigator.pop(ctx);
                _loadTacticalData();
              }
            },
            child: Text('confirm'.tr, style: const TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  void _showHelp() {
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
            const Icon(Icons.auto_awesome_rounded, color: AppTheme.primary, size: 32),
            const SizedBox(height: 16),
            Text('TACTICAL_AUDIT'.tr.toUpperCase(), style: AppTheme.headlineStyle.copyWith(fontSize: 18)),
            const SizedBox(height: 12),
            Text('HELPER_LEDGER_DESC'.tr, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.5)),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _LogTacticalTile extends StatelessWidget {
  final Map<String, dynamic> log;
  const _LogTacticalTile({required this.log});

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(log['created_at'] ?? '');
    final timeStr = date != null ? DateFormat('HH:mm').format(date) : '--:--';
    final type = log['action_type']?.toString() ?? 'SCAN';
    final isSecurity = type.contains('REFUSED') || type.contains('EJECT') || type.contains('BLOCK') || type.contains('SECURITY');
    final isEntry = type.contains('ENTRY') || type.contains('SCAN');
    final accent = isSecurity ? Colors.redAccent : (isEntry ? AppTheme.primary : AppTheme.secondary);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                child: Text(type.replaceAll('_', ' ').toUpperCase(), style: TextStyle(color: accent, fontSize: 7, fontWeight: FontWeight.w900, letterSpacing: 1)),
              ),
              const Spacer(),
              Text(timeStr, style: const TextStyle(color: Colors.white24, fontSize: 9, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          Text(log['description'] ?? '', style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.person_pin_rounded, color: Colors.white24, size: 10),
              const SizedBox(width: 8),
              Text('AGENT: ${log['user_name'] ?? 'TERMINAL'}'.toUpperCase(), style: const TextStyle(color: Colors.white24, fontSize: 7, fontWeight: FontWeight.bold)),
              const Spacer(),
              if (log['metadata']?['discount_applied'] == true)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                  child: const Row(
                    children: [
                      Icon(Icons.card_giftcard, color: Colors.amber, size: 8),
                      SizedBox(width: 4),
                      Text('BENEFIT_APPLIED', style: TextStyle(color: Colors.amber, fontSize: 6, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GeneratedPassTile extends StatelessWidget {
  final Booking booking;
  const _GeneratedPassTile({required this.booking});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.secondary.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppTheme.secondary.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: const Icon(Icons.confirmation_num_outlined, color: AppTheme.secondary, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(booking.userName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 4),
                Text('SERIAL: ${booking.walkinSerial ?? 'N/A'}'.toUpperCase(), style: const TextStyle(color: AppTheme.secondary, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(8)),
            child: Text(booking.ticketType.toUpperCase(), style: const TextStyle(color: Colors.white38, fontSize: 8, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

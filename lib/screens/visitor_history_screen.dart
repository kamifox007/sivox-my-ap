import 'package:flutter/material.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/services/audit_service.dart';
import 'package:my_app/services/translation_service.dart';
import 'package:intl/intl.dart';

class VisitorHistoryScreen extends StatefulWidget {
  const VisitorHistoryScreen({super.key});

  @override
  State<VisitorHistoryScreen> createState() => _VisitorHistoryScreenState();
}

class _VisitorHistoryScreenState extends State<VisitorHistoryScreen> {
  final _auditService = AuditService();
  bool _isLoading = true;
  List<Map<String, dynamic>> _history = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    final data = await _auditService.getVisitorHistory();
    if (mounted) {
      setState(() {
        _history = data;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          _buildBackground(),
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              _buildAppBar(),
              if (_isLoading)
                const SliverFillRemaining(child: Center(child: CircularProgressIndicator(color: AppTheme.primary)))
              else if (_history.isEmpty)
                SliverFillRemaining(child: _buildEmptyState())
              else
                SliverPadding(
                  padding: const EdgeInsets.all(24),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _buildHistoryCard(_history[index]),
                      childCount: _history.length,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      expandedHeight: 180,
      pinned: true,
      backgroundColor: Colors.transparent,
      flexibleSpace: FlexibleSpaceBar(
        title: Text('MY_CLUB_HISTORY'.tr.toUpperCase(), style: AppTheme.headlineStyle.copyWith(fontSize: 16, letterSpacing: 2)),
        background: Stack(
          alignment: Alignment.center,
          children: [
            Opacity(opacity: 0.3, child: Icon(Icons.history_toggle_off_rounded, size: 120, color: AppTheme.primary.withValues(alpha: 0.2))),
          ],
        ),
      ),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
        onPressed: () => Navigator.pop(context),
      ),
    );
  }

  Widget _buildHistoryCard(Map<String, dynamic> log) {
    final date = DateTime.tryParse(log['created_at'] ?? '');
    final dateStr = date != null ? DateFormat('EEEE, d MMMM yyyy').format(date) : '';
    final timeStr = date != null ? DateFormat('HH:mm').format(date) : '';
    final eventTitle = log['events']?['title'] ?? 'CLUB_EXPERIENCE'.tr;
    final imgUrl = log['events']?['image_url'];

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: [
          Container(
            height: 120,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
              image: imgUrl != null ? DecorationImage(image: NetworkImage(imgUrl), fit: BoxFit.cover) : null,
              color: Colors.white10,
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent]),
              ),
              padding: const EdgeInsets.all(20),
              alignment: Alignment.bottomLeft,
              child: Text(eventTitle.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                   Row(
                     children: [
                       const Icon(Icons.calendar_today_rounded, color: AppTheme.primary, size: 12),
                       const SizedBox(width: 8),
                       Text(dateStr, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500)),
                     ],
                   ),
                   const SizedBox(height: 8),
                   Row(
                     children: [
                       const Icon(Icons.access_time_rounded, color: AppTheme.secondary, size: 12),
                       const SizedBox(width: 8),
                       Text(timeStr, style: const TextStyle(color: Colors.white24, fontSize: 10, fontWeight: FontWeight.bold)),
                     ],
                   ),
                  ],
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2))),
                  child: Text('VERIFIED_ENTRY'.tr.toUpperCase(), style: const TextStyle(color: AppTheme.primary, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1)),
                ),
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
           Icon(Icons.auto_awesome_mosaic_rounded, color: Colors.white.withValues(alpha: 0.02), size: 100),
           const SizedBox(height: 24),
           Text('NO_VISIT_HISTORY'.tr, style: const TextStyle(color: Colors.white10, letterSpacing: 1.5, fontSize: 13, fontWeight: FontWeight.bold)),
         ],
       ),
     );
  }

  Widget _buildBackground() {
    return Positioned.fill(
      child: Stack(
        children: [
          Positioned(top: 200, left: -100, child: Container(width: 300, height: 300, decoration: BoxDecoration(shape: BoxShape.circle, color: AppTheme.primary.withValues(alpha: 0.05), boxShadow: [BoxShadow(color: AppTheme.primary.withValues(alpha: 0.03), blurRadius: 100)]))),
        ],
      ),
    );
  }
}
